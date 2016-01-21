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
Celluloid::Actor[:center] = Center.new
Celluloid::Actor[:center].sleep(1) while Celluloid::Actor[:center].alive?
# Celluloid::Actor[:center].run

