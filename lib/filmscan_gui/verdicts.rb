require "yaml"
require "fileutils"
require "time"

module FilmscanGUI
  # What the user called each roll's new render: better, worse or too close
  # to call, a note, and frames flagged for fixing. Kept in the workspace.
  class Verdicts
    CHOICES = %w[better worse close].freeze
    LABELS = { "better" => "Better", "worse" => "Worse", "close" => "Too close to call" }.freeze

    def initialize(workspace)
      @path = File.join(workspace, "gui", "verdicts.yml")
    end

    def all
      return {} unless File.exist?(@path)

      YAML.safe_load_file(@path) || {}
    rescue Psych::Exception
      {}
    end

    def for(roll) = all.fetch(roll.key, {})

    def set(roll, **values)
      data = all
      entry = data.fetch(roll.key, {}).merge(values.transform_keys(&:to_s).compact)
      entry["at"] = Time.now.iso8601
      data[roll.key] = entry
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, YAML.dump(data))
      entry
    end

    def clear(roll)
      data = all
      data.delete(roll.key)
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, YAML.dump(data))
    end
  end
end
