require_relative "canvas"
require_relative "filmstrip"

module FilmscanGUI
  module UI
    # The roll as a contact sheet, six across like the toolkit's own. Tiles
    # from older settings stay up, dimmed, until their new version lands.
    # Click picks a frame, Shift picks a run, Command adds or drops one; a
    # double click opens the frame.
    class SheetGrid < ScrollCanvas
      COLUMNS = 6
      GAP = 10
      PAD = 14
      NUMBER = 16

      attr_reader :picked

      def initialize(parent)
        super(parent, style: Wx::WANTS_CHARS)
        @stems = []
        @tiles = {}
        @fresh = []
        @picked = []
        @marked = []
        evt_left_down { |event| click(event) }
        evt_left_dclick { |event| open(event) }
      end

      def on_pick(&block) = (@on_pick = block) && self
      def on_open(&block) = (@on_open = block) && self

      def stems=(stems)
        @stems = stems
        layout_content
        refresh
      end

      def set_tile(stem, image, fresh: true)
        @tiles[stem] = Wx::Bitmap.new(image)
        fresh ? @fresh |= [stem] : @fresh -= [stem]
        refresh
      end

      # Every tile is out of date until its new render arrives.
      def outdate
        @fresh = []
        refresh
      end

      def marked=(stems)
        @marked = stems
        refresh
      end

      def picked=(stems)
        @picked = stems
        refresh
      end

      def fresh_count = @fresh.size

      # Frames on screen first, then the rest in order.
      def order
        top = offset
        visible = @stems.each_index.select do |i|
          y = cell_y(i)
          y + cell_h > top && y < top + height
        end
        visible.map { |i| @stems[i] } + (@stems - visible.map { |i| @stems[i] })
      end

      private

      def background = Theme.surround
      def cell_w = (width - 2 * PAD - (COLUMNS - 1) * GAP) / COLUMNS.to_f
      def cell_h = cell_w * 0.78 + NUMBER
      def cell_x(i) = PAD + (i % COLUMNS) * (cell_w + GAP)
      def cell_y(i) = PAD + (i / COLUMNS) * (cell_h + GAP)

      def layout_content
        rows = (@stems.size / COLUMNS.to_f).ceil
        self.content_height = 2 * PAD + rows * cell_h + [rows - 1, 0].max * GAP
      end

      def index_at(event)
        x, y = content_point(event)
        @stems.each_index.find { |i| x.between?(cell_x(i), cell_x(i) + cell_w) && y.between?(cell_y(i), cell_y(i) + cell_h) }
      end

      def click(event)
        set_focus
        i = index_at(event) or return
        stem = @stems[i]
        if event.shift_down && @anchor
          a, b = [@stems.index(@anchor), i].minmax
          @picked = @stems[a..b]
        elsif event.cmd_down
          @picked = @picked.include?(stem) ? @picked - [stem] : @picked + [stem]
          @anchor = stem
        else
          @picked = [stem]
          @anchor = stem
        end
        refresh
        @on_pick&.call(@picked)
      end

      def open(event)
        i = index_at(event) or return
        @on_open&.call(@stems[i])
      end

      def draw(gc, w, _h, top)
        cw = cell_w
        ch = cell_h
        box_h = ch - NUMBER
        @stems.each_with_index do |stem, i|
          x = cell_x(i)
          y = cell_y(i)
          next if y + ch < top || y > top + height

          tile = @tiles[stem]
          rect = picture(gc, tile, x, y, cw, box_h)
          unless rect
            pw = cw * 0.86
            ph = pw / 1.5
            placeholder(gc, x + (cw - pw) / 2, y + (box_h - ph) / 2, pw, ph, dark: true)
            rect = [x + (cw - pw) / 2, y + (box_h - ph) / 2, pw, ph]
          end
          stale = tile && !@fresh.include?(stem)
          if stale
            fill(gc, Theme.rgb(56, 56, 56, 120), *rect)
            pill(gc, "updating", rect[0] + rect[2] / 2.0, rect[1] + rect[3] / 2.0)
          end
          if @picked.include?(stem)
            outline(gc, Theme.rgb(245, 245, 242), rect[0] - 3, rect[1] - 3, rect[2] + 6, rect[3] + 6, 3, 2)
          end
          if @marked.include?(stem)
            gc.set_pen(Theme.pen(Theme.surround))
            gc.set_brush(Theme.brush(Theme.rgb(245, 245, 242)))
            gc.draw_ellipse(rect[0] + rect[2] - 11, rect[1] + 3, 8, 8)
          end
          text(gc, Filmstrip.number(stem), rect[0], rect[1] + rect[3] + 3, font: Theme.tiny, colour: Theme.surround_muted)
        end
      end

      def pill(gc, string, cx, cy)
        tw, th = measure(gc, string, font: Theme.tiny)
        fill(gc, Theme.rgb(24, 24, 24, 200), cx - tw / 2 - 7, cy - th / 2 - 3, tw + 14, th + 6, (th + 6) / 2.0)
        text(gc, string, cx - tw / 2, cy - th / 2, font: Theme.tiny, colour: Theme.rgb(235, 235, 230))
      end
    end
  end
end
