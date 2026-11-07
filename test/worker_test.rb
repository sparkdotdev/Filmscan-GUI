require "test_helper"
require "filmscan_gui/worker_client"
require "vips"

# Runs a real worker on a tiny roll made here, so it needs libvips but no
# library of scans.
class WorkerTest < Minitest::Test
  include Fixtures

  def setup
    @dir = Dir.mktmpdir
    @roll = File.join(@dir, "lib", "trip", "roll")
    FileUtils.mkdir_p(@roll)
    3.times do |i|
      grad = Vips::Image.xyz(600, 400)[0].cast(:float) / 600 * 200 + 20
      frame = grad.bandjoin([grad * 0.9, grad * 0.6]).cast(:uchar)
      frame.tiffsave(File.join(@roll, format("%06d.tiff", i + 1)))
    end
  end

  def teardown = FileUtils.rm_rf(@dir)

  def test_a_worker_measures_and_renders
    worker = FilmscanGUI::WorkerClient.new("roll")
    worker.send(op: "open", source: @roll, cache: File.join(@dir, "cache"),
                args: ["--fix", "--profile", "lucky-shd-400"], overrides: {})
    frames = worker.wait(30) { |h, _| h[:type] == "frames" }
    assert_equal %w[000001 000002 000003], frames[0][:stems]
    measured = worker.wait(120) { |h, _| h[:type] == "measured" || h[:type] == "error" }
    assert_equal "measured", measured[0][:type], measured[0][:message]
    refute measured[0][:stale]

    worker.send(op: "frame", stem: "000002", gen: 1, scan: true)
    scan = worker.wait(60) { |h, _| h[:type] == "scan" }
    frame = worker.wait(60) { |h, _| h[:type] == "frame" }
    assert_equal [600, 400], [scan[0][:w], scan[0][:h]]
    assert frame[0][:corrected]
    assert_equal 600 * 400 * 3, frame[1].bytesize

    worker.send(op: "settings", args: ["--fix", "--profile", "lucky-shd-400", "--contrast", "0.2"], overrides: {})
    state = worker.wait(30) { |h, _| h[:type] == "state" }
    assert state[0][:stale]
    refute state[0][:remeasure]
    worker.send(op: "settings", args: ["--fix", "--profile", "harman-phoenix-200"], overrides: {})
    assert worker.wait(30) { |h, _| h[:type] == "state" }[0][:remeasure]
  ensure
    worker&.close
  end
end
