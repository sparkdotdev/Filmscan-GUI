require "rbconfig"
require "fileutils"
require_relative "protocol"

module FilmscanGUI
  # The app's end of a worker process. Messages go out at once; answers are
  # collected by #poll, which the app calls from a timer on its own thread,
  # so the window never waits on a render.
  class WorkerClient
    MAIN = File.expand_path("worker/main.rb", __dir__)

    attr_reader :pid

    def initialize(kind, log: nil, nice: 0)
      FileUtils.mkdir_p(File.dirname(log)) if log
      command = [RbConfig.ruby, MAIN, kind]
      command = ["nice", "-n", nice.to_s, *command] if nice.positive?
      @io = IO.popen(command, "r+b", err: log ? [log, "a"] : :err)
      @pid = @io.pid
    end

    def send(header) = Protocol.write(@io, header)

    # Yields every message waiting, without blocking.
    def poll
      while !@io.closed? && IO.select([@io], nil, nil, 0)
        message = Protocol.read(@io)
        return close unless message

        yield(*message)
      end
    rescue IOError, Errno::EPIPE
      close
    end

    # Waits up to timeout seconds for messages, for tests and scripts.
    def wait(timeout)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      while (left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)).positive?
        IO.select([@io], nil, nil, left) or break
        message = Protocol.read(@io) or break
        return message if yield(*message)
      end
      nil
    end

    def alive? = !@io.closed?

    def close
      return if @io.closed?

      begin
        send(op: "quit")
      rescue IOError, Errno::EPIPE
        nil
      end
      @io.close
      nil
    end
  end
end
