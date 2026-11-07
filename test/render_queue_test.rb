require "test_helper"
require "filmscan_gui/render_queue"
require "open3"

# Runs the queue against a stand-in for the toolkit that prints what the
# real one prints and writes a file per frame.
class RenderQueueTest < Minitest::Test
  include Fixtures

  FAKE = <<~'RUBY'
    out = ARGV[ARGV.index("--out") + 1]
    source = ARGV.last
    exit 1 if source.include?("broken") && warn("too few pixels to measure a neutral").nil?
    frames = Dir.children(source).sort
    require "fileutils"
    FileUtils.mkdir_p(out)
    puts "sampling roll of #{frames.size} frames..."
    frames.each_with_index { |_, i| print "  sampling #{i + 1}/#{frames.size}" }
    puts
    puts "processing #{frames.size} frames -> #{out}"
    frames.each_with_index do |name, i|
      File.write(File.join(out, name.sub(/\.tiff\z/, ".heic")), "x")
      puts "  [#{i + 1}/#{frames.size}] #{name} -> #{name.sub(/\.tiff\z/, '.heic')}"
    end
    %w[settings.yml roll-fit.yml contact.jpg].each { |side| File.write(File.join(out, side), "x") }
    puts "done"
  RUBY

  def setup
    @dir = Dir.mktmpdir
    lib = make_library(File.join(@dir, "lib"), "Alps 2026/Original TIFFs/Zurich/10001 Lucky SHD 400" => %w[000001 000002 000003],
                                               "Alps 2026/Original TIFFs/Zurich/10009 broken" => %w[000001])
    @toolkit = File.join(@dir, "toolkit")
    FileUtils.mkdir_p(File.join(@toolkit, "bin"))
    stand_in(FAKE)
    @config = make_config(@dir, lib, preset: "trips", toolkit: @toolkit)
    assert_equal @toolkit, @config.toolkit
    @library = FilmscanGUI::Library.new(@config)
  end

  def teardown = FileUtils.rm_rf(@dir)

  # Writes the stand-in toolkit, only ever inside the test's own folder.
  def stand_in(script)
    path = File.join(@toolkit, "bin", "filmscan")
    assert_inside(path, @dir)
    File.write(path, script)
  end

  def run_queue(queue, job)
    deadline = Time.now + 20
    until %w[done failed stopped].include?(job.status) || Time.now > deadline
      queue.tick
      sleep 0.05
    end
  end

  def test_the_bundled_toolkit_runs_with_the_apps_locked_dependencies
    @config.update("toolkit" => Gem.loaded_specs.fetch("film_scan").full_gem_path)
    queue = FilmscanGUI::RenderQueue.new(@config, @library)
    command, dir = queue.send(:command_for, ["--help"])
    stdout, stderr, status = queue.send(:without_bundler) do
      Open3.capture3({ "BUNDLE_FROZEN" => "true" }, *command, chdir: dir)
    end

    assert status.success?, stderr
    assert_includes stdout, "--convert-only"
  end

  def test_a_render_runs_reports_progress_and_files_its_side_files
    roll = @library.find("Alps 2026", "Zurich/10001 Lucky SHD 400")
    queue = FilmscanGUI::RenderQueue.new(@config, @library)
    job = queue.add(roll, :trial)
    run_queue(queue, job)
    assert_equal "done", job.status, job.message
    assert_equal 3, job.done
    assert_equal %w[000001.heic 000002.heic 000003.heic], roll.trial.map { |p| File.basename(p) }
    side = roll.sidefiles_dir
    assert File.exist?(File.join(side, "settings.yml"))
    assert File.exist?(File.join(side, "run.log"))
    refute File.exist?(File.join(roll.trial_dir, "settings.yml"))
    again = FilmscanGUI::RenderQueue.new(@config, @library)
    assert_equal "done", again.jobs.first.status
  end

  def test_a_failed_render_says_why
    roll = @library.find("Alps 2026", "Zurich/10009 broken")
    queue = FilmscanGUI::RenderQueue.new(@config, @library)
    job = queue.add(roll, :final)
    run_queue(queue, job)
    assert_equal "failed", job.status
    assert_equal "too few pixels to measure a neutral", job.message
  end

  def test_previews_first_holds_a_render_and_lets_it_go
    roll = @library.find("Alps 2026", "Zurich/10001 Lucky SHD 400")
    stand_in("sleep 30\n")
    queue = FilmscanGUI::RenderQueue.new(@config, @library)
    job = queue.add(roll, :trial)
    queue.tick
    pid = queue.instance_variable_get(:@running)[job.id][:pid]
    queue.preview_activity
    sleep 0.3
    assert_equal "T", `ps -o stat= -p #{pid}`.strip[0], "held while a slider moves"
    queue.instance_variable_set(:@last_preview, Time.now - 10)
    queue.tick
    sleep 0.3
    refute_equal "T", `ps -o stat= -p #{pid}`.strip[0], "let go once the slider rests"
  ensure
    queue&.shutdown
  end

  def test_a_render_aimed_into_the_toolkit_is_refused
    config = make_config(@dir, @config.library, preset: "trips", toolkit: @toolkit, output: "#{@toolkit}/out/{path}")
    library = FilmscanGUI::Library.new(config)
    queue = FilmscanGUI::RenderQueue.new(config, library)
    job = queue.add(library.find("Alps 2026", "Zurich/10001 Lucky SHD 400"), :final)
    queue.tick
    assert_equal "failed", job.status
    assert_match(/inside the toolkit/, job.message)
    refute Dir.exist?(File.join(@toolkit, "out"))
  end

  def test_waiting_jobs_can_jump_the_line
    queue = FilmscanGUI::RenderQueue.new(@config, @library)
    queue.slots = 0
    a = queue.add(@library.find("Alps 2026", "Zurich/10001 Lucky SHD 400"), :trial)
    b = queue.add(@library.find("Alps 2026", "Zurich/10009 broken"), :trial)
    queue.run_next(b)
    assert_equal [b, a], queue.jobs
    queue.remove(a)
    assert_equal [b], queue.jobs
  end
end
