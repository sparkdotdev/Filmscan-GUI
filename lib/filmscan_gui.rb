require_relative "filmscan_gui/version"
require_relative "filmscan_gui/app"

# A desktop app for Filmscan-CLI.
module FilmscanGUI
  def self.run = App.run
end
