require "test_helper"

class SessionsTest < Minitest::Test
  include Fixtures

  def with_sessions
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sessions.yml")
      File.write(path, fixture("sessions.yml"))
      yield FilmscanGUI::Sessions.new(path), path
    end
  end

  def test_reads_a_rolls_match
    with_sessions do |sessions|
      own = sessions.match_for("Alps 2026", "Zurich/10002 Ilford Harman Phoenix")
      assert_equal ["Zurich/10010 FujiFilm Superia 200"], own.siblings
      shared = sessions.match_for("Alps 2026", "Zurich/10001 Lucky SHD 400")
      assert_equal 2, shared.siblings.size
      assert_nil shared.strength
      assert_in_delta 0.6, sessions.match_for("Alps 2026", "Lausanne/10003 Ilford Harman Phoenix").strength
      assert_nil sessions.match_for("Coast 2026", "10020 Lucky SHD 400")
    end
  end

  def test_changing_a_strength_keeps_every_comment
    with_sessions do |sessions, path|
      sessions.set_match("Alps 2026", "Lausanne/10003 Ilford Harman Phoenix",
                         siblings: ["Lausanne/10012 FujiFilm Superia 400/0000[5-7]*"], strength: 0.45)
      text = File.read(path)
      fixture("sessions.yml").lines.grep(/#/).each { |comment| assert_includes text, comment.strip }
      assert_in_delta 0.45, sessions.match_for("Alps 2026", "Lausanne/10003 Ilford Harman Phoenix").strength
      assert_equal 1, text.scan("strength:").size
    end
  end

  def test_full_strength_and_shared_siblings_are_left_out
    with_sessions do |sessions, path|
      sessions.set_match("Alps 2026", "Lausanne/10003 Ilford Harman Phoenix",
                         siblings: ["Lausanne/10012 FujiFilm Superia 400/0000[5-7]*"], strength: 1.0)
      refute_includes File.read(path), "strength:"
      sessions.set_match("Alps 2026", "Zurich/10002 Ilford Harman Phoenix",
                         siblings: ["Zurich/10010 FujiFilm Superia 200", "Zurich/10011 FujiFilm Superia 200"], strength: nil)
      refute_includes File.read(path), "siblings_for"
      assert_includes File.read(path), "# A roll listed here is matched to these instead."
      assert_equal 2, sessions.match_for("Alps 2026", "Zurich/10002 Ilford Harman Phoenix").siblings.size
    end
  end

  def test_a_roll_gets_its_own_siblings
    with_sessions do |sessions|
      sessions.set_match("Alps 2026", "Lugano/10004 Ilford Harman Phoenix",
                         siblings: ["Lugano/10013 FujiFilm Superia 400", "Lugano/10014 FujiFilm Superia 400/00000[12]*"],
                         strength: 0.8)
      match = sessions.match_for("Alps 2026", "Lugano/10004 Ilford Harman Phoenix")
      assert_equal 2, match.siblings.size
      assert_in_delta 0.8, match.strength
      assert_equal ["Lugano/10013 FujiFilm Superia 400"], sessions.data.dig("Alps 2026", "Lugano", "siblings")
    end
  end

  def test_a_new_roll_and_an_empty_trip
    with_sessions do |sessions, path|
      sessions.set_match("Coast 2026", "Faro/10020 Lucky SHD 400", siblings: ["Faro/10021 Kodak Gold 200"], strength: 0.7)
      match = sessions.match_for("Coast 2026", "Faro/10020 Lucky SHD 400")
      assert_equal ["Faro/10021 Kodak Gold 200"], match.siblings
      assert_in_delta 0.7, match.strength
      sessions.set_match("New 2026", "10030 Lucky SHD 400", siblings: ["10031 Kodak Gold 200"], strength: nil)
      assert_equal ["10031 Kodak Gold 200"], sessions.match_for("New 2026", "10030 Lucky SHD 400").siblings
      assert_includes File.read(path), "# No colour roll was shot alongside."
    end
  end
end
