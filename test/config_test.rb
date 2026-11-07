require "test_helper"

class ConfigTest < Minitest::Test
  include Fixtures

  def test_tests_never_see_the_real_settings_or_toolkit
    assert_nil ENV["FILMSCAN_PATH"]
    assert ENV["FILMSCAN_GUI_CONFIG"].start_with?(TEST_HOME)
    assert FilmscanGUI::Config.default_path.start_with?(TEST_HOME)
  end

  def test_the_toolkit_setting_wins_and_its_folder_is_off_limits
    Dir.mktmpdir do |dir|
      config = make_config(dir, File.join(dir, "lib"))
      ENV["FILMSCAN_PATH"] = File.join(dir, "elsewhere")
      assert_equal File.join(dir, "toolkit"), config.toolkit
    ensure
      ENV.delete("FILMSCAN_PATH")
    end
  end

  def test_refuses_paths_in_the_toolkit
    Dir.mktmpdir do |dir|
      config = make_config(dir, File.join(dir, "lib"))
      FileUtils.mkdir_p(File.join(dir, "toolkit", "bin"))
      assert config.inside_toolkit?(File.join(dir, "toolkit", "bin", "filmscan"))
      assert config.inside_toolkit?(File.join(dir, "toolkit"))
      refute config.inside_toolkit?(File.join(dir, "toolkit-renders", "x"))
      refute config.inside_toolkit?(File.join(dir, "lib", "x"))
      assert_raises(FilmscanGUI::Config::InsideToolkit) { config.refuse_toolkit!(File.join(dir, "toolkit", "new", "file")) }
    end
  end
end
