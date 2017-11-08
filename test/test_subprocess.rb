# coding: utf-8
require 'rubygems'
gem 'minitest'
require 'minitest/autorun'
require 'subprocess'

require 'timeout'
require 'pathname'
require 'tempfile'

# Because we're testing spawning processes, these tests assume you have a basic
# set of useful UNIX-y programs on your PATH. Efforts have been made to make the
# tests compatible with most environments, but it's possible these tests will
# fail on some system I've never heard about. Or Windows. It probably doesn't
# work on Windows.

describe Subprocess do

  def call_multiwrite_script(&block)
    script = <<EOF
sleep 10 &
trap "echo bar; kill $!; exit" HUP
echo foo 1>&2
wait
EOF

    Subprocess.check_call(
      ['bash', '-c', script],
      stdout: Subprocess::PIPE, stderr: Subprocess::PIPE,
      &block
    )
  end

  # A string larger than the pipe buffer. We ensure this is true in a test below.
  MULTI_WRITE_STRING = "x" * 1024 * 1024

  describe '.popen' do
    it 'creates Process objects' do
      p = Subprocess.popen(['true'])
      p.must_be_instance_of(Subprocess::Process)
      p.wait
    end

    it 'complains when not given an Array' do
      lambda {
        Subprocess.popen("not an Array")
      }.must_raise(ArgumentError)
    end

    it 'complains with a helpful error when given arrays with invalid elements' do
      exp = lambda {
        Subprocess.popen(["not", [:allowed], 5])
      }.must_raise(ArgumentError)
      assert_equal(
        "cmd must be an Array of strings (no implicit conversion of Array into String)",
        exp.message
      )
    end
  end

  describe '.call' do
    it 'returns a Process::Status' do
      Subprocess.call(['true']).must_be_instance_of(Process::Status)
    end

    it 'yields before and returns after the process exits' do
      start = Time.now
      sleep_time = 0.5
      Subprocess.call(['sleep', sleep_time.to_s]) do |p|
        (Time.now - start).must_be_close_to(0.0, 0.2)
      end

      # The point of this isn't to test /bin/sleep: we're okay with anything
      # that's much closer to sleep_time than zero.
      (Time.now - start).must_be_close_to(sleep_time, 0.2)
    end

    it 'returns a successful status when calling true' do
      Subprocess.call(['true']).success?.must_equal(true)
    end

    it 'returns a non-successful status when calling false' do
      Subprocess.call(['false']).success?.must_equal(false)
    end

    it "doesn't spawn a subshell when passed a single argument" do
      script = File.join(File.dirname(__FILE__), 'bin', 'ppid')
      Subprocess.check_output([script]).strip.must_equal($$.to_s)
    end
  end

  describe '.check_call' do
    it 'returns a Process::Status' do
      Subprocess.check_call(['true']).must_be_instance_of(Process::Status)
    end

    it 'returns a successful status when calling true' do
      Subprocess.check_call(['true']).success?.must_equal(true)
    end

    it 'raises a NonZeroExit when calling false' do
      lambda {
        Subprocess.check_call(['false'])
      }.must_raise(Subprocess::NonZeroExit)
    end
  end

  describe '.check_output' do
    it 'returns the stdout of the command' do
      string = 'hello world'
      Subprocess.check_output(['echo', '-n', string]).must_equal(string)
    end

    it 'raises a NonZeroExit when calling false' do
      lambda {
        Subprocess.check_output(['false'])
      }.must_raise(Subprocess::NonZeroExit)
    end
  end

  describe Subprocess::Process do
    it 'sets command' do
      command = ['echo', 'all', 'your', 'llamas', 'are', 'belong', 'to', 'us']
      p = Subprocess::Process.new(command, :stdout => '/dev/null')
      p.command.must_equal(command)
      p.wait
    end

    it 'has a pid after it has been called' do
      p = Subprocess::Process.new(['true'])
      p.pid.must_be(:>, 1)
      p.wait
    end

    it 'closes all file descriptors' do
      fd = File.open("/dev/null")
      # cat returns an error when the file doesn't exist. We use /dev/fd/ to
      # determine if the file is still opened in the child
      lambda {
        Subprocess.check_call(['cat', '/dev/fd/' + fd.fileno.to_s],
                              :stderr => '/dev/null')
      }.must_raise(Subprocess::NonZeroExit)
      fd.close
    end

    # We don't do a great job of testing stderr as comprehensively as we do
    # stdin and stdout because it's slightly annoying to do so. "Meh."

    it 'allows specifying files by name' do
      tmp = Tempfile.new('test')
      Subprocess.check_call(['cat'], :stdin => __FILE__, :stdout => tmp.path)
      File.read(__FILE__).must_equal(File.read(tmp.path))
      tmp.delete
    end

    it 'allows specifying files by IO' do
      f = File.open(__FILE__)
      tmp = Tempfile.new('test')
      Subprocess.check_call(['cat'], :stdin => f, :stdout => tmp.open)
      File.read(__FILE__).must_equal(File.read(tmp.path))
      tmp.delete
    end

    it 'allows specifying files by fd' do
      f = File.open(__FILE__)
      tmp = Tempfile.new('test')
      Subprocess.check_call(['cat'], :stdin => f.fileno, :stdout => tmp.fileno)
      File.read(__FILE__).must_equal(File.read(tmp.path))
      tmp.delete
    end

    it 'opens pipes for communication' do
      Subprocess.check_call(['cat'], :stdin => Subprocess::PIPE,
                            :stdout => Subprocess::PIPE) do |p|
        p.stdin.must_be_instance_of(IO)
        p.stdout.must_be_instance_of(IO)

        string = "Hello world"
        p.stdin.write(string)
        p.stdin.close
        p.stdout.read.must_equal(string)
      end
    end

    it "isn't obviously wrong for stderr" do
      stdout_text = "hello"
      stderr_text = "world"
      # sh's echo builtin doesn't support -n
      cmd = "/bin/echo -n '#{stdout_text}'; /bin/echo -n '#{stderr_text}' 1>&2"
      Subprocess.check_call(['sh', '-c', cmd], :stdout => Subprocess::PIPE,
                            :stderr => Subprocess::PIPE) do |p|

        p.stdout.must_be_instance_of(IO)
        p.stderr.must_be_instance_of(IO)
        p.stdout.read.must_equal(stdout_text)
        p.stderr.read.must_equal(stderr_text)
      end
    end

    it 'redirects stderr to stdout when asked' do
      stdout_text = "hello"
      stderr_text = "world"
      # sh's echo builtin doesn't support -n
      cmd = "/bin/echo -n '#{stdout_text}'; /bin/echo -n '#{stderr_text}' 1>&2"
      Subprocess.check_call(['sh', '-c', cmd], :stdout => Subprocess::PIPE,
                            :stderr => Subprocess::STDOUT) do |p|

        p.stdout.must_be_instance_of(IO)
        p.stdout.read.must_equal(stdout_text + stderr_text)
      end
    end

    it 'changes the working directory' do
      Dir.mktmpdir do |dir|
        real = Pathname.new(dir).realpath.to_s
        Subprocess.check_output(['pwd'], :cwd => dir).chomp.must_equal(real)
      end
    end

    it 'changes the environment' do
      env = {"weather" => "warm and sunny"}
      out = Subprocess.check_output(['sh', '-c', 'echo $weather'], :env => env)
      out.chomp.must_equal(env['weather'])
    end

    it 'provides helpful error messages with invalid environment arguments' do
      env = {symbol_key: "value"}
      exp = lambda {
        Subprocess.call(['false'], :env => env)
      }.must_raise(ArgumentError)
      assert_equal(
        "`env` option must be a hash where all keys and values are strings (no implicit conversion of Symbol into String)",
        exp.message
      )
    end

    it 'retains files when asked' do
      fd = File.open("/dev/null")
      Subprocess.check_call(['cat', '/dev/fd/' + fd.fileno.to_s],
                            :retain_fds => [fd.fileno])
    end

    it 'calls the preexec_fn in the child process' do
      # We write over a pipe that only we know about
      r, w = IO.pipe
      fn = Proc.new { w.write($$) }
      Subprocess.check_call(['true'], :preexec_fn => fn) do |p|
        w.close
        r.read.must_equal(p.pid.to_s)
        r.close
      end
    end

    it 'calls the preexec_fn in the correct working directory' do
      # We write over a pipe that only we know about
      r, w = IO.pipe
      fn = Proc.new { w.write(Dir.pwd) }
      Dir.mktmpdir do |dir|
        real = Pathname.new(dir).realpath.to_s
        Subprocess.check_call(['true'], :preexec_fn => fn, :cwd => real) do |p|
          w.close
          r.read.must_equal(real)
          r.close
        end
      end
    end

    it 'does not block when you call poll' do
      start = Time.now
      p = Subprocess::Process.new(['sleep', '1'])
      p.poll
      (Time.now - start).must_be_close_to(0.0, 0.2)
      p.terminate
      p.wait
    end

    it 'should not deadlock when #communicate-ing with large strings' do
      # First ensure that this string really is bigger than the pipe buffer
      # on this system.
      IO.pipe do |_r, w|
        begin
          written = w.write_nonblock(MULTI_WRITE_STRING)
        rescue IO::WaitWritable, Errno::EINTR
          retry
        end
        written.must_be :<, MULTI_WRITE_STRING.length
      end

      Subprocess.check_call(['cat'], :stdin => Subprocess::PIPE,
                            :stdout => Subprocess::PIPE) do |p|
        stdout, _stderr = p.communicate(MULTI_WRITE_STRING)
        stdout.must_equal(MULTI_WRITE_STRING)
      end
    end

    it 'does not deadlock if you #communicate without any pipes' do
      Timeout.timeout(5) do
        p = Subprocess.popen(['true'])
        p.wait
        out, err = p.communicate
      end
    end

    it 'should not raise an error when the process closes stdin before we finish writing' do
      script = <<EOF
