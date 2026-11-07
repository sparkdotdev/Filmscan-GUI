require "tmpdir"
require_relative "widgets"
require_relative "../config"
require_relative "../library"

module FilmscanGUI
  module UI
    # Where things are: the scans, how rolls are laid out among them, where
    # renders and the app's files go, and which toolkit renders. Every path
    # is the user's choice; the layouts are presets to start from.
    class Preferences < Wx::Dialog
      FIELDS = [
        ["originals", "Originals folder", "Name of the folder inside each trip that holds the rolls. Empty: rolls anywhere under the library."],
        ["output", "Final renders", "Where a roll's corrected files go."],
        ["trial", "Trial renders", "Where renders for review go, before they are approved."],
        ["sidefiles", "Side files", "Settings, fits, contact sheet and log of each render. Empty: beside the renders."],
        ["overrides", "Per-frame overrides", "The YAML file of a roll's per-frame settings."]
      ].freeze
      TOKENS = "{source} the roll's folder, {trip} its top folder, {path} its path in the trip, {roll} its name, " \
               "{id} its number, {date}, {workspace}. Relative paths are under the library."

      def initialize(parent, app, first: false)
        super(parent, title: first ? "Welcome to #{APP_NAME}" : "Settings", size: [760, 660],
                      style: Wx::DEFAULT_DIALOG_STYLE | Wx::RESIZE_BORDER)
        @app = app
        @config = app.config
        @first = first
        build
        load_values
      end

      def show_modal
        result = super
        save if result == Wx::ID_OK
        result
      end

      private

      def build
        root = Wx::ScrolledWindow.new(self, style: Wx::VSCROLL)
        root.set_scroll_rate(0, 12)
        column = Wx::VBoxSizer.new
        if @first
          intro = Wx::StaticText.new(root, label: "Choose the folder that holds your lab scans, and how rolls are laid out in it. " \
                                                  "Everything here can be changed later in Settings.")
          intro.wrap(700)
          column.add(intro, 0, Wx::ALL, 14)
        end

        grid = Wx::FlexGridSizer.new(2, 10, 12)
        grid.add_growable_col(1, 1)
        @library = Wx::DirPickerCtrl.new(root, message: "Choose the folder that holds your scans", style: Wx::DIRP_USE_TEXTCTRL)
        @library.evt_dirpicker_changed(@library.get_id) { find_example }
        add(root, grid, "Library folder", @library, "Every roll is a folder of TIFF, JPEG or PNG scans somewhere under it.")
        @preset = Wx::Choice.new(root, choices: Config::PRESETS.values.map { |p| p["label"] } + ["Custom"])
        @preset.evt_choice(@preset.get_id) { preset_picked }
        add(root, grid, "Layout", @preset, nil)
        @fields = {}
        FIELDS.each do |key, label, help|
          field = Wx::TextCtrl.new(root)
          field.set_font(Theme.mono)
          field.evt_text(field.get_id) { edited }
          @fields[key] = field
          add(root, grid, label, field, help)
        end
        grid.add_spacer(0)
        tokens = Wx::StaticText.new(root, label: TOKENS)
        tokens.set_font(Theme.small)
        tokens.set_foreground_colour(Theme.muted)
        tokens.wrap(520)
        grid.add(tokens, 0, Wx::EXPAND)
        grid.add_spacer(0)
        @example = Wx::StaticText.new(root, label: "")
        @example.set_font(Theme.small)
        grid.add(@example, 0, Wx::EXPAND)

        @workspace = Wx::DirPickerCtrl.new(root, message: "Choose a folder for the app's files", style: Wx::DIRP_USE_TEXTCTRL)
        @workspace.evt_dirpicker_changed(@workspace.get_id) { update_example }
        add(root, grid, "Workspace", @workspace, "Holds verdicts, the render queue and, by default, sessions.yml and overrides.")
        @sessions = Wx::TextCtrl.new(root)
        @sessions.set_font(Theme.mono)
        add(root, grid, "Siblings file", @sessions, "sessions.yml: which rolls were shot alongside which. Empty: in the workspace.")
        @toolkit = Wx::DirPickerCtrl.new(root, message: "Choose the toolkit's folder", style: Wx::DIRP_USE_TEXTCTRL)
        add(root, grid, "Toolkit", @toolkit, "The Filmscan-CLI checkout used for renders. Leave blank to use the bundled CLI.")
        @appearance = Wx::Choice.new(root, choices: ["Same as the system", "Light", "Dark"])
        add(root, grid, "Appearance", @appearance, "Frames always sit on neutral grey. Takes effect when the app next starts.")
        column.add(grid, 1, Wx::EXPAND | Wx::ALL, 14)
        root.set_sizer(column)

        outer = Wx::VBoxSizer.new
        outer.add(root, 1, Wx::EXPAND)
        buttons = Wx::StdDialogButtonSizer.new
        ok = Wx::Button.new(self, Wx::ID_OK, @first ? "Start" : "Save")
        ok.set_default
        ok.evt_button(Wx::ID_OK) { |event| (problem = toolkit_problem) ? refuse(problem) : event.skip }
        buttons.add_button(ok)
        buttons.add_button(Wx::Button.new(self, Wx::ID_CANCEL, "Cancel"))
        buttons.realize
        outer.add(buttons, 0, Wx::EXPAND | Wx::ALL, 12)
        set_sizer(outer)
      end

      def add(parent, grid, label, control, help)
        text = Wx::StaticText.new(parent, label: label)
        text.set_font(Theme.strong)
        grid.add(text, 0, Wx::ALIGN_TOP | Wx::TOP, 4)
        cell = Wx::VBoxSizer.new
        control.set_min_size([200, -1])
        control.set_initial_size([200, -1]) if control.respond_to?(:set_initial_size)
        cell.add(control, 0, Wx::EXPAND)
        if help
          note = Wx::StaticText.new(parent, label: help)
          note.set_font(Theme.small)
          note.set_foreground_colour(Theme.muted)
          note.wrap(520)
          cell.add(note, 0, Wx::TOP, 3)
        end
        grid.add(cell, 0, Wx::EXPAND)
      end

      def load_values
        @library.set_path(@config.library.to_s)
        presets = Config::PRESETS.keys
        custom = Config::LAYOUT_KEYS.any? { |key| !@config[key].nil? }
        @preset.set_selection(custom ? presets.size : presets.index(@config.preset).to_i)
        @loading = true
        Config::LAYOUT_KEYS.each { |key| @fields[key].change_value(@config.layout(key)) }
        @loading = false
        @workspace.set_path(@config.workspace)
        @sessions.change_value(@config["sessions"].to_s)
        @toolkit.set_path(@config["toolkit"].to_s)
        @appearance.set_selection(%w[system light dark].index(@config["appearance"] || "system") || 0)
        find_example
      end

      def preset_picked
        name = Config::PRESETS.keys[@preset.get_selection]
        return unless name

        @loading = true
        Config::LAYOUT_KEYS.each { |key| @fields[key].change_value(Config::PRESETS[name][key]) }
        @loading = false
        find_example
      end

      def edited
        return if @loading

        name = Config::PRESETS.keys[@preset.get_selection]
        matches = name && Config::LAYOUT_KEYS.all? { |key| @fields[key].get_value == Config::PRESETS[name][key] }
        @preset.set_selection(Config::PRESETS.size) unless matches
        @find_due = true
        update_example
      end

      # A config with what is on screen, not saved.
      def draft
        path = File.join(Dir.tmpdir, "filmscan-draft-#{Process.pid}.yml")
        draft = Config.new(path)
        draft.update(values)
      end

      def values
        name = Config::PRESETS.keys[@preset.get_selection]
        layout = Config::LAYOUT_KEYS.to_h { |key| [key, @fields[key].get_value.strip] }
        {
          "library" => @library.get_path.to_s.strip.then { |p| p.empty? ? nil : p },
          "preset" => name || "beside",
          "workspace" => @workspace.get_path.to_s.strip.then { |p| p.empty? ? nil : p },
          "sessions" => @sessions.get_value.strip.then { |p| p.empty? ? nil : p },
          "toolkit" => @toolkit.get_path.to_s.strip.then { |p| p.empty? ? nil : p },
          "appearance" => [nil, "light", "dark"][@appearance.get_selection]
        }.merge(name ? Config::LAYOUT_KEYS.to_h { |key| [key, nil] } : layout)
      end

      # The first roll the layout finds, to show where its files would go.
      def find_example
        config = draft
        @example_roll = config.configured? ? Library.new(config).rolls.first : nil
        update_example
      end

      def update_example
        find_example_soon if @find_due
        roll = @example_roll
        unless roll
          @example.set_label(@library.get_path.to_s.empty? ? "" : "No rolls found with this layout yet.")
          return
        end
        config = draft
        sample = Roll.new(Library.new(config), roll.trip, roll.base, roll.rel)
        root = config.library
        home = Dir.home
        short = lambda do |path|
          path = path.to_s
          path = if path.start_with?("#{root}/") then path.delete_prefix("#{root}/")
                 elsif path.start_with?("#{home}/") then "~/#{path.delete_prefix("#{home}/")}"
                 else path
                 end
          path.size > 62 ? "#{path[0, 24]}...#{path[-35..]}" : path
        end
        lines = ["For #{short.call(sample.source)}:",
                 "  final renders  #{short.call(sample.output_dir)}",
                 "  trial renders  #{short.call(sample.trial_dir)}",
                 "  side files     #{sample.sidefiles_dir ? short.call(sample.sidefiles_dir) : 'beside the renders'}",
                 "  overrides      #{short.call(sample.overrides_path)}"]
        @example.set_label(UI.plain(lines.join("\n")))
        @example.set_font(Theme.mono)
        layout
      end

      def find_example_soon
        @find_due = false
        return unless @fields["originals"].get_value != @last_originals

        @last_originals = @fields["originals"].get_value
        config = draft
        @example_roll = config.configured? ? Library.new(config).rolls.first : nil
      end

      def save = @config.update(values)

      # A place the app would write that lies inside the toolkit's folder.
      def toolkit_problem
        config = draft
        places = [config.workspace, config.sessions_path]
        if (roll = @example_roll)
          sample = Roll.new(Library.new(config), roll.trip, roll.base, roll.rel)
          places += [sample.output_dir, sample.trial_dir, sample.sidefiles_dir, sample.overrides_path]
        end
        places.compact.find { |path| config.inside_toolkit?(path) }
      end

      def refuse(path)
        Wx.message_box("#{path} is inside the toolkit's folder. The app only reads the toolkit, so choose somewhere else.",
                       "Choose another place", Wx::OK | Wx::ICON_WARNING, self)
      end
    end
  end
end
