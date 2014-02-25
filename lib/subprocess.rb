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
  # @see {Process#initialize}
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
  # @see {Process#initialize}
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
  # @see {Process#initialize}
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

        # sigh, why is ruby so silly
        if Signal.respond_to?(:signame)
          # ruby 2.0 way
          sig_name = Signal.signame(sig_num)
        elsif Signal.list.respond_to?(:key)
          # ruby 1.9 way
          sig_name = Signal.list.key(sig_num)
        else
          # ruby 1.8 way
          sig_name = Signal.list.index(sig_num)
        end

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
    #   cannnot be a String.
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
    #
    # @option opts [Proc] :preexec_fn A function that will be called in the
    #   child process immediately before executing `cmd`. Note: we don't
    #   actually close file descriptors, but instead set them to auto-close on
    #   `exec` (using `FD_CLOEXEC`), so your application will probably continue
    #   to behave as expected.
    #
    # @yield [process] Yields the just-spawned {Process} to the optional block.
    #   This occurs after all of {Process}'s error handling has been completed,
    #   and is a great place to call {Process#communicate}, especially when used
    #   in conjunction with {Subprocess::check_call}.
    # @yieldparam process [Process] The process that was just spawned.
    def initialize(cmd, opts={}, &blk)
      raise ArgumentError, "cmd must be an Array" unless Array === cmd

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
          require 'fcntl'

          FileUtils.cd(opts[:cwd]) if opts[:cwd]

          # The only way to mark an fd as CLOEXEC in ruby is to create an IO
          # object wrapping it. In 1.8, however, there's no way to create that
          # IO without it believing it owns the underlying fd, s.t. it will
          # close the fd if the IO is GC'd before the exec. Since we don't want
          # that, we stash a list of these IO objects to prevent them from
          # getting GC'd, since we are about to exec, which will clean
          # everything up anyways.
          fds = []

          # We have a whole ton of file descriptors that we don't want leaking
          # into the child. Set them all to close when we exec away.
          #
          # Ruby 1.9+ note: exec has a :close_others argument (and 2.0 closes
          # FDs by default). When we stop supporting Ruby 1.8, all of this can
          # go away.
          if File.directory?("/dev/fd")
            # On many modern UNIX-y systems, we can perform an optimization by
            # looking through /dev/fd, which is a sparse listing of all the
            # descriptors we have open. This allows us to avoid an expensive
            # linear scan.
            Dir.foreach("/dev/fd") do |file|
              fd = file.to_i
              if file.start_with?('.') || fd < 3 || retained_fds.include?(fd)
                next
              end
              begin
                fds << mark_fd_cloexec(fd)
              rescue Errno::EBADF
                # The fd might have been closed by now; that's peaceful.
              end
            end
          else
            # This is the big hammer. There's not really a good way of doing
            # this comprehensively across all platforms without just trying them
            # all. We only go up to the soft limit here. If you've been messing
            # with the soft limit, we might miss a few. Also, on OSX (perhaps
            # BSDs in general?), where the soft limit means something completely
            # different.
            special = [@child_stdin, @child_stdout, @child_stderr].compact
            special = Hash[special.map { |f| [f.fileno, f] }]
            3.upto(::Process.getrlimit(::Process::RLIMIT_NOFILE).first) do |fd|
              next if retained_fds.include?(fd)
              begin
                # I don't know why we need to do this, but OSX started freaking
                # out when trying to dup2 below if FD_CLOEXEC had been set on a
                # fresh IO instance referring to the same underlying file
                # descriptor as what we were trying to dup2 from.
                if special[fd]
                  special[fd].fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
                else
                  fds << mark_fd_cloexec(fd)
                end
              rescue Errno::EBADF # Ignore FDs that don't exist
              end
            end
          end

          # dup2 the correct descriptors into place. Note that this clears the
          # FD_CLOEXEC flag on the new file descriptors (but not the old ones).
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
            ENV.update(opts[:env])
          end

          # Call the user back, maybe?
          opts[:preexec_fn].call if opts[:preexec_fn]

          # Ruby 1.8's exec is really stupid--there's no way to specify that
          # you want to exec a single thing *without* performing shell
          # expansion. So this is the next best thing.
          args = cmd
          if cmd.length == 1
            args = ["'" + cmd[0].gsub("'", "\\'") + "'"]
          end
          if opts[:retain_fds]
            redirects = {}
            retained_fds.each { |fd| redirects[fd] = fd }
            args << redirects
          end
          exec(*args)

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
      [@child_stdin, @child_stdout, @child_stderr, control_w].each do |fd|
        fd.close unless fd.nil?
      end

      # Any errors during the spawn process? We'll get past this point when the
      # child execs and the OS closes control_w because of the FD_CLOEXEC
      begin
        e = Marshal.load(control_r)
        e = "Unknown Failure" unless e.is_a?(Exception) || e.is_a?(String)
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

    # Write the (optional) input to the process's `stdin`. Also, read (and
    # buffer in memory) the contents of `stdout` and `stderr`. Do this all using
    # `IO::select`, so we don't deadlock due to full pipe buffers.
    #
    # This is only really useful if you set some of `:stdin`, `:stdout`, and
    # `:stderr` to {Subprocess::PIPE}.
    #
    # @param [String] input A string to feed to the child's standard input.
    # @return [Array<String>] An array of two elements: the data read from the
    #   child's standard output and standard error, respectively.
    def communicate(input=nil)
      raise ArgumentError if !input.nil? && @stdin.nil?

      stdout, stderr = "", ""
      input = input.dup unless input.nil?

      @stdin.close if (input.nil? || input.empty?) && !@stdin.nil?

      self_read, self_write = IO.pipe
      self.class.catching_sigchld(pid, self_write) do
        wait_r = [@stdout, @stderr, self_read].compact
        wait_w = [input && @stdin].compact
        loop do
          ready_r, ready_w = select(wait_r, wait_w)

          # If the child exits, we still have to be sure to read any data left
          # in the pipes. So we poll the child, drain all the pipes, and *then*
          # check @status.
          #
          # It's very important that we do not call poll between draining the
          # pipes and checking @status. If we did, we open a race condition
          # where the child writes to stdout and exits in that brief window,
          # causing us to lose that data.
          poll

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
            begin
              written = @stdin.write_nonblock(input)
            rescue EOFError # Maybe I shouldn't catch this...
            rescue Errno::EINTR
            end
            input[0...written] = ''
            if input.empty?
              @stdin.close
              wait_w.delete(@stdin)
            end
          end

          break if @status

          # If there's nothing left to wait for, we're done!
          break if wait_r.length == 0 && wait_w.length == 0
        end
      end

      wait

      [stdout, stderr]
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
    #
    # If you pass either an IO or an Integer (i.e., a raw file descriptor), a
    # private copy of it will be made using `#dup`.
    def parse_fd(fd, mode)
      fds = case fd
      when PIPE
        IO.pipe
      when IO
        [fd.dup]
      when Integer
        [IO.new(fd, mode).dup]
      when String
        [File.open(fd, mode)]
      when nil
        []
      else
        raise ArgumentError
      end

      mode == 'r' ? fds : fds.reverse
    end

    def mark_fd_cloexec(fd)
      io = IO.new(fd)
      io.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
      io
    rescue ArgumentError => e
      # Ruby maintains a self-pipe for thread interrupts, but it handles closing
      # it on forks/execs
      raise unless e.message == "The given fd is not accessible because RubyVM reserves it"
    end

    @sigchld_mutex = Mutex.new
    @sigchld_fds = {}
    @sigchld_old_handler = nil

    # Wake up everyone. We can't tell who we should wake up without `wait`ing,
    # and we want to let the process itself do that. In practice, we're not
    # likely to have that many in-flight subprocesses, so this is probably not a
    # big deal.
    def self.handle_sigchld
      @sigchld_fds.values.each do |fd|
        begin
          fd.write_nonblock("\x00")
        rescue Errno::EWOULDBLOCK, Errno::EAGAIN
        end
      end
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

    def self.catching_sigchld(pid, fd)
      register_pid(pid, fd)
      yield
    ensure
      unregister_pid(pid)
    end
  end
end
