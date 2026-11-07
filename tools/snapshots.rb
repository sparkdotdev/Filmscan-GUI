# Walks through the app on a library and saves what each window shows, for
# checking how it looks without anyone at the screen. Each window captures
# itself; nothing reads the rest of the screen.
#
#   FILMSCAN_GUI_CONFIG=test.yml OUT=dir TRIP=name ROLL=path [RENDER=path] ruby tools/snapshots.rb
#
# RENDER queues a trial render of another roll and reviews it.
#
# wxWidgets reads the command line itself, so the rest comes by environment.
require_relative "../lib/filmscan_gui"

OUT, TRIP, ROLL = ENV.values_at("OUT", "TRIP", "ROLL")
abort "set OUT, TRIP and ROLL" unless OUT && TRIP && ROLL
FileUtils.mkdir_p(OUT)

class SnapshotApp < FilmscanGUI::App
  def on_init
    super
    @steps = []
    script
    @ticker = Wx::Timer.every(400) { advance }
    true
  end

  def step(name, wait: 0.5, ready: -> { true }, &action)
    @steps << { name: name, wait: wait, ready: ready, action: action }
  end

  def capture(window, name)
    bitmap = Wx::WindowDC.new(window).get_as_bitmap
    path = File.join(OUT, "#{name}.png")
    bitmap.save_file(path, Wx::BitmapType::BITMAP_TYPE_PNG)
    puts "saved #{path}"
  end

  def advance
    current = @steps.first
    return finish unless current

    unless @started
      @started = Time.now
      puts "step #{current[:name]}"
    end
    if (Time.now - @started).round % 15 == 14 && roll_frame && @said != (Time.now - @started).round
      @said = (Time.now - @started).round
      puts "  waiting: #{roll_frame.instance_variable_get(:@status)&.get_label}"
    end
    return unless Time.now - @started >= current[:wait] && current[:ready].call

    @steps.shift
    @started = nil
    current[:action]&.call
  rescue StandardError => e
    warn "#{current[:name]}: #{e.class}: #{e.message}\n#{e.backtrace.first(4).join("\n")}"
    @steps.shift
  end

  def finish
    @ticker.stop
    puts "done"
    exit_main_loop
  end

  def roll_frame = @rolls.values.first

  def script
    roll = library.find(TRIP, ROLL) or abort "no roll #{TRIP}/#{ROLL}"
    step("library", wait: 4) { capture(@library_frame, "01-library") }
    step("open") { open_roll(roll).set_size([1440, 920]) }
    step("measured", wait: 2, ready: -> { roll_frame.instance_variable_get(:@measured_at) && !roll_frame.instance_variable_get(:@viewer).instance_variable_get(:@busy) }) do
      capture(roll_frame, "02-frame")
    end
    step("approx") { roll_frame.setting_changed(:contrast, 0.14, true) }
    step("approx shot", wait: 4) { capture(roll_frame, "03-frame-approximate") }
    step("sheet") { roll_frame.command(:sheet_page) }
    step("sheet shot", wait: 30) { capture(roll_frame, "04-sheet") }
    step("frame scope") do
      roll_frame.command(:frame_page)
      roll_frame.scope_changed(:frame)
    end
    step("override") { roll_frame.frame_setting_changed(:keep_warmth, 0.3, true) }
    step("frame scope shot", wait: 4) { capture(roll_frame, "05-frame-scope") }
    step("match") do
      roll_frame.send(:apply_match, ["Lausanne/49614 FujiFilm Superia 400/0000[5-6]*"], 0.5)
    end
    step("match shot", wait: 3) { capture(roll_frame, "05b-rematch") }
    step("review") do
      roll_frame.scope_changed(:roll)
      roll_frame.command(:review_page)
    end
    step("review shot", wait: 6) { capture(roll_frame, "06-review") }
    step("siblings") do
      roll_frame.command(:frame_page)
      @dialog = FilmscanGUI::UI::SiblingDialog.new(roll_frame, self, roll, roll_frame.settings)
      @dialog.show
    end
    step("siblings shot", wait: 4) do
      capture(@dialog, "07-siblings")
      @dialog.destroy
    end
    if (other = ENV["RENDER"] && library.find(TRIP, ENV["RENDER"]))
      step("queue") do
        @job = queue.add(other, :trial)
        show_queue
        @queue_frame.set_size([1000, 560])
      end
      step("queue running", wait: 2, ready: -> { @job.done.to_i >= 2 || %w[failed done].include?(@job.status) }) { capture(@queue_frame, "08-queue-running") }
      step("queue done", ready: -> { %w[done failed].include?(@job.status) }) { capture(@queue_frame, "10-queue-done") }
      step("review trial") do
        @rolls.each_value(&:close)
        open_roll(other, page: :review_page).set_size([1440, 920])
      end
      step("review trial shot", wait: 25) { capture(roll_frame, "11-review-trial") }
      step("review frames") { roll_frame.instance_variable_get(:@review).send(:mode, 1) }
      step("review frames shot", wait: 10) { capture(roll_frame, "12-review-frames") }
      step("review blind") { roll_frame.instance_variable_get(:@review).send(:mode, 2) }
      step("review blind shot", wait: 4) { capture(roll_frame, "13-review-blind") }
    else
      step("queue") { show_queue }
      step("queue shot", wait: 1) { capture(@queue_frame, "08-queue") }
    end
    step("settings") do
      @prefs = FilmscanGUI::UI::Preferences.new(@library_frame, self)
      @prefs.show
    end
    step("settings shot", wait: 2) do
      capture(@prefs, "09-settings")
      @prefs.destroy
    end
  end
end

SnapshotApp.run
