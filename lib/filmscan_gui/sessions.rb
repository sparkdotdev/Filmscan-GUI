require "yaml"
require_relative "yaml_lines"

module FilmscanGUI
  # sessions.yml: per trip and place, the rolls to correct, the rolls shot
  # alongside them ("siblings", paths or patterns under the trip's "Original
  # TIFFs"), a roll's own siblings in "siblings_for" and its match strength
  # in "strength". The batch scripts read the same file.
  class Sessions
    Match = Struct.new(:place, :siblings, :strength, keyword_init: true)

    attr_reader :path

    def initialize(path)
      @path = path
    end

    def data
      return {} unless File.exist?(@path)

      YAML.safe_load_file(@path) || {}
    end

    # The siblings and strength for a roll, or nil when it has none.
    def match_for(trip, rel)
      places = data[trip]
      return nil unless places.is_a?(Hash)

      places.each do |place, session|
        next unless session.is_a?(Hash) && Array(session["correct"]).include?(rel)

        own = session.fetch("siblings_for", {})&.[](rel)
        siblings = Array(own || session["siblings"])
        return Match.new(place: place, siblings: siblings, strength: session.fetch("strength", {})&.[](rel))
      end
      nil
    end

    # Records a roll's siblings and strength. A strength of 1 or nil is the
    # default and is left out. Siblings equal to its place's are not repeated.
    def set_match(trip, rel, siblings:, strength:)
      text = File.exist?(@path) ? File.read(@path) : ""
      doc = YamlLines.new(text)
      doc = open_trip(doc, trip)
      place = place_of(doc, trip, rel) || (rel.include?("/") ? rel.split("/").first : trip.split.first)
      doc = ensure_correct(doc, trip, place, rel)

      place_node = -> { doc.find(doc.find(doc.root, trip)[1], place)[1] }
      general = Array(data_of(doc).dig(trip, place, "siblings"))
      if general.empty?
        doc.set(place_node.call, "siblings", block_list("siblings", siblings, doc.indent_of(place_node.call, 4)))
      elsif general == siblings
        drop_entry(doc, place_node, "siblings_for", rel)
      else
        set_entry(doc, place_node, "siblings_for", rel, siblings)
      end

      if strength.nil? || (strength.to_f - 1.0).abs < 1e-9
        drop_entry(doc, place_node, "strength", rel)
      else
        set_entry(doc, place_node, "strength", rel, strength.to_f.round(3))
      end
      File.write(@path, doc.to_s)
      self
    end

    private

    def data_of(doc) = YAML.safe_load(doc.to_s) || {}

    # The trip's mapping, made a block if it was {} and added if missing.
    def open_trip(doc, trip)
      pair = doc.find(doc.root, trip)
      if pair.nil?
        doc.insert(doc.lines.size, ["", "#{YamlLines.scalar(trip)}:"])
      elsif pair[1].is_a?(Psych::Nodes::Mapping) && pair[1].children.empty?
        line = pair[0].start_line
        doc.replace(line..line, [doc.lines[line].sub(/:\s*\{\s*\}/, ":")])
      end
      doc
    end

    def place_of(doc, trip, rel)
      places = data_of(doc)[trip]
      return nil unless places.is_a?(Hash)

      places.find { |_, session| session.is_a?(Hash) && Array(session["correct"]).include?(rel) }&.first
    end

    def ensure_correct(doc, trip, place, rel)
      trip_node = doc.find(doc.root, trip)[1]
      indent = doc.indent_of(trip_node, 2)
      unless doc.find(trip_node, place)
        doc.set(trip_node, place, ["#{' ' * indent}#{YamlLines.scalar(place)}:"])
        trip_node = doc.find(doc.root, trip)[1]
      end
      place_pair = doc.find(trip_node, place)
      session = data_of(doc).dig(trip, place)
      correct = Array(session.is_a?(Hash) ? session["correct"] : nil)
      return doc if correct.include?(rel)

      inner = place_pair[1].is_a?(Psych::Nodes::Mapping) ? doc.indent_of(place_pair[1], indent + 2) : indent + 2
      if place_pair[1].is_a?(Psych::Nodes::Mapping)
        doc.set(place_pair[1], "correct", block_list("correct", correct + [rel], inner))
      else
        line = place_pair[0].start_line
        doc.replace(line..line, [doc.lines[line].sub(/:.*\z/, ":")] + block_list("correct", [rel], inner))
      end
      doc
    end

    def block_list(key, items, indent)
      ["#{' ' * indent}#{key}:"] + items.map { |item| "#{' ' * (indent + 2)}- #{YamlLines.scalar(item)}" }
    end

    # Sets rel under a mapping key of the place, such as strength or
    # siblings_for, adding the key when the place has none.
    def set_entry(doc, place_node, key, rel, value)
      indent = doc.indent_of(place_node.call, 4)
      entry = if value.is_a?(Array)
                ["#{' ' * (indent + 2)}#{YamlLines.scalar(rel)}:"] +
                  value.map { |item| "#{' ' * (indent + 4)}- #{YamlLines.scalar(item)}" }
              else
                ["#{' ' * (indent + 2)}#{YamlLines.scalar(rel)}: #{YamlLines.scalar(value)}"]
              end
      pair = doc.find(place_node.call, key)
      if pair && pair[1].is_a?(Psych::Nodes::Mapping) && !pair[1].children.empty?
        inner = doc.indent_of(pair[1], indent + 2)
        entry = entry.map { |line| line.sub(/\A {#{indent + 2}}/, ' ' * inner) } if inner != indent + 2
        doc.set(pair[1], rel, entry)
      else
        doc.set(place_node.call, key, ["#{' ' * indent}#{key}:"] + entry)
      end
    end

    # Removes rel from a mapping key of the place, and the key once empty.
    def drop_entry(doc, place_node, key, rel)
      pair = doc.find(place_node.call, key)
      return unless pair && pair[1].is_a?(Psych::Nodes::Mapping)

      doc.delete(pair[1], rel)
      pair = doc.find(place_node.call, key)
      doc.delete(place_node.call, key) if pair && doc.pairs(pair[1]).empty?
    end
  end
end
