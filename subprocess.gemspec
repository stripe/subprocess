# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name        = "subprocess"
  s.version     = "0.16"
  s.authors     = ["Carl Jackson", "Evan Broder", "Nelson Elhage", "Andy Brody",
                   "Andreas Fuchs"]
  s.email       = %W{carl evan nelhage andy asf}.map{|who| "#{who}@stripe.com" }
  s.homepage    = "https://github.com/stripe/subprocess"
  s.summary     = "A port of Python's subprocess module to Ruby"
  s.description = "Control and communicate with spawned processes"
  s.license     = "MIT"

  s.files       = Dir.glob("{lib}/**/*") + %w(README.md)

  s.add_development_dependency "minitest", "~> 5.0"
  s.add_development_dependency "rake"
end
