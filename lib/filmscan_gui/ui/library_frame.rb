require_relative "widgets"
require_relative "filmstrip"
require_relative "../roll_settings"
require_relative "../match_summary"
require_relative "../verdicts"

module FilmscanGUI
  module UI
    # Trips and the places inside them, with how many rolls each holds.
    class Sidebar < ScrollCanvas
      ROW = 26

      def initialize(parent)
        super(parent)
        @items = []
        @selected = 0
        set_min_size([220, 200])
        evt_left_down { |event| click(event) }
      end

      def on_select(&block) = (@on_select = block) && self

      def library=(library)
        @root = library.root
        @items = library.trips.flat_map do |trip|
          [[:trip, trip, nil]] + trip.places.select(&:name).map { |place| [:place, trip, place] }
        end
        @selected = @selected.clamp(0, [@items.size - 1, 0].max)
        @others = library.others
        self.content_height = 54 + @items.size * ROW + 40
        refresh
      end

      def selection = @items[@selected]

      private

      def background = Theme.softer

      def click(event)
        _, y = content_point(event)
        index = ((y - 50) / ROW).floor
        return unless index.between?(0, @items.size - 1)

        @selected = index
        refresh
        @on_select&.call(@items[index])
      end

      def draw(gc, w, _h, _top)
        text(gc, "Library", 14, 12, font: Theme.small_strong, colour: Theme.muted)
        root = @root ? fitted(gc, File.basename(@root), w - 28, font: Theme.small) : "No folder chosen"
        text(gc, root, 14, 28, font: Theme.small, colour: Theme.muted)
        @items.each_with_index do |(kind, trip, place), i|
          y = 50 + i * ROW
          selected = i == @selected
          fill(gc, Theme.ink, 8, y, w - 16, ROW - 2, 6) if selected
          colour = selected ? Theme.on_ink : Theme.text
          indent = kind == :trip ? 16 : 32
          name = kind == :trip ? trip.name : place.name
          count = (kind == :trip ? trip.rolls : place.rolls).size.to_s
          cw, = measure(gc, count, font: Theme.small)
          font = kind == :trip ? Theme.strong : Theme.body
          label = fitted(gc, name, w - indent - cw - 30, font: font)
          _, th = measure(gc, label, font: font)
          text(gc, label, indent, y + (ROW - 2 - th) / 2.0, font: font, colour: colour)
          _, ch = measure(gc, count, font: Theme.small)
          text(gc, count, w - 18 - cw, y + (ROW - 2 - ch) / 2.0, font: Theme.small, colour: selected ? Theme.on_ink : Theme.muted)
        end
        return unless @others.to_i.positive?

        y = 58 + @items.size * ROW
        text(gc, "#{@others} more folders without rolls in this layout", 14, y, font: Theme.tiny, colour: Theme.muted)
      end
    end

    # The rolls of a trip or place: frames, film, status and siblings, in a
    # table grouped by place. Double click or Return opens a roll.
    class RollTable < ScrollCanvas
      ROW = 56
      HEADER = 26
      GROUP = 30
      COLUMNS = [["Frames", 0.0], ["Roll", 0.22], ["Film", 0.47], ["Status", 0.64], ["Siblings", 0.80]].freeze

      def initialize(parent, app)
        super(parent, style: Wx::WANTS_CHARS)
        @app = app
        @lines = []
        @thumbs = {}
        evt_left_down { |event| click(event) }
        evt_left_dclick { |_| open }
        evt_key_down { |event| key(event) }
      end

      def on_open(&block) = (@on_open = block) && self

      # Lines are [:group, name] or [:roll, row hash].
      def lines=(lines)
        kept = selected_roll
        @lines = lines
        @selected = (kept && @lines.index { |kind, data| kind == :roll && data[:roll] == kept }) ||
                    @lines.index { |kind, _| kind == :roll }
        self.content_height = HEADER + @lines.sum { |kind, _| kind == :group ? GROUP : ROW } + 20
        refresh
      end

      def empty_message=(text)
        @empty = text
        refresh
      end

      def thumb_arrived(path, image)
        @thumbs[path] = Wx::Bitmap.new(image)
        refresh
      end

      def selected_roll = @selected && @lines[@selected][1][:roll]

      private

      def background = Theme.list

      def tops
        y = HEADER
        @lines.map do |kind, _|
          top = y
          y += kind == :group ? GROUP : ROW
          top
        end
      end

      def click(event)
        set_focus
        _, y = content_point(event)
        tops.each_with_index do |top, i|
          span = @lines[i][0] == :group ? GROUP : ROW
          next unless y.between?(top, top + span) && @lines[i][0] == :roll

          @selected = i
          refresh
        end
      end

      def key(event)
        rows = @lines.each_index.select { |i| @lines[i][0] == :roll }
        at = rows.index(@selected) || 0
        case event.get_key_code
        when Wx::K_UP then @selected = rows[[at - 1, 0].max]
        when Wx::K_DOWN then @selected = rows[[at + 1, rows.size - 1].min]
        when Wx::K_RETURN, Wx::K_NUMPAD_ENTER then return open
        else return event.skip
        end
        top = tops[@selected]
        reveal(top, top + ROW) if top
        refresh
      end

      def open
        roll = selected_roll
        @on_open&.call(roll) if roll
      end

      def x_of(share, w) = 14 + share * (w - 28)

      def draw(gc, w, _h, top)
        if @lines.empty?
          centred(gc, @empty || "No rolls here", 0, 0, w, 160, font: Theme.body, colour: Theme.muted)
          return
        end
        fill(gc, Theme.softer, 0, top, w, HEADER)
        gc.set_pen(Theme.pen(Theme.line))
        gc.stroke_line(0, top + HEADER - 0.5, w, top + HEADER - 0.5)
        COLUMNS.each { |name, share| text(gc, name, x_of(share, w), top + 6, font: Theme.small_strong, colour: Theme.muted) }
        gc.push_state
        gc.clip(0, top + HEADER, w, height - HEADER)
        tops.each_with_index do |y, i|
          kind, data = @lines[i]
          span = kind == :group ? GROUP : ROW
          next if y + span < top || y > top + height

          kind == :group ? group(gc, data, y, w) : row(gc, data, y, w, i == @selected)
        end
        gc.pop_state
      end

      def group(gc, name, y, w)
        fill(gc, Theme.softer, 0, y, w, GROUP)
        _, th = measure(gc, name, font: Theme.strong)
        text(gc, name, 14, y + (GROUP - th) / 2.0, font: Theme.strong)
        gc.set_pen(Theme.pen(Theme.line))
        gc.stroke_line(0, y + GROUP - 0.5, w, y + GROUP - 0.5)
      end

      def row(gc, data, y, w, selected)
        fill(gc, Theme.selected_row, 0, y, w, ROW) if selected
        gc.set_pen(Theme.pen(Theme.line))
        gc.stroke_line(14, y + ROW - 0.5, w, y + ROW - 0.5)
        x = x_of(0, w)
        room = x_of(COLUMNS[1][1], w) - x - 14
        box = [[(room - 4 * 4) / 5.0, 44].min, 18].max
        data[:thumbs].each do |path|
          break if x + box > x_of(COLUMNS[1][1], w) - 10

          bitmap = @thumbs[path]
          if bitmap
            rect = picture(gc, bitmap, x, y + 9, box, ROW - 18)
            x = rect[0] + rect[2] + 4
          else
            placeholder(gc, x, y + 15, box * 0.86, ROW - 30)
            x += box * 0.86 + 4
          end
        end
        mid = y + ROW / 2.0
        roll_x = x_of(COLUMNS[1][1], w)
        film_x = x_of(COLUMNS[2][1], w)
        status_x = x_of(COLUMNS[3][1], w)
        sib_x = x_of(COLUMNS[4][1], w)
        name = fitted(gc, data[:roll].name, film_x - roll_x - 12, font: data[:muted] ? Theme.body : Theme.strong)
        _, th = measure(gc, name)
        text(gc, name, roll_x, mid - th / 2.0 - (data[:detail] ? 7 : 0), font: data[:muted] ? Theme.body : Theme.strong,
                                                                        colour: data[:muted] ? Theme.muted : Theme.text)
        if data[:detail]
          text(gc, fitted(gc, data[:detail], film_x - roll_x - 12, font: Theme.small), roll_x, mid + 2, font: Theme.small, colour: Theme.muted)
        end
        film = fitted(gc, data[:film], status_x - film_x - 12, font: Theme.small)
        _, fh = measure(gc, film, font: Theme.small)
        text(gc, film, film_x, mid - fh / 2.0, font: Theme.small, colour: data[:muted] ? Theme.muted : Theme.text)
        chip(gc, fitted(gc, data[:status], sib_x - status_x - 30, font: Theme.small), status_x, mid - 10, solid: data[:status_solid])
        sib = fitted(gc, data[:siblings], w - sib_x - 14, font: Theme.small)
        _, sh = measure(gc, sib, font: Theme.small)
        text(gc, sib, sib_x, mid - sh / 2.0, font: Theme.small, colour: Theme.muted)
      end
    end

    # The library: trips on the left, their rolls on the right.
    class LibraryFrame < Wx::Frame
      FILTERS = %w[All To\ review Not\ rendered].freeze

      def initialize(app)
        super(nil, title: "Library", size: Theme.fit_size(1240, 760))
        @app = app
        @verdicts = Verdicts.new(app.config.workspace)
        set_min_size([900, 520])
        build
        set_menu_bar(app.menus.build(self))
        app.queue.on_change { queue_changed }
        evt_close { |event| closing(event) }
        evt_activate { |event| reload_table if event.get_active; event.skip }
        reload
        centre
      end

      def reload
        @verdicts = Verdicts.new(@app.config.workspace)
        @sidebar.library = @app.library
        reload_table
        queue_changed
      end

      private

      def build
        root = Wx::Panel.new(self)
        root.set_background_colour(Theme.face)
        column = Wx::VBoxSizer.new
        band = Band.new(root, padding: [8, 14])
        title = Wx::StaticText.new(band, label: "Library")
        title.set_font(Theme.title)
        band.add(title, gap: 14)
        @filter = Segmented.new(band, FILTERS)
        @filter.on_change { reload_table }
        band.add(@filter, gap: 10)
        @search = Wx::SearchCtrl.new(band, size: [200, -1])
        @search.set_descriptive_text("Search rolls")
        @search.evt_text(@search.get_id) { reload_table }
        band.add(@search)
        band.stretch
        settings = Wx::Button.new(band, label: "Settings...")
        settings.evt_button(settings.get_id) { @app.preferences }
        band.add(settings)
        @queue_button = Wx::Button.new(band, label: "Render queue")
        @queue_button.evt_button(@queue_button.get_id) { @app.show_queue }
        band.add(@queue_button, gap: 0)
        column.add(band, 0, Wx::EXPAND)

        split = Wx::SplitterWindow.new(root, style: Wx::SP_LIVE_UPDATE | Wx::SP_3DSASH | Wx::SP_NOBORDER)
        split.set_minimum_pane_size(180)
        @sidebar = Sidebar.new(split)
        @sidebar.on_select { reload_table }
        @table = RollTable.new(split, @app)
        @table.on_open { |roll| @app.open_roll(roll) }
        split.split_vertically(@sidebar, @table, 240)
        column.add(split, 1, Wx::EXPAND)
        root.set_sizer(column)
      end

      def reload_table
        unless @app.config.configured?
          @table.lines = []
          @table.empty_message = "Choose the folder that holds your scans in Settings."
          return
        end
        kind, trip, place = @sidebar.selection
        unless kind
          @table.lines = []
          @table.empty_message = "No rolls found. Check the layout in Settings."
          return
        end
        places = kind == :trip ? trip.places : [place]
        query = @search.get_value.strip.downcase
        lines = places.flat_map do |p|
          rows = p.rolls.select { |roll| query.empty? || roll.name.downcase.include?(query) }.map { |roll| row_for(roll) }
          rows = rows.select { |row| keep?(row) }
          next [] if rows.empty?

          [[:group, p.name || trip.name]] + rows.map { |row| [:roll, row] }
        end
        @table.empty_message = "No rolls match."
        @table.lines = lines
        lines.each do |kind_, data|
          next unless kind_ == :roll

          data[:thumbs].each { |path| @app.thumbs.fetch(path, 160) { |image| @table.thumb_arrived(path, image) } }
        end
      end

      def keep?(row)
        case @filter.selection
        when 1 then row[:review]
        when 2 then row[:unrendered]
        else true
        end
      end

      def row_for(roll)
        settings = RollSettings.new(roll)
        output = roll.output
        trial = roll.trial
        job = @app.queue.jobs.reverse.find { |j| j.trip == roll.trip && j.rel == roll.rel && %w[running paused waiting].include?(j.status) }
        verdict = @verdicts.for(roll)["verdict"]
        status, solid = if job&.status == "running" then ["Rendering #{job.done} of #{job.total}", false]
                        elsif job&.status == "paused" then ["Paused at #{job.done} of #{job.total}", false]
                        elsif job then ["Waiting to render", false]
                        elsif trial.any? then [verdict ? "Trial: #{Verdicts::LABELS[verdict]}" : "Trial to review", true]
                        elsif output.any? then ["Rendered #{File.mtime(output.first).strftime('%-d %b')}", false]
                        else ["Not rendered", false]
                        end
        film = if settings.convert_only then "Convert only"
               elsif settings.profile then profile_name(settings.profile)
               else "Choose a film"
               end
        {
          roll: roll,
          detail: roll.frames.size == 1 ? "1 frame" : "#{roll.frames.size} frames",
          film: film,
          status: status,
          status_solid: solid,
          siblings: settings.convert_only ? "" : MatchSummary.describe(roll, settings),
          thumbs: sample(roll),
          muted: settings.convert_only,
          review: trial.any?,
          unrendered: output.empty? && trial.empty?
        }
      end

      def profile_name(key)
        @names ||= {}
        @names[key] ||= (FilmScan::Profile.load(key).name rescue key)
      end

      # Five frames spread through the roll, from its output when there is one.
      def sample(roll)
        frames = roll.frames
        return [] if frames.empty?

        output = roll.output.to_h { |path| [File.basename(path, ".*"), path] }
        picks = (0...5).map { |i| frames[(i * (frames.size - 1) / 4.0).round] }.uniq
        picks.map { |path| output[File.basename(path, ".*")] || path }
      end

      def queue_changed
        running = @app.queue.jobs.count { |j| j.status == "running" }
        waiting = @app.queue.jobs.count { |j| j.status == "waiting" }
        label = if running.positive? then "Queue: #{running} running#{", #{waiting} waiting" if waiting.positive?}"
                elsif waiting.positive? then "Queue: #{waiting} waiting"
                else "Render queue"
                end
        @queue_button.set_label(label) unless @queue_button.get_label == label
        @queue_button.get_parent.layout
        # Statuses follow the queue, at most every two seconds.
        signature = @app.queue.jobs.map { |j| [j.id, j.status, j.done] }
        return if signature == @signature || (@refreshed && Time.now - @refreshed < 2)

        @signature = signature
        @refreshed = Time.now
        reload_table if is_shown
      end

      # On a Mac the app lives on with its window closed, as Mac apps do.
      def closing(event)
        if RUBY_PLATFORM.include?("darwin") && event.can_veto
          hide
          event.veto
        else
          event.skip
        end
      end
    end
  end
end
