require 'rubygems'
require 'bundler'
Bundler.require(:default)
$LOAD_PATH.unshift('./lib') unless $LOAD_PATH.include?('./lib')
$LOAD_PATH.unshift('./models') unless $LOAD_PATH.include?('./models')
require 'web'
require 'utils'
require 'celluloid/redis'
require 'redis/connection/celluloid'
MultiJson.load_options = {symbolize_keys: true}
require 'store'
require 'center'
Celluloid::Actor[:center] = Center.new
Message::Create.new('/swot/control', {type:"create",game:{name:"aa",description:"",company:"aa",country:"",industry:""},players:[{name:"aa",email:"aa@aa.aa",state:"not_invited",error:false}],start:{time:Time.now.to_i+60,time_zone:"+03:00"}}).process
Celluloid::Actor[:center].sleep(1) while Celluloid::Actor[:center].alive?
# Celluloid::Actor[:center].run

