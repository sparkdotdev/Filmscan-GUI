require_relative "canvas"

module FilmscanGUI
  module UI
    # The roll's frames in a column, numbered without the lab's zeros, the
    # current one outlined and frames with overrides marked with a dot.
    class Filmstrip < ScrollCanvas
      WIDTH = 92
      BOX = 66
      ROW = BOX + 22

      attr_reader :selection

      def initialize(parent)
        super(parent, style: Wx::WANTS_CHARS)
        set_min_size([WIDTH, 120])
        @stems = []
        @thumbs = {}
        @marked = []
        evt_left_down { |event| click(event) }
        evt_key_down { |event| key(event) }
      end

      def on_select(&block)
        @on_select = block
        self
      end

      def stems=(stems)
        @stems = stems
        self.content_height = @stems.size * ROW + 8
        refresh
      end

      def set_thumb(stem, image)
        @thumbs[stem] = Wx::Bitmap.new(image)
        refresh
      end

      def marked=(stems)
        @marked = stems
        refresh
      end

      def selection=(stem)
        @selection = stem
        index = @stems.index(stem)
        reveal(index * ROW, (index + 1) * ROW + 8) if index
        refresh
      end

      def self.number(stem) = stem.sub(/\A0+(?=.)/, "")

      private

      def background = Theme.softer

      def click(event)
        set_focus
        _, y = content_point(event)
        index = ((y - 4) / ROW).floor
        stem = @stems[index] if index >= 0
        choose(stem) if stem
      end

      def key(event)
        index = @stems.index(@selection) || 0
        case event.get_key_code
        when Wx::K_UP, Wx::K_LEFT then choose(@stems[[index - 1, 0].max])
        when Wx::K_DOWN, Wx::K_RIGHT then choose(@stems[[index + 1, @stems.size - 1].min])
        else event.skip
        end
      end

      def choose(stem)
        return if stem == @selection

        self.selection = stem
        @on_select&.call(stem)
      end

      def draw(gc, w, _h, top)
        first = [(top / ROW).floor - 1, 0].max
        last = [((top + height) / ROW).ceil + 1, @stems.size - 1].min
        (first..last).each do |i|
          stem = @stems[i]
          y = 6 + i * ROW
          x = (w - BOX) / 2.0
          rect = picture(gc, @thumbs[stem], x, y, BOX, BOX) || begin
            placeholder(gc, x + 4, y + 11, BOX - 8, BOX - 22)
            [x + 4, y + 11, BOX - 8, BOX - 22]
          end
          if stem == @selection
            outline(gc, Theme.ink, rect[0] - 2.5, rect[1] - 2.5, rect[2] + 5, rect[3] + 5, 3, 2)
          end
          if @marked.include?(stem)
            gc.set_pen(Theme.pen(Theme.softer))
            gc.set_brush(Theme.brush(Theme.ink))
            gc.draw_ellipse(rect[0] + rect[2] - 9, rect[1] + 2, 8, 8)
          end
          centred(gc, Filmstrip.number(stem), 0, y + BOX + 1, w, 16, font: Theme.tiny,
                  colour: stem == @selection ? Theme.text : Theme.muted)
        end
      end
    end
  end
end
