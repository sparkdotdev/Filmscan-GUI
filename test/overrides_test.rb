require "test_helper"

class OverridesTest < Minitest::Test
  def test_edits_frames_in_order_and_keeps_comments
    Dir.mktmpdir do |dir|
      path = File.join(dir, "10001.yml")
      File.write(path, <<~YAML)
        # The dusk sequence was picked with the lamps held in full.
        "000053": { lamp_guard: 1.0 }
        "000058": { lamp_guard: 1.0 }
      YAML
      overrides = FilmscanGUI::Overrides.new(path)
      overrides.set("000055", { lamp_guard: 1.0, keep_warmth: 0.3 })
      overrides.set("000058", {})
      text = File.read(path)
      assert_equal ["# The dusk sequence was picked with the lamps held in full.",
                    %("000053": { lamp_guard: 1.0 }),
                    %("000055": { lamp_guard: 1.0, keep_warmth: 0.3 })], text.lines.map(&:chomp)
      assert_equal({ lamp_guard: 1.0, keep_warmth: 0.3 }, overrides.for("000055"))
    end
  end

  def test_an_empty_file_and_updates
    Dir.mktmpdir do |dir|
      path = File.join(dir, "10002.yml")
      File.write(path, "# none after the picks.\n{}\n")
      overrides = FilmscanGUI::Overrides.new(path)
      overrides.update(%w[000002 000001], :keep_warmth, 0.25)
      assert_equal({ "000001" => { keep_warmth: 0.25 }, "000002" => { keep_warmth: 0.25 } }, overrides.all)
      overrides.update(%w[000001], :keep_warmth, nil)
      assert_equal %w[000002], overrides.all.keys
      assert File.read(path).start_with?("# none after the picks.")
    end
  end
end
