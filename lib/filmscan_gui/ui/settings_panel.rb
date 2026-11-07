require_relative "widgets"
require_relative "../schema"
require_relative "../yaml_lines"

module FilmscanGUI
  module UI
    # A group's title bar: a caret, the name and a note on the right. A
    # click folds the group.
    class SectionHeader < Canvas
      def initialize(parent, title, detail: nil, open: true)
        super(parent, size: [-1, 30])
        @title = title
        @detail = detail
        @open = open
        set_min_size([100, 30])
        set_cursor(Wx::Cursor.new(Wx::CURSOR_HAND))
        evt_left_down { toggle }
      end

      attr_reader :open

      def on_toggle(&block)
        @on_toggle = block
        self
      end

      def detail=(text)
        @detail = text
        refresh
      end

      def toggle
        @open = !@open
        refresh
        @on_toggle&.call(@open)
      end

      private

      def draw(gc, w, h)
        gc.set_pen(Theme.pen(Theme.line))
        gc.stroke_line(0, 0.5, w, 0.5)
        cx = 6
        cy = h / 2.0 + 1
        gc.set_pen(Theme.no_pen)
        gc.set_brush(Theme.brush(Theme.muted))
        path = gc.create_path
        if @open
          path.move_to_point(cx - 4, cy - 2)
          path.add_line_to_point(cx + 4, cy - 2)
          path.add_line_to_point(cx, cy + 3)
        else
          path.move_to_point(cx - 2, cy - 4)
          path.add_line_to_point(cx + 3, cy)
          path.add_line_to_point(cx - 2, cy + 4)
        end
        path.close_subpath
        gc.fill_path(path)
        _, th = measure(gc, @title, font: Theme.strong)
        text(gc, @title, 16, (h - th) / 2.0 + 1, font: Theme.strong)
        return unless @detail

        dw, dh = measure(gc, @detail, font: Theme.small)
        text(gc, @detail, w - dw - 2, (h - dh) / 2.0 + 1, font: Theme.small, colour: Theme.muted)
      end
    end

    # The three cost markers with their names.
    class Legend < Canvas
      ITEMS = [[:live, "live"], [:approx, "approximate"], [:remeasure, "re-measure"]].freeze

      def initialize(parent)
        super(parent, size: [-1, 18])
        set_min_size([200, 18])
      end

      private

      def draw(gc, _w, h)
        x = 0
        ITEMS.each do |tier, name|
          CostDot.draw(gc, tier, x, (h - 10) / 2.0)
          tw, th = measure(gc, name, font: Theme.small)
          text(gc, name, x + 14, (h - th) / 2.0, font: Theme.small, colour: Theme.muted)
          x += 14 + tw + 14
        end
      end
    end

    # Every setting, in --help's groups. In roll scope the sliders edit the
    # roll and their ticks show the profile's values; in frame scope they
    # edit the current frame's override, ticks show the roll's values, and
    # settings the toolkit applies once per roll are greyed out.
    class SettingsPanel < Wx::Panel
      FIXES = %w[floor flat shadows sharpen grain].freeze
      LABEL_WIDTH = 108

      Row = Struct.new(:setting, :label, :slider, :number, :dot, :check, :clear, :widgets, keyword_init: true)

      attr_reader :scope

      def initialize(parent, owner)
        super(parent)
        @owner = owner
        @scope = :roll
        @rows = {}
        @more = {}
        set_background_colour(Theme.face)
        build
      end

      # Called with the frame's stem when it changes, to relabel the scope.
      def frame=(stem)
        @frame = stem
        @scope_switch.labels = ["Roll", "This frame: #{Filmstrip.number(stem.to_s)}"]
        refresh_values
      end

      # Shows the reach chosen elsewhere, such as frames picked on the sheet.
      def reach=(reach)
        index = %i[frame picked range].index(reach) || 0
        @reach[index].set_value(true)
        [@range_from, @range_to].each { |field| field.enable(index == 2) }
      end

      def scope=(scope)
        @scope = scope
        @scope_switch.selection = scope == :roll ? 0 : 1
        @overrides_box.show(scope == :frame)
        refresh_values
        @scroll.fit_inside
        layout
      end

      # Puts the model's values back on the controls.
      def refresh_values
        settings = @owner.settings
        frame = @scope == :frame ? @owner.frame_overrides : {}
        @rows.each do |key, row|
          setting = row.setting
          roll_value = settings.value(key)
          value = frame.key?(key) ? frame[key] : roll_value
          tick = @scope == :frame ? roll_value : settings.base(key)
          enabled = !(@scope == :frame && !setting.frame) && !settings.convert_only
          case setting.kind
          when :float, :optional, :optional_int, :int
            row.slider.set(value, tick)
            row.number.change_value(format_value(setting, value)) unless row.number.has_focus
          when :bool
            row.check.set_value(value ? true : false)
          when :fixes
            row.widgets.each { |name, box| box.set_value(Array(value).map(&:to_s).include?(name)) }
          when :choice
            row.check.set_string_selection(value.to_s.empty? ? "default" : value.to_s)
          end
          overridden = @scope == :frame && frame.key?(key)
          row.label.set_font(overridden ? Theme.small_strong : Theme.small)
          row.clear&.show(overridden)
          (row.widgets.is_a?(Hash) ? row.widgets.values : row.widgets).each { |w| w.enable(enabled) }
        end
        update_overrides_box
        @scroll.layout
      end

      private

      def build
        outer = Wx::VBoxSizer.new
        top = Wx::BoxSizer.new(Wx::VERTICAL)
        @scope_switch = Segmented.new(self, ["Roll", "This frame"])
        @scope_switch.on_change { |i| @owner.scope_changed(i.zero? ? :roll : :frame) }
        top.add(@scope_switch, 0, Wx::BOTTOM, 8)
        top.add(Legend.new(self), 0, Wx::EXPAND)
        outer.add(top, 0, Wx::EXPAND | Wx::ALL, 12)

        @scroll = Wx::ScrolledWindow.new(self, style: Wx::VSCROLL)
        @scroll.set_scroll_rate(0, 12)
        @scroll.set_background_colour(Theme.face)
        @column = Wx::VBoxSizer.new
        @overrides_box = build_overrides(@scroll)
        @column.add(@overrides_box, 0, Wx::EXPAND | Wx::BOTTOM, 6)
        @overrides_box.hide
        Schema::GROUPS.each { |group| build_group(@scroll, group) }
        @scroll.set_sizer(@column)
        outer.add(@scroll, 1, Wx::EXPAND | Wx::LEFT | Wx::RIGHT, 12)

        buttons = Wx::HBoxSizer.new
        reset = Wx::Button.new(self, label: "Reset to profile")
        copy = Wx::Button.new(self, label: "Copy command")
        reset.evt_button(reset.get_id) { @owner.reset_settings }
        copy.evt_button(copy.get_id) { @owner.copy_command }
        reset.set_tool_tip("Put every setting back to the profile's value. Siblings and match strength stay.")
        copy.set_tool_tip("Copy the filmscan command line that renders exactly what is on screen.")
        buttons.add(reset, 0, Wx::RIGHT, 6)
        buttons.add(copy, 0)
        outer.add(buttons, 0, Wx::ALL, 12)
        set_sizer(outer)
      end

      def build_group(parent, group)
        settings = Schema.in_group(group)
        open = group != "Output"
        detail = group == "Output" ? output_summary : nil
        header = SectionHeader.new(parent, group, detail: detail, open: open)
        @output_header = header if group == "Output"
        body = Wx::Panel.new(parent)
        body.set_background_colour(Theme.face)
        grid = Wx::FlexGridSizer.new(4, 6, 6)
        grid.add_growable_col(1, 1)
        more = Wx::Panel.new(body)
        more.set_background_colour(Theme.face)
        more_grid = Wx::FlexGridSizer.new(4, 6, 6)
        more_grid.add_growable_col(1, 1)

        settings.each do |setting|
          target_parent, target = setting.common ? [body, grid] : [more, more_grid]
          add_row(target_parent, target, setting)
        end
        sizer = Wx::VBoxSizer.new
        if @fix_block
          sizer.add(@fix_block, 0, Wx::EXPAND | Wx::TOP, 6)
          @fix_block = nil
        end
        sizer.add(grid, 0, Wx::EXPAND | Wx::TOP | Wx::BOTTOM, 4)
        rest = settings.count { |s| !s.common }
        if rest.positive?
          more.set_sizer(more_grid)
          sizer.add(more, 0, Wx::EXPAND | Wx::BOTTOM, 4)
          more.hide
          link = MoreLink.new(body, "#{rest} more")
          link.on_click do
            more.show(!more.is_shown)
            link.text = more.is_shown ? "Fewer" : "#{rest} more"
            relayout
          end
          sizer.add(link, 0, Wx::BOTTOM, 6)
        else
          more.destroy
        end
        body.set_sizer(sizer)
        body.hide unless open
        header.on_toggle do |shown|
          body.show(shown)
          relayout
        end
        @column.add(header, 0, Wx::EXPAND)
        @column.add(body, 0, Wx::EXPAND)
      end

      def relayout
        @scroll.layout
        @scroll.fit_inside
        @scroll.refresh
      end

      def add_row(parent, grid, setting)
        label = Wx::StaticText.new(parent, label: setting.label, size: [LABEL_WIDTH, -1])
        label.set_font(Theme.small)
        label.set_tool_tip(setting.help) if setting.help
        dot = CostDot.new(parent, setting.tier)
        row = Row.new(setting: setting, label: label, dot: dot)
        case setting.kind
        when :float, :optional, :optional_int, :int
          slider = ValueSlider.new(parent, min: setting.min, max: setting.max, step: setting.step)
          slider.on_change { |value, final| changed(setting, value, final) }
          number = Wx::TextCtrl.new(parent, size: [54, -1], style: Wx::TE_PROCESS_ENTER | Wx::TE_RIGHT)
          number.set_font(Theme.small)
          number.evt_text_enter(number.get_id) { typed(setting, number) }
          number.evt_kill_focus { |event| typed(setting, number); event.skip }
          row.slider = slider
          row.number = number
          row.widgets = [slider, number]
          grid.add(label, 0, Wx::ALIGN_CENTER_VERTICAL)
          grid.add(slider, 1, Wx::EXPAND | Wx::ALIGN_CENTER_VERTICAL)
          grid.add(number, 0, Wx::ALIGN_CENTER_VERTICAL)
        when :bool
          check = Wx::CheckBox.new(parent, label: "")
          check.evt_checkbox(check.get_id) { changed(setting, check.get_value, true) }
          row.check = check
          row.widgets = [check]
          grid.add(label, 0, Wx::ALIGN_CENTER_VERTICAL)
          grid.add(check, 0, Wx::ALIGN_CENTER_VERTICAL)
          grid.add_spacer(0)
        when :fixes
          boxes = FIXES.to_h do |name|
            box = Wx::CheckBox.new(parent, label: name)
            box.set_font(Theme.small)
            box.evt_checkbox(box.get_id) { changed(setting, FIXES.select { |n| row.widgets[n].get_value }.map(&:to_sym), true) }
            [name, box]
          end
          row.widgets = boxes
          # The fixes take the panel's whole width, above the group's grid.
          @fix_block = Wx::VBoxSizer.new
          head = Wx::HBoxSizer.new
          head.add(label, 1, Wx::ALIGN_CENTER_VERTICAL)
          head.add(dot, 0, Wx::ALIGN_CENTER_VERTICAL)
          @fix_block.add(head, 0, Wx::EXPAND | Wx::BOTTOM, 4)
          wrap = Wx::WrapSizer.new(Wx::HORIZONTAL)
          boxes.each_value { |box| wrap.add(box, 0, Wx::RIGHT | Wx::BOTTOM, 10) }
          @fix_block.add(wrap, 0, Wx::EXPAND)
          @rows[setting.key] = row
          return
        when :choice
          choices = setting.key == :format ? Schema::FORMATS : %w[default 8 10 12 16]
          choice = Wx::Choice.new(parent, choices: choices)
          choice.set_font(Theme.small)
          choice.evt_choice(choice.get_id) do
            picked = choice.get_string_selection
            value = setting.key == :bits ? (picked == "default" ? nil : picked.to_i) : picked
            changed(setting, value, true)
          end
          row.check = choice
          row.widgets = [choice]
          grid.add(label, 0, Wx::ALIGN_CENTER_VERTICAL)
          grid.add(choice, 0, Wx::ALIGN_CENTER_VERTICAL)
          grid.add_spacer(0)
        end
        cell = Wx::HBoxSizer.new
        cell.add(dot, 0, Wx::ALIGN_CENTER_VERTICAL)
        clear = ClearButton.new(parent)
        clear.set_tool_tip("Remove this frame's override")
        clear.on_click { @owner.clear_override(setting.key) }
        clear.hide
        row.clear = clear
        cell.add(clear, 0, Wx::ALIGN_CENTER_VERTICAL | Wx::LEFT, 2)
        grid.add(cell, 0, Wx::ALIGN_CENTER_VERTICAL)
        @rows[setting.key] = row
      end

      def changed(setting, value, final)
        if setting.kind == :optional_int || setting.kind == :int
          value = value&.round
        end
        if @scope == :frame
          @owner.frame_setting_changed(setting.key, value, final)
        else
          @owner.setting_changed(setting.key, value, final)
        end
        row = @rows[setting.key]
        row.number.change_value(format_value(setting, value)) if row&.number && !row.number.has_focus
        @output_header&.detail = output_summary if setting.group == "Output"
      end

      def typed(setting, field)
        raw = field.get_value.strip
        value = if raw.empty? || raw.casecmp?("auto") || raw.casecmp?("off")
                  return unless %i[optional optional_int].include?(setting.kind)

                  nil
                else
                  Float(raw, exception: false) or return field.change_value(format_value(setting, current(setting)))
                end
        return if value == current(setting)

        changed(setting, value, true)
        refresh_values
      end

      def current(setting)
        frame = @scope == :frame ? @owner.frame_overrides : {}
        frame.key?(setting.key) ? frame[setting.key] : @owner.settings.value(setting.key)
      end

      def format_value(setting, value)
        return "auto" if value.nil?
        return value.round.to_s if setting.digits.zero?

        format("%.#{setting.digits}f", value)
      end

      def output_summary
        return "" unless @owner.respond_to?(:settings) && @owner.settings

        s = @owner.settings
        bits = s.value(:bits) ? ", #{s.value(:bits)} bit" : ""
        "#{s.value(:format).to_s.upcase}#{bits}, quality #{s.value(:quality)}"
      end

      # The frame's overrides, how far they reach, and the YAML they write.
      def build_overrides(parent)
        box = Wx::Panel.new(parent)
        box.set_background_colour(Theme.face)
        sizer = Wx::VBoxSizer.new
        @overrides_title = SectionHeader.new(box, "Overrides for this frame")
        sizer.add(@overrides_title, 0, Wx::EXPAND)
        @overrides_list = Wx::StaticText.new(box, label: "")
        @overrides_list.set_font(Theme.small)
        sizer.add(@overrides_list, 0, Wx::EXPAND | Wx::TOP | Wx::BOTTOM, 6)
        apply = Wx::StaticText.new(box, label: "Apply changes to")
        apply.set_font(Theme.small_strong)
        sizer.add(apply, 0, Wx::TOP, 4)
        @reach = ["This frame", "Frames picked on the sheet", "A range of frames"].each_with_index.map do |text, i|
          radio = Wx::RadioButton.new(box, label: text, style: i.zero? ? Wx::RB_GROUP : 0)
          radio.set_font(Theme.small)
          radio.evt_radiobutton(radio.get_id) do
            @owner.reach_changed(%i[frame picked range][i])
            [@range_from, @range_to].each { |field| field.enable(i == 2) }
          end
          sizer.add(radio, 0, Wx::TOP, 3)
          radio
        end
        @reach.first.set_value(true)
        range = Wx::HBoxSizer.new
        @range_from = Wx::TextCtrl.new(box, size: [52, -1], style: Wx::TE_PROCESS_ENTER)
        @range_to = Wx::TextCtrl.new(box, size: [52, -1], style: Wx::TE_PROCESS_ENTER)
        [@range_from, @range_to].each do |field|
          field.set_font(Theme.small)
          field.set_hint("frame")
          field.evt_text(field.get_id) { @owner.range_changed(@range_from.get_value, @range_to.get_value) }
        end
        range.add(@range_from, 0, Wx::RIGHT, 4)
        to = Wx::StaticText.new(box, label: "to")
        to.set_font(Theme.small)
        range.add(to, 0, Wx::ALIGN_CENTER_VERTICAL | Wx::RIGHT, 4)
        range.add(@range_to, 0)
        [@range_from, @range_to].each(&:disable)
        sizer.add(range, 0, Wx::LEFT | Wx::TOP | Wx::BOTTOM, 4)
        @yaml_label = Wx::StaticText.new(box, label: "")
        @yaml_label.set_font(Theme.small_strong)
        sizer.add(@yaml_label, 0, Wx::TOP, 6)
        @yaml = Wx::TextCtrl.new(box, size: [-1, 74], style: Wx::TE_MULTILINE | Wx::TE_READONLY | Wx::TE_DONTWRAP)
        @yaml.set_font(Theme.mono)
        sizer.add(@yaml, 0, Wx::EXPAND | Wx::TOP, 4)
        box.set_sizer(sizer)
        box
      end

      def update_overrides_box
        return unless @scope == :frame && @frame

        stem = @frame
        @overrides_title.detail = stem
        frame = @owner.frame_overrides
        lines = frame.map do |key, value|
          setting = Schema::BY_KEY[key]
          roll = @owner.settings.value(key)
          name = setting ? setting.label : key.to_s
          "#{name}  #{setting ? format_value(setting, value) : value}    roll #{setting ? format_value(setting, roll) : roll}"
        end
        @overrides_list.set_label(lines.empty? ? "None yet. Move any setting below to add one." : lines.join("\n"))
        @overrides_list.set_foreground_colour(lines.empty? ? Theme.muted : Theme.text)
        path = @owner.settings.overrides_path
        @yaml_label.set_label(File.basename(path))
        @yaml.change_value(@owner.overrides_yaml_lines.join("\n"))
      end
    end

    # A small text link, such as "10 more".
    class MoreLink < Canvas
      def initialize(parent, text)
        super(parent, size: [-1, 18])
        @text = text
        set_min_size([90, 18])
        set_cursor(Wx::Cursor.new(Wx::CURSOR_HAND))
        evt_left_down { @on_click&.call }
      end

      def on_click(&block)
        @on_click = block
        self
      end

      def text=(text)
        @text = text
        refresh
      end

      private

      def draw(gc, _w, h)
        _, th = measure(gc, @text, font: Theme.small)
        text(gc, @text, LABEL_OFFSET, (h - th) / 2.0, font: Theme.small, colour: Theme.muted)
      end

      LABEL_OFFSET = 0
    end

    # A small x that removes a frame's override for one setting.
    class ClearButton < Canvas
      def initialize(parent)
        super(parent, size: [14, 14])
        set_min_size([14, 14])
        set_cursor(Wx::Cursor.new(Wx::CURSOR_HAND))
        evt_left_down { @on_click&.call }
      end

      def on_click(&block)
        @on_click = block
        self
      end

      private

      def draw(gc, w, h)
        Theme.stroke(gc, Theme.muted, 1.5)
        gc.stroke_line(4, 4, w - 4, h - 4)
        gc.stroke_line(w - 4, 4, 4, h - 4)
      end
    end
  end
end
