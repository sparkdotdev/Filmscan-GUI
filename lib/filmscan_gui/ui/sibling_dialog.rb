require_relative "widgets"
require_relative "filmstrip"
require_relative "../frame_pattern"
require_relative "../match_summary"

module FilmscanGUI
  module UI
    # A roll's frames as small tiles to pick from: drag across to pick a
    # run, click one to add or drop it.
    class BrushStrip < ScrollCanvas
      CELL = [62, 58].freeze
      GAP = 6

      def initialize(parent)
        super(parent)
        @stems = []
        @paths = {}
        @thumbs = {}
        @picked = []
        set_min_size([300, 150])
        evt_left_down { |event| press(event) }
        evt_motion { |event| drag(event) if @anchor && event.left_is_down }
        evt_left_up { |_| finish }
      end

      def on_change(&block) = (@on_change = block) && self

      def show_roll(stems, paths, picked)
        @stems = stems
        @paths = paths
        @picked = picked.dup
        layout_content
        refresh
      end

      def picked = @picked.dup

      def thumb_arrived(path, image)
        @thumbs[path] = Wx::Bitmap.new(image)
        refresh
      end

      private

      def background = Theme.surround
      def across = [((width - GAP) / (CELL[0] + GAP)).floor, 1].max

      def layout_content
        rows = (@stems.size / across.to_f).ceil
        self.content_height = GAP + rows * (CELL[1] + GAP)
      end

      def index_at(event)
        x, y = content_point(event)
        col = ((x - GAP) / (CELL[0] + GAP)).floor
        row = ((y - GAP) / (CELL[1] + GAP)).floor
        i = row * across + col
        col.between?(0, across - 1) && i.between?(0, @stems.size - 1) ? i : nil
      end

      def press(event)
        i = index_at(event) or return
        @anchor = i
        @adding = !@picked.include?(@stems[i])
        @before = @picked.dup
        apply(i)
      end

      def drag(event)
        i = index_at(event) or return
        apply(i)
      end

      def apply(i)
        a, b = [@anchor, i].minmax
        run = @stems[a..b]
        @picked = @adding ? (@before | run) : (@before - run)
        @picked = @stems & @picked
        refresh
      end

      def finish
        return unless @anchor

        @anchor = nil
        @on_change&.call(@picked)
      end

      def draw(gc, _w, _h, _top)
        @stems.each_with_index do |stem, i|
          x = GAP + (i % across) * (CELL[0] + GAP)
          y = GAP + (i / across) * (CELL[1] + GAP)
          box_h = CELL[1] - 14
          rect = picture(gc, @thumbs[@paths[stem]], x, y, CELL[0], box_h)
          unless rect
            rect = [x + 4, y + 6, CELL[0] - 8, box_h - 12]
            placeholder(gc, *rect, dark: true)
          end
          picked = @picked.include?(stem)
          fill(gc, Theme.rgb(56, 56, 56, 160), *rect) unless picked
          outline(gc, Theme.rgb(245, 245, 242), rect[0] - 2, rect[1] - 2, rect[2] + 4, rect[3] + 4, 2, 2) if picked
          text(gc, Filmstrip.number(stem), x + 1, y + box_h + 1, font: Theme.tiny,
                                                                 colour: picked ? Theme.surround_text : Theme.surround_muted)
        end
      end
    end

    # Picks the rolls shot alongside this one, which of their frames to
    # match and how strongly. Shown as a sheet on the roll's window.
    class SiblingDialog < Wx::Dialog
      Candidate = Struct.new(:roll, :stems, :paths, :picked, keyword_init: true)

      attr_reader :strength

      def initialize(parent, app, roll, settings)
        super(parent, title: "Match to rolls shot alongside", size: [940, 600],
                      style: Wx::DEFAULT_DIALOG_STYLE | Wx::RESIZE_BORDER)
        @app = app
        @roll = roll
        @settings = settings
        @strength = settings.value(:match_strength).to_f
        @candidates = candidates
        build
        show_candidate(@candidates.index { |c| c.picked.any? } || 0)
      end

      # The chosen siblings as sessions.yml keeps them.
      def patterns
        @candidates.select { |c| c.picked.any? }.map do |c|
          pattern = FramePattern.for(c.stems, c.picked)
          pattern == "*" ? c.roll.rel : "#{c.roll.rel}/#{pattern}"
        end
      end

      private

      # Rolls in the same trip, those the lab scanned well first and those
      # from the same place before the rest.
      def candidates
        chosen = MatchSummary.rolls(@roll, @settings).to_h { |dir, picked, _| [dir, picked.map { |p| File.basename(p, ".*") }] }
        rolls = @app.library.rolls.select { |r| r.trip == @roll.trip && r != @roll }
        rolls = rolls.sort_by do |r|
          [chosen.key?(r.source) ? 0 : 1, r.place == @roll.place ? 0 : 1, Films.guess(r.name) == :convert ? 0 : 1, r.rel]
        end
        rolls.map do |r|
          output = r.output.to_h { |path| [File.basename(path, ".*"), path] }
          paths = r.frames.to_h { |path| stem = File.basename(path, ".*"); [stem, output[stem] || path] }
          Candidate.new(roll: r, stems: r.stems, paths: paths, picked: chosen.fetch(r.source, []))
        end
      end

      def build
        root = Wx::Panel.new(self)
        outer = Wx::VBoxSizer.new
        intro = Wx::StaticText.new(root, label: "Tick the rolls shot in the same place and light. Each counts the same in " \
                                                "the match, however many frames it has.")
        intro.set_foreground_colour(Theme.muted)
        outer.add(intro, 0, Wx::ALL, 14)

        row = Wx::HBoxSizer.new
        left = Wx::VBoxSizer.new
        label = Wx::StaticText.new(root, label: "Rolls on this trip")
        label.set_font(Theme.strong)
        left.add(label, 0, Wx::BOTTOM, 6)
        @list = Wx::CheckListBox.new(root, size: [270, -1], choices: @candidates.map { |c| candidate_label(c) })
        @candidates.each_with_index { |c, i| @list.check(i, c.picked.any?) }
        @list.evt_listbox(@list.get_id) { show_candidate(@list.get_selection) }
        @list.evt_checklistbox(@list.get_id) { |event| ticked(event.get_int) }
        left.add(@list, 1, Wx::EXPAND)
        row.add(left, 0, Wx::EXPAND | Wx::LEFT | Wx::BOTTOM, 14)

        right = Wx::VBoxSizer.new
        head = Wx::HBoxSizer.new
        @title = Wx::StaticText.new(root, label: "")
        @title.set_font(Theme.strong)
        head.add(@title, 0, Wx::ALIGN_CENTER_VERTICAL)
        hint = Wx::StaticText.new(root, label: "  drag across frames to pick them, click one to add or drop it")
        hint.set_font(Theme.small)
        hint.set_foreground_colour(Theme.muted)
        head.add(hint, 0, Wx::ALIGN_CENTER_VERTICAL)
        right.add(head, 0, Wx::BOTTOM, 8)
        @strip = BrushStrip.new(root)
        @strip.on_change { |picked| picked_changed(picked) }
        right.add(@strip, 1, Wx::EXPAND)

        pattern_row = Wx::HBoxSizer.new
        pattern_label = Wx::StaticText.new(root, label: "Pattern")
        pattern_label.set_foreground_colour(Theme.muted)
        @pattern = Wx::TextCtrl.new(root, style: Wx::TE_PROCESS_ENTER)
        @pattern.set_font(Theme.mono)
        @pattern.evt_text_enter(@pattern.get_id) { pattern_typed }
        @pattern.evt_kill_focus { |event| pattern_typed; event.skip }
        @count = Wx::StaticText.new(root, label: "")
        @count.set_foreground_colour(Theme.muted)
        pattern_row.add(pattern_label, 0, Wx::ALIGN_CENTER_VERTICAL | Wx::RIGHT, 8)
        pattern_row.add(@pattern, 1, Wx::ALIGN_CENTER_VERTICAL | Wx::RIGHT, 8)
        pattern_row.add(@count, 0, Wx::ALIGN_CENTER_VERTICAL)
        right.add(pattern_row, 0, Wx::EXPAND | Wx::TOP, 10)

        strength_row = Wx::HBoxSizer.new
        strength_label = Wx::StaticText.new(root, label: "Strength")
        strength_label.set_font(Theme.strong)
        @slider = ValueSlider.new(root, min: 0, max: 1, step: 0.01)
        @slider.set(@strength, 1.0)
        @slider.on_change { |value, _| strength_moved(value) }
        @percent = Wx::StaticText.new(root, label: percent)
        strength_row.add(strength_label, 0, Wx::ALIGN_CENTER_VERTICAL | Wx::RIGHT, 12)
        strength_row.add(@slider, 1, Wx::ALIGN_CENTER_VERTICAL | Wx::RIGHT, 10)
        strength_row.add(@percent, 0, Wx::ALIGN_CENTER_VERTICAL)
        right.add(strength_row, 0, Wx::EXPAND | Wx::TOP, 12)
        note = Wx::StaticText.new(root, label: "New siblings change what the roll is balanced toward, so the roll is " \
                                               "measured again after saving. Strength alone previews at once.")
        note.set_font(Theme.small)
        note.set_foreground_colour(Theme.muted)
        note.wrap(560)
        right.add(note, 0, Wx::TOP, 10)
        row.add(right, 1, Wx::EXPAND | Wx::LEFT | Wx::RIGHT | Wx::BOTTOM, 14)
        outer.add(row, 1, Wx::EXPAND)

        buttons = Wx::StdDialogButtonSizer.new
        ok = Wx::Button.new(root, Wx::ID_OK, "Save")
        ok.set_default
        buttons.add_button(ok)
        buttons.add_button(Wx::Button.new(root, Wx::ID_CANCEL, "Cancel"))
        buttons.realize
        outer.add(buttons, 0, Wx::EXPAND | Wx::ALL, 14)
        root.set_sizer(outer)
      end

      def candidate_label(c)
        place = c.roll.place
        place && place != @roll.place ? "#{c.roll.name}  (#{place})" : c.roll.name
      end

      def show_candidate(index)
        return if index.nil? || index.negative? || index >= @candidates.size

        @current = @candidates[index]
        @list.set_selection(index)
        @title.set_label(UI.plain(@current.roll.name))
        @strip.show_roll(@current.stems, @current.paths, @current.picked)
        @current.paths.each_value { |path| @app.thumbs.fetch(path, 120) { |image| @strip.thumb_arrived(path, image) } }
        show_pattern
      end

      def ticked(index)
        c = @candidates[index]
        c.picked = @list.is_checked(index) ? c.stems.dup : []
        show_candidate(index)
      end

      def picked_changed(picked)
        @current.picked = picked
        @list.check(@candidates.index(@current), picked.any?)
        show_pattern
      end

      def show_pattern
        pattern = FramePattern.for(@current.stems, @current.picked)
        @pattern.change_value(pattern.nil? ? "" : (pattern == "*" ? "all frames" : pattern))
        @count.set_label("#{@current.picked.size} of #{@current.stems.size} frames")
        @count.get_parent.layout
      end

      def pattern_typed
        raw = @pattern.get_value.strip
        picked = if raw.empty? then []
                 elsif raw == "all frames" || raw == "*" then @current.stems.dup
                 else FramePattern.matches(@current.stems, raw)
                 end
        @current.picked = picked
        @strip.show_roll(@current.stems, @current.paths, picked)
        @list.check(@candidates.index(@current), picked.any?)
        show_pattern
      end

      def strength_moved(value)
        @strength = value
        @percent.set_label(percent)
      end

      def percent = "#{(@strength * 100).round}%"
    end
  end
end
