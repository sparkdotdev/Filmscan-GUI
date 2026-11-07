require "fileutils"

module FilmscanGUI
  # Moves files to the system's Trash, never deleting them outright.
  module Trash
    module_function

    def move(paths)
      paths = Array(paths).select { |path| File.exist?(path) }
      return true if paths.empty?

      # Tests and walk-throughs keep their throwaway files out of the real Trash.
      if (bin = ENV["FILMSCAN_TRASH"])
        FileUtils.mkdir_p(bin)
        paths.each { |path| FileUtils.mv(path, File.join(bin, "#{File.basename(path)}.#{Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)}")) }
        return true
      end
      if File.executable?("/usr/bin/trash")
        system("/usr/bin/trash", *paths, out: File::NULL, err: File::NULL)
      elsif system("which gio", out: File::NULL, err: File::NULL)
        system("gio", "trash", *paths, out: File::NULL, err: File::NULL)
      else
        bin = File.expand_path("~/.local/share/Trash/files")
        FileUtils.mkdir_p(bin)
        paths.each { |path| FileUtils.mv(path, File.join(bin, "#{File.basename(path)}.#{Time.now.to_i}")) }
        true
      end
    end
  end
end
