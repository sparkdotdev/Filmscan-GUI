# A worker process: `ruby main.rb roll` holds one roll for previews, and
# `ruby main.rb utility` makes thumbnails. Messages arrive on stdin and
# answers leave on stdout, so anything the toolkit prints is caught first.
RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable)

require "vips"
require "film_scan"
require "film_scan/cli"
require_relative "../protocol"
require_relative "progress"

out = $stdout.dup
out.binmode
out.sync = true
$stdin.binmode
mutex = Mutex.new
send = lambda do |header, payload = nil|
  mutex.synchronize { FilmscanGUI::Protocol.write(out, header, payload) }
end
$stdout = FilmscanGUI::Worker::Progress.new(send)

case ARGV[0]
when "roll"
  require_relative "roll_engine"
  FilmscanGUI::Worker::RollEngine.new(send).run($stdin)
when "utility"
  require_relative "utility_engine"
  FilmscanGUI::Worker::UtilityEngine.new(send).run($stdin)
else
  abort "which worker? roll or utility"
end
