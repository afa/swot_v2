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
    @queue = Queue.new
    if params[:game_uuid]
      @game_uuid = params[:game_uuid]
      state = Actor[:"state_#{params[:game_uuid]}"]
      state.players.each{|i| add(i) }
    else
      @players = []
    end
    @queue = Queue.new(game_uuid: @game_uuid)
  end

  def push_event event, params = {}
    players.each{|p| p.push_event event, params }
  end

  def push_state params = {}
    players.each{|p| p.push_state params }
  end

  def players
    @players.map{|i| Actor["player_#{i}"] }
  end

  def add player
    state = Actor[:"state_#{@game_uuid}"]
    @players << player.is_a?(String) ? player : player.uuid
    # state.async
  end

  def push_start_step
    game = Actor[:"game_#{@game_uuid}"]
    players.each do |pl|
      push_event(:start_step, turn_in: @queue.ids.index(@uuid), pitcher_name: current_pitcher.uglify_name(game.stage), step: {current: game.step, total: game.total_steps, status: 'pitch'})
    end
  end

  def current_pitcher
    @queue.first
  end

end
