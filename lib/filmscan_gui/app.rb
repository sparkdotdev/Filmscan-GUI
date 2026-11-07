require "wx"
require "digest"
require "fileutils"
require "film_scan"
require_relative "version"
require_relative "config"
require_relative "library"
require_relative "render_queue"
require_relative "worker_client"
require_relative "ui/theme"
require_relative "ui/menus"
require_relative "ui/library_frame"
require_relative "ui/roll_frame"
require_relative "ui/queue_frame"
require_relative "ui/sibling_dialog"
require_relative "ui/preferences"

module FilmscanGUI
  # Small copies of images, made by the utility worker and kept on disk.
  class Thumbnails
    def initialize(app, dir)
      @app = app
      @dir = dir
      @waiting = {}
    end

    def file_for(path, size)
      stamp = File.exist?(path) ? File.mtime(path).to_i : 0
      File.join(@dir, size.to_s, "#{Digest::SHA1.hexdigest("#{path}|#{stamp}")}.jpg")
    end

    # Yields a Wx::Image now if it is cached, or when the worker has made it.
    def fetch(path, size, &block)
      return unless path

      file = file_for(path, size)
      if File.exist?(file)
        image = Wx::Image.new(file)
        return block.call(image) if image.is_ok
      end
      first = !@waiting.key?(file)
      (@waiting[file] ||= []) << block
      @app.utility.send(op: "thumb", path: path, size: size, file: file, quality: size > 600 ? 92 : 86) if first
    end

    def arrived(header)
      callbacks = @waiting.delete(header[:file]) || []
      return if header[:type] == "thumb_failed" || !File.exist?(header[:file])

      image = Wx::Image.new(header[:file])
      callbacks.each { |callback| UI.guard { callback.call(image) } } if image.is_ok
    end
  end

  class App < Wx::App
    attr_reader :config, :library, :queue, :thumbs, :utility, :menus

    def on_init
      set_app_name(APP_NAME)
      set_app_display_name(APP_NAME)
      Wx::Image.add_handler(Wx::JPEGHandler.new) rescue nil
      @config = Config.new
      keep_errors
      appearance = { "light" => Wx::App::Appearance::Light, "dark" => Wx::App::Appearance::Dark }[@config["appearance"]]
      set_appearance(appearance) if appearance
      @library = Library.new(@config)
      @watchers = {}
      @rolls = {}
      @utility = WorkerClient.new("utility", log: log_path)
      @thumbs = Thumbnails.new(self, File.join(@config.cache_dir, "thumbs"))
      watch(@utility) { |header, _| @thumbs.arrived(header) }
      @queue = RenderQueue.new(@config, @library)
      @menus = UI::Menus.new(self)
      @poll = Wx::Timer.new(self)
      evt_timer(@poll.get_id) { poll }
      @poll.start(15)
      @library_frame = UI::LibraryFrame.new(self)
      @library_frame.show
      preferences(first: true) unless @config.configured?
      true
    end

    def on_exit
      @poll&.stop
      @queue&.shutdown
      @watchers.each_key(&:close)
      0
    end

    def log_path = File.join(@config.cache_dir, "logs", "workers.log")

    # Opened from the Dock the app has nowhere to write what goes wrong, so
    # it goes to logs/app.log beside the workers' log instead.
    def keep_errors
      return if $stderr.tty?

      path = File.join(@config.cache_dir, "logs", "app.log")
      FileUtils.mkdir_p(File.dirname(path))
      $stderr.reopen(path, "a")
      $stderr.sync = true
      warn "#{Time.now.strftime('%F %T')} started"
    end

    def watch(client, &block) = @watchers[client] = block
    def unwatch(client) = @watchers.delete(client)

    def roll_worker = WorkerClient.new("roll", log: log_path)

    # Where a roll's analysis for previews is kept. The toolkit keeps a
    # copy under ~/.cache/film_scan too, which renders find.
    def analysis_cache(roll) = File.join(@config.cache_dir, "rolls", Digest::SHA1.hexdigest(roll.source))

    def open_roll(roll, page: nil)
      frame = @rolls[roll.key] ||= UI::RollFrame.new(self, roll)
      frame.show
      frame.raise_window
      frame.command(page) if page
      frame
    end

    def roll_closed(frame) = @rolls.delete(frame.roll.key)

    def show_library
      @library_frame.show
      @library_frame.raise_window
    end

    def show_queue
      @queue_frame ||= UI::QueueFrame.new(self)
      @queue_frame.show
      @queue_frame.raise_window
    end

    def queue_closed = @queue_frame = nil

    def preferences(first: false)
      dialog = UI::Preferences.new(@library_frame, self, first: first)
      if dialog.show_modal == Wx::ID_OK
        @library.reload
        @library_frame.reload
      end
      dialog.destroy
    end

    def about
      Wx.message_box("#{APP_NAME} #{VERSION}\nUses Filmscan-CLI #{FilmScan::VERSION}.",
                     "About #{APP_NAME}", Wx::OK, @library_frame)
    end

    private

    def poll
      @watchers.to_a.each do |client, handler|
        client.poll do |header, payload|
          handler.call(header, payload)
        rescue StandardError => e
          warn "#{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
        end
      end
      @queue.tick
    rescue StandardError => e
      warn "#{e.class}: #{e.message}\n#{e.backtrace.first(6).join("\n")}"
    end
  end
end
