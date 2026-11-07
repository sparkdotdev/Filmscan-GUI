require "json"

module FilmscanGUI
  # How the app and its workers talk over a pipe: a JSON line, followed by
  # raw bytes when the line says how many.
  module Protocol
    module_function

    def write(io, header, payload = nil)
      header = header.merge(bytes: payload.bytesize) if payload
      io.write(JSON.generate(header), "\n")
      io.write(payload) if payload
      io.flush
    end

    # Blocks until a message arrives. Nil at end of file.
    def read(io)
      line = io.gets or return nil
      header = JSON.parse(line, symbolize_names: true)
      payload = header[:bytes] ? io.read(header[:bytes]) : nil
      [header, payload]
    end
  end
end
