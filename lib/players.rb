require 'players/player'
require 'players/queue'
# require 'forwardable'
class Players
  # extend Forwardable
  include Celluloid
  include Celluloid::Internals::Logger

  attr_accessor :players
  # def_delegators :@players, :<<, :+

  def initialize params = {}
    @game_uuid = params[:game_uuid]
    if params[:game_uuid]
      @players = []
      @game_uuid = params[:game_uuid]
      @queue = Center.current.to_supervise as: :"queue_#{@game_uuid}", type: Queue, args: [{game_uuid: @game_uuid}]
      state = Actor[:"state_#{params[:game_uuid]}"]
      state.players.each{|i| add(i) }
    else
      @players = []
    end
  end

  def push_event event, params = {}
    players.each{|p| p.push_event event, params }
  end

  def push_state params = {}
    players.each{|p| p.push_state params }
  end

  def players
    @players.map{|i| Actor[:"player_#{i}"] }
  end

  def add player
    state = Actor[:"state_#{@game_uuid}"]
    pl_id = player.is_a?(String) ? player : player.uuid
    @players << pl_id
    Control.current.add_player(@game_uuid, pl_id)
    # state.async
  end

  def push_start_stage
    game = Actor[:"game_#{@game_uuid}"]
    players.each do |pl|
      push_event(:start_stage, value: game.stage)
    end
  end

  def push_start_step
    game = Actor[:"game_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    players.each do |pl|
      push_event(:start_step, turn_in: queue.ids.index(@uuid), pitcher_name: current_pitcher.uglify_name(game.stage), step: {current: game.step, total: game.total_steps, status: 'pitch'})
    end
  end

  def push_pitch params = {}
    players.each do |pl|
      pl.send_pitch params
    end
  end

  def push_pass
    players.each do |pl|
      pl.send_pass
    end
  end

  def push_vote
    players.each do |pl|
      pl.send_vote
    end
  end


  def current_pitcher
    queue = Actor[:"queue_#{@game_uuid}"]
    Actor[:"player_#{queue.first}"]
  end

  def queue
    Actor[:"queue_#{@game_uuid}"]
  end
end
