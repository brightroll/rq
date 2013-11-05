# unixrack

A ruby RACK webserver only for unix using the old unix style.
We developed and used it in production at Brightroll.com. 
We recommend it for any small rack, sinatra, etc app that needs to have
a high uptime. It is great for production use as well as development.

## License

see LICENSE.txt (basically MIT license)


## Installation

Add this line to your application's Gemfile:

    gem 'unixrack'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install unixrack

## Sample sinatra bring up

put instructions here

    $ gem install sinatra
    $ gem build unixrack.gemspec
    $ gem install unirack*gem

    #!/usr/bin/ruby

    require 'rubygems'
    require 'sinatra/base'
    require 'unixrack'

    class MyApp < Sinatra::Base
      get '/' do
        "Hello"
      end
    end

    Rack::Handler::UnixRack.run(MyApp.new)

## Usage

Here is an example command to run the standard Rack lobster web app. 
You can get the sample in the samples directory from the github repo
at: https://github.com/drudru/unixrack. Copy lobster.ru into your current dir
then run:

    $ RACK_ENV=stage rackup --port 4004 -s unixrack -r unixrack lobster.ru 

To run your own application, just create your own rackup (.ru) file with your
own Rack middleware.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
