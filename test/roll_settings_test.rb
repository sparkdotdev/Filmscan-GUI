require "test_helper"

class RollSettingsTest < Minitest::Test
  include Fixtures

  def setup
    @dir = Dir.mktmpdir
    @library = File.join(@dir, "lib")
    @workspace = File.join(@dir, "ws")
    make_library(@library, "Alps 2026/Original TIFFs/Lausanne/10003 Ilford Harman Phoenix" => %w[000001],
                           "Alps 2026/Original TIFFs/Lausanne/10012 FujiFilm Superia 400" => %w[000050])
    FileUtils.mkdir_p(@workspace)
    File.write(File.join(@workspace, "sessions.yml"), fixture("sessions.yml"))
    config = make_config(@dir, @library, preset: "trips")
    @roll = FilmscanGUI::Library.new(config).find("Alps 2026", "Lausanne/10003 Ilford Harman Phoenix")
  end

  def teardown = FileUtils.rm_rf(@dir)

  def test_reads_profile_and_match_and_builds_the_scripts_command
    settings = FilmscanGUI::RollSettings.new(@roll)
    assert_equal "harman-phoenix-200", settings.profile
    assert_in_delta 0.6, settings.value(:match_strength)
    out = "/out/10003"
    args = settings.render_args(out)
    sibling = File.join(@roll.base, "Lausanne/10012 FujiFilm Superia 400/0000[5-7]*")
    assert_equal ["--format", "heic", "--quality", "98", "--contact-sheet", "--out", out, "--fix",
                  "--profile", "harman-phoenix-200", "--match-strength", "0.6", "--match", sibling, @roll.source], args
  end

  def test_values_equal_to_the_profile_are_dropped
    settings = FilmscanGUI::RollSettings.new(@roll)
    settings.set(:contrast, 0.12)
    settings.set(:frame_balance, settings.base(:frame_balance))
    assert_equal({ match_strength: 0.6, contrast: 0.12 }, settings.values)
    assert_includes settings.setting_args.each_cons(2).to_a, ["--contrast", "0.12"]
    settings.set(:sky_neutral, true)
    assert_includes settings.setting_args, "--sky-neutral"
  end

  def test_costs
    settings = FilmscanGUI::RollSettings.new(@roll)
    assert_equal :live, settings.tier_of(%i[match_strength roll_tone])
    assert_equal :approx, settings.tier_of(%i[match_strength contrast])
    before = settings.fix.dup
    settings.fix = before - [:sharpen]
    assert_equal :approx, settings.tier_of(%i[fix], before_fix: before)
    settings.fix = before - [:flat]
    assert_equal :remeasure, settings.tier_of(%i[fix], before_fix: before)
  end

  def test_save_and_load_and_sessions
    settings = FilmscanGUI::RollSettings.new(@roll)
    settings.set(:contrast, 0.12)
    settings.set(:match_strength, 0.45)
    settings.save
    again = FilmscanGUI::RollSettings.new(@roll)
    assert_in_delta 0.12, again.value(:contrast)
    assert_in_delta 0.45, again.value(:match_strength)
    assert_includes File.read(File.join(@workspace, "sessions.yml")), "# Paler sky, so less of the match."
  end
end
