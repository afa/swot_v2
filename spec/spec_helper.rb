require "rubygems"
require "bundler/setup"

require 'celluloid/current'
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
