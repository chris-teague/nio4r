module NIO
  # Selectors monitor IO objects for events of interest
  class Selector
    # Create a new NIO::Selector
    def initialize
      @selectables = {}
      @lock = Mutex.new

      # Other threads can wake up a selector
      @wakeup, @waker = IO.pipe
      @closed = false
    end

    # Register interest in an IO object with the selector for the given types
    # of events. Valid event types for interest are:
    # * :r - is the IO readable?
    # * :w - is the IO writeable?
    # * :rw - is the IO either readable or writeable?
    def register(io, interest)
      @lock.synchronize do
        raise ArgumentError, "this IO is already registered with the selector" if @selectables[io]

        monitor = Monitor.new(io, interest, self)
        @selectables[io] = monitor

        monitor
      end
    end

    # Deregister the given IO object from the selector
    def deregister(io)
      @lock.synchronize do
        monitor = @selectables.delete io
        monitor.close(false) if monitor and not monitor.closed?
        monitor
      end
    end

    # Is the given IO object registered with the selector?
    def registered?(io)
      @lock.synchronize { @selectables.has_key? io }
    end

    # Select which monitors are ready
    def select(timeout = nil)
      @lock.synchronize do
        readers, writers = [@wakeup], []

        @selectables.each do |io, monitor|
          readers << io if monitor.interests == :r || monitor.interests == :rw
          writers << io if monitor.interests == :w || monitor.interests == :rw
          monitor.readiness = nil
        end

        ready_readers, ready_writers = Kernel.select readers, writers, [], timeout
        return unless ready_readers # timeout or wakeup
        
        selected_monitors = Set.new

        win_threads = []
        count = 0

        require 'thread'

        Thread.new {
          ready_readers.each do |io|
            if io == @wakeup
              # Clear all wakeup signals we've received by reading them
              # Wakeups should have level triggered behavior
              begin

                p "READY READER ##{count}"
                
                # FIXME: Windows does not like IO.pipe's read_nonblock.
                #        For now, do the dodgy and accept a blocking read.

                if NIO::windows?
                  @wakeup.read(1024)
                  count += 1
                else
                  @wakeup.read_nonblock(1024)
                end

                # Loop until we've drained all incoming events
                redo
              rescue Errno::EWOULDBLOCK
              end

              count += 1
              
              return
            else
              monitor = @selectables[io]
              monitor.readiness = :r
              selected_monitors << monitor
            end
          end
        }.join
        
        ready_writers.each do |io|
          monitor = @selectables[io]
          monitor.readiness = case monitor.readiness
          when :r
            :rw
          else
            :w
          end
          selected_monitors << monitor
        end
        
        if block_given?
          selected_monitors.each do |m|
            yield m
          end
          selected_monitors.size
        else
          selected_monitors
        end
      end
    end

    # Wake up a thread that's in the middle of selecting on this selector, if
    # any such thread exists.
    #
    # Invoking this method more than once between two successive select calls
    # has the same effect as invoking it just once. In other words, it provides
    # level-triggered behavior.
    def wakeup
      # Send the selector a signal in the form of writing data to a pipe
      @waker << "\0"
      nil
    end

    # Close this selector and free its resources
    def close
      @lock.synchronize do
        return if @closed

        @wakeup.close rescue nil
        @waker.close rescue nil
        @closed = true
      end
    end

    # Is this selector closed?
    def closed?; @closed end
    
    def empty?
      @selectables.empty?
    end
  end
end
