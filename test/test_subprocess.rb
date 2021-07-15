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
      assert_instance_of(Subprocess::Process, p)
      p.wait
    end

    it 'complains when not given an Array' do
      assert_raises(ArgumentError) {
        Subprocess.popen("not an Array")
      }
    end

    it 'complains with a helpful error when given arrays with invalid elements' do
      exp = assert_raises(ArgumentError) {
        Subprocess.popen(["not", [:allowed], 5])
      }
      assert_equal(
        "cmd must be an Array of strings (no implicit conversion of Array into String)",
        exp.message
      )
    end
  end

  describe '.call' do
    it 'returns a Process::Status' do
      assert_instance_of(Process::Status, Subprocess.call(['true']))
    end

    it 'yields before and returns after the process exits' do
      start = Time.now
      sleep_time = 0.5
      Subprocess.call(['sleep', sleep_time.to_s]) do |p|
        assert_in_delta(0.0, Time.now - start, 0.2)
      end

      # The point of this isn't to test /bin/sleep: we're okay with anything
      # that's much closer to sleep_time than zero.
      assert_in_delta(sleep_time, Time.now - start, 0.2)
    end

    it 'returns a successful status when calling true' do
      assert(Subprocess.call(['true']).success?)
    end

    it 'returns a non-successful status when calling false' do
      refute(Subprocess.call(['false']).success?)
    end

    it "doesn't spawn a subshell when passed a single argument" do
      script = File.join(File.dirname(__FILE__), 'bin', 'ppid')
      assert_equal($$.to_s, Subprocess.check_output([script]).strip)
    end
  end

  describe '.check_call' do
    it 'returns a Process::Status' do
      assert_instance_of(Process::Status, Subprocess.check_call(['true']))
    end

    it 'returns a successful status when calling true' do
      assert(Subprocess.check_call(['true']).success?)
    end

    it 'raises a NonZeroExit when calling false' do
      assert_raises(Subprocess::NonZeroExit) {
        Subprocess.check_call(['false'])
      }
    end
  end

  describe '.check_output' do
    it 'returns the stdout of the command' do
      string = 'hello world'
      assert_equal(string, Subprocess.check_output(['echo', '-n', string]))
    end

    it 'raises a NonZeroExit when calling false' do
      assert_raises(Subprocess::NonZeroExit) {
        Subprocess.check_output(['false'])
      }
    end
  end

  describe Subprocess::Process do
    it 'sets command' do
      command = ['echo', 'all', 'your', 'llamas', 'are', 'belong', 'to', 'us']
      p = Subprocess::Process.new(command, :stdout => '/dev/null')
      assert_equal(command, p.command)
      p.wait
    end

    it 'has a pid after it has been called' do
      p = Subprocess::Process.new(['true'])
      _(p.pid).must_be(:>, 1)
      p.wait
    end

    it 'closes all file descriptors' do
      fd = File.open("/dev/null")
      # cat returns an error when the file doesn't exist. We use /dev/fd/ to
      # determine if the file is still opened in the child
      assert_raises(Subprocess::NonZeroExit) {
        Subprocess.check_call(['cat', '/dev/fd/' + fd.fileno.to_s],
                              :stderr => '/dev/null')
      }
      fd.close
    end

    # We don't do a great job of testing stderr as comprehensively as we do
    # stdin and stdout because it's slightly annoying to do so. "Meh."

    it 'allows specifying files by name' do
      tmp = Tempfile.new('test')
      Subprocess.check_call(['cat'], :stdin => __FILE__, :stdout => tmp.path)
      assert_equal(File.read(tmp.path), File.read(__FILE__))
      tmp.delete
    end

    it 'allows specifying files by IO' do
      f = File.open(__FILE__)
      tmp = Tempfile.new('test')
      Subprocess.check_call(['cat'], :stdin => f, :stdout => tmp.open)
      assert_equal(File.read(__FILE__), File.read(tmp.path))
      tmp.delete
    end

    it 'allows specifying files by fd' do
      f = File.open(__FILE__)
      tmp = Tempfile.new('test')
      Subprocess.check_call(['cat'], :stdin => f.fileno, :stdout => tmp.fileno)
      assert_equal(File.read(tmp.path), File.read(__FILE__))
      tmp.delete
    end

    it 'opens pipes for communication' do
      Subprocess.check_call(['cat'], :stdin => Subprocess::PIPE,
                            :stdout => Subprocess::PIPE) do |p|
        assert_instance_of(IO, p.stdin)
        assert_instance_of(IO, p.stdout)

        string = "Hello world"
        p.stdin.write(string)
        p.stdin.close
        assert_equal(string, p.stdout.read)
      end
    end

    it "isn't obviously wrong for stderr" do
      stdout_text = "hello"
      stderr_text = "world"
      # sh's echo builtin doesn't support -n
      cmd = "/bin/echo -n '#{stdout_text}'; /bin/echo -n '#{stderr_text}' 1>&2"
      Subprocess.check_call(['sh', '-c', cmd], :stdout => Subprocess::PIPE,
                            :stderr => Subprocess::PIPE) do |p|

        assert_instance_of(IO, p.stdout)
        assert_instance_of(IO, p.stderr)
        assert_equal(stdout_text, p.stdout.read)
        assert_equal(stderr_text, p.stderr.read)
      end
    end

    it 'redirects stderr to stdout when asked' do
      stdout_text = "hello"
      stderr_text = "world"
      # sh's echo builtin doesn't support -n
      cmd = "/bin/echo -n '#{stdout_text}'; /bin/echo -n '#{stderr_text}' 1>&2"
      Subprocess.check_call(['sh', '-c', cmd], :stdout => Subprocess::PIPE,
                            :stderr => Subprocess::STDOUT) do |p|

        assert_instance_of(IO, p.stdout)
        assert_equal(stdout_text + stderr_text, p.stdout.read)
      end
    end

    it 'changes the working directory' do
      Dir.mktmpdir do |dir|
        real = Pathname.new(dir).realpath.to_s
        assert_equal(real, Subprocess.check_output(['pwd'], :cwd => dir).chomp)
      end
    end

    it 'changes the environment' do
      env = {"weather" => "warm and sunny"}
      out = Subprocess.check_output(['sh', '-c', 'echo $weather'], :env => env)
      assert_equal(env['weather'], out.chomp)
    end

    it 'provides helpful error messages with invalid environment arguments' do
      env = {symbol_key: "value"}
      exp = assert_raises(ArgumentError) {
        Subprocess.call(['false'], :env => env)
      }
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
        assert_equal(p.pid.to_s, r.read)
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
          assert_equal(real, r.read)
          r.close
        end
      end
    end

    it 'does not block when you call poll' do
      start = Time.now
      p = Subprocess::Process.new(['sleep', '1'])
      p.poll
      assert_in_delta(0.0, Time.now - start, 0.2)
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
        _(written).must_be :<, MULTI_WRITE_STRING.length
      end

      Subprocess.check_call(['cat'], :stdin => Subprocess::PIPE,
                            :stdout => Subprocess::PIPE) do |p|
        stdout, _stderr = p.communicate(MULTI_WRITE_STRING)
        assert_equal(MULTI_WRITE_STRING, stdout)
      end
    end

    it 'does not deadlock if you #communicate without any pipes' do
      Timeout.timeout(5) do
        p = Subprocess.popen(['true'])
        p.wait
        _out, _err = p.communicate
      end
    end

    it 'does not deadlock when communicating with a process that forks' do
      script = <<EOF
  echo "fork"
  (echo "me" && sleep 10) &
