module FilmscanGUI
  module UI
    # Colours and fonts. Text and backgrounds follow the system's light or
    # dark appearance; anything that frames a photograph stays a neutral grey
    # with no colour in it, so frames are judged against grey.
    module Theme
      SURROUND = [56, 56, 56].freeze

      module_function

      # Each colour is asked of the system once and kept until the appearance
      # changes: on macOS each answer takes about 2 ms, and a scroll asks for
      # hundreds.
      def remember(name) = (@colours ||= {}).fetch(name) { @colours[name] = yield }
      def forget = @colours = nil

      def dark? = remember(:dark) { Wx::SystemSettings.is_appearance_dark }

      # A window size that fits the screen it opens on.
      def fit_size(width, height)
        screen = Wx.get_client_display_rect
        [[width, (screen.width * 0.94).round].min, [height, (screen.height * 0.92).round].min]
      end

      def system(name) = remember(name) { Wx::SystemSettings.get_colour(Wx.const_get(name)) }

      def window = system(:SYS_COLOUR_WINDOW)
      def face = system(:SYS_COLOUR_BTNFACE)
      def list = system(:SYS_COLOUR_LISTBOX)
      def text = system(:SYS_COLOUR_WINDOWTEXT)
      def muted = system(:SYS_COLOUR_GRAYTEXT)

      # The dark ink of the mockups: selected segments, knobs and markers.
      def ink = remember(:ink) { dark? ? rgb(232, 232, 228) : rgb(38, 38, 36) }
      def on_ink = remember(:on_ink) { dark? ? rgb(30, 30, 30) : rgb(250, 250, 248) }
      def line = remember(:line) { mix(text, face, 0.14) }
      def soft = remember(:soft) { mix(text, face, 0.07) }
      def softer = remember(:softer) { mix(text, face, 0.04) }
      def selected_row = remember(:selected_row) { mix(text, list, dark? ? 0.16 : 0.09) }
      def track = remember(:track) { mix(text, face, 0.18) }
      def surround = rgb(*SURROUND)
      def surround_text = rgb(200, 200, 196)
      def surround_muted = rgb(150, 150, 146)

      def rgb(r, g, b, a = 255) = Wx::Colour.new(r, g, b, a)

      # a over b, by share of a.
      def mix(a, b, share)
        rgb(*[[a.red, b.red], [a.green, b.green], [a.blue, b.blue]].map { |x, y| (x * share + y * (1 - share)).round })
      end

      def alpha(colour, a) = rgb(colour.red, colour.green, colour.blue, a)

      def base_font = Wx::SystemSettings.get_font(Wx::SYS_DEFAULT_GUI_FONT)

      def font(size: nil, weight: nil, mono: false)
        @fonts ||= {}
        @fonts[[size, weight, mono]] ||= begin
          font = mono ? Wx::Font.new(base_font.get_point_size, Wx::FONTFAMILY_TELETYPE, Wx::FONTSTYLE_NORMAL, Wx::FONTWEIGHT_NORMAL)
                      : Wx::Font.new(base_font)
          font.set_point_size(size) if size
          font.set_weight(weight == :bold ? Wx::FONTWEIGHT_BOLD : Wx::FONTWEIGHT_SEMIBOLD) if weight
          font
        end
      end

      def body = font
      def strong = font(weight: :semibold)
      def small = font(size: 11)
      def small_strong = font(size: 11, weight: :semibold)
      def tiny = font(size: 10)
      def title = font(size: 15, weight: :bold)
      def mono = font(size: 11, mono: true)

      # Pens and brushes are made once each and kept: on macOS a graphics
      # context takes about 1.5 ms to set a pen it has not seen before, and a
      # scroll redraws hundreds of them.
      def pen(colour, width = 1)
        width = width.round.clamp(1, 64)
        (@pens ||= {})[[key(colour), width]] ||= Wx::Pen.new(colour, width, Wx::PENSTYLE_SOLID)
      end

      # A pen of any width, fractions included, for a graphics context.
      def stroke(gc, colour, width = 1)
        return gc.set_pen(pen(colour, width)) if width.is_a?(Integer)

        gc.set_pen((@strokes ||= {})[[key(colour), width]] ||=
                     Wx::GraphicsRenderer.get_default_renderer.create_pen(Wx::GraphicsPenInfo.new(colour, width)))
      end

      def no_pen = @no_pen ||= Wx::Pen.new(rgb(0, 0, 0), 1, Wx::PENSTYLE_TRANSPARENT)
      def brush(colour) = (@brushes ||= {})[key(colour)] ||= Wx::Brush.new(colour)
      def no_brush = @no_brush ||= Wx::Brush.new(rgb(0, 0, 0), Wx::BRUSHSTYLE_TRANSPARENT)

      def key(colour) = [colour.red, colour.green, colour.blue, colour.alpha]
    end
  end
end
