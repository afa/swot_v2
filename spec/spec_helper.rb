require "rubygems"
require "bundler/setup"
Bundler.require(:default, :test)
$LOAD_PATH.unshift('./lib') unless $LOAD_PATH.include?('./lib')
$LOAD_PATH.unshift('./models') unless $LOAD_PATH.include?('./models')
MultiJson.load_options = {symbolize_keys: true}
env = ENV.fetch('ENV', 'development').to_sym
@config = MultiJson.load(File.open('./config.json'){|f| f.read })[env]
Ohm.redis = Redic.new(@config[:redis_db])

require 'celluloid/current'
require 'celluloid/io'
require "celluloid/test"
# require "game"
#

# config.around(:each) do |ex|
#   Celluloid.boot
#   ex.run
#   Celluloid.shutdown
# end


RSpec.configure do |config|
  # config.expose_dsl_globally = false

  config.around(:each) do |ex|
    Celluloid.boot
    ex.run
    Celluloid.shutdown
  end

  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  config.order = :random
end
