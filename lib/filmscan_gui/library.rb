require "date"

module FilmscanGUI
  # The scans on disk. A roll is any folder of scan images under the library
  # folder. With an originals folder name set (such as "Original TIFFs"),
  # rolls are looked for inside that folder of each top-level folder;
  # without one, anywhere under the library. Either way a roll belongs to a
  # trip, the top-level folder it is under, and sits at a path inside it.
  class Library
    SCANS = /\.(tiff?|jpe?g|png)\z/i
    OUTPUT = /\.(heic|heif|tiff?|jpe?g|png|jp2)\z/i
    DEPTH = 5

    Trip = Struct.new(:name, :places, keyword_init: true) do
      def rolls = places.flat_map(&:rolls)
    end

    # The folder a roll sits in inside its trip, or nil for the trip itself.
    Place = Struct.new(:name, :rolls, keyword_init: true)

    attr_reader :config

    def initialize(config)
      @config = config
    end

    def root = @config.library
    def exist? = !root.to_s.empty? && File.directory?(root)

    def trips
      @trips ||= read
    end

    # Top-level folders without the originals folder, which hold no rolls.
    def others
      trips
      @others
    end

    def rolls = trips.flat_map(&:rolls)

    def find(trip, rel)
      rolls.find { |roll| roll.trip == trip && roll.rel == rel }
    end

    def reload
      @trips = nil
      self
    end

    private

    def read
      @others = 0
      return [] unless exist?

      rolls = []
      originals = @config.layout("originals")
      if originals.empty?
        folders_with_scans(root, DEPTH).each do |dir|
          parts = dir.delete_prefix("#{root}/").split("/")
          trip, base = parts.size == 1 ? [File.basename(root), root] : [parts.first, File.join(root, parts.first)]
          rolls << Roll.new(self, trip, base, dir.delete_prefix("#{base}/"))
        end
      else
        subfolders(root).each do |top|
          base = File.join(top, originals)
          next @others += 1 unless File.directory?(base)

          folders_with_scans(base, DEPTH - 1).each do |dir|
            rolls << Roll.new(self, File.basename(top), base, dir.delete_prefix("#{base}/"))
          end
        end
      end
      # A render written beside its roll looks like a roll of its own.
      made = rolls.flat_map { |roll| [roll.output_dir, roll.trial_dir] }.to_set
      rolls.reject! { |roll| made.include?(roll.source) }
      rolls.group_by(&:trip).sort.map do |trip, trip_rolls|
        places = trip_rolls.group_by(&:place).sort_by { |place, _| place.to_s }
                           .map { |place, place_rolls| Place.new(name: place, rolls: place_rolls.sort_by(&:rel)) }
        Trip.new(name: trip, places: places)
      end
    end

    def folders_with_scans(dir, depth)
      return [] if depth.negative?
      return [dir] if scans_in?(dir)

      subfolders(dir).flat_map { |sub| folders_with_scans(sub, depth - 1) }
    end

    def subfolders(dir)
      Dir.children(dir).reject { |name| name.start_with?(".") }.sort
         .map { |name| File.join(dir, name) }.select { |path| File.directory?(path) }
    rescue SystemCallError
      []
    end

    def scans_in?(dir)
      Dir.children(dir).any? { |name| name.match?(SCANS) }
    rescue SystemCallError
      false
    end
  end

  # One roll: its scans, the film its name suggests and where its output goes.
  class Roll
    attr_reader :library, :trip, :base, :rel

    def initialize(library, trip, base, rel)
      @library = library
      @trip = trip
      @base = base
      @rel = rel
    end

    def config = @library.config
    def name = File.basename(@rel)
    def place = File.dirname(@rel) == "." ? nil : File.dirname(@rel)

    # The number a lab roll name starts with, or the whole name.
    def id = name[/\A\d+/] || name

    def source = File.join(@base, @rel)
    def key = "#{@trip}/#{@rel}"
    def output_dir = config.expand(config.layout("output"), self)
    def trial_dir = config.expand(config.layout("trial"), self)
    def overrides_path = config.expand(config.layout("overrides"), self)

    # Side files of a render (settings, fits, contact sheet, log) go here,
    # or stay with the output when the layout names no place.
    def sidefiles_dir(date = Date.today)
      template = config.layout("sidefiles")
      template.empty? ? nil : config.expand(template, self, date: date)
    end

    def frames
      @frames ||= Dir.children(source).select { |file| file.match?(Library::SCANS) }.sort.map { |file| File.join(source, file) }
    end

    def stems = frames.map { |path| File.basename(path, ".*") }
    def output = images_in(output_dir)
    def trial = images_in(trial_dir)

    # The profile the folder name points to, :convert for a stock labs scan
    # well, or nil when the name says nothing. Only ever a suggestion.
    def film = Films.guess(name)

    def ==(other) = other.is_a?(Roll) && other.key == key
    alias eql? ==
    def hash = key.hash

    private

    def images_in(dir)
      return [] unless File.directory?(dir)

      Dir.children(dir).select { |file| file.match?(Library::OUTPUT) }.sort.map { |file| File.join(dir, file) }
    end
  end

  module Films
    # Checked in order, so a black and white Ilford never reads as Phoenix.
    GUESSES = [
      [/phoenix/i, "harman-phoenix-200"],
      [/lucky\s*shd/i, "lucky-shd-400"],
      [/(lomochrome|lomography)\s*colou?r\s*'?92/i, "lomochrome-color-92"],
      [/kentmere|hp5|fp4|delta|lady grey|foma|tri-?x|t-?max|pan\s*\d+|b&w|black and white/i, "black-and-white"],
      [/superia|fuji|kodak|portra|ektar|ultramax|gold|colorplus|cinestill|lomography negative/i, :convert]
    ].freeze

    module_function

    def guess(name)
      GUESSES.find { |pattern, _| name.match?(pattern) }&.last
    end
  end
end
