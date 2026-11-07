require_relative "library"

module FilmscanGUI
  # Words and frames for a roll's siblings: the summary on the roll's
  # toolbar, the frames a pattern picks, and the sibling frame to show
  # beside a given frame.
  module MatchSummary
    module_function

    # [[roll folder, its frames the patterns pick, all its frames]], with a
    # roll's patterns joined.
    def rolls(roll, settings)
      settings.match_paths.each_with_object({}) do |pattern, found|
        dir, frames = if File.directory?(pattern)
                        [pattern, images_in(pattern)]
                      else
                        [File.dirname(pattern), Dir.glob(pattern).select { |p| p.match?(Library::SCANS) }.sort]
                      end
        entry = (found[dir] ||= [[], images_in(dir)])
        entry[0] |= frames
      end.map { |dir, (picked, all)| [dir, picked.sort, all] }
    end

    def describe(roll, settings)
      return "Not corrected, so not matched" if settings.convert_only
      return "No siblings" if settings.match.empty?

      found = rolls(roll, settings)
      dir, picked, all = found.first
      parts = [File.basename(dir)]
      parts << frames_text(picked) if picked.size < all.size && picked.any?
      parts << "#{(settings.value(:match_strength).to_f * 100).round}%"
      text = parts.join(", ")
      found.size > 1 ? "#{text}, and #{found.size - 1} more" : text
    end

    def frames_text(paths)
      numbers = paths.map { |p| File.basename(p, ".*").sub(/\A0+(?=.)/, "") }
      return "frame #{numbers.first}" if numbers.size == 1

      "frames #{numbers.first} to #{numbers.last}"
    end

    # The sibling frame at the same point in its roll, preferring the
    # sibling's own converted output when there is one.
    def nearest_sibling(roll, settings, stem)
      found = rolls(roll, settings)
      return nil if found.empty? || !roll.stems.include?(stem)

      dir, picked, = found.first
      return nil if picked.empty?

      share = roll.stems.index(stem) / [roll.stems.size - 1, 1].max.to_f
      frame = picked[(share * (picked.size - 1)).round]
      sibling = Roll.new(roll.library, roll.trip, roll.base, dir.delete_prefix("#{roll.base}/"))
      output = sibling.output.find { |path| File.basename(path, ".*") == File.basename(frame, ".*") }
      output || frame
    end

    def images_in(dir)
      return [] unless File.directory?(dir)

      Dir.children(dir).select { |name| name.match?(Library::SCANS) }.sort.map { |name| File.join(dir, name) }
    end
  end
end
