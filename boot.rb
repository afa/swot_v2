require 'rubygems'
require 'bundler'
Bundler.require(:default)
$LOAD_PATH.unshift('./lib') unless $LOAD_PATH.include?('./lib')
$LOAD_PATH.unshift('./models') unless $LOAD_PATH.include?('./models')
require 'celluloid/redis'
require 'redis/connection/celluloid'
MultiJson.load_options = {symbolize_keys: true}
require 'store'
require 'center'
Center.run

