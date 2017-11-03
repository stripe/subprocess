require 'thread'
require 'set'

require 'subprocess/version'

# A Ruby clone of Python's subprocess module.
#
# @see http://docs.python.org/2/library/subprocess.html
module Subprocess

  # An opaque constant that indicates that a pipe should be opened.
  PIPE = -1
  # An opaque constant that can be passed to the `:stderr` option that indicates
  # that the standard error stream should be redirected to the standard output.
  STDOUT = -2

  # An alias for `Process.new`. Mostly here to better emulate the Python API.
  #
  # @return [Process] A process with the given arguments
  def self.popen(cmd, opts={}, &blk)
    Process.new(cmd, opts, &blk)
  end

  # Call and wait for the return of a given process.
  #
  # @note If you call this function with `:stdout => PIPE` or `:stderr => PIPE`,
  #   this function will block indefinitely as soon as the OS's pipe buffer
  #   fills up, as neither file descriptor will be read from. To avoid this, use
  #   {Process#communicate} from a passed block.
  #
  # @return [::Process::Status] The exit status of the process
  #
  # @see Process#initialize
  def self.call(cmd, opts={}, &blk)
    Process.new(cmd, opts, &blk).wait
  end

  # Like {Subprocess::call}, except raise a {NonZeroExit} if the process did not
  # terminate successfully.
  #
  # @example Grep a file for a string
  #   Subprocess.check_call(%W{grep -q llama ~/favorite_animals})
  #
  # @example Communicate with a child process
  #   Subprocess.check_call(%W{sendmail -t}, :stdin => Subprocess::PIPE) do |p|
  #     p.communicate <<-EMAIL
  #   From: alpaca@example.com
  #   To: llama@example.com
  #   Subject: I am so fluffy.
  #
  #   SO FLUFFY!
  #   http://upload.wikimedia.org/wikipedia/commons/3/3e/Unshorn_alpaca_grazing.jpg
  #     EMAIL
  #   end
  #
  # @note If you call this function with `:stdout => PIPE` or `:stderr => PIPE`,
  #   this function will block indefinitely as soon as the OS's pipe buffer
  #   fills up, as neither file descriptor will be read from. To avoid this, use
  #   {Process#communicate} from a passed block.
  #
  # @raise [NonZeroExit] if the process returned a non-zero exit status (i.e.,
  #   was terminated with an error or was killed by a signal)
  # @return [::Process::Status] The exit status of the process
  #
  # @see Process#initialize
  def self.check_call(cmd, opts={}, &blk)
    status = Process.new(cmd, opts, &blk).wait
    raise NonZeroExit.new(cmd, status) unless status.success?
    status
  end

  # Like {Subprocess::check_call}, but return the contents of `stdout`, much
  # like `Kernel#system`.
  #
  # @example Get the system load
  #   system_load = Subprocess.check_output(['uptime']).split(' ').last(3)
  #
  # @raise [NonZeroExit] if the process returned a non-zero exit status (i.e.,
  #   was terminated with an error or was killed by a signal)
  # @return [String] The contents of `stdout`
  #
  # @see Process#initialize
  def self.check_output(cmd, opts={}, &blk)
    opts[:stdout] = PIPE
    child = Process.new(cmd, opts, &blk)
    output, _ = child.communicate()
    raise NonZeroExit.new(cmd, child.status) unless child.wait.success?
    output
  end

  # Print a human readable interpretation of a process exit status.
  #
  # @param [::Process::Status] status The status returned by `waitpid2`.
  # @param [Boolean] convert_high_exit Whether to convert exit statuses greater
  #   than 128 into the usual convention for exiting after trapping a signal.
  #   (e.g. many programs will exit with status 130 after receiving a SIGINT /
  #   signal 2.)
  # @return [String] Text interpretation
  #
  def self.status_to_s(status, convert_high_exit=true)
    # use an array just in case we somehow get a status with all the bits set
    parts = []
    if status.exited?
      parts << "exited with status #{status.exitstatus}"
      if convert_high_exit && status.exitstatus > 128
        # convert high exit statuses into what the original signal may have
        # been according to the usual exit status convention
        sig_num = status.exitstatus - 128

        sig_name = Signal.signame(sig_num)

        if sig_name
          parts << "(maybe SIG#{sig_name})"
        end
      end
    end
    if status.signaled?
      parts << "killed by signal #{status.termsig}"
    end
    if status.stopped?
      parts << "stopped by signal #{status.stopsig}"
    end

    if parts.empty?
      raise ArgumentError.new("Don't know how to interpret #{status.inspect}")
    end

    parts.join(', ')
  end

  # Error class representing a process's abnormal exit.
  class NonZeroExit < StandardError
    # @!attribute [r] command
    #   @note This is intended only for use in user-facing error messages. In
    #     particular, no shell quoting of any sort is performed when
    #     constructing this string, meaning that blindly running it in a shell
    #     might have different semantics than the original command.
    #   @return [String] The command and arguments for the process that exited
    #     abnormally.
    # @!attribute [r] status
    #   @return [::Process::Status] The Ruby status object returned by `waitpid`
    attr_reader :command, :status

    # Return an instance of {NonZeroExit}.
    #
    # @param [Array<String>] cmd The command that returned a non-zero status.
    # @param [::Process::Status] status The status returned by `waitpid`.
    def initialize(cmd, status)
      @command, @status = cmd.join(' '), status
      message = "Command #{command} "
      if status.exited?
        message << "returned non-zero exit status #{status.exitstatus}"
      elsif status.signaled?
        message << "was terminated by signal #{status.termsig}"
      elsif status.stopped?
        message << "was stopped by signal #{status.stopsig}"
      else
        message << "exited for an unknown reason (FIXME)"
      end
      super(message)
    end
  end

  # Error class representing a timeout during a call to `communicate`
  class CommunicateTimeout < StandardError
    # @!attribute [r] stdout
    #   @return [String] Content read from stdout before the timeout
    # @!attribute [r] stderr
    #   @return [String] Content read from stderr before the timeout
    attr_reader :stdout, :stderr

    def initialize(cmd, stdout, stderr)
      @stdout = stdout
      @stderr = stderr

      super("Timeout communicating with `#{cmd.join(' ')}`")
    end
  end

  # A child process. The preferred way of spawning a subprocess is through the
  # functions on {Subprocess} (especially {Subprocess::check_call} and
  # {Subprocess::check_output}).
  class Process
    # @!attribute [r] stdin
    #   @return [IO] The `IO` that is connected to this process's `stdin`.
    # @!attribute [r] stdout
    #   @return [IO] The `IO` that is connected to this process's `stdout`.
    # @!attribute [r] stderr
    #   @return [IO] The `IO` that is connected to this process's `stderr`.
    attr_reader :stdin, :stdout, :stderr

    # @!attribute [r] command
    #   @return [Array<String>] The command this process was invoked with.
    # @!attribute [r] pid
    #   @return [Fixnum] The process ID of the spawned process.
    # @!attribute [r] status
    #   @return [::Process::Status] The exit status code of the process. Only
    #     set after the process has exited.
    attr_reader :command, :pid, :status

    # Create a new process.
    #
    # @param [Array<String>] cmd The command to run and its arguments (in the
    #   style of an `argv` array). Unlike Python's subprocess module, `cmd`
    #   cannot be a String.
    #
    # @option opts [IO, Fixnum, String, Subprocess::PIPE, nil] :stdin The `IO`,
    #   file descriptor number, or file name to use for the process's standard
    #   input. If the magic value {Subprocess::PIPE} is passed, a new pipe will
    #   be opened.
    # @option opts [IO, Fixnum, String, Subprocess::PIPE, nil] :stdout The `IO`,
    #   file descriptor number, or file name to use for the process's standard
    #   output. If the magic value {Subprocess::PIPE} is passed, a pipe will be
    #   opened and attached to the process.
    # @option opts [IO, Fixnum, String, Subprocess::PIPE, Subprocess::STDOUT,
    #   nil] :stderr The `IO`, file descriptor number, or file name to use for
    #   the process's standard error. If the special value {Subprocess::PIPE} is
    #   passed, a pipe will be opened and attached to the process. If the
    #   special value {Subprocess::STDOUT} is passed, the process's `stderr`
    #   will be redirected to its `stdout` (much like bash's `2>&1`).
    #
    # @option opts [String] :cwd The directory to change to before executing the
    #   child process.
    # @option opts [Hash<String, String>] :env The environment to use in the
    #   child process.
    # @option opts [Array<Fixnum>] :retain_fds An array of file descriptor
    #   numbers that should not be closed before executing the child process.
    #   Note that, unlike Python (which has :close_fds defaulting to false), all
    #   file descriptors not specified here will be closed.
    # @option opts [Hash] :exec_opts A hash that will be merged into the options
    #   hash of the call to {Kernel#exec}.
    #
    # @option opts [Proc] :preexec_fn A function that will be called in the
    #   child process immediately before executing `cmd`.
    #
    # @yield [process] Yields the just-spawned {Process} to the optional block.
    #   This occurs after all of {Process}'s error handling has been completed,
    #   and is a great place to call {Process#communicate}, especially when used
    #   in conjunction with {Subprocess::check_call}.
    # @yieldparam process [Process] The process that was just spawned.
    def initialize(cmd, opts={}, &blk)
      raise ArgumentError, "cmd must be an Array of strings" unless Array === cmd
      raise ArgumentError, "cmd cannot be empty" if cmd.empty?

      @command = cmd

      # Figure out what file descriptors we should pass on to the child (and
      # make externally visible ourselves)
      @child_stdin, @stdin = parse_fd(opts[:stdin], 'r')
      @child_stdout, @stdout = parse_fd(opts[:stdout], 'w')
      unless opts[:stderr] == STDOUT
        @child_stderr, @stderr = parse_fd(opts[:stderr], 'w')
      end

      retained_fds = Set.new(opts[:retain_fds] || [])

      # A control pipe for ferrying errors back from the child
      control_r, control_w = IO.pipe

      @pid = fork do
        begin
          ::STDIN.reopen(@child_stdin) if @child_stdin
          ::STDOUT.reopen(@child_stdout) if @child_stdout
          if opts[:stderr] == STDOUT
            ::STDERR.reopen(::STDOUT)
          else
            ::STDERR.reopen(@child_stderr) if @child_stderr
          end

          # Set up a new environment if we're requested to do so.
          if opts[:env]
            ENV.clear
            begin
              ENV.update(opts[:env])
            rescue TypeError => e
              raise ArgumentError, "`env` option must be a hash where all keys and values are strings (#{e})"
            end
          end

          # Call the user back, maybe?
          if opts[:preexec_fn]
            if opts[:cwd]
              Dir.chdir(opts[:cwd], &opts[:preexec_fn])
            else
              opts[:preexec_fn].call
            end
          end

          options = {close_others: true}.merge(opts.fetch(:exec_opts, {}))
          if opts[:retain_fds]
            retained_fds.each { |fd| options[fd] = fd }
          end
          if opts[:cwd]
            # We use the chdir option to `exec` since wrapping the
            # `exec` in a Dir.chdir block caused these sporadic errors on macOS:
            # Too many open files - getcwd (Errno::EMFILE)
            options[:chdir] = opts[:cwd]
          end

          begin
            # Ruby's Kernel#exec will call an exec(3) variant if called with two
            # or more arguments, but when called with just a single argument will
            # spawn a subshell with that argument as the command. Since we always
            # want to call exec(3), we use the third exec form, which passes a
            # [cmdname, argv0] array as its first argument and never invokes a
            # subshell.
            exec([cmd[0], cmd[0]], *cmd[1..-1], options)
          rescue TypeError => e
            raise ArgumentError, "cmd must be an Array of strings (#{e})"
          end

        rescue Exception => e
          # Dump all errors up to the parent through the control socket
          Marshal.dump(e, control_w)
          control_w.flush
        end

        # Something has gone terribly, terribly wrong if we're hitting this :(
        exit!(1)
      end

      # Meanwhile, in the parent process...

      # First, let's close some things we shouldn't have access to
      @child_stdin.close if our_fd?(opts[:stdin])
      @child_stdout.close if our_fd?(opts[:stdout])
      @child_stderr.close if our_fd?(opts[:stderr])
      control_w.close

      # Any errors during the spawn process? We'll get past this point when the
      # child execs and the OS closes control_w
      begin
        e = Marshal.load(control_r)
        e = "Unknown Failure" unless e.is_a?(Exception) || e.is_a?(String)
        # Because we're throwing an exception and not returning a
        # Process, we need to make sure the child gets reaped
        wait
        raise e
      rescue EOFError # Nothing to read? Great!
      ensure
        control_r.close
      end

      # Everything is okay. Good job, team!
      blk.call(self) if blk
    end

    # Poll the child, setting (and returning) its status. If the child has not
    # terminated, return nil and exit immediately
    #
    # @return [::Process::Status, nil] The exit status of the process
    def poll
      @status ||= (::Process.waitpid2(@pid, ::Process::WNOHANG) || []).last
    end

    # Wait for the child to return, setting and returning the status of the
    # child.
    #
    # @return [::Process::Status] The exit status of the process
    def wait
      @status ||= ::Process.waitpid2(@pid).last
    end

    # Do nonblocking reads from `fd`, appending all data read into `buf`.
    #
    # @param [IO] fd The file to read from.
    # @param [String] buf A buffer to append the read data to.
    #
    # @return [true, false] Whether `fd` was closed due to an exceptional
    #   condition (`EOFError` or `EPIPE`).
    def drain_fd(fd, buf=nil)
      loop do
        tmp = fd.read_nonblock(4096)
        buf << tmp unless buf.nil?
      end
    rescue EOFError, Errno::EPIPE
      fd.close
      true
    rescue Errno::EINTR
    rescue Errno::EWOULDBLOCK, Errno::EAGAIN
      false
    end

    # Write the (optional) input to the process's `stdin` and read the contents of
    # `stdout` and `stderr`. If a block is provided, stdout and stderr are yielded as they
    # are read. Otherwise they are buffered in memory and returned when the process
    # exits. Do this all using `IO::select`, so we don't deadlock due to full pipe
    # buffers.
    #
    # This is only really useful if you set some of `:stdin`, `:stdout`, and
    # `:stderr` to {Subprocess::PIPE}.
    #
    # @param [String] input A string to feed to the child's standard input.
    # @param [Numeric] timeout_s Raise {Subprocess::CommunicateTimeout} if communicate
    #   does not finish after timeout_s seconds.
    # @yieldparam [String] stdout Data read from stdout since the last yield
    # @yieldparam [String] stderr Data read from stderr since the last yield
    # @return [Array(String, String), nil] An array of two elements: the data read from the
    #   child's standard output and standard error, respectively.
    #   Returns nil if a block is provided.
    def communicate(input=nil, timeout_s=nil)
      raise ArgumentError if !input.nil? && @stdin.nil?

      stdout, stderr = "", ""
      stdout_encoding = @stdout.external_encoding if @stdout
      stderr_encoding = @stderr.external_encoding if @stderr

      input = input.dup unless input.nil?

      @stdin.close if (input.nil? || input.empty?) && !@stdin.nil?

      timeout_at = Time.now + timeout_s if timeout_s

      self.class.catching_sigchld(pid) do |self_read|
        wait_r = [@stdout, @stderr, self_read].compact
        wait_w = [input && @stdin].compact
        loop do
          # If the process has exited and we're not waiting to read anything
          # other than the self pipe, then we're done.
          break if poll && wait_r == [self_read]

          ready_r, ready_w = select_until(wait_r, wait_w, [], timeout_at)
          raise CommunicateTimeout.new(@command, stdout, stderr) if ready_r.nil?

          if ready_r.include?(@stdout)
            if drain_fd(@stdout, stdout)
              wait_r.delete(@stdout)
            end
          end

          if ready_r.include?(@stderr)
            if drain_fd(@stderr, stderr)
              wait_r.delete(@stderr)
            end
          end

          if ready_r.include?(self_read)
            if drain_fd(self_read)
              raise "Unexpected internal error -- someone closed our self-pipe!"
            end
          end

          if ready_w.include?(@stdin)
            written = 0
            begin
              written = @stdin.write_nonblock(input)
            rescue EOFError # Maybe I shouldn't catch this...
            rescue Errno::EINTR
            rescue IO::WaitWritable
              # On OS X, a pipe can raise EAGAIN even after select indicates
              # that it is writable. Once the process consumes from the pipe,
              # the next write should succeed and we should make forward progress.
              # Until then, treat this as not writing any bytes and continue looping.
              # For details see: https://github.com/stripe/subprocess/pull/22
              nil
            rescue Errno::EPIPE
              # The other side of the pipe closed before we could
              # write all of our input. This can happen if the
              # process exits prematurely.
              @stdin.close
              wait_w.delete(@stdin)
            end
            input[0...written] = ''
            if input.empty?
              @stdin.close
              wait_w.delete(@stdin)
            end
          end

          if block_given? && !(stderr.empty? && stdout.empty?)
            yield stdout, stderr
            stdout, stderr = "", ""
          end
        end
      end

      wait

      stdout.force_encoding(stdout_encoding) if stdout_encoding
      stderr.force_encoding(stderr_encoding) if stderr_encoding

      if block_given?
        nil
      else
        [stdout, stderr]
      end
    end

    # Does exactly what it says on the box.
    #
    # @param [String, Symbol, Fixnum] signal The signal to send to the child
    #   process. Accepts all the same arguments as Ruby's built-in
    #   {::Process::kill}, for instance a string like "INT" or "SIGINT", or a
    #   signal number like 2.
    def send_signal(signal)
      ::Process.kill(signal, pid)
    end

    # Sends `SIGTERM` to the process.
    def terminate
      send_signal("TERM")
    end

    private
    # Return a pair of values (child, mine), which are how the given file
    # descriptor should appear to the child and to this process, respectively.
    # "mine" is only non-nil in the case of a pipe (in fact, we just return a
    # list of length one, since ruby will unpack nils from missing list items).
    def parse_fd(fd, mode)
      fds = case fd
      when PIPE
        IO.pipe
      when IO
        [fd]
      when Integer
        [IO.new(fd, mode)]
      when String
        [File.open(fd, mode)]
      when nil
        []
      else
        raise ArgumentError
      end

      mode == 'r' ? fds : fds.reverse
    end

    # The pair to parse_fd, returns whether or not the file descriptor was
    # opened by us (and therefore should be closed by us).
    def our_fd?(fd)
      case fd
      when PIPE, String
        true
      else
        false
      end
    end

    # Call IO.select timing out at Time `timeout_at`. If `timeout_at` is nil, never times out.
    def select_until(read_array, write_array, err_array, timeout_at)
      if !timeout_at
        return IO.select(read_array, write_array, err_array)
      end

      remaining = (timeout_at - Time.now)
      return nil if remaining <= 0

      IO.select(read_array, write_array, err_array, remaining)
    end

    @sigchld_mutex = Mutex.new
    @sigchld_fds = {}
    @sigchld_old_handler = nil

    # Wake up everyone. We can't tell who we should wake up without `wait`ing,
    # and we want to let the process itself do that. In practice, we're not
    # likely to have that many in-flight subprocesses, so this is probably not a
    # big deal.
    def self.handle_sigchld
      # Do the wakeups inside a thread so that we can safely grab
      # `sigchld_mutex`. Ruby signal handlers are not executed
      # atomically with respect to other Ruby threads, so we need to
      # properly synchronize.
      th = Thread.new do
        @sigchld_mutex.synchronize do
          @sigchld_fds.values.each do |fd|
            begin
              fd.write_nonblock("\x00")
            rescue Errno::EWOULDBLOCK, Errno::EAGAIN
              # If the pipe is full, the other end will be woken up
              # regardless when it next reads, so it's fine to skip the
              # write (the pipe is a wakeup channel, and doesn't contain
              # meaningful data).
            end
          end
        end
      end
      th.name = 'subprocess:handle_sigchld'
    end

    def self.register_pid(pid, fd)
      @sigchld_mutex.synchronize do
        @sigchld_fds[pid] = fd
        if @sigchld_fds.length == 1
          @sigchld_old_handler = Signal.trap('SIGCHLD') {handle_sigchld}
        end
      end
    end

    def self.unregister_pid(pid)
      @sigchld_mutex.synchronize do
        if @sigchld_fds.length == 1
          Signal.trap('SIGCHLD', @sigchld_old_handler || 'DEFAULT')
        end
        @sigchld_fds.delete(pid)
      end
    end

    def self.catching_sigchld(pid)
      IO.pipe do |self_read, self_write|
        begin
          register_pid(pid, self_write)
          yield self_read
        ensure
          unregister_pid(pid)
        end
      end
    end
  end
end
