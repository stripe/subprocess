# frozen_string_literal: true
require 'rubygems'
gem 'minitest'
require 'minitest/autorun'
require 'subprocess'

# Test to confirm bug where subprocess.communicate("") doesn't properly close stdin
describe Subprocess do
  describe "empty string stdin issue" do
    it "should not cause a broken pipe with empty string input" do
      # This script waits for stdin to close and then outputs "stdin closed"
      script = <<-EOF
      # Wait for stdin to close, then output a message
      require 'io/wait'
      STDIN.wait_readable
      puts "stdin closed"
      EOF

      # Run the process and communicate with empty string input
      Subprocess.check_call(['ruby', '-e', script], 
                           stdin: Subprocess::PIPE,
                           stdout: Subprocess::PIPE) do |p|
        stdout, _ = p.communicate("")
        assert_includes(stdout, "stdin closed", "STDIN was not properly closed with empty string input")
      end
    end

    it "should work fine with non-empty string input" do
      # Same test but with non-empty input
      script = <<-EOF
      # Wait for stdin to close, then output a message
      require 'io/wait'
      content = STDIN.read
      puts "received: \#{content}"
      puts "stdin closed"
      EOF

      # Run the process and communicate with non-empty string input
      Subprocess.check_call(['ruby', '-e', script], 
                           stdin: Subprocess::PIPE,
                           stdout: Subprocess::PIPE) do |p|
        stdout, _ = p.communicate("boop")
        assert_includes(stdout, "received: boop", "Input was not received properly")
        assert_includes(stdout, "stdin closed", "STDIN was not properly closed with non-empty input")
      end
    end
  end
end