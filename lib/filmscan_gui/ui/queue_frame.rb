require_relative "widgets"

module FilmscanGUI
  module UI
    # The queue as a table: roll, job, a progress bar, time left and the
    # buttons each row can use.
    class QueueTable < ScrollCanvas
      ROW = 48
      HEADER = 26
      COLUMNS = [["Roll", 0.03], ["Job", 0.30], ["Progress", 0.47], ["Left", 0.69], ["", 0.79]].freeze

      def initialize(parent)
        super(parent, style: Wx::WANTS_CHARS)
        @jobs = []
        @buttons = []
        evt_left_down { |event| click(event) }
      end

      def on_action(&block) = (@on_action = block) && self
      def on_select(&block) = (@on_select = block) && self

      def jobs=(jobs)
        @jobs = jobs
        @selected = nil unless jobs.any? { |j| j.id == @selected }
        @selected ||= (jobs.find { |j| j.status == "running" } || jobs.first)&.id
        self.content_height = HEADER + jobs.size * ROW + 20
        refresh
      end

      def selected = @jobs.find { |j| j.id == @selected }

      private

      def background = Theme.list

      def actions(job)
        case job.status
        when "running" then [["Pause", :pause], ["Stop", :stop]]
        when "paused" then [["Resume", :resume], ["Stop", :stop]]
        when "waiting" then [["Run next", :run_next], ["Remove", :remove]]
        when "done" then [["Review", :review], ["Remove", :remove]]
        else [["Retry", :retry], ["Remove", :remove]]
        end
      end

      def click(event)
        set_focus
        x, y = content_point(event)
        button = @buttons.find { |bx, by, bw, bh, _, _| x.between?(bx, bx + bw) && y.between?(by, by + bh) }
        return @on_action&.call(button[4], button[5]) if button

        index = ((y - HEADER) / ROW).floor
        job = @jobs[index] if index >= 0
        return unless job

        @selected = job.id
        refresh
        @on_select&.call(job)
      end

      def x_of(share, w) = share * w

      def draw(gc, w, _h, top)
        @buttons = []
        if @jobs.empty?
          centred(gc, "Nothing queued. Render a roll from its window.", 0, 0, w, 140, colour: Theme.muted)
          return
        end
        fill(gc, Theme.softer, 0, top, w, HEADER)
        gc.set_pen(Theme.pen(Theme.line))
        gc.stroke_line(0, top + HEADER - 0.5, w, top + HEADER - 0.5)
        COLUMNS.each { |name, share| text(gc, name, x_of(share, w), top + 6, font: Theme.small_strong, colour: Theme.muted) }
        @jobs.each_with_index do |job, i|
          y = HEADER + i * ROW
          row(gc, job, y, w)
        end
      end

      def row(gc, job, y, w)
        fill(gc, Theme.selected_row, 0, y, w, ROW) if job.id == @selected
        gc.set_pen(Theme.pen(Theme.line))
        gc.stroke_line(0, y + ROW - 0.5, w, y + ROW - 0.5)
        mid = y + ROW / 2.0
        done = %w[done].include?(job.status)
        colour = done ? Theme.muted : Theme.text
        mark = { "running" => "▶", "paused" => "‖", "done" => "✓", "failed" => "!", "stopped" => "■" }[job.status]
        text(gc, mark, 10, mid - 8, font: Theme.small, colour: colour) if mark
        name_x = x_of(COLUMNS[0][1], w) + 16
        name = fitted(gc, job.name, x_of(COLUMNS[1][1], w) - name_x - 10, font: job.status == "running" ? Theme.strong : Theme.body)
        text(gc, name, name_x, mid - 15, font: job.status == "running" ? Theme.strong : Theme.body, colour: colour)
        text(gc, fitted(gc, job.trip, x_of(COLUMNS[1][1], w) - name_x - 10, font: Theme.small), name_x, mid + 2,
             font: Theme.small, colour: Theme.muted)
        jx = x_of(COLUMNS[1][1], w)
        text(gc, job.label, jx, mid - 15, font: Theme.small, colour: colour)
        text(gc, fitted(gc, job.message || status_word(job), x_of(COLUMNS[2][1], w) - jx - 10, font: Theme.small), jx, mid + 2,
             font: Theme.small, colour: Theme.muted)
        px = x_of(COLUMNS[2][1], w)
        pw = x_of(COLUMNS[3][1], w) - px - 20
        if %w[running paused].include?(job.status) || (job.done.to_i.positive? && job.status != "waiting")
          share = job.total.to_i.positive? ? job.done.to_f / job.total : 0
          fill(gc, Theme.window, px, mid - 10, pw, 8, 4)
          outline(gc, Theme.line, px + 0.5, mid - 9.5, pw - 1, 7, 3.5)
          fill(gc, Theme.ink, px, mid - 10, [pw * share, 8].max, 8, 4) if share.positive?
          text(gc, fitted(gc, job.phase.to_s, pw, font: Theme.small), px, mid + 2, font: Theme.small, colour: Theme.muted)
        else
          text(gc, job.status == "waiting" ? "waiting" : job.phase.to_s, px, mid - 7, font: Theme.small, colour: Theme.muted)
        end
        left = job.left
        left_text = if left then left > 90 ? "about #{(left / 60).round} min" : "under 2 min"
                    elsif job.status == "done" && job.finished then "done at #{job.finished.strftime('%H:%M')}"
                    else ""
                    end
        text(gc, left_text, x_of(COLUMNS[3][1], w), mid - 7, font: Theme.small, colour: Theme.muted)
        bx = w - 12
        actions(job).reverse_each do |label, action|
          tw, th = measure(gc, label, font: Theme.small)
          bw = tw + 18
          bx -= bw
          by = mid - (th + 8) / 2.0
          primary = action == :review
          fill(gc, primary ? Theme.ink : Theme.window, bx, by, bw, th + 8, 5)
          outline(gc, primary ? Theme.ink : Theme.line, bx + 0.5, by + 0.5, bw - 1, th + 7, 5)
          text(gc, label, bx + 9, by + 4, font: Theme.small, colour: primary ? Theme.on_ink : Theme.text)
          @buttons << [bx, by, bw, th + 8, action, job]
          bx -= 6
        end
      end

      def status_word(job)
        { "waiting" => "Waiting", "running" => "Running", "paused" => "Paused", "done" => "Done",
          "failed" => "Failed", "stopped" => "Stopped" }[job.status]
      end
    end

    # The render queue window.
    class QueueFrame < Wx::Frame
      def initialize(app)
        super(nil, title: "Render queue", size: Theme.fit_size(980, 560))
        @app = app
        @queue = app.queue
        set_min_size([760, 380])
        build
        set_menu_bar(app.menus.build(self))
        @queue.on_change { changed if is_shown }
        evt_close { |event| @app.queue_closed; event.skip }
        changed
        centre
      end

      private

      def build
        root = Wx::Panel.new(self)
        root.set_background_colour(Theme.face)
        column = Wx::VBoxSizer.new
        band = Band.new(root, padding: [8, 14])
        title = Wx::StaticText.new(band, label: "Render queue")
        title.set_font(Theme.title)
        band.add(title, gap: 14)
        band.stretch
        speed = Segmented.new(band, ["Full speed", "Gentle"], selection: @queue.gentle ? 1 : 0)
        speed.on_change do |i|
          @queue.gentle = i == 1
          @queue.settings_changed
        end
        speed.set_tool_tip("Gentle uses half the cores at low priority. It applies to renders started from now on.")
        band.add(speed, gap: 10)
        slots = Wx::Choice.new(band, choices: ["One at a time", "Two at a time"])
        slots.set_selection(@queue.slots == 2 ? 1 : 0)
        slots.evt_choice(slots.get_id) do
          @queue.slots = slots.get_selection + 1
          @queue.settings_changed
        end
        band.add(slots, gap: 10)
        pause = Wx::Button.new(band, label: "Pause after this frame")
        pause.evt_button(pause.get_id) { (job = running) && @queue.pause_after_frame(job) }
        band.add(pause, gap: 10)
        first = Wx::CheckBox.new(band, label: "Previews first")
        first.set_value(@queue.previews_first)
        first.set_tool_tip("Hold the running render while you move a slider, so previews come back quickly.")
        first.evt_checkbox(first.get_id) do
          @queue.previews_first = first.get_value
          @queue.settings_changed
        end
        band.add(first, gap: 0)
        column.add(band, 0, Wx::EXPAND)

        @table = QueueTable.new(root)
        @table.on_action { |action, job| act(action, job) }
        @table.on_select { show_log }
        column.add(@table, 1, Wx::EXPAND)
        @log = Wx::TextCtrl.new(root, size: [-1, 120], style: Wx::TE_MULTILINE | Wx::TE_READONLY | Wx::TE_DONTWRAP)
        @log.set_font(Theme.mono)
        column.add(@log, 0, Wx::EXPAND | Wx::ALL, 10)
        root.set_sizer(column)
      end

      def running = @queue.jobs.find { |job| job.status == "running" }

      def act(action, job)
        case action
        when :pause then @queue.pause(job)
        when :resume then @queue.resume(job)
        when :stop then @queue.stop(job)
        when :run_next then @queue.run_next(job)
        when :remove then @queue.remove(job)
        when :retry then @queue.retry(job)
        when :review
          roll = @app.library.find(job.trip, job.rel)
          @app.open_roll(roll, page: :review_page) if roll
        end
      end

      def changed
        @table.jobs = @queue.jobs
        show_log
      end

      def show_log
        job = @table.selected
        lines = job ? @queue.lines[job.id] : []
        if lines.empty? && job&.log && File.exist?(job.log)
          lines = File.readlines(job.log, chomp: true).last(40)
        end
        text = lines.last(40).join("\n")
        return if text == @log_text

        @log_text = text
        @log.change_value(text)
        @log.show_position(@log.get_last_position)
      end
    end
  end
end
