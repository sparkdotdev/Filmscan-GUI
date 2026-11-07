require "yaml"
require "fileutils"
require "date"

module FilmscanGUI
  # The user's choices: which folder holds the scans, how rolls are laid out
  # in it, where output and the app's own files go, and which toolkit runs
  # the renders. Kept as YAML in the platform's settings folder, or in the
  # file FILMSCAN_GUI_CONFIG names. Nothing about anyone's folders is built
  # in; the presets below are starting points.
  class Config
    # Path templates take {source} (the roll's folder), {trip} (the folder a
    # roll belongs to under the library), {path} (the roll's path inside
    # it), {roll} (its folder name), {id} (the number it starts with, or its
    # name), {date} and {workspace}. A relative result is under the library.
    PRESETS = {
      "beside" => {
        "label" => "Beside each roll",
        "originals" => "",
        "output" => "{source} - corrected",
        "trial" => "{source} - trial",
        "sidefiles" => "",
        "overrides" => "{workspace}/overrides/{trip}/{path}.yml"
      },
      "trips" => {
        "label" => "Trip folders with Original TIFFs",
        "originals" => "Original TIFFs",
        "output" => "{trip}/Corrected HEICs/{path}",
        "trial" => "{trip}/Matched HEICs/{path}",
        "sidefiles" => "{workspace}/renders-{date}/{trip}/{path}",
        "overrides" => "{workspace}/overrides/{id}.yml"
      }
    }.freeze
    LAYOUT_KEYS = %w[originals output trial sidefiles overrides].freeze

    attr_reader :path

    def self.default_path
      return ENV["FILMSCAN_GUI_CONFIG"] if ENV["FILMSCAN_GUI_CONFIG"]

      File.join(settings_dir, "settings.yml")
    end

    def self.settings_dir
      base = if RUBY_PLATFORM.include?("darwin")
               File.expand_path("~/Library/Application Support")
             else
               ENV.fetch("XDG_CONFIG_HOME", File.expand_path("~/.config"))
             end
      File.join(base, "filmscan")
    end

    def initialize(path = Config.default_path)
      @path = path
      @data = File.exist?(path) ? (YAML.safe_load_file(path) || {}) : {}
    end

    # Nil until the user picks a folder.
    def library = @data["library"]
    def configured? = !library.to_s.empty? && File.directory?(library)

    def workspace = @data["workspace"] || File.join(File.dirname(@path), "workspace")
    def sessions_path = @data["sessions"] || File.join(workspace, "sessions.yml")
    def preset = @data["preset"] || "beside"

    def layout(key)
      @data.fetch(key) { PRESETS.fetch(preset, PRESETS["beside"])[key] }.to_s
    end

    # The toolkit checkout renders run from: the setting, FILMSCAN_PATH, or
    # the film_scan gem this app was loaded with.
    def toolkit
      @data["toolkit"] || ENV["FILMSCAN_PATH"] || Gem.loaded_specs["film_scan"]&.full_gem_path
    end

    def [](key) = @data[key.to_s]

    class InsideToolkit < StandardError; end

    # True when a path is the toolkit's checkout or anywhere in it.
    def inside_toolkit?(path)
      root = toolkit
      return false if root.to_s.empty? || path.to_s.empty?

      root = real(File.expand_path(root))
      path = real(File.expand_path(path))
      path == root || path.start_with?("#{root}/")
    end

    # The app drives the toolkit and only reads it; anything it is about to
    # write inside it is refused.
    def refuse_toolkit!(*paths)
      bad = paths.compact.find { |path| inside_toolkit?(path) }
      raise InsideToolkit, "#{bad} is inside the toolkit's folder, which the app never writes to" if bad
    end

    def update(values)
      values.each { |key, value| value.nil? ? @data.delete(key.to_s) : @data[key.to_s] = value }
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, YAML.dump(@data))
      self
    end

    # Applies a preset's layout, dropping any templates set by hand.
    def use_preset(name)
      update(LAYOUT_KEYS.to_h { |key| [key, nil] }.merge("preset" => name))
    end

    # Fills a path template for a roll. Empty templates stay empty.
    def expand(template, roll, date: Date.today)
      return "" if template.to_s.empty?

      text = template.gsub(/\{(\w+)\}/) do
        case Regexp.last_match(1)
        when "source" then roll.source
        when "trip" then roll.trip
        when "path" then roll.rel
        when "roll" then roll.name
        when "id" then roll.id
        when "date" then date.iso8601
        when "workspace" then workspace
        else Regexp.last_match(0)
        end
      end
      path = File.expand_path(text, library)
      path.squeeze("/")
    end

    private

    # The real path of a file, or of its nearest folder that exists.
    def real(path)
      return File.realpath(path) if File.exist?(path)

      parent = File.dirname(path)
      parent == path ? path : File.join(real(parent), File.basename(path))
    end

    public

    # A folder for things that can be made again: thumbnails, decoded HEICs
    # and the roll analyses the previews use.
    def cache_dir
      base = if RUBY_PLATFORM.include?("darwin")
               File.expand_path("~/Library/Caches")
             else
               ENV.fetch("XDG_CACHE_HOME", File.expand_path("~/.cache"))
             end
      @data["cache"] || File.join(base, "filmscan-gui")
    end
  end
end
