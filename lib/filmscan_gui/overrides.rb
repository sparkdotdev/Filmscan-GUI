require "yaml"
require "fileutils"
require_relative "yaml_lines"

module FilmscanGUI
  # A roll's per-frame settings, as --overrides reads them: frame name to
  # settings, one line per frame in flow style. Entries are kept in frame
  # order and the file's comments stay where they are.
  class Overrides
    attr_reader :path

    def initialize(path)
      @path = path
    end

    def all
      return {} unless File.exist?(@path)

      raw = YAML.safe_load_file(@path) || {}
      raw.to_h { |stem, settings| [stem.to_s, (settings || {}).transform_keys { |k| k.to_s.tr("-", "_").to_sym }] }
    end

    def for(stem) = all.fetch(stem, {})
    def any? = all.any? { |_, settings| !settings.empty? }

    # Replaces a frame's settings. An empty hash removes the frame.
    def set(stem, settings)
      doc = YamlLines.new(File.exist?(@path) ? File.read(@path) : "")
      doc = open_root(doc)
      root = doc.root
      if settings.empty?
        doc.delete(root, stem) if root.is_a?(Psych::Nodes::Mapping)
      else
        line = "#{YamlLines.scalar(stem)}: #{YamlLines.scalar(settings.transform_keys(&:to_s))}"
        pair = doc.find(root, stem)
        if pair
          doc.replace(doc.range(*pair), [line])
        else
          after = doc.pairs(root).find { |key, _| key.value.to_s > stem }
          doc.insert(after ? after[0].start_line : doc.lines.size, [line])
        end
      end
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, doc.to_s)
      self
    end

    # Sets one setting on several frames, or clears it with nil.
    def update(stems, key, value)
      current = all
      stems.each do |stem|
        settings = current.fetch(stem, {}).dup
        value.nil? ? settings.delete(key.to_sym) : settings[key.to_sym] = value
        set(stem, settings)
      end
      self
    end

    private

    # An empty file reads "{}"; that line goes so entries can follow.
    def open_root(doc)
      root = doc.root
      return doc unless root.is_a?(Psych::Nodes::Mapping) && root.children.empty? && root.style == Psych::Nodes::Mapping::FLOW

      doc.replace(root.start_line..root.end_line, []) if doc.lines[root.start_line].to_s.strip == "{}"
      doc
    end
  end
end
