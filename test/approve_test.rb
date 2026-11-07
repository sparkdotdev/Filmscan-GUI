require "test_helper"
require "filmscan_gui/approve"

class ApproveTest < Minitest::Test
  include Fixtures

  def test_the_trial_takes_the_outputs_place
    Dir.mktmpdir do |dir|
      lib = make_library(File.join(dir, "lib"), "Alps 2026/Original TIFFs/10001 Lucky SHD 400" => %w[000001 000002])
      roll = FilmscanGUI::Library.new(make_config(dir, lib, preset: "trips")).find("Alps 2026", "10001 Lucky SHD 400")
      FileUtils.mkdir_p([roll.output_dir, roll.trial_dir])
      %w[000001 000002].each do |stem|
        File.write(File.join(roll.output_dir, "#{stem}.heic"), "old")
        File.write(File.join(roll.trial_dir, "#{stem}.heic"), "new")
      end
      File.write(File.join(roll.trial_dir, "settings.yml"), "new")
      trash = ENV["FILMSCAN_TRASH"]
      before = Dir.exist?(trash) ? Dir.children(trash).size : 0
      log = File.join(dir, "approve.log")

      assert_equal 2, FilmscanGUI::Approve.swap(roll, log)
      assert_equal %w[new new], roll.output.map { |path| File.read(path) }
      assert_equal "new", File.read(File.join(roll.output_dir, "settings.yml"))
      refute Dir.exist?(roll.trial_dir)
      assert_equal before + 2, Dir.children(trash).size
      assert_equal 2, File.readlines(log).grep(/TRASH/).size
      assert_equal 3, File.readlines(log).grep(/MOVE/).size
    end
  end

  def test_never_writes_into_the_toolkit
    Dir.mktmpdir do |dir|
      lib = make_library(File.join(dir, "lib"), "Alps 2026/Original TIFFs/10001 Lucky SHD 400" => %w[000001])
      toolkit = File.join(dir, "toolkit")
      config = make_config(dir, lib, preset: "trips", toolkit: toolkit, output: "#{toolkit}/out/{path}")
      roll = FilmscanGUI::Library.new(config).find("Alps 2026", "10001 Lucky SHD 400")
      FileUtils.mkdir_p(roll.trial_dir)
      File.write(File.join(roll.trial_dir, "000001.heic"), "new")
      assert_raises(FilmscanGUI::Config::InsideToolkit) { FilmscanGUI::Approve.swap(roll, File.join(dir, "log")) }
      refute Dir.exist?(File.join(toolkit, "out"))
      assert File.exist?(File.join(roll.trial_dir, "000001.heic"))
    end
  end
end
