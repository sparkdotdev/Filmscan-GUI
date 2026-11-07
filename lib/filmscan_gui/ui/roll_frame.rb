require "time"
require_relative "widgets"
require_relative "viewer"
require_relative "filmstrip"
require_relative "sheet_grid"
require_relative "settings_panel"
require_relative "review_page"
require_relative "../roll_settings"
require_relative "../overrides"
require_relative "../match_summary"

module FilmscanGUI
  module UI
    # One roll: its frames, the settings, the contact sheet and the review
    # of a render. Previews come from a worker process that holds the roll.
    class RollFrame < Wx::Frame
      VIEWS = [[:split, "Split"], [:side, "Side by side"], [:scan, "Lab scan"], [:corrected, "Corrected"]].freeze
      OTHERS = [[:now, "Now"], [:sibling, "Sibling"]].freeze
      DEBOUNCE = 150

      attr_reader :roll, :settings, :stem

      def initialize(app, roll)
        super(nil, title: roll.name, size: Theme.fit_size(1440, 920))
        @app = app
        @roll = roll
        @settings = RollSettings.new(roll)
        @overrides = Overrides.new(roll.overrides_path)
        @scans = {}
        @gen = 0
        @sheet_gen = 0
        @undo = []
        @redo = []
        @reach = :frame
        set_min_size([1000, 640])
        build
        set_menu_bar(@app.menus.build(self))
        start_worker
        evt_close { |event| closing(event) }
        evt_char_hook { |event| key(event) }
        centre
      end

      # Called by the app's menus.
      def command(name)
        case name
        when :undo then undo
        when :redo then redo_change
        when :copy_command then copy_command
        when :remeasure then remeasure
        when :full then full_size
        when :trial then render(:trial)
        when :final then render(:final)
        when :match then edit_match
        when :frame_page then show_page(0)
        when :sheet_page then show_page(1)
        when :review_page then show_page(2)
        when :fit then zoom(:fit)
        when :actual then zoom(:actual)
        when *VIEWS.map(&:first), *OTHERS.map(&:first) then view(name)
        end
      end

      # Called by the settings panel.
      def frame_overrides = @stem ? @overrides.for(@stem) : {}

      def setting_changed(key, value, final)
        before = snapshot if final
        old_fix = @settings.fix.dup
        @settings.set(key, value)
        tier = @settings.tier_of([key], before_fix: old_fix)
        remember(before) if final
        settings_moved(tier, final)
      end

      def frame_setting_changed(key, value, final)
        stems = reach_stems
        return unless writable?(@overrides.path)

        @overrides.update(stems, key, value) if final
        @pending_override = final ? nil : [stems, key, value]
        @filmstrip.marked = marked
        @sheet.marked = marked
        settings_moved(:live, final)
        @panel.refresh_values if final
      end

      def clear_override(key)
        return unless writable?(@overrides.path)

        @overrides.update([@stem], key, nil)
        @filmstrip.marked = marked
        @sheet.marked = marked
        settings_moved(:live, true)
        @panel.refresh_values
      end

      def scope_changed(scope)
        @panel.scope = scope
      end

      def reach_changed(reach)
        @reach = reach
      end

      def range_changed(from, to)
        @range = [from.strip, to.strip]
      end

      def overrides_yaml_lines
        path = @overrides.path
        return ["# no overrides yet"] unless File.exist?(path)

        File.readlines(path, chomp: true).last(12)
      end

      def reset_settings
        before = snapshot
        @settings.reset
        remember(before)
        @panel.refresh_values
        settings_moved(:remeasure, true)
      end

      def copy_command
        out = @roll.output_dir
        Wx::Clipboard.open { |clip| clip.set_data(Wx::TextDataObject.new(@settings.command_line(out))) }
        status("Copied the command line for this roll.")
      end

      private

      # Layout ---------------------------------------------------------------

      def build
        root = Wx::Panel.new(self)
        root.set_background_colour(Theme.face)
        column = Wx::VBoxSizer.new

        header = Band.new(root, padding: [8, 14])
        title = Wx::StaticText.new(header, label: UI.plain(@roll.name))
        title.set_font(Theme.title)
        header.add(title, gap: 10)
        place = [@roll.trip, @roll.place].compact.join(", ")
        header.label(place)
        header.stretch
        @pages = Segmented.new(header, %w[Frame Sheet Review])
        @pages.on_change { |i| show_page(i) }
        header.add(@pages, gap: 0)
        column.add(header, 0, Wx::EXPAND)

        tools = Band.new(root)
        tools.label("Profile")
        @profile = Wx::Choice.new(tools, choices: profile_choices.map(&:last))
        @profile.evt_choice(@profile.get_id) { profile_picked }
        tools.add(@profile, gap: 14)
        tools.label("Match")
        @match = ChipLabel.new(tools, MatchSummary.describe(@roll, @settings))
        tools.add(@match)
        edit = Wx::Button.new(tools, label: "Edit...")
        edit.evt_button(edit.get_id) { edit_match }
        tools.add(edit)
        tools.stretch
        remeasure_button = Wx::Button.new(tools, label: "Re-measure roll")
        remeasure_button.evt_button(remeasure_button.get_id) { remeasure }
        remeasure_button.set_tool_tip("Measure the roll again with the current settings, so approximate previews become exact.")
        tools.add(remeasure_button)
        @render_button = Wx::Button.new(tools, label: "Render roll")
        @render_button.evt_button(@render_button.get_id) { render_menu }
        tools.add(@render_button, gap: 0)
        column.add(tools, 0, Wx::EXPAND)

        @split = Wx::SplitterWindow.new(root, style: Wx::SP_LIVE_UPDATE | Wx::SP_3DSASH | Wx::SP_NOBORDER)
        @split.set_minimum_pane_size(280)
        @split.set_sash_gravity(1.0)
        @book = Wx::Simplebook.new(@split)
        @book.add_page(build_frame_page(@book), "Frame")
        @book.add_page(build_sheet_page(@book), "Sheet")
        @review = ReviewPage.new(@book, @app, self)
        @book.add_page(@review, "Review")
        @panel = SettingsPanel.new(@split, self)
        @split.split_vertically(@book, @panel, -330)
        column.add(@split, 1, Wx::EXPAND)
        root.set_sizer(column)
        refresh_profile
        @panel.refresh_values
      end

      def build_frame_page(parent)
        page = Wx::Panel.new(parent)
        page.set_background_colour(Theme.face)
        row = Wx::HBoxSizer.new
        @filmstrip = Filmstrip.new(page)
        @filmstrip.on_select { |stem| select_frame(stem) }
        row.add(@filmstrip, 0, Wx::EXPAND)
        line = Wx::Panel.new(page, size: [1, -1])
        line.set_background_colour(Theme.line)
        row.add(line, 0, Wx::EXPAND)

        centre = Wx::VBoxSizer.new
        modes = Wx::HBoxSizer.new
        @views = Segmented.new(page, VIEWS.map(&:last))
        @views.on_change { |i| view(VIEWS[i][0]) }
        @others = Segmented.new(page, OTHERS.map(&:last), selection: nil)
        @others.on_change { |i| view(OTHERS[i][0]) }
        @zoom = Segmented.new(page, ["Fit", "100%"])
        @zoom.on_change { |i| zoom(i.zero? ? :fit : :actual) }
        modes.add(@views, 0, Wx::RIGHT, 8)
        modes.add(@others, 0)
        modes.add_stretch_spacer(1)
        modes.add(@zoom, 0)
        centre.add(modes, 0, Wx::EXPAND | Wx::ALL, 10)

        @viewer = Viewer.new(page)
        @viewer.evt_key_up { |event| space_up(event) }
        centre.add(@viewer, 1, Wx::EXPAND | Wx::LEFT | Wx::RIGHT, 10)

        status = Wx::HBoxSizer.new
        @status = Wx::StaticText.new(page, label: "Opening the roll...")
        @status.set_font(Theme.small)
        @status.set_foreground_colour(Theme.muted)
        @measured_chip = ChipLabel.new(page, "")
        @measured_chip.hide
        hint = Wx::StaticText.new(page, label: "Hold Space for the previous settings")
        hint.set_font(Theme.small)
        hint.set_foreground_colour(Theme.muted)
        full = Wx::Button.new(page, label: "Check at full size")
        full.evt_button(full.get_id) { full_size }
        full.set_tool_tip("Render this frame at full resolution in the background, since the toolkit's output depends on input size.")
        status.add(@status, 0, Wx::ALIGN_CENTER_VERTICAL | Wx::RIGHT, 8)
        status.add(@measured_chip, 0, Wx::ALIGN_CENTER_VERTICAL)
        status.add_stretch_spacer(1)
        status.add(hint, 0, Wx::ALIGN_CENTER_VERTICAL | Wx::RIGHT, 10)
        status.add(full, 0, Wx::ALIGN_CENTER_VERTICAL)
        centre.add(status, 0, Wx::EXPAND | Wx::LEFT | Wx::RIGHT | Wx::TOP, 10)

        @banner = Banner.new(page)
        @banner.on_click { remeasure }
        @banner.hide
        centre.add(@banner, 0, Wx::EXPAND | Wx::ALL, 10)
        centre.add_spacer(4)
        row.add(centre, 1, Wx::EXPAND)
        page.set_sizer(row)
        page
      end

      def build_sheet_page(parent)
        page = Wx::Panel.new(parent)
        page.set_background_colour(Theme.face)
        column = Wx::VBoxSizer.new
        bar = Wx::HBoxSizer.new
        @sheet_note = Wx::StaticText.new(page, label: "")
        @sheet_note.set_font(Theme.small)
        @sheet_note.set_foreground_colour(Theme.muted)
        @edit_picked = Wx::Button.new(page, label: "Edit picked frames")
        @edit_picked.evt_button(@edit_picked.get_id) { edit_picked }
        @edit_picked.disable
        bar.add(@sheet_note, 0, Wx::ALIGN_CENTER_VERTICAL)
        bar.add_stretch_spacer(1)
        bar.add(@edit_picked, 0, Wx::ALIGN_CENTER_VERTICAL)
        column.add(bar, 0, Wx::EXPAND | Wx::ALL, 10)
        @sheet = SheetGrid.new(page)
        @sheet.on_pick { |picked| sheet_picked(picked) }
        @sheet.on_open do |stem|
          select_frame(stem)
          show_page(0)
        end
        @sheet.evt_scrollwin { |event| request_sheet(keep_gen: true); event.skip }
        column.add(@sheet, 1, Wx::EXPAND)
        page.set_sizer(column)
        page
      end

      # Worker ---------------------------------------------------------------

      def start_worker
        @worker = @app.roll_worker
        @app.watch(@worker) { |header, payload| worker_said(header, payload) }
        @worker.send(op: "open", source: @roll.source, cache: @app.analysis_cache(@roll),
                     args: @settings.setting_args, overrides: overrides_for_worker)
        @measuring = !@settings.convert_only
        status(@measuring ? "Measuring the roll..." : "Opening the roll...")
      end

      def overrides_for_worker
        all = @overrides.all
        if @pending_override
          stems, key, value = @pending_override
          stems.each { |stem| all[stem] = all.fetch(stem, {}).merge(key => value) }
        end
        all.transform_values { |values| values.transform_keys(&:to_s) }
      end

      def worker_said(header, payload)
        case header[:type]
        when "frames"
          @stems = header[:stems]
          @filmstrip.stems = @stems
          @filmstrip.marked = marked
          @sheet.stems = @stems
          @sheet.marked = marked
          select_frame(@stems.first) if @stems.any?
        when "thumb" then @filmstrip.set_thumb(header[:stem], image(header, payload))
        when "progress" then progress(header)
        when "measured" then measured(header)
        when "state" then state(header)
        when "scan"
          @scans[header[:stem]] = true
          @viewer.set(:scan, image(header, payload)) if header[:stem] == @stem
        when "frame" then frame_arrived(header, payload)
        when "tile"
          @sheet.set_tile(header[:stem], image(header, payload), fresh: header[:gen] == @sheet_gen)
          sheet_note
        when "full"
          return unless header[:stem] == @stem

          @viewer.set(:full, image(header, payload))
          @viewer.busy = false
          status(format("Frame %s at full size, %.1f s", Filmstrip.number(@stem), header[:ms] / 1000.0))
        when "error"
          @viewer.busy = false
          status("The worker hit a problem: #{header[:message]}")
          warn "#{header[:message]} at #{header[:where]}"
        end
      end

      def image(header, payload) = Wx::Image.new(header[:w], header[:h], payload)

      def progress(header)
        text = header[:text].to_s
        text = "#{text} #{header[:done]} of #{header[:total]}" if header[:total].to_i.positive?
        @measuring = true
        @banner.show_progress(text)
        @banner.show
        @banner.get_parent.layout
        status("Measuring the roll: #{text}")
      end

      def measured(header)
        @measuring = false
        @stale = header[:stale]
        @remeasure = false
        @measured_at = Time.now
        @measured_chip.text = "roll measured at #{@measured_at.strftime('%H:%M')}"
        @measured_chip.show
        update_banner
        request_frame
        request_sheet if @book.get_selection == 1
      end

      def state(header)
        @stale = header[:stale]
        @remeasure = header[:remeasure]
        update_banner
      end

      def frame_arrived(header, payload)
        return unless header[:stem] == @stem

        @viewer.keep_previous
        @viewer.set(:corrected, image(header, payload))
        @viewer.busy = header[:gen] != @gen
        @stale = header[:stale]
        kind = header[:corrected] ? "preview 1500px" : "lab scan only"
        status(format("Frame %s, %s, %.1f s", Filmstrip.number(@stem), kind, header[:ms] / 1000.0))
        update_banner
      end

      # Requests -------------------------------------------------------------

      def request_frame
        return unless @stem

        @gen += 1
        @worker.send(op: "frame", stem: @stem, gen: @gen, scan: !@scans.key?(@stem))
        @viewer.busy = true
      end

      def request_sheet(keep_gen: false)
        return unless @stems

        unless keep_gen
          @sheet_gen += 1
          @sheet.outdate
        end
        @worker.send(op: "sheet", stems: @sheet.order, gen: @sheet_gen)
        sheet_note
      end

      def send_settings
        @worker.send(op: "settings", args: @settings.setting_args, overrides: overrides_for_worker)
      end

      # A slider moved: the worker hears the new settings at once, and the
      # render waits for the hand to settle.
      def settings_moved(_tier, final)
        @match.text = MatchSummary.describe(@roll, @settings)
        send_settings
        @debounce ||= Wx::Timer.new(self).tap { |t| evt_timer(t.get_id) { settled } }
        @debounce.start(final ? 1 : DEBOUNCE, Wx::TIMER_ONE_SHOT)
        @app.queue.preview_activity
        @save_due = true
      end

      def settled
        request_frame
        request_sheet if @book.get_selection == 1
        if @save_due
          @settings.save
          @save_due = false
        end
      end

      def update_banner
        if @measuring
          @banner.show
        elsif @remeasure && !@settings.convert_only
          @banner.show_message("Re-measure first: this change alters what the roll's analysis measures.", "Re-measure now")
          @banner.show
        elsif @stale && !@settings.convert_only
          @banner.show_message("Approximate: settings changed since the roll was measured.", "Re-measure now, 1 to 3 min")
          @banner.show
        else
          @banner.hide
        end
        @banner.get_parent.layout
      end

      def status(text)
        @status.set_label(text)
        @status.get_parent.layout
      end

      # Actions --------------------------------------------------------------

      def select_frame(stem)
        return if stem.nil?

        @stem = stem
        @filmstrip.selection = stem
        @viewer.set(:corrected, nil)
        @viewer.set(:scan, nil)
        @viewer.set(:full, nil)
        @scans.delete(stem)
        @panel.frame = stem
        load_others(stem)
        request_frame
      end

      # The current output's version of the frame, and the sibling roll's
      # frame with the same position in the roll, for the Now and Sibling
      # views.
      def load_others(stem)
        now = @roll.output.find { |path| File.basename(path, ".*") == stem }
        @viewer.set(:now, nil)
        @viewer.set(:sibling, nil)
        @app.thumbs.fetch(now, 1500) { |img| @viewer.set(:now, img) if @stem == stem } if now
        sibling = MatchSummary.nearest_sibling(@roll, @settings, stem)
        @app.thumbs.fetch(sibling, 1500) { |img| @viewer.set(:sibling, img) if @stem == stem } if sibling
      end

      def view(mode)
        if VIEWS.any? { |key, _| key == mode }
          @views.selection = VIEWS.index { |key, _| key == mode }
          @others.selection = nil
        else
          @others.selection = OTHERS.index { |key, _| key == mode }
          @views.selection = nil
        end
        @viewer.mode = mode
      end

      def zoom(level)
        @zoom.selection = level == :fit ? 0 : 1
        @viewer.zoom = level
      end

      def full_size
        return unless @stem

        @worker.send(op: "full", stem: @stem, gen: @gen)
        @viewer.busy = true
        status("Rendering frame #{Filmstrip.number(@stem)} at full size, 8 to 15 s...")
      end

      def remeasure
        @worker.send(op: "measure")
        @measuring = true
        @banner.show_progress("Measuring the roll")
        @banner.show
        @banner.get_parent.layout
      end

      def show_page(index)
        @book.set_selection(index)
        @pages.selection = index
        if index == 2
          @split.unsplit(@panel) if @split.is_split
          @review.shown
        else
          @split.split_vertically(@book, @panel, -330) unless @split.is_split
          request_sheet if index == 1
        end
      end

      def sheet_picked(picked)
        @edit_picked.enable(picked.any?)
        @edit_picked.set_label(picked.size > 1 ? "Edit #{picked.size} picked frames" : "Edit picked frame")
        @edit_picked.get_parent.layout
      end

      def edit_picked
        picked = @sheet.picked
        return if picked.empty?

        @reach = picked.size > 1 ? :picked : :frame
        select_frame(picked.first)
        @panel.scope = :frame
        show_page(0)
      end

      def sheet_note
        return unless @stems

        fresh = @sheet.fresh_count
        @sheet_note.set_label(fresh >= @stems.size ? "All #{@stems.size} frames up to date" : "#{fresh} of #{@stems.size} frames updated, visible first")
      end

      def marked = @overrides.all.reject { |_, v| v.empty? }.keys

      # Which frames a per-frame change reaches.
      def reach_stems
        case @reach
        when :picked then @sheet.picked.any? ? @sheet.picked : [@stem]
        when :range
          from, to = (@range || []).map { |n| n.to_s.rjust(@stem.size, "0") }
          return [@stem] unless from && to && !from.strip.empty? && !to.strip.empty?

          (@stems || []).select { |stem| stem.between?(from, to) }
        else [@stem]
        end
      end

      def profile_choices
        @profile_choices ||= [["convert", "Convert only, no correction"]] +
                             FilmScan::Profile.available.map do |name|
                               [name, (FilmScan::Profile.load(name).name rescue name)]
                             end
      end

      def refresh_profile
        key = @settings.convert_only ? "convert" : @settings.profile
        index = profile_choices.index { |name, _| name == key }
        if index
          @profile.set_selection(index)
        else
          @profile.set_selection(Wx::NOT_FOUND)
        end
      end

      def profile_picked
        before = snapshot
        key = profile_choices[@profile.get_selection][0]
        if key == "convert"
          @settings.convert_only = true
        else
          @settings.convert_only = false
          @settings.profile = key
        end
        remember(before)
        @panel.refresh_values
        settings_moved(:remeasure, true)
      end

      def edit_match
        dialog = SiblingDialog.new(self, @app, @roll, @settings)
        dialog.show_window_modal do |result|
          apply_match(dialog.patterns, dialog.strength) if result == Wx::ID_OK
          dialog.destroy
        end
      end

      # New siblings and strength, written to sessions.yml; the roll is then
      # measured again against them.
      def apply_match(patterns, strength)
        before = snapshot
        @settings.match = patterns
        @settings.set(:match_strength, strength)
        remember(before)
        @settings.save
        @match.text = MatchSummary.describe(@roll, @settings)
        @panel.refresh_values
        settings_moved(:remeasure, true)
        load_others(@stem)
      end

      def render_menu
        menu = Wx::Menu.new
        trial = menu.append(Wx::ID_ANY, UI.plain("Trial render into #{short(@roll.trial_dir)}"))
        final = menu.append(Wx::ID_ANY, UI.plain("Final render into #{short(@roll.output_dir)}"))
        menu.evt_menu(trial.get_id) { render(:trial) }
        menu.evt_menu(final.get_id) { render(:final) }
        @render_button.popup_menu(menu, 0, @render_button.get_size.height)
      end

      def short(path)
        root = @app.config.library.to_s
        path.start_with?("#{root}/") ? path.delete_prefix("#{root}/") : path
      end

      def render(kind)
        @settings.save
        target = kind == :trial ? @roll.trial_dir : @roll.output_dir
        existing = kind == :trial ? @roll.trial : @roll.output
        if existing.any?
          answer = Wx.message_box("#{existing.size} files are already in #{short(target)}. They go to the Trash when the render starts.",
                                  "Replace the #{kind == :trial ? 'trial' : 'current'} render?",
                                  Wx::OK | Wx::CANCEL | Wx::ICON_QUESTION, self)
          return unless answer == Wx::OK
        end
        @app.queue.add(@roll, kind)
        @app.show_queue
      end

      # The toolkit's folder is never written to; says so when asked.
      def writable?(path)
        @app.config.refuse_toolkit!(path)
        true
      rescue Config::InsideToolkit => e
        status("Not saved: #{e.message}")
        false
      end

      # Undo -----------------------------------------------------------------

      def snapshot = @settings.to_h.merge("match" => @settings.match.dup)

      def remember(before)
        return unless before && before != snapshot

        @undo << before
        @undo.shift while @undo.size > 100
        @redo.clear
      end

      def restore(state)
        @settings.profile = state["profile"]
        @settings.convert_only = state["convert_only"]
        @settings.fix = state["fix"].map(&:to_sym)
        @settings.values.replace(state["values"].transform_keys(&:to_sym))
        @settings.match = state["match"]
        refresh_profile
        @panel.refresh_values
        settings_moved(:remeasure, true)
      end

      def undo
        return if @undo.empty?

        @redo << snapshot
        restore(@undo.pop)
      end

      def redo_change
        return if @redo.empty?

        @undo << snapshot
        restore(@redo.pop)
      end

      # Keys -----------------------------------------------------------------

      def key(event)
        focus = Wx::Window.find_focus
        typing = focus.is_a?(Wx::TextCtrl)
        code = event.get_key_code
        if code == Wx::K_SPACE && !typing && @book.get_selection.zero?
          @viewer.holding = true
          @viewer.set_focus
          return
        end
        if !typing && @book.get_selection.zero? && [Wx::K_LEFT, Wx::K_RIGHT, Wx::K_UP, Wx::K_DOWN].include?(code) && !focus.is_a?(Filmstrip)
          index = (@stems || []).index(@stem) || 0
          step = [Wx::K_LEFT, Wx::K_UP].include?(code) ? -1 : 1
          select_frame(@stems[(index + step).clamp(0, @stems.size - 1)]) if @stems
          return
        end
        event.skip
      end

      def space_up(event)
        @viewer.holding = false if event.get_key_code == Wx::K_SPACE
        event.skip
      end

      def closing(event)
        @settings.save if @save_due
        @debounce&.stop
        @app.unwatch(@worker)
        @worker.close
        @app.roll_closed(self)
        event.skip
      end
    end

    # A rounded, outlined label that sits among native controls.
    class ChipLabel < Canvas
      def initialize(parent, text)
        super(parent, size: [40, 22])
        self.text = text
      end

      def text=(text)
        @text = text
        w = Wx::GraphicsContext.draw_on { |gc| gc.set_font(Theme.small, Theme.text); gc.get_text_extent(@text.to_s)[0] }
        set_min_size([w.ceil + 18, 22])
        set_size([w.ceil + 18, 22])
        get_parent.layout
        refresh
      end

      private

      def background = get_parent.get_background_colour

      def draw(gc, w, h)
        chip(gc, @text, 1, (h - 18) / 2.0, solid: true)
      end
    end

    # The dashed notice under the viewer: approximate preview, re-measure
    # needed, or a measurement under way.
    class Banner < Canvas
      def initialize(parent)
        super(parent, size: [-1, 38])
        set_min_size([200, 38])
        @message = ""
        @action = nil
        set_cursor(Wx::Cursor.new(Wx::CURSOR_ARROW))
        evt_left_down { |event| @on_click&.call if @action && on_button?(event.get_position.x) }
        evt_motion { |event| set_cursor(Wx::Cursor.new(@action && on_button?(event.get_position.x) ? Wx::CURSOR_HAND : Wx::CURSOR_ARROW)) }
      end

      def on_click(&block)
        @on_click = block
        self
      end

      def show_message(message, action)
        @message = message
        @action = action
        @progress = false
        refresh
      end

      def show_progress(message)
        @message = message
        @action = nil
        @progress = true
        refresh
      end

      private

      def background = get_parent.get_background_colour

      def on_button?(x) = @button && x.between?(@button[0], @button[0] + @button[1])

      def draw(gc, w, h)
        gc.set_pen(gc.create_pen(Wx::GraphicsPenInfo.new(Theme.ink, 1).style(Wx::PENSTYLE_SHORT_DASH)))
        gc.set_brush(Theme.no_brush)
        gc.draw_rounded_rectangle(0.5, 0.5, w - 1, h - 1, 6)
        x = 12
        if @progress
          gc.set_pen(Theme.no_pen)
          gc.set_brush(Theme.brush(Theme.ink))
          gc.draw_ellipse(x, h / 2.0 - 4, 8, 8)
          x += 16
        else
          CostDot.draw(gc, :approx, x, (h - 10) / 2.0)
          x += 18
        end
        _, th = measure(gc, @message, font: Theme.small)
        text(gc, fitted(gc, @message, w - x - 200, font: Theme.small), x, (h - th) / 2.0, font: Theme.small)
        @button = nil
        return unless @action

        bw, bh = measure(gc, @action, font: Theme.small_strong)
        bx = w - bw - 30
        fill(gc, Theme.window, bx, (h - bh - 10) / 2.0, bw + 20, bh + 10, 5)
        outline(gc, Theme.line, bx + 0.5, (h - bh - 10) / 2.0 + 0.5, bw + 19, bh + 9, 5)
        text(gc, @action, bx + 10, (h - bh) / 2.0, font: Theme.small_strong)
        @button = [bx, bw + 20]
      end
    end
  end
end
