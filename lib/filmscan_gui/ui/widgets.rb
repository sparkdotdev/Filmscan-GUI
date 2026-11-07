require_relative "canvas"

module FilmscanGUI
  module UI
    # A row of buttons where one is chosen, drawn as one rounded control.
    class Segmented < Canvas
      attr_reader :selection

      def initialize(parent, labels, selection: 0, font: Theme.body)
        super(parent)
        @labels = labels
        @selection = selection
        @font = font
        @widths = nil
        set_min_size(best_size)
        evt_left_down { |event| click(event.get_position.x) }
      end

      # The block gets the chosen index. wxRuby takes a constructor's block
      # for itself, so callbacks are set here.
      def on_change(&block)
        @on_change = block
        self
      end

      def labels=(labels)
        @labels = labels
        @widths = nil
        set_min_size(best_size)
        get_parent.layout
        refresh
      end

      def selection=(index)
        @selection = index
        refresh
      end

      def label(index) = @labels[index]

      private

      def best_size
        widths = segment_widths
        [widths.sum + 2, line_height + 8]
      end

      def line_height
        @line_height ||= Wx::GraphicsContext.draw_on { |gc| gc.set_font(@font, Theme.text); gc.get_text_extent("Ag")[1].ceil }
      end

      def segment_widths
        @widths ||= Wx::GraphicsContext.draw_on do |gc|
          gc.set_font(@font, Theme.text)
          @labels.map { |label| gc.get_text_extent(label)[0].ceil + 20 }
        end
      end

      def click(x)
        edge = 1
        segment_widths.each_with_index do |w, i|
          if x < edge + w
            return if i == @selection

            @selection = i
            refresh
            return @on_change&.call(i)
          end
          edge += w
        end
      end

      def draw(gc, w, h)
        r = 5
        fill(gc, Theme.window, 0.5, 0.5, w - 1, h - 1, r)
        x = 1
        segment_widths.each_with_index do |sw, i|
          if i == @selection
            fill(gc, Theme.ink, x, 1, sw, h - 2, r - 1)
            centred(gc, @labels[i], x, 0, sw, h, font: @font, colour: Theme.on_ink)
          else
            if i.positive? && i - 1 != @selection && @selection != i
              gc.set_pen(Theme.pen(Theme.line))
              gc.stroke_line(x, 5, x, h - 5)
            end
            centred(gc, @labels[i], x, 0, sw, h, font: @font)
          end
          x += sw
        end
        outline(gc, Theme.line, 0.5, 0.5, w - 1, h - 1, r)
      end
    end

    # A slider with a tick at the profile's value. Dragging reports values
    # as it goes and once more when let go; a double click returns to the
    # tick. Values outside the range still show, pinned to an end.
    class ValueSlider < Canvas
      KNOB = 13

      attr_reader :value, :tick
      attr_accessor :enabled_look

      def initialize(parent, min:, max:, step:)
        super(parent, size: [120, 20])
        @min = min.to_f
        @max = max.to_f
        @step = step.to_f
        @value = @min
        set_min_size([60, 20])
        # No mouse capture: a view keeps getting drag events after a click
        # on macOS, and wxRuby has no capture-lost handler to pair with it.
        evt_left_down { |event| grab(event) }
        evt_motion { |event| drag(event) if @dragging && event.left_is_down }
        evt_left_up { |event| let_go(event) }
        evt_left_dclick { reset }
      end

      # The block gets the value and whether the drag has ended.
      def on_change(&block)
        @on_change = block
        self
      end

      def set(value, tick)
        @value = value
        @tick = tick
        refresh
      end

      private

      def background = get_parent.get_background_colour

      def x_of(value)
        return KNOB / 2.0 if value.nil?

        share = ((value.to_f - @min) / (@max - @min)).clamp(0.0, 1.0)
        KNOB / 2.0 + share * (width - KNOB)
      end

      def value_at(x)
        share = ((x - KNOB / 2.0) / (width - KNOB)).clamp(0.0, 1.0)
        raw = @min + share * (@max - @min)
        ((raw / @step).round * @step).round(6)
      end

      def grab(event)
        @dragging = true
        drag(event)
      end

      def drag(event)
        value = value_at(event.get_position.x)
        return if value == @value

        @value = value
        refresh
        @on_change&.call(@value, false)
      end

      def let_go(_event)
        return unless @dragging

        @dragging = false
        @on_change&.call(@value, true)
      end

      def reset
        return if @tick.nil? || @tick == @value

        @value = @tick
        refresh
        @on_change&.call(@value, true)
      end

      def draw(gc, w, h)
        mid = h / 2.0
        fill(gc, Theme.track, KNOB / 2.0, mid - 2, w - KNOB, 4, 2)
        if @tick
          tx = x_of(@tick)
          fill(gc, Theme.muted, tx - 1, mid - 6, 2, 12, 1)
        end
        kx = x_of(@value)
        Theme.stroke(gc, @value.nil? || !is_enabled ? Theme.muted : Theme.ink, 1.5)
        gc.set_brush(Theme.brush(Theme.window))
        gc.draw_ellipse(kx - KNOB / 2.0 + 0.75, mid - KNOB / 2.0 + 0.75, KNOB - 1.5, KNOB - 1.5)
      end
    end

    # The marker for what a change costs: filled is live, half is shown at
    # once but only approximately, a ring needs the roll measured again.
    class CostDot < Canvas
      TIPS = {
        live: "Live: the preview is exact straight away.",
        approx: "Approximate: shown at once from the roll's last measurement; re-measure to make it exact.",
        remeasure: "Re-measure first: this changes what the roll's analysis measures."
      }.freeze

      def initialize(parent, tier)
        super(parent, size: [12, 12])
        @tier = tier
        set_min_size([12, 12])
        set_tool_tip(TIPS[tier])
      end

      def tier=(tier)
        @tier = tier
        set_tool_tip(TIPS[tier])
        refresh
      end

      def self.draw(gc, tier, x, y, d = 10)
        Theme.stroke(gc, Theme.ink, 1.5)
        gc.set_brush(tier == :live ? Theme.brush(Theme.ink) : Theme.no_brush)
        gc.draw_ellipse(x + 0.75, y + 0.75, d - 1.5, d - 1.5)
        return unless tier == :approx

        gc.set_pen(Theme.no_pen)
        gc.set_brush(Theme.brush(Theme.ink))
        path = gc.create_path
        path.move_to_point(x + d / 2.0, y + 0.75)
        path.add_arc(x + d / 2.0, y + d / 2.0, d / 2.0 - 0.75, -Math::PI / 2, Math::PI / 2, false)
        path.close_subpath
        gc.fill_path(path)
      end

      private

      def background = get_parent.get_background_colour

      def draw(gc, w, h)
        CostDot.draw(gc, @tier, (w - 10) / 2.0, (h - 10) / 2.0)
      end
    end

    # A band across the top of a window that holds controls, with a hairline
    # under it, like the mockups' toolbars.
    class Band < Wx::Panel
      def initialize(parent, padding: [6, 10])
        super(parent)
        set_background_colour(Theme.softer)
        @sizer = Wx::HBoxSizer.new
        outer = Wx::VBoxSizer.new
        outer.add(@sizer, 1, Wx::EXPAND | Wx::TOP | Wx::BOTTOM | Wx::LEFT | Wx::RIGHT, padding[0])
        set_sizer(outer)
        evt_paint do
          paint do |dc|
            dc.set_pen(Theme.pen(Theme.line))
            dc.draw_line(0, get_client_size.height - 1, get_client_size.width, get_client_size.height - 1)
          end
        end
      end

      def add(window, proportion = 0, gap: 6)
        @sizer.add(window, proportion, Wx::ALIGN_CENTER_VERTICAL | Wx::RIGHT, gap)
        window
      end

      def stretch = @sizer.add_stretch_spacer(1)

      def label(text, muted: true)
        label = Wx::StaticText.new(self, label: UI.plain(text))
        label.set_foreground_colour(Theme.muted) if muted
        add(label)
      end
    end
  end
end
