# Turns assets/icon.svg into assets/Filmscan.icns with libvips and iconutil.
require "vips"
require "tmpdir"
require "fileutils"

root = File.expand_path("..", __dir__)
Dir.mktmpdir do |dir|
  set = File.join(dir, "Filmscan.iconset")
  FileUtils.mkdir_p(set)
  [16, 32, 64, 128, 256, 512, 1024].each do |size|
    image = Vips::Image.svgload(File.join(root, "assets", "icon.svg"), scale: size / 1024.0)
    image.pngsave(File.join(set, "icon_#{size}x#{size}.png")) unless size == 1024
    half = size / 2
    image.pngsave(File.join(set, "icon_#{half}x#{half}@2x.png")) if half >= 16
  end
  system("iconutil", "-c", "icns", set, "-o", File.join(root, "assets", "Filmscan.icns"), exception: true)
  Vips::Image.svgload(File.join(root, "assets", "icon.svg"), scale: 0.25).pngsave(File.join(root, "assets", "icon-256.png"))
end
puts "assets/Filmscan.icns"
