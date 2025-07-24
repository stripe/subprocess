# frozen_string_literal: true
require 'rubygems'
gem 'minitest'
require 'minitest/autorun'
require 'subprocess'

describe Subprocess do
  describe "communicate with empty string input" do
    # Bug report: subprocess.communicate("") doesn't properly handle stdin,
    # causing it to close incorrectly and result in a broken pipe.
    it "should not raise IOError when passing empty string" do
      # Before the fix, this would raise: IOError: closed stream
      Subprocess.check_call(['cat'],
                           stdin: Subprocess::PIPE,
                           stdout: Subprocess::PIPE) do |p|
        stdout, stderr = p.communicate("")
        assert_equal("", stdout, "Empty input should produce empty output")
        assert_equal("", stderr, "No errors expected")
      end
    end

    it "should work correctly with non-empty string input" do
      test_input = "hello world"
      Subprocess.check_call(['cat'],
                           stdin: Subprocess::PIPE,
                           stdout: Subprocess::PIPE) do |p|
        stdout, stderr = p.communicate(test_input)
        assert_equal(test_input, stdout, "Input should be echoed back")
        assert_equal("", stderr, "No errors expected")
      end
    end

    it "should work correctly with nil input" do
      Subprocess.check_call(['cat'],
                           stdin: Subprocess::PIPE,
                           stdout: Subprocess::PIPE) do |p|
        stdout, stderr = p.communicate(nil)
        assert_equal("", stdout, "Nil input should produce empty output")
        assert_equal("", stderr, "No errors expected")
      end
    end

    it "should handle already closed stdin gracefully" do
      # Edge case: what if stdin is already closed?
      p = Subprocess.popen(['cat'], stdin: Subprocess::PIPE, stdout: Subprocess::PIPE)
      p.stdin.close
      stdout, stderr = p.communicate("")
      assert_equal("", stdout)
      assert_equal("", stderr)
      p.wait
    end
  end
end
