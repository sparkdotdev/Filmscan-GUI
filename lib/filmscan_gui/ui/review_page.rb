require "fileutils"
require "time"
require_relative "widgets"
require_relative "viewer"
require_relative "filmstrip"
require_relative "../verdicts"
require_relative "../match_summary"
require_relative "../trash"
require_relative "../approve"

module FilmscanGUI
  module UI
    # One column of a review: a roll's frames as a small contact sheet.
    class ReviewSheet < ScrollCanvas
      ACROSS = 4
      GAP = 8
      NUMBER = 15

      def initialize(parent)
        super(parent)
        @items = []
        @thumbs = {}
        evt_left_dclick { |event| open(event) }
      end

      def on_open(&block) = (@on_open = block) && self
      def on_scroll(&block) = (@on_scroll = block) && self

      # Items are [stem, path].
      def items=(items)
        @items = items
        layout_content
        refresh
      end

      def thumb_arrived(path, image)
        @thumbs[path] = Wx::Bitmap.new(image)
        refresh
      end

      def blank=(text)
        @blank = text
        refresh
      end

      private

      def background = Theme.surround
      def cell_w = (width - GAP * (ACROSS + 1)) / ACROSS.to_f
      def cell_h = cell_w * 0.72 + NUMBER

      def layout_content
        rows = (@items.size / ACROSS.to_f).ceil
        self.content_height = GAP + rows * (cell_h + GAP)
      end

      def open(event)
        x, y = content_point(event)
        col = ((x - GAP) / (cell_w + GAP)).floor
        row = ((y - GAP) / (cell_h + GAP)).floor
        item = @items[row * ACROSS + col] if col.between?(0, ACROSS - 1)
        @on_open&.call(item[0]) if item
      end

      def draw(gc, w, _h, _top)
        if @items.empty?
          centred(gc, @blank || "Nothing here", 0, 0, w, 120, font: Theme.small, colour: Theme.surround_text)
          return
        end
        cw = cell_w
        box = cell_h - NUMBER
        @items.each_with_index do |(stem, path), i|
          x = GAP + (i % ACROSS) * (cw + GAP)
          y = GAP + (i / ACROSS) * (cell_h + GAP)
          rect = picture(gc, @thumbs[path], x, y, cw, box)
          unless rect
            rect = [x + cw * 0.08, y + box * 0.12, cw * 0.84, box * 0.76]
            placeholder(gc, *rect, dark: true)
          end
          label = stem.include?(" ") ? stem.split(" ").then { |id, s| "#{id} #{Filmstrip.number(s)}" } : Filmstrip.number(stem)
          text(gc, label, rect[0], rect[1] + rect[3] + 3, font: Theme.tiny, colour: Theme.surround_muted)
        end
      end
    end

    # Review: the output now, the new render and the sibling side by side,
    # as sheets or a frame at a time, with a verdict and the swap that puts
    # the new render in place of the old.
    class ReviewPage < Wx::Panel
      MODES = ["Sheets", "Frame by frame", "Blind"].freeze
      COLUMNS = %i[now new sibling].freeze

      def initialize(parent, app, owner)
        super(parent)
        @app = app
        @owner = owner
        @roll = owner.roll
        @verdicts = Verdicts.new(app.config.workspace)
        @index = 0
        set_background_colour(Theme.face)
        build
      end

      # Called when the page comes to the front.
      def shown
        @lists = {
          now: by_stem(@roll.output),
          new: by_stem(@roll.trial),
          sibling: sibling_items
        }
        @stems = (@lists[:now].keys | @lists[:new].keys).sort
        @stems = @roll.stems if @stems.empty?
        @swap = {}
        fill_sheets
        load_verdict
        show_frame if @mode != 0
        update_heads
      end

      private

      def build
        column = Wx::VBoxSizer.new
        bar = Wx::HBoxSizer.new
        @modes = Segmented.new(self, MODES)
        @modes.on_change { |i| mode(i) }
        bar.add(@modes, 0, Wx::ALIGN_CENTER_VERTICAL)
        @position = Wx::StaticText.new(self, label: "")
        @position.set_foreground_colour(Theme.muted)
        bar.add(@position, 0, Wx::ALIGN_CENTER_VERTICAL | Wx::LEFT, 12)
        bar.add_stretch_spacer(1)
        @zoom = Segmented.new(self, ["Fit", "100%"])
        @zoom.on_change { |i| @viewers&.each_value { |v| v.zoom = i.zero? ? :fit : :actual } }
        bar.add(@zoom, 0, Wx::ALIGN_CENTER_VERTICAL)
        column.add(bar, 0, Wx::EXPAND | Wx::ALL, 10)

        @book = Wx::Simplebook.new(self)
        @book.add_page(build_sheets(@book), "Sheets")
        @book.add_page(build_frames(@book), "Frames")
        column.add(@book, 1, Wx::EXPAND | Wx::LEFT | Wx::RIGHT, 10)
        column.add(build_verdict, 0, Wx::EXPAND | Wx::ALL, 10)
        set_sizer(column)
        @mode = 0
        @zoom.hide
      end

      def build_sheets(parent)
        page = Wx::Panel.new(parent)
        page.set_background_colour(Theme.face)
        row = Wx::HBoxSizer.new
        @heads = {}
        @sheets = {}
        COLUMNS.each_with_index do |key, i|
          col = Wx::VBoxSizer.new
          title = Wx::StaticText.new(page, label: "")
          title.set_font(Theme.strong)
          sub = Wx::StaticText.new(page, label: "")
          sub.set_font(Theme.small)
          sub.set_foreground_colour(Theme.muted)
          @heads[key] = [title, sub]
          col.add(title, 0)
          col.add(sub, 0, Wx::BOTTOM, 6)
          sheet = ReviewSheet.new(page)
          sheet.on_open do |stem|
            @index = @stems.index(stem) || 0
            mode(1)
          end
          @sheets[key] = sheet
          col.add(sheet, 1, Wx::EXPAND)
          row.add(col, 1, Wx::EXPAND | (i < 2 ? Wx::RIGHT : 0), 10)
        end
        page.set_sizer(row)
        page
      end

      def build_frames(parent)
        page = Wx::Panel.new(parent)
        page.set_background_colour(Theme.face)
        row = Wx::HBoxSizer.new
        @viewers = {}
        COLUMNS.each_with_index do |key, i|
          viewer = Viewer.new(page)
          viewer.mode = :scan
          viewer.evt_key_down { |event| arrow(event) }
          @viewers[key] = viewer
          row.add(viewer, 1, Wx::EXPAND | (i < 2 ? Wx::RIGHT : 0), 6)
        end
        page.set_sizer(row)
        page
      end

      def build_verdict
        bar = Wx::HBoxSizer.new
        label = Wx::StaticText.new(self, label: "This roll")
        label.set_font(Theme.strong)
        bar.add(label, 0, Wx::ALIGN_CENTER_VERTICAL | Wx::RIGHT, 10)
        @verdict = Segmented.new(self, ["1  Better", "2  Worse", "3  Too close to call"], selection: nil)
        @verdict.on_change { |i| verdict(Verdicts::CHOICES[i]) }
        bar.add(@verdict, 0, Wx::ALIGN_CENTER_VERTICAL | Wx::RIGHT, 10)
        @note = Wx::TextCtrl.new(self, style: Wx::TE_PROCESS_ENTER)
        @note.set_hint("Note")
        @note.evt_kill_focus { |event| save_note; event.skip }
        @note.evt_text_enter(@note.get_id) { save_note }
        bar.add(@note, 1, Wx::ALIGN_CENTER_VERTICAL | Wx::RIGHT, 10)
        @flagged = Wx::StaticText.new(self, label: "")
        bar.add(@flagged, 0, Wx::ALIGN_CENTER_VERTICAL | Wx::RIGHT, 8)
        @flag = Wx::Button.new(self, label: "Flag frame")
        @flag.evt_button(@flag.get_id) { flag }
        bar.add(@flag, 0, Wx::ALIGN_CENTER_VERTICAL | Wx::RIGHT, 6)
        fix = Wx::Button.new(self, label: "Fix in workspace")
        fix.evt_button(fix.get_id) { fix_flagged }
        bar.add(fix, 0, Wx::ALIGN_CENTER_VERTICAL | Wx::RIGHT, 6)
        @approve = Wx::Button.new(self, label: "Approve...")
        @approve.evt_button(@approve.get_id) { approve }
        @approve.set_tool_tip("Put the new render in place of the current output. The old files go to the Trash.")
        bar.add(@approve, 0, Wx::ALIGN_CENTER_VERTICAL)
        evt_char_hook { |event| keys(event) }
        bar
      end

      def by_stem(paths) = paths.to_h { |path| [File.basename(path, ".*"), path] }

      def sibling_items
        found = MatchSummary.rolls(@roll, @owner.settings)
        found.flat_map do |dir, picked, _|
          sibling = Roll.new(@roll.library, @roll.trip, @roll.base, dir.delete_prefix("#{@roll.base}/"))
          output = by_stem(sibling.output)
          prefix = found.size > 1 ? "#{sibling.id} " : ""
          picked.map { |path| stem = File.basename(path, ".*"); ["#{prefix}#{stem}", output[stem] || path] }
        end.to_h
      end

      def short(path)
        root = @app.config.library.to_s
        path.start_with?("#{root}/") ? path.delete_prefix("#{root}/") : path
      end

      def dated(paths) = paths.empty? ? "" : ", #{File.mtime(paths.first).strftime('%-d %b')}"

      def update_heads
        titles = { now: "Now", new: "New render", sibling: "Sibling" }
        subs = {
          now: @lists[:now].empty? ? "No output yet" : "#{short(@roll.output_dir)}#{dated(@lists[:now].values)}",
          new: @lists[:new].empty? ? "No trial render yet" : "#{short(@roll.trial_dir)}#{dated(@lists[:new].values)}",
          sibling: @owner.settings.match.empty? ? "No siblings chosen" : MatchSummary.describe(@roll, @owner.settings)
        }
        COLUMNS.each do |key|
          title, sub = @heads[key]
          title.set_label(titles[key])
          sub.set_label(UI.plain(subs[key]))
        end
        @approve.enable(@lists[:new].any?)
      end

      def fill_sheets
        blanks = { now: "No output yet", new: "Render a trial to review it here", sibling: "No siblings chosen" }
        COLUMNS.each do |key|
          sheet = @sheets[key]
          items = @lists[key].to_a
          sheet.blank = blanks[key]
          sheet.items = items
          items.each { |_, path| @app.thumbs.fetch(path, 360) { |image| sheet.thumb_arrived(path, image) } }
        end
      end

      def mode(index)
        @mode = index
        @modes.selection = index
        @book.set_selection(index.zero? ? 0 : 1)
        @zoom.show(!index.zero?)
        @zoom.get_parent.layout
        if index.zero?
          @position.set_label("")
          fill_sheets
        else
          show_frame
          @viewers[:new].set_focus
        end
        layout
      end

      def blind? = @mode == 2

      def show_frame
        return if @stems.empty?

        @index = @index.clamp(0, @stems.size - 1)
        stem = @stems[@index]
        swapped = blind? && (@swap[stem] ||= [true, false].sample)
        left, right = swapped ? %i[new now] : %i[now new]
        names = { now: "Now", new: "New render" }
        revealed = !blind? || @revealed
        { now: left, new: right }.each_with_index do |(slot, source), i|
          viewer = @viewers[slot]
          viewer.labels = viewer.labels.merge(scan: revealed ? names[source] : %w[A B][i])
          viewer.set(:scan, nil)
          path = @lists[source][stem]
          viewer.empty_text = path ? nil : (source == :now ? "No output for this frame" : "Not in the new render")
          @app.thumbs.fetch(path, 1500) { |image| viewer.set(:scan, image) if @stems[@index] == stem } if path
        end
        sibling = MatchSummary.nearest_sibling(@roll, @owner.settings, stem)
        @viewers[:sibling].labels = @viewers[:sibling].labels.merge(scan: "Sibling")
        @viewers[:sibling].set(:scan, nil)
        @viewers[:sibling].empty_text = sibling ? nil : "No sibling chosen"
        @app.thumbs.fetch(sibling, 1500) { |image| @viewers[:sibling].set(:scan, image) if @stems[@index] == stem } if sibling
        flagged = Array(@verdicts.for(@roll)["flagged"]).include?(stem)
        @position.set_label("Frame #{Filmstrip.number(stem)}, #{@index + 1} of #{@stems.size}#{flagged ? ', flagged' : ''}" \
                            "#{blind? && !@revealed ? '. A and B are hidden until you give a verdict.' : ''}")
        @position.get_parent.layout
      end

      def arrow(event)
        case event.get_key_code
        when Wx::K_LEFT, Wx::K_UP then step(-1)
        when Wx::K_RIGHT, Wx::K_DOWN then step(1)
        else event.skip
        end
      end

      def step(by)
        @index = (@index + by).clamp(0, [@stems.size - 1, 0].max)
        show_frame
      end

      def keys(event)
        typing = Wx::Window.find_focus.is_a?(Wx::TextCtrl)
        choice = { "1".ord => 0, "2".ord => 1, "3".ord => 2 }[event.get_key_code]
        if choice && !typing && !event.cmd_down
          @verdict.selection = choice
          verdict(Verdicts::CHOICES[choice])
        elsif !typing && @mode != 0 && [Wx::K_LEFT, Wx::K_RIGHT].include?(event.get_key_code)
          step(event.get_key_code == Wx::K_LEFT ? -1 : 1)
        else
          event.skip
        end
      end

      def load_verdict
        entry = @verdicts.for(@roll)
        @verdict.selection = Verdicts::CHOICES.index(entry["verdict"])
        @note.change_value(entry["note"].to_s)
        @revealed = !entry["verdict"].nil?
        show_flagged(entry)
      end

      def verdict(choice)
        return if @app.config.inside_toolkit?(@app.config.workspace)

        @verdicts.set(@roll, verdict: choice)
        @revealed = true
        show_frame if @mode != 0
      end

      def save_note = @verdicts.set(@roll, note: @note.get_value.strip)

      def flag
        stem = @stems[@index] or return
        flagged = Array(@verdicts.for(@roll)["flagged"])
        flagged = flagged.include?(stem) ? flagged - [stem] : (flagged + [stem]).sort
        show_flagged(@verdicts.set(@roll, flagged: flagged))
        show_frame if @mode != 0
      end

      def show_flagged(entry)
        flagged = Array(entry["flagged"])
        @flagged.set_label(flagged.empty? ? "" : "Flagged: #{flagged.map { |s| Filmstrip.number(s) }.join(', ')}")
        @flag.set_label(@mode != 0 && flagged.include?(@stems&.[](@index)) ? "Unflag frame" : "Flag frame")
        layout
      end

      def fix_flagged
        flagged = Array(@verdicts.for(@roll)["flagged"])
        stem = flagged.first || @stems[@index]
        @owner.command(:frame_page)
        @owner.send(:select_frame, stem) if stem
        @owner.scope_changed(:frame)
      end

      # Moves the current output to the Trash and the new render into its
      # place, roll by roll, and logs every file moved.
      def approve
        incoming = @roll.trial
        return if incoming.empty?

        outgoing = @roll.output
        message = if outgoing.any?
                    "The #{outgoing.size} files in #{short(@roll.output_dir)} go to the Trash, and the #{incoming.size} " \
                      "new ones take their place."
                  else
                    "The #{incoming.size} new files move into #{short(@roll.output_dir)}."
                  end
        dialog = Wx::MessageDialog.new(get_parent, message, "Swap in the new render?", Wx::OK | Wx::CANCEL | Wx::ICON_QUESTION)
        dialog.set_ok_label("Approve and swap")
        dialog.show_window_modal do |answer|
          swap(incoming, outgoing) if answer == Wx::ID_OK
          dialog.destroy
        end
      end

      def swap(incoming, _outgoing)
        log = File.join(@app.config.workspace, "gui", "approve.log")
        moved = Approve.swap(@roll, log)
        @verdicts.set(@roll, approved: Time.now.iso8601)
        shown
        Wx.message_box("#{moved} files are now in #{short(@roll.output_dir)}.", "Approved", Wx::OK, get_parent)
      rescue StandardError => e
        Wx.message_box("The swap stopped: #{e.message}. Nothing more was moved; see #{log}.", "Approve", Wx::OK | Wx::ICON_ERROR,
                       get_parent)
      end
    end
  end
end
