require 'sinatra/base'
require 'timers'
class Game < Sinatra::Base
  include Celluloid
  timers = Timers::Group.new
  configure do
    enable :logging 
  end
  get '/' do
    'ok'
  end
  every_five_seconds = timers.every(5) { puts "Another 5 seconds" }

  # loop { timers.wait }
end
