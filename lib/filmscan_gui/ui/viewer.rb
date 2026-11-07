require_relative "canvas"

module FilmscanGUI
  module UI
    # One frame on a neutral grey surround: the lab scan and the correction
    # split by a divider you drag, side by side, or one at a time, plus the
    # current output ("now") and the sibling roll's nearest frame. Fit shows
    # all of it; 100% shows pixels one to one and drags to pan.
    class Viewer < Canvas
      MODES = %i[split side scan corrected now sibling].freeze
      LABELS = { scan: "Lab scan", corrected: "Corrected", now: "Now", sibling: "Sibling" }.freeze
      INSET = 18

      attr_reader :mode, :zoom
      attr_accessor :labels, :empty_text

      def initialize(parent)
        super(parent, style: Wx::WANTS_CHARS)
        @mode = :split
        @zoom = :fit
        @split = 0.5
        @pan = [0.0, 0.0]
        @bitmaps = {}
        @labels = LABELS.dup
        set_min_size([320, 220])
        evt_left_down { |event| press(event) }
        evt_motion { |event| move(event) }
        evt_left_up { |_| @drag = nil }
        evt_leave_window { |_| set_cursor(Wx::Cursor.new(Wx::CURSOR_ARROW)) unless @drag }
      end

      def mode=(mode)
        @mode = mode
        refresh
      end

      def zoom=(zoom)
        @zoom = zoom
        @pan = [0.0, 0.0]
        refresh
      end

      # Sets one of the images, as a Wx::Image or nil.
      def set(kind, image)
        @bitmaps[kind] = image && Wx::Bitmap.new(image)
        refresh
      end

      def has?(kind) = !@bitmaps[kind].nil?

      # Keeps the shown correction aside, for holding Space.
      def keep_previous
        @bitmaps[:previous] = @bitmaps[:corrected] if @bitmaps[:corrected]
      end

      def holding=(on)
        @holding = on && @bitmaps[:previous]
        refresh
      end

      def busy=(on)
        @busy = on
        refresh
      end

      def note=(text)
        @note = text
        refresh
      end

      def clear
        @bitmaps.clear
        @note = nil
        refresh
      end

      private

      def background = Theme.surround

      def corrected = @holding ? @bitmaps[:previous] : (@bitmaps[:full] || @bitmaps[:corrected])
      def bitmap_for(kind) = kind == :corrected ? corrected : @bitmaps[kind]

      # Where the main picture goes: fitted into the window, or at one image
      # pixel per screen pixel when zoomed, moved by the pan.
      def frame_rect(bitmap, x, y, w, h)
        bw = bitmap.get_width.to_f
        bh = bitmap.get_height.to_f
        if @zoom == :fit
          s = [w / bw, h / bh].min
        else
          # The full-size render, when there is one, sets the scale for both.
          full = @bitmaps[:full]
          s = (full ? full.get_width / bw : 1.0) / scale
        end
        dw = bw * s
        dh = bh * s
        [x + (w - dw) / 2.0 + @pan[0], y + (h - dh) / 2.0 + @pan[1], dw, dh]
      end

      def draw(gc, w, h)
        x = INSET
        y = INSET
        aw = w - 2 * INSET
        ah = h - 2 * INSET
        case @mode
        when :split then draw_split(gc, x, y, aw, ah)
        when :side
          half = (aw - INSET) / 2.0
          draw_one(gc, :scan, x, y, half, ah)
          draw_one(gc, :corrected, x + half + INSET, y, half, ah)
        else draw_one(gc, @mode, x, y, aw, ah)
        end
        draw_status(gc, w, h)
      end

      def draw_split(gc, x, y, w, h)
        base = bitmap_for(:scan) || corrected
        return waiting(gc, x, y, w, h) unless base

        rx, ry, rw, rh = frame_rect(base, x, y, w, h)
        cut = rx + rw * @split
        gc.push_state
        gc.clip(rx, ry, cut - rx, rh)
        gc.draw_bitmap(bitmap_for(:scan) || base, rx, ry, rw, rh)
        gc.pop_state
        gc.push_state
        gc.clip(cut, ry, rx + rw - cut, rh)
        if corrected
          gc.draw_bitmap(corrected, rx, ry, rw, rh)
        else
          placeholder(gc, cut, ry, rx + rw - cut, rh, dark: true)
        end
        gc.pop_state
        @divider = [cut, ry, rh]
        fill(gc, Theme.rgb(255, 255, 255, 230), cut - 1, ry, 2, rh)
        handle(gc, cut, ry + rh / 2.0)
        label(gc, @labels[:scan], rx + 10, ry + 10)
        right = @holding ? "Previous" : @labels[:corrected]
        label(gc, right, rx + rw - 10, ry + 10, align: :right)
      end

      def draw_one(gc, kind, x, y, w, h)
        bitmap = bitmap_for(kind)
        return waiting(gc, x, y, w, h, kind) unless bitmap

        rx, ry, rw, rh = frame_rect(bitmap, x, y, w, h)
        gc.draw_bitmap(bitmap, rx, ry, rw, rh)
        text = kind == :corrected && @holding ? "Previous" : @labels[kind]
        label(gc, text, rx + 10, ry + 10) if text
      end

      def waiting(gc, x, y, w, h, kind = nil)
        aspect = 1.5
        dw = [w, h * aspect].min
        dh = dw / aspect
        placeholder(gc, x + (w - dw) / 2, y + (h - dh) / 2, dw, dh, dark: true)
        message = @empty_text || (kind && %i[now sibling].include?(kind) ? "No #{@labels[kind].downcase} frame" : "Loading")
        centred(gc, message, x, y, w, h, font: Theme.small, colour: Theme.surround_text)
      end

      # A dark rounded label over the picture.
      def label(gc, string, x, y, align: :left)
        tw, th = measure(gc, string, font: Theme.small_strong)
        bw = tw + 14
        bx = align == :right ? x - bw : x
        fill(gc, Theme.rgb(24, 24, 24, 190), bx, y, bw, th + 6, (th + 6) / 2.0)
        text(gc, string, bx + 7, y + 3, font: Theme.small_strong, colour: Theme.rgb(240, 240, 236))
      end

      def handle(gc, cx, cy)
        r = 13
        Theme.stroke(gc, Theme.rgb(30, 30, 30), 1.5)
        gc.set_brush(Theme.brush(Theme.rgb(248, 248, 246)))
        gc.draw_ellipse(cx - r, cy - r, 2 * r, 2 * r)
        Theme.stroke(gc, Theme.rgb(40, 40, 40), 1.5)
        [-1, 1].each do |side|
          gc.stroke_line(cx + 6 * side, cy, cx + 2 * side, cy - 4)
          gc.stroke_line(cx + 6 * side, cy, cx + 2 * side, cy + 4)
        end
      end

      def draw_status(gc, w, h)
        parts = []
        parts << "Rendering" if @busy
        parts << @note if @note
        return if parts.empty?

        string = parts.join("  ")
        tw, th = measure(gc, string, font: Theme.small)
        bw = tw + 22
        bx = w - bw - 10
        by = h - th - 16
        fill(gc, Theme.rgb(24, 24, 24, 200), bx, by, bw, th + 8, (th + 8) / 2.0)
        if @busy
          gc.set_pen(Theme.no_pen)
          gc.set_brush(Theme.brush(Theme.rgb(230, 230, 226)))
          gc.draw_ellipse(bx + 8, by + (th + 8) / 2.0 - 3, 6, 6)
        end
        text(gc, string, bx + (@busy ? 18 : 11), by + 4, font: Theme.small, colour: Theme.rgb(236, 236, 232))
      end

      def near_divider?(x, y)
        return false unless @mode == :split && @divider

        cut, top, span = @divider
        (x - cut).abs <= 10 && y.between?(top, top + span)
      end

      def press(event)
        set_focus
        point = event.get_position
        @last = [point.x, point.y]
        @drag = if near_divider?(point.x, point.y) then :divider
                elsif @zoom != :fit then :pan
                end
      end

      def move(event)
        point = event.get_position
        unless event.left_is_down && @drag
          cursor = near_divider?(point.x, point.y) ? Wx::CURSOR_SIZEWE : (@zoom == :fit ? Wx::CURSOR_ARROW : Wx::CURSOR_HAND)
          set_cursor(Wx::Cursor.new(cursor))
          return
        end
        if @drag == :divider
          base = bitmap_for(:scan) || corrected
          return unless base

          rx, _, rw, = frame_rect(base, INSET, INSET, width - 2 * INSET, height - 2 * INSET)
          @split = ((point.x - rx) / rw).clamp(0.0, 1.0)
        else
          @pan = [@pan[0] + point.x - @last[0], @pan[1] + point.y - @last[1]]
        end
        @last = [point.x, point.y]
        refresh
      end
    end
  end
end
