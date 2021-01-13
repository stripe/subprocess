# typed: strong
# A Ruby clone of Python's subprocess module.
#
# @see http://docs.python.org/2/library/subprocess.html
module Subprocess
  PIPE = T.let(-1, T.untyped)
  STDOUT = T.let(-2, T.untyped)
  VERSION = T.let('1.5.3', T.untyped)

  # An alias for `Process.new`. Mostly here to better emulate the Python API.
  #
  # _@param_ `cmd` — See {Process#initialize}
  #
  # _@param_ `opts` — See {Process#initialize}
  #
  # _@return_ — A process with the given arguments
  #
  # _@see_ `Process#initialize`
  sig { params(cmd: T::Array[String], opts: T::Hash[T.untyped, T.untyped], blk: T.proc.params(process: Process).void).returns(Process) }
  def self.popen(cmd, opts = {}, &blk); end

  # Call and wait for the return of a given process.
  #
  # _@param_ `cmd` — See {Process#initialize}
  #
  # _@param_ `opts` — See {Process#initialize}
  #
  # _@return_ — The exit status of the process
  #
  # _@note_ — If you call this function with `:stdout => PIPE` or `:stderr => PIPE`,
  # this function will block indefinitely as soon as the OS's pipe buffer
  # fills up, as neither file descriptor will be read from. To avoid this, use
  # {Process#communicate} from a passed block.
  #
  # _@see_ `Process#initialize`
  sig { params(cmd: T::Array[String], opts: T::Hash[T.untyped, T.untyped], blk: T.proc.params(process: Process).void).returns(::Process::Status) }
  def self.call(cmd, opts = {}, &blk); end

  # Like {Subprocess::call}, except raise a {NonZeroExit} if the process did not
  # terminate successfully.
  #
  # _@param_ `cmd` — See {Process#initialize}
  #
  # _@param_ `opts` — See {Process#initialize}
  #
  # _@return_ — The exit status of the process
  #
  # Grep a file for a string
  # ```ruby
  # Subprocess.check_call(%W{grep -q llama ~/favorite_animals})
  # ```
  #
  # Communicate with a child process
  # ```ruby
  # Subprocess.check_call(%W{sendmail -t}, :stdin => Subprocess::PIPE) do |p|
  #   p.communicate <<-EMAIL
  # From: alpaca@example.com
  # To: llama@example.com
  # Subject: I am so fluffy.
  #
  # SO FLUFFY!
  # http://upload.wikimedia.org/wikipedia/commons/3/3e/Unshorn_alpaca_grazing.jpg
  #   EMAIL
  # end
  # ```
  #
  # _@note_ — If you call this function with `:stdout => PIPE` or `:stderr => PIPE`,
  # this function will block indefinitely as soon as the OS's pipe buffer
  # fills up, as neither file descriptor will be read from. To avoid this, use
  # {Process#communicate} from a passed block.
  #
  # _@see_ `Process#initialize`
  sig { params(cmd: T::Array[String], opts: T::Hash[T.untyped, T.untyped], blk: T.proc.params(process: Process).void).returns(::Process::Status) }
  def self.check_call(cmd, opts = {}, &blk); end

  # Like {Subprocess::check_call}, but return the contents of `stdout`, much
  # like {::Kernel#system}.
  #
  # _@param_ `cmd` — See {Process#initialize}
  #
  # _@param_ `opts` — See {Process#initialize}
  #
  # _@return_ — The contents of `stdout`
  #
  # Get the system load
  # ```ruby
  # system_load = Subprocess.check_output(['uptime']).split(' ').last(3)
  # ```
  #
  # _@see_ `Process#initialize`
  sig { params(cmd: T::Array[String], opts: T::Hash[T.untyped, T.untyped], blk: T.proc.params(process: Process).void).returns(String) }
  def self.check_output(cmd, opts = {}, &blk); end

  # Print a human readable interpretation of a process exit status.
  #
  # _@param_ `status` — The status returned by `waitpid2`.
  #
  # _@param_ `convert_high_exit` — Whether to convert exit statuses greater than 128 into the usual convention for exiting after trapping a signal. (e.g. many programs will exit with status 130 after receiving a SIGINT / signal 2.)
  #
  # _@return_ — Text interpretation
  sig { params(status: ::Process::Status, convert_high_exit: T::Boolean).returns(String) }
  def self.status_to_s(status, convert_high_exit = true); end

  # Error class representing a process's abnormal exit.
  class NonZeroExit < StandardError
    # Return an instance of {NonZeroExit}.
    #
    # _@param_ `cmd` — The command that returned a non-zero status.
    #
    # _@param_ `status` — The status returned by `waitpid`.
    sig { params(cmd: T::Array[String], status: ::Process::Status).void }
    def initialize(cmd, status); end

    # _@return_ — The command and arguments for the process that exited
    # abnormally.
    #
    # _@note_ — This is intended only for use in user-facing error messages. In
    # particular, no shell quoting of any sort is performed when
    # constructing this string, meaning that blindly running it in a shell
    # might have different semantics than the original command.
    sig { returns(String) }
    attr_reader :command

    # _@return_ — The Ruby status object returned by `waitpid`
    sig { returns(::Process::Status) }
    attr_reader :status
  end

  # Error class representing a timeout during a call to `communicate`
  class CommunicateTimeout < StandardError
    # _@param_ `cmd`
    #
    # _@param_ `stdout`
    #
    # _@param_ `stderr`
    sig { params(cmd: T::Array[String], stdout: String, stderr: String).void }
    def initialize(cmd, stdout, stderr); end

    # _@return_ — Content read from stdout before the timeout
    sig { returns(String) }
    attr_reader :stdout

    # _@return_ — Content read from stderr before the timeout
    sig { returns(String) }
    attr_reader :stderr
  end

  # A child process. The preferred way of spawning a subprocess is through the
  # functions on {Subprocess} (especially {Subprocess::check_call} and
  # {Subprocess::check_output}).
  class Process
    # Create a new process.
    #
    # _@param_ `cmd` — The command to run and its arguments (in the style of an `argv` array). Unlike Python's subprocess module, `cmd` cannot be a String.
    sig { params(cmd: T::Array[String], opts: T::Hash[T.untyped, T.untyped], blk: T.proc.params(process: Process).void).void }
    def initialize(cmd, opts = {}, &blk); end

    # Poll the child, setting (and returning) its status. If the child has not
    # terminated, return nil and exit immediately
    #
    # _@return_ — The exit status of the process
    sig { returns(T.nilable(::Process::Status)) }
    def poll; end

    # Wait for the child to return, setting and returning the status of the
    # child.
    #
    # _@return_ — The exit status of the process
    sig { returns(::Process::Status) }
    def wait; end

    # Do nonblocking reads from `fd`, appending all data read into `buf`.
    #
    # _@param_ `fd` — The file to read from.
    #
    # _@param_ `buf` — A buffer to append the read data to.
    #
    # _@return_ — Whether `fd` was closed due to an exceptional
    # condition (`EOFError` or `EPIPE`).
    sig { params(fd: IO, buf: T.nilable(String)).returns(T::Boolean) }
    def drain_fd(fd, buf = nil); end

    # Write the (optional) input to the process's `stdin` and read the contents of
    # `stdout` and `stderr`. If a block is provided, stdout and stderr are yielded as they
    # are read. Otherwise they are buffered in memory and returned when the process
    # exits. Do this all using `IO::select`, so we don't deadlock due to full pipe
    # buffers.
    #
    # This is only really useful if you set some of `:stdin`, `:stdout`, and
    # `:stderr` to {Subprocess::PIPE}.
    #
    # _@param_ `input` — A string to feed to the child's standard input.
    #
    # _@param_ `timeout_s` — Raise {Subprocess::CommunicateTimeout} if communicate does not finish after timeout_s seconds.
    #
    # _@return_ — An array of two elements: the data read from the
    # child's standard output and standard error, respectively.
    # Returns nil if a block is provided.
    sig { params(input: T.nilable(String), timeout_s: T.nilable(Numeric)).returns(T.nilable([String, String])) }
    def communicate(input = nil, timeout_s = nil); end

    # Does exactly what it says on the box.
    #
    # _@param_ `signal` — The signal to send to the child process. Accepts all the same arguments as Ruby's built-in {::Process::kill}, for instance a string like "INT" or "SIGINT", or a signal number like 2.
    #
    # _@return_ — See {::Process.kill}
    #
    # _@see_ `::Process.kill`
    sig { params(signal: T.any(String, Symbol, Integer)).returns(Integer) }
    def send_signal(signal); end

    # Sends `SIGTERM` to the process.
    #
    # _@return_ — See {send_signal}
    #
    # _@see_ `send_signal`
    sig { returns(Integer) }
    def terminate; end

    # Return a pair of values (child, mine), which are how the given file
    # descriptor should appear to the child and to this process, respectively.
    # "mine" is only non-nil in the case of a pipe (in fact, we just return a
    # list of length one, since ruby will unpack nils from missing list items).
    #
    # _@param_ `fd`
    #
    # _@param_ `mode`
    sig { params(fd: T.nilable(T.any(IO, Integer, String, Subprocess::PIPE)), mode: String).returns(T::Array[IO]) }
    def parse_fd(fd, mode); end

    # The pair to parse_fd, returns whether or not the file descriptor was
    # opened by us (and therefore should be closed by us).
    #
    # _@param_ `fd`
    sig { params(fd: T.nilable(T.any(IO, Integer, String, Subprocess::PIPE))).returns(T::Boolean) }
    def our_fd?(fd); end

    # Call IO.select timing out at Time `timeout_at`. If `timeout_at` is nil, never times out.
    #
    # _@param_ `read_array`
    #
    # _@param_ `write_array`
    #
    # _@param_ `err_array`
    #
    # _@param_ `timeout_at`
    sig do
      params(
        read_array: T.nilable(T::Array[IO]),
        write_array: T.nilable(T::Array[IO]),
        err_array: T.nilable(T::Array[IO]),
        timeout_at: T.nilable(T.any(Integer, Float))
      ).returns(T.nilable(T::Array[T::Array[IO]]))
    end
    def select_until(read_array, write_array, err_array, timeout_at); end

    sig { void }
    def self.handle_sigchld; end

    # Wake up everyone. We can't tell who we should wake up without `wait`ing,
    # and we want to let the process itself do that. In practice, we're not
    # likely to have that many in-flight subprocesses, so this is probably not a
    # big deal.
    sig { void }
    def self.wakeup_sigchld; end

    # _@param_ `pid`
    #
    # _@param_ `fd`
    sig { params(pid: Integer, fd: IO).void }
    def self.register_pid(pid, fd); end

    # _@param_ `pid`
    sig { params(pid: Integer).void }
    def self.unregister_pid(pid); end

    # _@param_ `pid`
    sig { params(pid: Integer).void }
    def self.catching_sigchld(pid); end

    # _@return_ — The `IO` that is connected to this process's `stdin`.
    sig { returns(IO) }
    attr_reader :stdin

    # _@return_ — The `IO` that is connected to this process's `stdout`.
    sig { returns(IO) }
    attr_reader :stdout

    # _@return_ — The `IO` that is connected to this process's `stderr`.
    sig { returns(IO) }
    attr_reader :stderr

    # _@return_ — The command this process was invoked with.
    sig { returns(T::Array[String]) }
    attr_reader :command

    # _@return_ — The process ID of the spawned process.
    sig { returns(Integer) }
    attr_reader :pid

    # _@return_ — The exit status code of the process. Only
    # set after the process has exited.
    sig { returns(::Process::Status) }
    attr_reader :status
  end
end
