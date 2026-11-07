require "test_helper"
require "filmscan_gui/frame_pattern"

class FramePatternTest < Minitest::Test
  STEMS = (%w[000001] + (37..71).map { |n| format("%06d", n) }).freeze

  def check(picked)
    pattern = FilmscanGUI::FramePattern.for(STEMS, picked)
    assert_equal picked.sort, FilmscanGUI::FramePattern.matches(STEMS, pattern), pattern
    pattern
  end

  def test_the_city_shots
    assert_equal "0000[5-7]*", check((50..71).map { |n| format("%06d", n) })
  end

  def test_whole_roll_one_frame_and_scattered
    assert_equal "*", FilmscanGUI::FramePattern.for(STEMS, STEMS)
    assert_equal "000040*", check(%w[000040])
    check(%w[000001 000038 000039 000061])
    check((37..49).map { |n| format("%06d", n) })
  end
end
