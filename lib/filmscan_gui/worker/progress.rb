require "stringio"

module FilmscanGUI
  module Worker
    # Stands in for $stdout so the toolkit's progress lines become messages
    # to the app, and are kept for the roll's report.
    class Progress < StringIO
      attr_reader :lines

      def initialize(send)
        super(+"")
        @send = send
        @partial = +""
        @lines = []
      end

      def write(*parts)
        text = parts.join
        @partial << text
        while (cut = @partial.index(/[\r\n]/))
          line = @partial.slice!(0..cut).strip
          report(line) unless line.empty?
        end
        text.bytesize
      end

      def take_lines
        taken = @lines
        @lines = []
        taken
      end

      private

      # "sampling 3/36" comes many times to a line, so it is split up.
      def report(line)
        line.split(/(?=\bsampling \d+\/\d+)/).each do |part|
          part = part.strip
          next if part.empty?

          if (step = part.match(/\Asampling (\d+)\/(\d+)\z/))
            @send.call(type: "progress", text: "Sampling frames", done: step[1].to_i, total: step[2].to_i)
          else
            @lines << part
            @send.call(type: "progress", text: part)
          end
        end
      end
    end
  end
end
