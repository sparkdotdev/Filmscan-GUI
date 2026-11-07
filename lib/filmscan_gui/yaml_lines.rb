require "psych"
require "json"

module FilmscanGUI
  # Edits a YAML file a few lines at a time, so the comments the owner wrote
  # around the entries survive. Psych gives each node its lines; an edit
  # replaces or inserts whole lines and parses the text again.
  class YamlLines
    def initialize(text)
      @lines = text.lines.map(&:chomp)
      parse
    end

    def to_s = @lines.empty? ? "" : "#{@lines.join("\n")}\n"
    def root = @root
    def lines = @lines

    # [key node, value node] pairs of a mapping node.
    def pairs(mapping)
      return [] unless mapping.is_a?(Psych::Nodes::Mapping)

      mapping.children.each_slice(2).to_a
    end

    def find(mapping, key)
      pairs(mapping).find { |k, _| k.respond_to?(:value) && k.value == key }
    end

    # The lines a pair covers, up to its last scalar, so the comments that
    # follow it stay with whatever comes next.
    def range(key, value)
      return key.start_line..key.start_line if value.is_a?(Psych::Nodes::Scalar) && value.value.empty?

      key.start_line..[last_line(value), key.start_line].max
    end

    def last_line(node)
      if node.is_a?(Psych::Nodes::Mapping) || node.is_a?(Psych::Nodes::Sequence)
        return node.end_line if node.children.empty? || node.style == Psych::Nodes::Mapping::FLOW

        return last_line(node.children.last)
      end
      last = node.end_column.zero? && node.end_line > node.start_line ? node.end_line - 1 : node.end_line
      # A plain scalar's end can run on over the blank lines after it.
      last -= 1 while last > node.start_line && (@lines[last].to_s.strip.empty? || @lines[last].lstrip.start_with?("#"))
      last
    end

    # Sets key in a block mapping to the given lines (the key's own line
    # first), replacing the pair if it is there and adding it after the last
    # pair if not. An empty flow mapping ({}) is opened into a block first.
    def set(mapping, key, new_lines)
      pair = find(mapping, key)
      if pair
        replace(range(*pair), new_lines)
      else
        last = pairs(mapping).last
        at = last ? range(*last).last : mapping.start_line
        insert(at + 1, new_lines)
      end
    end

    def delete(mapping, key)
      pair = find(mapping, key)
      replace(range(*pair), []) if pair
    end

    # The column a mapping's keys sit at, for lines added to it.
    def indent_of(mapping, fallback)
      first = pairs(mapping).first
      first ? first[0].start_column : fallback
    end

    def replace(range, new_lines)
      @lines[range] = new_lines
      parse
    end

    def insert(at, new_lines)
      @lines.insert(at, *new_lines)
      parse
    end

    # A value as YAML, in flow style inside { } and [ ], quoted where a plain
    # scalar would be read as something else.
    def self.scalar(value, flow: false)
      case value
      when Hash then "{ #{value.map { |k, v| "#{scalar(k.to_s, flow: true)}: #{scalar(v, flow: true)}" }.join(', ')} }"
      when Array then "[#{value.map { |v| scalar(v, flow: true) }.join(', ')}]"
      when Float then value.round(4).to_s
      when Integer, true, false then value.to_s
      when nil then "~"
      else plain?(value.to_s, flow) ? value.to_s : JSON.generate(value.to_s)
      end
    end

    def self.plain?(text, flow)
      return false if text.empty? || text.match?(/\A[-?:,\[\]{}#&*!|>'"%@`\s~]/) || text.match?(/\s\z/)
      return false if text.include?(": ") || text.include?(" #") || text.end_with?(":")
      return false if flow && text.match?(/[\[\]{},]/)
      return false if text.match?(/\A(\d[\d_]*(\.\d*)?|true|false|yes|no|on|off|null|~)\z/i)

      true
    end

    private

    def parse
      document = Psych.parse(to_s.empty? ? "{}\n" : to_s)
      @root = document.is_a?(Psych::Nodes::Document) ? document.root : nil
    end
  end
end
