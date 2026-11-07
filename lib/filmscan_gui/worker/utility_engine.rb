require "fileutils"
require "tmpdir"
require "open3"

module FilmscanGUI
  module Worker
    # Small copies of scans and renders, for the library and for review,
    # written as JPEGs into the cache so the app can read them straight off
    # disk next time. The newest request goes first, since it is usually
    # what is on screen.
    class UtilityEngine
      def initialize(send)
        @send = send
        @inbox = Thread::Queue.new
        @wanted = []
      end

      def run(input)
        Thread.new do
          while (message = Protocol.read(input))
            @inbox << message[0]
          end
          @inbox << { op: "quit" }
        end
        loop do
          message = @wanted.empty? ? @inbox.pop : (@inbox.pop(true) rescue nil)
          while message
            return if message[:op] == "quit"

            @wanted.delete_if { |w| w[:file] == message[:file] }
            @wanted << message if message[:op] == "thumb"
            message = (@inbox.pop(true) rescue nil)
          end
          make(@wanted.pop) if @wanted.any?
        end
      end

      private

      def make(request)
        unless File.exist?(request[:file])
          image = load(request[:path], request[:size])
          FileUtils.mkdir_p(File.dirname(request[:file]))
          partial = "#{request[:file]}.#{Process.pid}.partial.jpg"
          image.jpegsave(partial, Q: request[:quality] || 88, strip: true)
          File.rename(partial, request[:file])
        end
        @send.call(type: "thumb", path: request[:path], file: request[:file], tag: request[:tag])
      rescue StandardError => e
        @send.call(type: "thumb_failed", path: request[:path], file: request[:file], tag: request[:tag],
                   message: e.message.lines.first.to_s.strip)
      end

      # libvips first; HEICs written in one large slice only open through
      # the system's own decoder, so on macOS sips takes those.
      def load(path, size)
        image = Vips::Image.thumbnail(path, size, height: size, size: :down)
        image = image[0..2] if image.bands > 3
        image = (image.cast(:float) / 257.0).cast(:uchar) if image.format == :ushort
        image.copy_memory
      rescue Vips::Error
        raise unless File.executable?("/usr/bin/sips")

        Dir.mktmpdir do |dir|
          jpeg = File.join(dir, "frame.jpg")
          _, status = Open3.capture2e("/usr/bin/sips", "-s", "format", "jpeg", "-Z", size.to_s, path, "--out", jpeg)
          raise "could not read #{File.basename(path)}" unless status.success? && File.exist?(jpeg)

          Vips::Image.new_from_file(jpeg).copy_memory
        end
      end
    end
  end
end
