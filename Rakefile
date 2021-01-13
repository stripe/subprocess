require 'bundler/gem_tasks'
require 'bundler/setup'
require 'rake/testtask'

require 'tempfile'

task :default do
  sh 'rake -T'
end

Rake::TestTask.new do |t|
  t.libs.push "lib"
  t.test_files = FileList['test/test_*.rb']
  t.verbose = true
end

task :sord do
  rbi_file = 'rbi/subprocess.rbi'
  sh 'sord', '--no-sord-comments', rbi_file

  Tempfile.create do |tmp|
    File.open(rbi_file) do |f|
      f.each do |line|
        tmp.puts(line.rstrip)
      end
    end
    File.rename(tmp.path, rbi_file)
  end
end
