module FilmscanGUI
  module UI
    # The menu bar, the same in every window. Items a window cannot do are
    # greyed out there; the rest go to the window or to the app.
    class Menus
      ITEMS = [
        ["File", [[:close, "Close Window\tCtrl+W"], [:preferences, "Settings...\tCtrl+,", Wx::ID_PREFERENCES],
                  [:about, "About #{APP_NAME}", Wx::ID_ABOUT], [:quit, "Quit #{APP_NAME}\tCtrl+Q", Wx::ID_EXIT]]],
        ["Edit", [[:undo, "Undo\tCtrl+Z"], [:redo, "Redo\tCtrl+Shift+Z"], nil, [:copy_command, "Copy Command Line\tCtrl+Shift+C"]]],
        ["View", [[:frame_page, "Frame\tCtrl+1"], [:sheet_page, "Contact Sheet\tCtrl+2"], [:review_page, "Review\tCtrl+3"], nil,
                  [:split, "Split\tCtrl+Alt+1"], [:side, "Side by Side\tCtrl+Alt+2"], [:scan, "Lab Scan\tCtrl+Alt+3"],
                  [:corrected, "Corrected\tCtrl+Alt+4"], [:now, "Now\tCtrl+Alt+5"], [:sibling, "Sibling\tCtrl+Alt+6"], nil,
                  [:fit, "Fit\tCtrl+0"], [:actual, "Actual Size\tCtrl+="]]],
        ["Roll", [[:remeasure, "Re-measure\tCtrl+R"], [:full, "Check at Full Size\tCtrl+K"], [:match, "Match Siblings...\tCtrl+M"], nil,
                  [:trial, "Trial Render\tCtrl+T"], [:final, "Final Render\tCtrl+Shift+T"]]],
        ["Window", [[:library, "Library\tCtrl+L"], [:queue, "Render Queue\tCtrl+J"]]]
      ].freeze
      APP = %i[preferences about quit library queue].freeze

      def initialize(app)
        @app = app
        @ids = {}
        next_id = Wx::ID_HIGHEST + 100
        ITEMS.each do |_, items|
          items.compact.each do |name, _, id|
            @ids[name] = id || (next_id += 1)
          end
        end
      end

      def build(frame)
        bar = Wx::MenuBar.new
        ITEMS.each do |title, items|
          menu = Wx::Menu.new
          items.each do |item|
            next menu.append_separator unless item

            name, label, = item
            menu.append(@ids[name], label)
            frame.evt_menu(@ids[name]) { run(frame, name) }
            menu.enable(@ids[name], false) unless APP.include?(name) || name == :close || frame.respond_to?(:command)
          end
          bar.append(menu, title)
        end
        bar
      end

      private

      def run(frame, name)
        case name
        when :close then frame.close
        when :preferences then @app.preferences
        when :about then @app.about
        when :quit then @app.exit_main_loop
        when :library then @app.show_library
        when :queue then @app.show_queue
        else frame.command(name) if frame.respond_to?(:command)
        end
      end
    end
  end
end