<&-
sleep 10 &
trap "kill $!; exit" HUP
echo -n foo
wait
EOF
      Subprocess.check_call(['bash', '-c', script], :stdin => Subprocess::PIPE,
                            :stdout => Subprocess::PIPE) do |p|
        # Wait for the read on stdout to be available before we force a read to stdin
        IO.select([p.stdout])

        yielded = false
        p.communicate(MULTI_WRITE_STRING) do |stdout, _stderr|
          if yielded
            stdout.must_equal("")
          else
            stdout.must_equal("foo")
            p.send_signal("HUP")
            yielded = true
          end
        end
      end
    end

    it 'should not timeout in communicate if the command completes in time' do
      Subprocess.check_call(['echo', 'foo'], stdout: Subprocess::PIPE) do |p|
        stdout, _, = p.communicate(nil, 1)
        stdout.must_equal("foo\n")
      end
    end

    it 'should timeout in communicate without losing data' do
      call_multiwrite_script do |p|
        # Read the first echo and timeout
        e = lambda {
          p.communicate(nil, 0.2)
        }.must_raise(Subprocess::CommunicateTimeout)
        e.stderr.must_equal("foo\n")
        e.stdout.must_equal("")

        # Send a signal and read the next echo
        p.send_signal('HUP')
        stdout, stderr = p.communicate
        stdout.must_equal("bar\n")
        stderr.must_equal("")
      end
    end

    it 'incrementally yields output to a block in communicate' do
      call_multiwrite_script do |p|
        called = 0

        res = p.communicate(nil, 5) do |stdout, stderr|
          case called
          when 0
            stderr.must_equal("foo\n")
            stdout.must_equal("")
            p.send_signal("HUP")
          when 1
            stderr.must_equal("")
            stdout.must_equal("bar\n")
          else
            raise "Unexpected #{called+1}th call to `communicate` with `#{stdout}` and `#{stderr}`"
          end

          called += 1
        end

        res.must_be_nil
      end
    end

    it 'has a license to kill' do
      start = Time.now
      lambda {
        Subprocess.check_call(['sleep', '9001']) do |p|
          p.terminate
        end
      }.must_raise(Subprocess::NonZeroExit)
      (Time.now - start).must_be_close_to(0.0, 0.2)
    end

    it 'sends other signals too' do
      Subprocess.check_call(['bash', '-c', 'read var'],
                            stdin: Subprocess::PIPE) do |p|
        p.send_signal("STOP")
        Process.waitpid(p.pid, Process::WUNTRACED).must_equal(p.pid)
        p.send_signal("CONT")
        p.stdin.write("foo\n")
      end
    end

    it "doesn't leak children when throwing errors" do
      lambda {
        Subprocess.call(['/not/a/file', ':('])
      }.must_raise(Errno::ENOENT)

      ps_pid = 0
      procs = Subprocess.check_output(['ps', '-o', 'pid ppid']) do |p|
        ps_pid = p.pid
      end

      pid_table = procs.split("\n")[1..-1].map{ |l| l.split(' ').map(&:to_i) }
      children = pid_table.find_all{ |pid, ppid| ppid == $$ && pid != ps_pid }

      children.must_equal([])
    end

    it "properly encodes output strings" do
      test_string = 'aå'
      output = Subprocess.check_output(['echo', '-n', test_string])
      output.must_equal(test_string)
    end
  end
end
