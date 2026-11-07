require "digest"

module FilmscanGUI
  module Worker
    # The toolkit's own CLI, with its small copies of frames taken from the
    # worker's, so a frame is decoded once for both previews and analysis.
    class AnalysisCLI < FilmScan::CLI
      def initialize(proxies)
        super()
        @proxies = proxies
      end

      private

      def small(path) = @proxies.float(path)
    end

    # Each frame at the size the roll analysis reads it, kept in memory as
    # eight or sixteen bit, and made float when a render wants it.
    class Proxies
      WIDTH = FilmScan::CLI::TUNE_WIDTH

      def initialize
        @images = {}
      end

      def [](path)
        @images[path] ||= begin
          image = Vips::Image.thumbnail(path, WIDTH, size: :down).copy_memory
          image.bands > 3 ? image[0..2].copy_memory : image
        end
      end

      def float(path)
        image = self[path]
        image.cast(:float) / (image.format == :ushort ? 65_535.0 : 255.0)
      end

      def loaded?(path) = @images.key?(path)
    end

    # One roll, for previews: renders the frame being looked at, the contact
    # sheet's tiles and a frame at full size, and measures the roll when its
    # settings need it. Only the newest request of each kind is kept.
    class RollEngine
      # Settings that change what the analysis measures. The rest change
      # only how its result is applied.
      REMEASURE = %i[profile reference match film_gains roll_balance_limit sky_neutral convert_only chroma_map].freeze
      STRENGTHS = { balance: :roll_balance, tone: :roll_tone, fit: :roll_fit, flat: :flat_field, look: :match_strength }.freeze
      TILE = 460
      THUMB = 240

      def initialize(send)
        @send = send
        @inbox = Thread::Queue.new
        @proxies = Proxies.new
        @overrides = {}
        @thumbs = []
        @sheet = []
      end

      def run(input)
        Thread.new do
          while (message = Protocol.read(input))
            @inbox << message[0]
          end
          @inbox << { op: "quit" }
        end
        loop do
          drain(work?)
          break if @quit

          step if work?
        end
      end

      private

      def drain(busy)
        message = busy ? (@inbox.pop(true) rescue nil) : @inbox.pop
        while message
          handle(message)
          message = (@inbox.pop(true) rescue nil)
        end
      end

      def handle(message)
        case message[:op]
        when "open"
          @source = message[:source]
          @cache = message[:cache]
          @paths = FilmScan::CLI.new.send(:find_files, @source, nil)
          @stems = @paths.to_h { |path| [File.basename(path, ".*"), path] }
          @send.call(type: "frames", stems: @stems.keys)
          @thumbs = @paths.dup
          settings(message[:args], message[:overrides])
          @measure = !@convert
        when "settings" then settings(message[:args], message[:overrides])
        when "frame" then @frame = message
        when "sheet" then @sheet = message[:stems].dup.tap { @sheet_gen = message[:gen] }
        when "full" then @full = message
        when "measure" then @measure = true
        when "quit" then @quit = true
        end
      end

      def work? = @measure || @full || @frame || @sheet.any? || @thumbs.any?

      def step
        if @measure then measure
        elsif @full then render_full
        elsif @frame then render_frame
        elsif @sheet.any? then render_tile
        else thumb
        end
      rescue StandardError => e
        warn "#{e.class}: #{e.message}\n#{e.backtrace&.first(12)&.join("\n")}"
        ours = e.backtrace&.find { |line| line.include?("filmscan_gui/") || line.include?("film_scan") }
        @send.call(type: "error", message: "#{e.class}: #{e.message.lines.first.to_s.strip}", where: ours)
      end

      # The command-line settings, read by the toolkit's own parser so they
      # mean exactly what they mean to a render.
      def settings(args, overrides)
        @overrides = (overrides || {}).to_h { |stem, values| [stem.to_s, values.transform_keys(&:to_sym)] }
        flags = { previews: false }
        argv = FilmScan::CLI.bare_fix(args.dup)
        FilmScan::CLI.new.send(:build_parser, flags).parse!(argv)
        @convert = flags[:convert_only]
        @profile = @convert ? nil : FilmScan::Profile.load(flags[:profile])
        @options = FilmScan::DEFAULTS.merge(@profile ? @profile.settings : {}).merge(flags)
        # The engine a render would pick, so previews match the files and get
        # the GPU where the toolkit has one.
        @options[:engine] ||= FilmScan::Metal.default_engine if defined?(FilmScan::Metal)
        @send.call(type: "state", stale: stale?, remeasure: remeasure?)
        @measure = true if @fits && remeasure?
      end

      def fit_key(options) = options.except(*FilmScan::CLI::NOT_IN_FITS).merge(fix: Array(options[:fix]).sort)

      def remeasure_key(options)
        options.slice(*REMEASURE).merge(profile: options[:profile], flat: Array(options[:fix]).include?(:flat))
      end

      def stale? = !@convert && (@fits.nil? || fit_key(@options) != fit_key(@fit_options))
      def remeasure? = !@convert && (@fits.nil? || remeasure_key(@options) != remeasure_key(@fit_options))

      def measure
        @measure = false
        return @send.call(type: "measured", stale: false, report: []) if @convert

        @send.call(type: "progress", text: "Measuring the roll", done: 0, total: 0)
        $stdout.take_lines
        cli = AnalysisCLI.new(@proxies)
        options = @options
        reference = if options[:match]
                      cli.send(:matched_reference, options[:match], @cache)
                    else
                      options[:reference] && FilmScan::Reference.load(options[:reference])
                    end
        options = cli.send(:measure_frame_balance, @source, reference, options)
        @fits = cli.send(:analyse_roll, @source, @cache, @profile, reference, options)
        @reference = reference
        @fit_options = options
        @send.call(type: "measured", stale: stale?, report: $stdout.take_lines)
      end

      def frame_options(stem)
        STRENGTHS.each do |fit, setting|
          # A roll with no siblings carries its film's own look, from the profile.
          setting = :look_strength if fit == :look && !@options[:match]
          @fits[fit].strength = @options[setting] if @fits&.[](fit)
        end
        @options.merge(@overrides.fetch(stem, {}))
      end

      def corrected(stem, image)
        return image if @convert || @fits.nil?

        FilmScan::Pipeline.new(frame_options(stem), reference: @reference, **@fits).render(image)
      end

      def bytes_of(image) = (image * 255).cast(:uchar).copy_memory

      def reply(header, image)
        image = image.bandjoin([image, image]) if image.bands == 1
        image = image.copy_memory
        @send.call(header.merge(w: image.width, h: image.height, bands: image.bands), image.write_to_memory)
      end

      def render_frame
        request = @frame
        @frame = nil
        stem = request[:stem]
        path = @stems.fetch(stem)
        reply({ type: "scan", stem: stem }, bytes_of(@proxies.float(path))) if request[:scan]
        started = clock
        image = bytes_of(corrected(stem, @proxies.float(path)))
        reply({ type: "frame", stem: stem, gen: request[:gen], corrected: !(@convert || @fits.nil?),
                stale: stale?, ms: ((clock - started) * 1000).round }, image)
      end

      def render_tile
        stem = @sheet.shift
        path = @stems[stem] or return
        image = bytes_of(corrected(stem, @proxies.float(path))).thumbnail_image(TILE, height: TILE, size: :down)
        reply({ type: "tile", stem: stem, gen: @sheet_gen, stale: stale? }, image)
      end

      def render_full
        request = @full
        @full = nil
        stem = request[:stem]
        path = @stems.fetch(stem)
        started = clock
        image = if @convert || @fits.nil?
                  FilmScan::Colour.load(path)
                else
                  FilmScan::Pipeline.new(frame_options(stem), reference: @reference, **@fits).call(path)
                end
        reply({ type: "full", stem: stem, gen: request[:gen], ms: ((clock - started) * 1000).round }, bytes_of(image))
      end

      def thumb
        path = @thumbs.shift or return
        image = @proxies[path]
        image = (image.cast(:float) / 257.0).cast(:uchar) if image.format == :ushort
        reply({ type: "thumb", stem: File.basename(path, ".*") }, image.thumbnail_image(THUMB, height: THUMB, size: :down))
      end

      def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
