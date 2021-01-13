# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'subprocess/version'

Gem::Specification.new do |s|
  s.name        = "subprocess"
  s.version     = Subprocess::VERSION
  s.authors     = ["Carl Jackson", "Evan Broder", "Nelson Elhage",
                   "Andy Brody", "Andreas Fuchs"]
  s.email       = %W{carl evan nelhage andy asf}.map{|who| "#{who}@stripe.com"}
  s.homepage    = "https://github.com/stripe/subprocess"
  s.summary     = "A port of Python's subprocess module to Ruby"
  s.description = "Control and communicate with spawned processes"
  s.license     = "MIT"

  s.files       = Dir.glob("{lib}/**/*") + %w(README.md)

  s.add_development_dependency "minitest", "~> 5.0"
  s.add_development_dependency "rake"
  s.add_development_dependency "pry"
  s.add_development_dependency "sord"
end
