require "yaml"
require "time"
require "fileutils"
require "securerandom"
require "rbconfig"
require_relative "roll_settings"
require_relative "trash"

module FilmscanGUI
  # Renders waiting their turn, run one or two at a time as the toolkit's
  # own command line, the same arguments the render scripts pass. The list
  # is a file in the workspace, so it outlives the app. A running render
  # can be paused, and with "previews first" it is held while a slider
  # moves, so previews come back quickly.
  class RenderQueue
    SIDE = %w[settings.yml roll-fit.yml contact.jpg match-reference.yml].freeze
    QUIET = 2.5

    Job = Struct.new(:id, :trip, :rel, :kind, :status, :done, :total, :phase, :added, :started, :finished,
                     :first_frame, :message, :log, keyword_init: true) do
      def name = File.basename(rel)
      def label = kind == "trial" ? "Trial render" : "Final render"
      def active? = %w[running paused].include?(status)

      # Seconds left, from the pace of the frames done so far.
      def left
        return nil unless status == "running" && first_frame && done.to_i.positive? && total.to_i.positive?

        pace = (Time.now - first_frame) / done
        pace * (total - done)
      end

      def to_h = super.transform_keys(&:to_s).transform_values { |v| v.is_a?(Time) ? v.iso8601 : v }
    end

    attr_reader :jobs, :lines
    attr_accessor :gentle, :slots, :previews_first

    def initialize(config, library)
      @config = config
      @library = library
      @path = File.join(config.workspace, "gui", "queue.yml")
      @jobs = []
      @running = {}
      @lines = Hash.new { |h, k| h[k] = [] }
      @listeners = []
      @gentle = config["gentle"] || false
      @slots = config["slots"] || 1
      @previews_first = config["previews_first"] != false
      load
    end

    def on_change(&block) = @listeners << block

    def add(roll, kind)
      job = Job.new(id: SecureRandom.hex(4), trip: roll.trip, rel: roll.rel, kind: kind.to_s, status: "waiting",
                    done: 0, total: roll.frames.size, phase: "Waiting", added: Time.now)
      @jobs << job
      changed
      job
    end

    def find(id) = @jobs.find { |job| job.id == id }

    # Called from the app's timer: takes in output, notices finished
    # renders, starts waiting ones, and lets a held render go again.
    def tick
      @running.each do |id, run|
        read(find(id), run)
      end
      @running.to_a.each do |id, run|
        pid, status = Process.wait2(run[:pid], Process::WNOHANG)
        finish(find(id), status) if pid
      rescue Errno::ECHILD
        finish(find(id), nil)
      end
      resume_after_previews
      start_next
    end

    def preview_activity
      return unless @previews_first && @running.any?

      @last_preview = Time.now
      return if @held

      @held = true
      @running.each_value { |run| signal("STOP", run[:pid]) }
    end

    def pause(job)
      run = @running[job.id] or return
      signal("STOP", run[:pid])
      job.status = "paused"
      changed
    end

    def resume(job)
      run = @running[job.id] or return
      signal("CONT", run[:pid]) unless @held
      job.status = "running"
      changed
    end

    # Pauses the render once the frame it is on is written.
    def pause_after_frame(job)
      @running[job.id]&.store(:pause_after, true)
      job.message = "Pausing after this frame"
      changed
    end

    def stop(job)
      if (run = @running[job.id])
        signal("CONT", run[:pid])
        signal("TERM", run[:pid])
        run[:stopped] = true
      else
        job.status = "stopped"
        changed
      end
    end

    def remove(job)
      return if job.active?

      @jobs.delete(job)
      changed
    end

    def run_next(job)
      return unless job.status == "waiting"

      @jobs.delete(job)
      index = @jobs.index { |j| j.status == "waiting" } || @jobs.size
      @jobs.insert(index, job)
      changed
    end

    def move(job, to)
      @jobs.delete(job)
      @jobs.insert(to.clamp(0, @jobs.size), job)
      changed
    end

    def retry(job)
      return if job.active?

      job.status = "waiting"
      job.done = 0
      job.phase = "Waiting"
      job.message = nil
      changed
    end

    def settings_changed
      @config.update("gentle" => @gentle, "slots" => @slots, "previews_first" => @previews_first)
    end

    def shutdown
      @running.each_value do |run|
        signal("CONT", run[:pid])
        signal("TERM", run[:pid])
      end
    end

    private

    def changed
      save
      @listeners.each(&:call)
    end

    def load
      return unless File.exist?(@path)

      (YAML.safe_load_file(@path, permitted_classes: [Time]) || []).each do |row|
        job = Job.new(**row.transform_keys(&:to_sym))
        %i[added started finished first_frame].each { |k| job[k] = Time.parse(job[k]) if job[k].is_a?(String) }
        # A render the app was running when it quit did not finish.
        if job.active?
          job.status = "stopped"
          job.message = "The app quit during this render"
        end
        @jobs << job
      end
    rescue Psych::Exception, ArgumentError
      @jobs = []
    end

    def save
      @config.refuse_toolkit!(@path)
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, YAML.dump(@jobs.map(&:to_h)))
    end

    def start_next
      return if @running.size >= @slots

      job = @jobs.find { |j| j.status == "waiting" } or return
      start(job)
    end

    def start(job)
      roll = @library.find(job.trip, job.rel)
      return fail(job, "The roll is no longer in the library") unless roll

      settings = RollSettings.new(roll)
      target = job.kind == "trial" ? roll.trial_dir : roll.output_dir
      log = File.join(@config.workspace, "gui", "logs", "#{job.id}.log")
      begin
        @config.refuse_toolkit!(target, roll.sidefiles_dir, log)
      rescue Config::InsideToolkit => e
        return fail(job, e.message)
      end
      old = job.kind == "trial" ? roll.trial : roll.output
      return fail(job, "Could not move the old files to the Trash") unless Trash.move(old)

      FileUtils.mkdir_p(target)
      args = settings.render_args(target, gentle: @gentle)
      command, dir = command_for(args)
      FileUtils.mkdir_p(File.dirname(log))
      reader, writer = IO.pipe
      pid = without_bundler do
        Process.spawn({ "BUNDLE_FROZEN" => "true" }, *command, chdir: dir, out: writer, err: writer, pgroup: true)
      end
      writer.close
      @running[job.id] = { pid: pid, io: reader, partial: +"", log: File.open(log, "w"), target: target, roll: roll }
      @running[job.id][:log].puts("$ #{command.join(' ')}")
      job.status = "running"
      job.started = Time.now
      job.phase = "Starting"
      job.log = log
      job.done = 0
      job.total = roll.frames.size
      job.message = nil
      changed
    end

    # The toolkit runs from its checkout through Bundler, as the scripts
    # run it, or as an installed command.
    def command_for(args)
      toolkit = @config.toolkit
      if toolkit && File.expand_path(toolkit) == Gem.loaded_specs["film_scan"]&.full_gem_path
        [[RbConfig.ruby, "-rbundler/setup", File.join(toolkit, "bin", "filmscan"), *args],
         File.expand_path("../..", __dir__)]
      elsif toolkit && File.exist?(File.join(toolkit, "Gemfile"))
        [["bundle", "exec", "./bin/filmscan", *args], toolkit]
      elsif toolkit && File.exist?(File.join(toolkit, "bin", "filmscan"))
        [[RbConfig.ruby, File.join(toolkit, "bin", "filmscan"), *args], toolkit]
      else
        [["filmscan", *args], Dir.home]
      end
    end

    def without_bundler(&block)
      return yield unless defined?(Bundler)

      Bundler.with_unbundled_env(&block)
    end

    def read(job, run)
      loop do
        chunk = run[:io].read_nonblock(65_536)
        run[:log].write(chunk)
        run[:log].flush
        run[:partial] << chunk
        while (cut = run[:partial].index(/[\r\n]/))
          line = run[:partial].slice!(0..cut).strip
          progress(job, run, line) unless line.empty?
        end
      end
    rescue IO::WaitReadable, EOFError
      nil
    end

    def progress(job, run, line)
      line.split(/(?=\bsampling \d+\/\d+)/).map(&:strip).reject(&:empty?).each do |part|
        @lines[job.id] << part
        @lines[job.id].shift while @lines[job.id].size > 200
        case part
        when /\Asampling (\d+)\/(\d+)/ then job.phase = "Measuring the roll, frame #{Regexp.last_match(1)} of #{Regexp.last_match(2)}"
        when /\Ameasuring (.+) to match/ then job.phase = "Measuring the siblings"
        when /\Aprocessing (\d+) frames/
          job.total = Regexp.last_match(1).to_i
          job.phase = "Rendering"
          job.first_frame = Time.now
        when /\A\[(\d+)\/(\d+)\]/
          job.done = Regexp.last_match(1).to_i
          job.total = Regexp.last_match(2).to_i
          job.phase = job.done >= job.total ? "Finishing" : "Frame #{job.done + 1} of #{job.total}"
          if run.delete(:pause_after)
            signal("STOP", run[:pid])
            job.status = "paused"
            job.message = nil
          end
        when /\Acontact sheet/ then job.phase = "Contact sheet"
        end
      end
      @listeners.each(&:call)
    end

    def finish(job, status)
      run = @running.delete(job.id)
      read(job, run)
      run[:io].close
      run[:log].close
      job.finished = Time.now
      ok = status&.success? && !run[:stopped]
      if run[:stopped]
        job.status = "stopped"
        job.message = "Stopped"
      elsif ok
        job.status = "done"
        job.phase = "Done"
        job.done = job.total
        keep_side_files(run[:roll], run[:target], job)
        notify("#{job.name} is rendered", "#{job.label}, #{job.total} frames")
      else
        job.status = "failed"
        said = @lines[job.id].reject { |line| line.match?(/\Asampling \d+\/\d+|\A\[\d+\/\d+\]/) }
        job.message = said.find { |line| line.match?(/error|too few|cannot|could not|no such|not a|refusing/i) } ||
                      said.last || "The render stopped with an error"
      end
      changed
    end

    def fail(job, message)
      job.status = "failed"
      job.message = message
      changed
    end

    # Side files go where the layout says, beside a copy of the log, or
    # stay with the output when it names no place.
    def keep_side_files(roll, target, job)
      dir = roll.sidefiles_dir
      dir ||= target
      FileUtils.mkdir_p(dir)
      SIDE.each do |name|
        path = File.join(target, name)
        FileUtils.mv(path, File.join(dir, name)) if File.exist?(path) && dir != target
      end
      FileUtils.cp(job.log, File.join(dir, "run.log")) if job.log && File.exist?(job.log)
    rescue SystemCallError => e
      job.message = "Rendered, but the side files could not be moved: #{e.message}"
    end

    def resume_after_previews
      return unless @held && Time.now - @last_preview > QUIET

      @held = false
      @running.each { |id, run| signal("CONT", run[:pid]) unless find(id)&.status == "paused" }
    end

    def signal(name, pid)
      Process.kill(name, -Process.getpgid(pid))
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end

    def notify(title, body)
      return unless File.executable?("/usr/bin/osascript")

      script = "display notification #{body.to_s.dump} with title #{title.to_s.dump}"
      Process.detach(Process.spawn("/usr/bin/osascript", "-e", script, out: File::NULL, err: File::NULL))
    end
  end
end
