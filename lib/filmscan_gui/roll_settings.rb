require "yaml"
require "fileutils"
require "shellwords"
require "film_scan"
require_relative "schema"
require_relative "sessions"
require_relative "overrides"
require_relative "library"

module FilmscanGUI
  # What the app has chosen for one roll: its profile, the settings moved
  # away from the profile's, its siblings and the output. It becomes the
  # same command line the render scripts use, so a roll renders identically
  # from the app or from a terminal.
  class RollSettings
    LIVE_STRENGTHS = { balance: :roll_balance, tone: :roll_tone, fit: :roll_fit, flat: :flat_field,
                       look: :match_strength }.freeze

    attr_reader :roll, :values, :match
    attr_accessor :profile, :convert_only, :fix

    def initialize(roll)
      @roll = roll
      @config = roll.config
      @values = {}
      @fix = FilmScan::DEFAULT_FIXES.dup
      film = roll.film
      @convert_only = film == :convert
      @profile = film.is_a?(String) ? film : nil
      @match = []
      session = Sessions.new(sessions_path).match_for(roll.trip, roll.rel)
      if session
        @match = session.siblings
        @values[:match_strength] = session.strength.to_f if session.strength
      end
      load_saved
    end

    def sessions_path = @config.sessions_path
    def overrides_path = @roll.overrides_path
    def saved_path = File.join(@config.workspace, "gui", "rolls", @roll.trip, "#{@roll.rel}.yml")

    def ready? = @convert_only || !@profile.nil?

    # The profile's settings over the toolkit's defaults: what a slider's tick
    # shows and where a reset goes.
    def profile_settings
      return FilmScan::DEFAULTS.dup unless @profile

      FilmScan::DEFAULTS.merge(FilmScan::Profile.load(@profile).settings)
    rescue ArgumentError
      FilmScan::DEFAULTS.dup
    end

    def base(key)
      return FilmScan::DEFAULT_FIXES if key.to_sym == :fix
      return "heic" if key.to_sym == :format
      return 98 if key.to_sym == :quality

      profile_settings[key.to_sym]
    end

    def value(key)
      key = key.to_sym
      return @fix if key == :fix

      @values.key?(key) ? @values[key] : base(key)
    end

    def set(key, value)
      key = key.to_sym
      return @fix = Array(value).map(&:to_sym) if key == :fix

      if value == base(key)
        @values.delete(key)
      else
        @values[key] = value
      end
    end

    def reset
      strength = @values[:match_strength]
      @values.clear
      @values[:match_strength] = strength if strength
      @fix = FilmScan::DEFAULT_FIXES.dup
    end

    def match=(patterns)
      @match = patterns
    end

    # Siblings as --match takes them. sessions.yml keeps them relative to
    # the folder the roll's own path starts from.
    def match_paths
      @match.map { |pattern| File.join(@roll.base, pattern) }
    end

    # The command-line settings, without source or output.
    def setting_args
      args = []
      if @convert_only
        args << "--convert-only"
      else
        args += fix_args
        args += ["--profile", @profile] if @profile
        @values.sort_by { |key, _| key.to_s }.each do |key, value|
          next if %i[format quality bits].include?(key)
          next if key == :match_strength && @match.empty?
          next if key == :look_strength && @match.any?

          args += value_args(key, value)
        end
        match_paths.each { |path| args += ["--match", path] }
      end
      args
    end

    # The full command for a render into out, as the scripts run it.
    def render_args(out, threads: nil, gentle: false, contact_sheet: true)
      args = []
      args += ["--threads", threads.to_s] if threads
      args << "--gentle" if gentle
      args += ["--format", value(:format).to_s, "--quality", value(:quality).to_s]
      args += ["--bits", value(:bits).to_s] if value(:bits)
      args << "--contact-sheet" if contact_sheet
      args += ["--out", out]
      args += setting_args
      args += ["--overrides", overrides_path] if !@convert_only && Overrides.new(overrides_path).any?
      args << @roll.source
      args
    end

    def command_line(out)
      (%w[bundle exec ./bin/filmscan] + render_args(out)).shelljoin
    end

    # What changing these keys costs, given which fixes are on.
    def tier_of(keys, before_fix: @fix)
      keys = keys.map(&:to_sym)
      flat_changed = before_fix.include?(:flat) != @fix.include?(:flat)
      keys = keys.map { |key| key == :fix && !flat_changed ? :recovery : key }
      Schema.tier_of(keys)
    end

    def to_h
      { "profile" => @profile, "convert_only" => @convert_only, "fix" => @fix.map(&:to_s),
        "values" => @values.transform_keys(&:to_s) }
    end

    # Saves the app's choices, and the match into sessions.yml where it
    # differs from what is there.
    def save
      @config.refuse_toolkit!(saved_path, sessions_path)
      FileUtils.mkdir_p(File.dirname(saved_path))
      File.write(saved_path, YAML.dump(to_h.merge("command" => command_line("OUT"))))
      sessions = Sessions.new(sessions_path)
      current = sessions.match_for(@roll.trip, @roll.rel)
      strength = @values[:match_strength]
      changed = current.nil? ? @match.any? : (current.siblings != @match || current.strength&.to_f != strength)
      sessions.set_match(@roll.trip, @roll.rel, siblings: @match, strength: strength) if changed && @match.any?
      self
    end

    private

    def load_saved
      return unless File.exist?(saved_path)

      saved = YAML.safe_load_file(saved_path) || {}
      @profile = saved["profile"] if saved.key?("profile")
      @convert_only = saved["convert_only"] if saved.key?("convert_only")
      @fix = saved["fix"].map(&:to_sym) if saved["fix"]
      session_strength = @values[:match_strength]
      @values = (saved["values"] || {}).transform_keys(&:to_sym)
      @values[:match_strength] = session_strength if session_strength
    end

    def fix_args
      return [] if @fix.empty?
      return ["--fix"] if @fix.sort == FilmScan::DEFAULT_FIXES.sort

      ["--fix", @fix.join(",")]
    end

    def value_args(key, value)
      setting = Schema::BY_KEY[key]
      flag = "--#{key.to_s.tr('_', '-')}"
      case setting&.kind
      when :bool
        key == :crop ? (value ? [flag] : []) : [value ? flag : "--no-#{key.to_s.tr('_', '-')}"]
      else
        value.nil? ? [] : [flag, format_number(value)]
      end
    end

    def format_number(value)
      value.is_a?(Float) ? value.round(4).to_s : value.to_s
    end
  end
end
