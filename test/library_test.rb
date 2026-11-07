require "test_helper"

class LibraryTest < Minitest::Test
  include Fixtures

  def test_trip_folders_with_an_originals_folder
    Dir.mktmpdir do |dir|
      lib = make_library(File.join(dir, "lib"),
                         "Alps 2026/Original TIFFs/Zurich/10001 Lucky SHD 400" => %w[000001 000002],
                         "Alps 2026/Original TIFFs/10005 Kodak Gold 200" => %w[000001],
                         "Alps 2026/Corrected HEICs/Zurich/10001 Lucky SHD 400" => [],
                         "Old trip/10009" => %w[000001])
      library = FilmscanGUI::Library.new(make_config(dir, lib, preset: "trips"))
      assert_equal ["Alps 2026"], library.trips.map(&:name)
      assert_equal 1, library.others
      assert_equal [nil, "Zurich"], library.trips.first.places.map(&:name)
      roll = library.find("Alps 2026", "Zurich/10001 Lucky SHD 400")
      assert_equal %w[000001 000002], roll.stems
      assert_equal File.join(lib, "Alps 2026/Corrected HEICs/Zurich/10001 Lucky SHD 400"), roll.output_dir
      assert_equal File.join(lib, "Alps 2026/Matched HEICs/Zurich/10001 Lucky SHD 400"), roll.trial_dir
      assert_equal File.join(dir, "ws/overrides/10001.yml"), roll.overrides_path
      assert_match %r{ws/renders-\d{4}-\d\d-\d\d/Alps 2026/Zurich/10001 Lucky SHD 400\z}, roll.sidefiles_dir
    end
  end

  def test_rolls_anywhere_with_renders_beside_them
    Dir.mktmpdir do |dir|
      lib = make_library(File.join(dir, "scans"),
                         "2025/spring/roll-a" => %w[a1 a2],
                         "2025/spring/roll-a - corrected" => %w[a1],
                         "roll-b" => %w[b1],
                         "empty/nothing" => [])
      library = FilmscanGUI::Library.new(make_config(dir, lib))
      assert_equal %w[2025 scans], library.trips.map(&:name)
      roll = library.find("2025", "spring/roll-a")
      assert_equal "spring", roll.place
      assert_equal "#{roll.source} - corrected", roll.output_dir
      assert_equal "#{roll.source} - trial", roll.trial_dir
      assert_nil roll.sidefiles_dir
      assert_equal File.join(dir, "ws/overrides/2025/spring/roll-a.yml"), roll.overrides_path
      assert library.find("scans", "roll-b")
      assert_equal 2, library.rolls.size
    end
  end

  def test_no_library_chosen
    Dir.mktmpdir do |dir|
      config = FilmscanGUI::Config.new(File.join(dir, "settings.yml"))
      refute config.configured?
      assert_empty FilmscanGUI::Library.new(config).trips
    end
  end

  def test_film_guesses
    films = FilmscanGUI::Films
    assert_equal "harman-phoenix-200", films.guess("49605 Ilford Harman Phoenix")
    assert_equal "lomochrome-color-92", films.guess("49601 Lomography Color 92")
    assert_equal "black-and-white", films.guess("50187 Ilford Kentmere 400")
    assert_equal "black-and-white", films.guess("47790 Lomography Lady Grey")
    assert_equal :convert, films.guess("47792 Lomography Negative 800")
    assert_equal :convert, films.guess("49608 FujiFilm Superia 200")
    assert_nil films.guess("51054 Film type Uncatalogued")
    assert_nil films.guess("roll-a")
  end
end
