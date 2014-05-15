# Subprocess [![Build Status](https://travis-ci.org/stripe/subprocess.svg?branch=master)](https://travis-ci.org/stripe/subprocess)

![Jacques Cousteau Submarine](http://i.imgur.com/lmej24F.jpg)

A port of Python's excellent subprocess module to Ruby.

Many thanks to [Bram Swenson][bram], the author of the old [subprocess][old]
gem, for graciously letting us use the name.

[bram]: https://github.com/bramswenson
[old]: https://github.com/bramswenson/subprocess

Installation
------------

The recommended way of installing `subprocess` is through Rubygems:

    $ gem install subprocess

You can also build `subprocess` from source by running:

    $ gem build subprocess.gemspec


Usage
-----

Most of the documentation for Python's [subprocess][python] module applies
equally well to this gem as well. While there are a few places when our
semantics differs from Python's, users of the Python module should largely feel
at home using `subprocess`. We have attempted to [document][rubydoc] all of the
differences, but if we have missed something, please file an issue.

[python]: http://docs.python.org/library/subprocess.html
[rubydoc]: http://rubydoc.info/github/stripe/subprocess

A few examples:

```ruby
require 'subprocess'
```

Check user's animal allegiances:

```ruby
begin
  Subprocess.check_call(['grep', '-q', 'llamas', '~/favorite_animals'])
rescue Subprocess::NonZeroExit => e
  puts e.message
  puts "Why aren't llamas one of your favorite animals?"
end
```

Parse the output of `uptime(1)` to find the system's load:

```ruby
system_load = Subprocess.check_output(['uptime']).split(' ').last(3)
```

Send mail to your friends with `sendmail(1)`:

```ruby
Subprocess.check_call(%W{sendmail -t}, :stdin => Subprocess::PIPE) do |p|
  p.communicate <<-EMAIL
From: alpaca@example.com
To: llama@example.com
Subject: I am so fluffy.

SO FLUFFY!
http://upload.wikimedia.org/wikipedia/commons/3/3e/Unshorn_alpaca_grazing.jpg
  EMAIL
end
```
