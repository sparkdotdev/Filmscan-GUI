require "fileutils"
require "time"
require_relative "trash"

module FilmscanGUI
  # Puts a roll's trial render in place of its output: the old files go to
  # the Trash, the new ones move in, side files travel with their frames,
  # and every move is logged. Stops at the first thing that fails.
  module Approve
    SIDE = %w[settings.yml roll-fit.yml contact.jpg match-reference.yml run.log].freeze

    module_function

    # Returns the number of frames moved in.
    def swap(roll, log)
      incoming = roll.trial
      raise ArgumentError, "there is no trial render to approve" if incoming.empty?

      roll.config.refuse_toolkit!(roll.output_dir, roll.trial_dir, log)
      outgoing = roll.output
      side = SIDE.map { |name| File.join(roll.trial_dir, name) }.select { |path| File.exist?(path) }
      replaced = side.map { |path| File.join(roll.output_dir, File.basename(path)) }.select { |path| File.exist?(path) }
      FileUtils.mkdir_p(File.dirname(log))
      File.open(log, "a") do |file|
        stamp = Time.now.iso8601
        raise "the Trash refused the old files" unless Trash.move(outgoing + replaced)

        (outgoing + replaced).each { |path| file.puts("#{stamp} TRASH #{path}") }
        FileUtils.mkdir_p(roll.output_dir)
        (incoming + side).each do |path|
          dest = File.join(roll.output_dir, File.basename(path))
          FileUtils.mv(path, dest)
          file.puts("#{stamp} MOVE #{path} -> #{dest}")
        end
      end
      Dir.rmdir(roll.trial_dir) if Dir.exist?(roll.trial_dir) && Dir.empty?(roll.trial_dir)
      incoming.size
    end
  end
end
