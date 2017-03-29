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
  end

  describe '.call' do
    it 'returns a Process::Status' do
      Subprocess.call(['true']).must_be_instance_of(Process::Status)
    end

    it 'waits for the process to exit' do
      start = Time.now
      Subprocess.call(['sleep', '1'])
      # The point of this isn't to test /bin/sleep: we're okay with anything
      # that's much closer to 1 than it is to 0.
      (Time.now - start).must_be_close_to(1.0, 0.2)
    end

    it 'yields before the process exits' do
      start = Time.now
      Subprocess.call(['sleep', '1']) do |p|
        (Time.now - start).must_be_close_to(0.0, 0.2)
      end
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

    it 'does not block when you call poll' do
      start = Time.now
      p = Subprocess::Process.new(['sleep', '1'])
      p.poll
      (Time.now - start).must_be_close_to(0.0, 0.2)
      p.wait
    end

    it 'should not deadlock when #communicate-ing with large strings' do
      Subprocess.check_call(['cat'], :stdin => Subprocess::PIPE,
                            :stdout => Subprocess::PIPE) do |p|
        # Generate a 16MB string, which happens to be quite a bit bigger than
        # the pipe buffers on all systems I know about. A naive solution here
        # would deadlock pretty quickly.
        string = "x" * 1024 * 1024 * 16
        stdout, stderr = p.communicate(string)
        stdout.must_equal(string)
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
      script = File.join(File.dirname(__FILE__), 'bin', 'closer.rb')
      Subprocess.check_call(['bash', '-c', '<&-; echo -n "foo"; sleep 1'], :stdin => Subprocess::PIPE,
                            :stdout => Subprocess::PIPE) do |p|
        # Wait for the read on stdout to be available before we force a read to stdin
        IO.select([p.stdout])

        # Generate a 16MB string, which happens to be quite a bit bigger than
        # the pipe buffers on all systems I know about. A naive solution here
        # would deadlock pretty quickly.
        string = "x" * 1024 * 1024 * 16
        stdout, stderr = p.communicate(string)
        stdout.must_equal("foo")
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
      start = Time.now
      Subprocess.check_call(['sleep', '1']) do |p|
        p.send_signal("STOP")
        sleep 1
        p.send_signal("CONT")
      end
      (Time.now - start).must_be_close_to(2.0, 0.2)
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
