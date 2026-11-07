require_relative "lib/filmscan_gui/version"

Gem::Specification.new do |spec|
  spec.name = "filmscan-gui"
  spec.version = FilmscanGUI::VERSION
  spec.authors = ["mszaro"]
  spec.summary = "A desktop app for reviewing and correcting film scans"
  spec.description = <<~TEXT
    Browse a library of lab scans, try the toolkit's settings on a frame or a
    whole contact sheet, match rolls to the ones shot alongside them, queue
    renders and review the results before they replace the old files.
  TEXT
  spec.homepage = "https://github.com/sparkdotdev/Filmscan-GUI"
  spec.license = "LicenseRef-LICENSE.MD"
  spec.required_ruby_version = ">= 4.0"

  spec.files = Dir["lib/**/*.rb", "bin/*", "tools/*.rb", "assets/*", "README.md", "LICENSE.MD", "CONTRIBUTING.md"]
  spec.bindir = "bin"
  spec.executables = ["filmscan-gui"]
  spec.require_paths = ["lib"]

  spec.add_dependency "film_scan"
  spec.add_dependency "ruby-vips", "~> 2.2"
  spec.add_dependency "wxruby3", "~> 1.8"
end