EOF
      p = Subprocess::Process.new(['bash', '-c', script], stdout: Subprocess::PIPE)
      stdout, _stderr = p.communicate(nil, 5)
      assert_includes(stdout, "fork\n")
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
            assert_equal("", stdout)
          else
            assert_equal("foo", stdout)
            p.send_signal("HUP")
            yielded = true
          end
        end
      end
    end

    it 'should not timeout in communicate if the command completes in time' do
      Subprocess.check_call(['echo', 'foo'], stdout: Subprocess::PIPE) do |p|
        stdout, _, = p.communicate(nil, 1)
        assert_equal("foo\n", stdout)
      end
    end

    it 'should timeout in communicate without losing data' do
      call_multiwrite_script do |p|
        # Read the first echo and timeout
        e = assert_raises(Subprocess::CommunicateTimeout) {
          p.communicate(nil, 0.2)
        }
        assert_equal("foo\n", e.stderr)
        assert_equal("", e.stdout)

        # Send a signal and read the next echo
        p.send_signal('HUP')
        stdout, stderr = p.communicate
        assert_equal("bar\n", stdout)
        assert_equal("", stderr)
      end
    end

    it 'incrementally yields output to a block in communicate' do
      call_multiwrite_script do |p|
        called = 0

        res = p.communicate(nil, 5) do |stdout, stderr|
          case called
          when 0
            assert_equal("foo\n", stderr)
            assert_equal("", stdout)
            p.send_signal("HUP")
          when 1
            assert_equal("", stderr)
            assert_equal("bar\n", stdout)
          else
            raise "Unexpected #{called+1}th call to `communicate` with `#{stdout}` and `#{stderr}`"
          end

          called += 1
        end

        assert_nil(res)
      end
    end

    it 'has a license to kill' do
      start = Time.now
      assert_raises(Subprocess::NonZeroExit) {
        Subprocess.check_call(['sleep', '9001']) do |p|
          p.terminate
        end
      }
      assert_in_delta(0.0, Time.now - start, 0.2)
    end

    it 'sends other signals too' do
      Subprocess.check_call(['bash', '-c', 'read var'],
                            stdin: Subprocess::PIPE) do |p|
        p.send_signal("STOP")
        assert_equal(p.pid, Process.waitpid(p.pid, Process::WUNTRACED))
        p.send_signal("CONT")
        p.stdin.write("foo\n")
      end
    end

    it "doesn't leak children when throwing errors" do
      # For some reason GitHub Actions CI fails this test.
      skip if RUBY_PLATFORM.include?('darwin')
      assert_raises(Errno::ENOENT) {
        Subprocess.call(['/not/a/file', ':('])
      }

      ps_pid = 0
      procs = Subprocess.check_output(['ps', '-o', 'pid ppid']) do |p|
        ps_pid = p.pid
      end

      pid_table = procs.split("\n")[1..-1].map{ |l| l.split(' ').map(&:to_i) }
      children = pid_table.find_all{ |pid, ppid| ppid == $$ && pid != ps_pid }

      assert_equal([], children)
    end

    describe '#communicate' do
      script = %Q(echo -n 你好; sleep 1; echo -n 世界) # Use `sleep` to cycle IO#select

      it 'preserves encoding across IO selection cycles with no block given' do
        process = Subprocess::Process.new(['bash', '-c', script], :stdout => Subprocess::PIPE)

        stdout, _stderr =  process.communicate

        assert_equal("你好世界", stdout)
      end

      it 'preserves encoding  across IO selection cycles with a block given' do
        process = Subprocess::Process.new(['bash', '-c', script], :stdout => Subprocess::PIPE)
        stdout = ""

        process.communicate do |out, _err|
          stdout << out
        end

        assert_equal("你好世界", stdout)
      end

      it 'handles binary data as stdin' do
        message = 'ḧëḷḷöẅöṛḷḋ' * 64 * 1024
        assert_equal(Encoding::UTF_8, message.encoding)

        process = Subprocess::Process.new(['cat'], :stdin => Subprocess::PIPE, :stdout => Subprocess::PIPE)
        stdout = ""
        process.communicate(message) do |out, _err|
          stdout << out
        end
        assert_equal(message.size, stdout.size)
        assert_equal(message, stdout)
      end
    end
  end
end
