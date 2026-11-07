module FilmscanGUI
  # Turns frames picked from a roll into the glob --match takes, as short
  # as it can be: frames 50 to 71 of a roll that ends at 71 are
  # "0000[5-7]*". The glob matches exactly the frames picked.
  module FramePattern
    module_function

    def for(stems, picked)
      picked = picked & stems
      return nil if picked.empty?
      return "*" if picked.size == stems.size

      prefixes = picked.map { |stem| shortest(stems, picked, stem) }.uniq.sort
      parts = prefixes.group_by { |p| [p.size, p[0...-1]] }.map do |(_, head), group|
        group.size == 1 ? group.first : "#{head}#{char_class(group.map { |p| p[-1] })}"
      end
      parts.size == 1 ? "#{parts.first}*" : "{#{parts.map { |p| "#{p}*" }.join(',')}}"
    end

    def matches(stems, pattern)
      stems.select { |stem| File.fnmatch(pattern, "#{stem}.tiff", File::FNM_EXTGLOB) }
    end

    # The shortest start of a stem that only picked frames share.
    def shortest(stems, picked, stem)
      (1..stem.size).each do |n|
        head = stem[0, n]
        return head if stems.all? { |s| !s.start_with?(head) || picked.include?(s) }
      end
      stem
    end

    def char_class(chars)
      chars = chars.uniq.sort
      runs = chars.slice_when { |a, b| b.ord != a.ord + 1 }.map { |run| run.size > 2 ? "#{run.first}-#{run.last}" : run.join }
      "[#{runs.join}]"
    end
  end
end
