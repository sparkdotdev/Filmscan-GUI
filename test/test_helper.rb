require "minitest/autorun"
require "tmpdir"

# Tests touch nothing of the user's: no real settings, no toolkit checkout,
# no Trash and no shared caches. Everything lives under one folder that is
# removed at the end.
TEST_HOME = Dir.mktmpdir("filmscan-gui-tests")
Minitest.after_run { FileUtils.rm_rf(TEST_HOME) }
ENV.delete("FILMSCAN_PATH")
ENV["FILMSCAN_GUI_CONFIG"] = File.join(TEST_HOME, "settings.yml")
ENV["FILMSCAN_TRASH"] = File.join(TEST_HOME, "trash")
ENV["XDG_CACHE_HOME"] = File.join(TEST_HOME, "cache")
require "fileutils"
require "filmscan_gui/config"
require "filmscan_gui/library"
require "filmscan_gui/sessions"
require "filmscan_gui/overrides"
require "filmscan_gui/roll_settings"

module Fixtures
  # A library of empty scan files laid out like the real one.
  def make_library(dir, rolls)
    rolls.each do |rel, stems|
      path = File.join(dir, rel)
      FileUtils.mkdir_p(path)
      stems.each { |stem| FileUtils.touch(File.join(path, "#{stem}.tiff")) }
    end
    dir
  end

  def fixture(name) = File.read(File.join(__dir__, "fixtures", name))

  # A config in dir for a library at library, with a preset and settings.
  # Its toolkit is an empty stand-in in dir unless one is given, so nothing
  # can reach a real checkout.
  def make_config(dir, library, preset: "beside", **settings)
    config = FilmscanGUI::Config.new(File.join(dir, "settings.yml"))
    config.use_preset(preset)
    defaults = { "library" => library, "workspace" => File.join(dir, "ws"), "toolkit" => File.join(dir, "toolkit"),
                 "cache" => File.join(dir, "cache") }
    config.update(defaults.merge(settings.transform_keys(&:to_s)))
  end

  # Fails unless path is inside dir, before a test writes to it.
  def assert_inside(path, dir)
    path = File.expand_path(path)
    dir = File.expand_path(dir)
    assert path.start_with?("#{dir}/"), "#{path} is outside #{dir}; a test may only write inside its own folder"
  end
end
