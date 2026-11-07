# Builds Filmscan-GUI.app around this checkout, so macOS shows the app by its
# own name and icon: a launcher, a copy of the Ruby binary that runs it,
# and an Info.plist. The app still runs this checkout through Bundler.
#
#   ruby tools/make_app.rb [where/Filmscan-GUI.app]
require "fileutils"
require "rbconfig"
require_relative "../lib/filmscan_gui/version"

app = File.expand_path(ARGV[0] || "~/Applications/#{FilmscanGUI::APP_NAME}.app")
root = File.expand_path("..", __dir__)
macos = File.join(app, "Contents", "MacOS")
resources = File.join(app, "Contents", "Resources")
FileUtils.rm_rf(app)
FileUtils.mkdir_p([macos, resources])

# A process only counts as the app when its binary sits in Contents/MacOS.
FileUtils.cp(RbConfig.ruby, File.join(macos, "filmscan-ruby"))
# wxRuby's prebuilt library finds libruby beside the Ruby binary, at
# ../lib from wherever that binary runs.
lib = File.join(app, "Contents", "lib")
FileUtils.mkdir_p(lib)
libruby = RbConfig::CONFIG["LIBRUBY_SO"]
File.symlink(File.join(RbConfig::CONFIG["libdir"], libruby), File.join(lib, libruby))
icon = File.join(root, "assets", "Filmscan.icns")
FileUtils.cp(icon, resources) if File.exist?(icon)

File.write(File.join(macos, "Filmscan"), <<~SH)
  #!/bin/bash
  # Starts #{FilmscanGUI::APP_NAME} from #{root} through Bundler. Apps opened from the
  # Finder get a short PATH, so the usual places for Homebrew come first.
  HERE="$(cd "$(dirname "$0")" && pwd)"
  export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
  export BUNDLE_GEMFILE=#{File.join(root, "Gemfile").dump}
  exec "$HERE/filmscan-ruby" -rbundler/setup #{File.join(root, "bin", "filmscan-gui").dump} "$@"
SH
FileUtils.chmod(0o755, File.join(macos, "Filmscan"))

File.write(File.join(app, "Contents", "Info.plist"), <<~PLIST)
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
    <key>CFBundleName</key><string>#{FilmscanGUI::APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>#{FilmscanGUI::APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>local.filmscan.gui</string>
    <key>CFBundleExecutable</key><string>Filmscan</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>#{FilmscanGUI::VERSION}</string>
    <key>CFBundleVersion</key><string>#{FilmscanGUI::VERSION}</string>
    <key>CFBundleIconFile</key><string>Filmscan</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSRequiresAquaSystemAppearance</key><false/>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
  </dict>
  </plist>
PLIST
puts app
