# subprocess ![Ruby](https://github.com/stripe/subprocess/workflows/Ruby/badge.svg) [![Yard Docs](http://img.shields.io/badge/yard-docs-blue.svg)](http://rubydoc.info/github/stripe/subprocess/subprocess)

![Jacques Cousteau Submarine](http://i.imgur.com/lmej24F.jpg)

A solid subprocess library for ruby, inspired by python's.

Installation
------------

The recommended way of installing `subprocess` is through Rubygems:

    $ gem install subprocess

You can also build `subprocess` from source by running:

    $ gem build subprocess.gemspec

Usage
-----

Full documentation is on [RubyDoc][rubydoc]. A few examples:

```ruby
require 'subprocess'
```

Check user's animal allegiances:

```ruby
begin
  subprocess.check_call(['grep', '-q', 'llamas', '~/favorite_animals'])
rescue subprocess::NonZeroExit => e
  puts e.message
  puts "Why aren't llamas one of your favorite animals?"
end
```

Parse the output of `uptime(1)` to find the system's load:

```ruby
system_load = subprocess.check_output(['uptime']).split(' ').last(3)
```

Send mail to your friends with `sendmail(1)`:

```ruby
subprocess.check_call(%W{sendmail -t}, :stdin => subprocess::PIPE) do |p|
  p.communicate <<-EMAIL
From: alpaca@example.com
To: llama@example.com
Subject: I am so fluffy.

SO FLUFFY!
http://upload.wikimedia.org/wikipedia/commons/3/3e/Unshorn_alpaca_grazing.jpg
  EMAIL
end
```

Most of the documentation for Python's [subprocess][python] module applies
equally well to this gem as well. While there are a few places when our
semantics differs from Python's, users of the Python module should largely feel
at home using `subprocess`. We have attempted to [document][rubydoc] all of the
differences, but if we have missed something, please file an issue.

[python]: http://docs.python.org/library/subprocess.html
[rubydoc]: http://rubydoc.info/github/stripe/subprocess/subprocess

Maintenance
-----------

Steps to release a new version:

```bash
# Work directly on master
git checkout master

# -- edit version in lib/subprocess/version.rb --

# Update RBI files
bundle exec rake sord

# Subsequent commands reference the version
VERSION=1.5.5
git commit -am "Bump version to $VERSION"
git tag "v$VERSION"
git push origin master --tags
bundle exec rake publish
```

If you get errors, ask someone to add you to `bindings/rubygems-api-key` in
Vault or ask someone who already has permissions. See <http://go/password-vault>

Acknowledgements
----------------

Many thanks to [Bram Swenson][bram], the author of the old [subprocess][old]
gem, for graciously letting us use the name.

[bram]: https://github.com/bramswenson
[old]: https://github.com/bramswenson/subprocess
