require_relative "theme"

module FilmscanGUI
  module UI
    # Runs a block from an event handler, logging what it raises: an error
    # escaping a handler would take the whole app down.
    def self.guard
      yield
    rescue StandardError => e
      # A window closed while its image was on the way.
      return nil if e.class.name.to_s.end_with?("PreviouslyDeleted")

      warn "#{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}"
      nil
    end

    # Text for a native label or menu item, where & marks a mnemonic.
    def self.plain(text) = text.to_s.gsub("&", "&&")

    # Drawing helpers for custom-drawn controls.
    module Drawing
      private

      def fill(gc, colour, x, y, w, h, radius = 0)
        gc.set_pen(Theme.no_pen)
        gc.set_brush(Theme.brush(colour))
        radius.positive? ? gc.draw_rounded_rectangle(x, y, w, h, radius) : gc.draw_rectangle(x, y, w, h)
      end

      def outline(gc, colour, x, y, w, h, radius = 0, width = 1)
        Theme.stroke(gc, colour, width)
        gc.set_brush(Theme.no_brush)
        radius.positive? ? gc.draw_rounded_rectangle(x, y, w, h, radius) : gc.draw_rectangle(x, y, w, h)
      end

      # Light or dark mode changed: the colours kept for it are asked for again.
      def appearance_changed(event)
        Theme.forget
        refresh
        event.skip
      end

      def text(gc, string, x, y, font: Theme.body, colour: Theme.text)
        gc.set_font(font, colour)
        gc.draw_text(string.to_s, x, y)
      end

      # Kept, since measuring takes about 0.25 ms and a scroll redraws the
      # same few hundred strings over and over.
      def measure(gc, string, font: Theme.body)
        Drawing.remembered(:extent, string.to_s, font) do
          gc.set_font(font, Theme.text)
          w, h, = gc.get_text_extent(string.to_s)
          [w, h]
        end
      end

      def self.remembered(*key)
        @remembered ||= {}
        @remembered.clear if @remembered.size > 50_000
        @remembered.fetch(key) { @remembered[key] = yield }
      end

      # Text centred in a box.
      def centred(gc, string, x, y, w, h, font: Theme.body, colour: Theme.text)
        tw, th = measure(gc, string, font: font)
        text(gc, string, x + (w - tw) / 2.0, y + (h - th) / 2.0, font: font, colour: colour)
      end

      # Text cut with an ellipsis to fit a width.
      def fitted(gc, string, max, font: Theme.body)
        string = string.to_s
        Drawing.remembered(:fitted, string, max.floor, font) do
          next string if measure(gc, string, font: font)[0] <= max

          cut = string
          cut = cut[0...-1] while cut.length > 1 && measure(gc, "#{cut}...", font: font)[0] > max
          "#{cut}..."
        end
      end

      # A rounded label, filled or outlined. Returns its width.
      def chip(gc, string, x, y, solid: false, font: Theme.small, inverted: false)
        tw, th = measure(gc, string, font: font)
        w = tw + 14
        h = th + 4
        if inverted
          fill(gc, Theme.ink, x, y, w, h, h / 2.0)
          text(gc, string, x + 7, y + 2, font: font, colour: Theme.on_ink)
        else
          fill(gc, solid ? Theme.soft : Theme.face, x, y, w, h, h / 2.0)
          outline(gc, Theme.line, x + 0.5, y + 0.5, w - 1, h - 1, (h - 1) / 2.0)
          text(gc, string, x + 7, y + 2, font: font, colour: Theme.text)
        end
        w
      end

      # A photo or tile, scaled into a box with its aspect kept. Returns the
      # rectangle it took.
      def picture(gc, bitmap, x, y, w, h)
        return nil unless bitmap

        bw = bitmap.get_width.to_f
        bh = bitmap.get_height.to_f
        s = [w / bw, h / bh].min
        dw = bw * s
        dh = bh * s
        dx = x + (w - dw) / 2.0
        dy = y + (h - dh) / 2.0
        gc.draw_bitmap(bitmap, dx, dy, dw, dh)
        [dx, dy, dw, dh]
      end

      # Hatched stand-in for a frame that has not arrived yet.
      def placeholder(gc, x, y, w, h, dark: false)
        base = dark ? Theme.rgb(70, 70, 70) : Theme.soft
        fill(gc, base, x, y, w, h)
        gc.set_pen(Theme.pen(dark ? Theme.rgb(82, 82, 82) : Theme.line))
        gc.push_state
        gc.clip(x, y, w, h)
        step = 7
        (-h.to_i..w.to_i).step(step) { |d| gc.stroke_line(x + d, y + h, x + d + h, y) }
        gc.pop_state
      end
    end

    # A custom-drawn control. Subclasses implement #draw(gc, width, height)
    # with an antialiased graphics context, double buffered.
    class Canvas < Wx::Window
      include Drawing

      def initialize(parent, size: Wx::DEFAULT_SIZE, style: 0)
        super(parent, Wx::ID_ANY, Wx::DEFAULT_POSITION, size, style | Wx::FULL_REPAINT_ON_RESIZE | Wx::BORDER_NONE)
        set_background_style(Wx::BG_STYLE_PAINT)
        evt_paint { paint_buffered { |dc| UI.guard { render(dc) } } }
        evt_sys_colour_changed { |event| appearance_changed(event) }
      end

      def width = get_client_size.width
      def height = get_client_size.height

      # Pixels per point, 2 on a Retina screen.
      def scale = get_content_scale_factor

      private

      def render(dc)
        Wx::GraphicsContext.draw_on(dc) do |gc|
          gc.set_antialias_mode(Wx::ANTIALIAS_DEFAULT)
          gc.set_interpolation_quality(Wx::INTERPOLATION_BEST)
          gc.set_brush(Theme.brush(background))
          gc.set_pen(Theme.no_pen)
          gc.draw_rectangle(0, 0, width, height)
          draw(gc, width, height)
        end
      end

      def background = Theme.face
    end

    # A custom-drawn area taller than its window, with a native scrollbar.
    # #draw gets the whole content height; what is off screen is clipped.
    class ScrollCanvas < Wx::ScrolledCanvas
      include Drawing
      STEP = 12

      def initialize(parent, style: 0)
        super(parent, Wx::ID_ANY, Wx::DEFAULT_POSITION, Wx::DEFAULT_SIZE,
              style | Wx::VSCROLL | Wx::FULL_REPAINT_ON_RESIZE | Wx::BORDER_NONE)
        set_background_style(Wx::BG_STYLE_PAINT)
        set_scroll_rate(0, STEP)
        evt_paint { paint_buffered { |dc| UI.guard { render(dc) } } }
        evt_sys_colour_changed { |event| appearance_changed(event) }
        evt_size { |event| UI.guard { layout_content }; event.skip }
      end

      def width = get_client_size.width
      def height = get_client_size.height
      def scale = get_content_scale_factor
      def offset = get_view_start.y * STEP

      # Content coordinates of a mouse event.
      def content_point(event)
        point = event.get_position
        [point.x, point.y + offset]
      end

      def content_height=(h)
        set_virtual_size(width, h.ceil)
      end

      # Scrolls so a band of content shows.
      def reveal(top, bottom)
        if top < offset
          scroll(0, (top / STEP).floor)
        elsif bottom > offset + height
          scroll(0, ((bottom - height) / STEP.to_f).ceil)
        end
      end

      private

      def layout_content; end

      def render(dc)
        Wx::GraphicsContext.draw_on(dc) do |gc|
          gc.set_antialias_mode(Wx::ANTIALIAS_DEFAULT)
          gc.set_interpolation_quality(Wx::INTERPOLATION_BEST)
          gc.set_brush(Theme.brush(background))
          gc.set_pen(Theme.no_pen)
          gc.draw_rectangle(0, 0, width, height)
          gc.translate(0, -offset)
          draw(gc, width, height, offset)
        end
      end

      def background = Theme.face
    end
  end
end
