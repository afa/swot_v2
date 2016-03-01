require 'rubygems'
require 'bundler'
Bundler.require(:default)
$LOAD_PATH.unshift('./lib') unless $LOAD_PATH.include?('./lib')
$LOAD_PATH.unshift('./models') unless $LOAD_PATH.include?('./models')
SWOT_VERSION = File.open('./VERSION'){|f| f.read }.strip
require 'web'
require 'utils'
require 'celluloid/redis'
require 'redis/connection/celluloid'
MultiJson.load_options = {symbolize_keys: true}
env = ENV.fetch('ENV', 'development').to_sym
@config = MultiJson.load(File.open('./config.json'){|f| f.read })[env]
Ohm.redis = Redic.new(@config[:redis_db])
require 'store'
require 'center'
Celluloid::Actor[:center] = Center.new(@config)
if @config.has_key? :autostart
  msg = @config[:autostart]
  if msg && msg[:start] && msg[:start][:time]
    msg[:start][:time] = Time.now + msg[:start][:time].to_i
  end
  Message::Create.new('/swot/control', msg).process if msg
  # Message::Create.new('/swot/control', {type:"create",game:{name:"aa",description:"",company:"aa",country:"",industry:""},players:[{name:"aa",email:"aa@aa.aa",state:"not_invited",error:false},{name:"bb",email:"bb@bb.bb",state:"not_invited",error:false}],start:{time:Time.now.to_i+90,time_zone:"+03:00"}}).process
  # Message::Create.new('/swot/control', {type:"create",game:{name:"aa",description:"",company:"aa",country:"",industry:""},players:[{name:"aa",email:"aa@aa.aa",state:"not_invited",error:false},{name:"bb",email:"bb@bb.bb",state:"not_invited",error:false},{name:"cc",email:"cc@cc.cc",state:"not_invited",error:false},{name:"dd",email:"dd@dd.dd",state:"not_invited",error:false}],start:{time:Time.now.to_i+300,time_zone:"+03:00"}}).process
  # Message::Create.new('/swot/control', {type:"create",game:{name:"aa",description:"",company:"aa",country:"",industry:""},players:[{name:"aa",email:"aa@aa.aa",state:"not_invited",error:false},{name:"bb",email:"bb@bb.bb",state:"not_invited",error:false},{name:"cc",email:"cc@cc.cc",state:"not_invited",error:false},{name:"dd",email:"dd@dd.dd",state:"not_invited",error:false},{name:"aaa",email:"aaa@aa.aa",state:"not_invited",error:false},{name:"bba",email:"bba@bb.bb",state:"not_invited",error:false},{name:"cca",email:"cca@cc.cc",state:"not_invited",error:false},{name:"dda",email:"dda@dd.dd",state:"not_invited",error:false},{name:"aab",email:"aab@aa.aa",state:"not_invited",error:false},{name:"bbb",email:"bbb@bb.bb",state:"not_invited",error:false},{name:"ccb",email:"ccb@cc.cc",state:"not_invited",error:false},{name:"ddb",email:"ddb@dd.dd",state:"not_invited",error:false}],start:{time:Time.now.to_i+600,time_zone:"+03:00"}}).process
end
Celluloid::Actor[:center].sleep(1) while Celluloid::Actor[:center].alive?
# Celluloid::Actor[:center].run

