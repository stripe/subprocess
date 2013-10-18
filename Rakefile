require 'bundler/gem_tasks'
require 'bundler/setup'
require 'rake/testtask'

task :default do
  sh 'rake -T'
end

Rake::TestTask.new do |t|
  t.libs.push "lib"
  t.test_files = FileList['test/test_*.rb']
  t.verbose = true
end
