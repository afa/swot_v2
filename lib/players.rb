require 'hashing'
require 'players/player'
require 'players/queue'
# require 'forwardable'
class Players
  include Hashing
  # extend Forwardable
  include Celluloid
  include Celluloid::IO
  include Celluloid::Notifications
  include Celluloid::Internals::Logger

  attr :players
  # attr_accessor :players
  # def_delegators :@players, :<<, :+

  def initialize params = {}
    @players = []
    if params[:game_uuid]
      @game_uuid = params[:game_uuid]
      async.mk_queue
      async.mk_players

      # state = Actor[:"state_#{params[:game_uuid]}"]
      # state.players.each{|i| add(i) }
    end
    subscribe :save_game_data, :save_game_data
  end

  def mk_queue
    Center.current.to_supervise as: :"queue_#{@game_uuid}", type: Queue, args: [{game_uuid: @game_uuid}]
  end

  def mk_players
    splayers = Store::Player.find(game_uuid: @game_uuid).to_a.sort_by(&:order)
    splayers.each do |pl|
      p_id = pl.uuid
      Center.current.to_supervise(as: :"player_#{p_id}", type: Player, args: [uuid: p_id])
      async.add p_id
    end
  end

  def save_game_data topic, game_id
    return unless game_id == @game_uuid
    sync_players
    publish :game_data_saved, @game_uuid, :players
  end

  def sync_players
    info 'syncing players'
  end

  def push_event event, params = {}
    players.each{|p| p.send_event event, params }
  end

  def push_state params = {}
    players.each{|p| p.send_state params }
  end

  def push_messages params = {}
    players.each{|p| p.send_messages params }
  end

  def players
    @players.map{|i| Actor[:"player_#{i}"] }.select{|p| p && p.alive? }
  end

  def player_ids
    @players
  end

  def add player
    queue = Actor[:"queue_#{@game_uuid}"]
    ord = players.inject(0){|r, p| r >= p.order.to_i ? r : p.order.to_i }
    pl_id = player.is_a?(String) ? player : player.uuid
    Actor[:"player_#{pl_id}"].order = ord + 1
    state = Actor[:"state_#{@game_uuid}"]
    info "add pl_id #{pl_id.inspect}"
    @players << pl_id
    queue.add pl_id
    Control.current.add_player(@game_uuid, pl_id)
    # state.async
  end

  def copy_half
    players.each do |pl|
      pl.async.copy_half
    end
  end

  def copy_before
    players.each do |pl|
      pl.async.copy_before
    end
  end

  def push_start_stage
    game = Actor[:"game_#{@game_uuid}"]
    players.each do |pl|
      info "send start stage to #{pl.uuid}"
      pl.send_start_stage
    end
  end

  def push_start_step
    game = Actor[:"game_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    players.each do |pl|
      info "send start step to #{pl.uuid}"
      pl.catcher_apply_delta(0.0)
      pl.send_start_step
      pl.send_state
      # push_event(:start_step, turn_in: queue.ids.index(@uuid), pitcher_name: current_pitcher.uglify_name(game.stage), step: {current: game.step, total: game.total_steps, status: 'pitch'})
    end
  end

  def push_end_step params = {}
    game = Actor[:"game_#{@game_uuid}"]
    players.each do |pl|
      info "send end step to #{pl.uuid}"
      pl.async.send_end_step params
    end
  end

  def push_end_stage
    # game = Actor[:"game_#{@game_uuid}"]
    info "send end stage for #{players.map(&:uuid).inspect}"
    players.each do |pl|
      info "send end stage to #{pl.uuid}"
      pl.async.send_end_stage
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

  def push_quorum
    players.each do |pl|
      pl.send_quorum
    end
  end

  def push_vote
    players.each do |pl|
      pl.send_vote
    end
  end

  # def push_player_log params = {}
  #   stat_id = params[:statement]
  #   statements = Actor[:"statements_#{@game_uuid}"]
  #   statement = statements.find(stat_id)
  #   return unless statement
  #   @players.each do |pl|
  #     p = Actor[:"player_#{pl}"]
  #     #TODO voting at moment
  #     publish :player_log_push, p.uuid, statement.uuid if p && p.alive? && p.online
  #   end
  # end

  def push_terminated
    players.each do |pl|
      pl.send_terminated
    end
  end

  def push_game_results
    players.each do |pl|
      pl.send_game_results
    end
  end

  def enough_players
    state = Actor[:"state_#{@game_uuid}"]
    cfg = state.setting
    online.size >= cfg[:min_players].to_i
  end

  def online
    players.select(&:online)
  end

  def was_online
    players.select(&:was_online)
  end

  def check_min_players
    state = Actor[:"state_#{@game_uuid}"]
    if state.state == :started && %w(s sw w wo o ot t).include?(state.stage.to_s)
      if enough_players
        Timings::Terminate.instance(@game_uuid).cancel if Timings::Terminate.instance(@game_uuid).next_time
      else
        Timings::Terminate.instance(@game_uuid).start unless Timings::Terminate.instance(@game_uuid).next_time
      end
    end
  end

  def find pl_id
    if @players.include? pl_id
      Actor[:"player_#{pl_id}"]
    else 
      nil
    end
  end

  def build_queue
    queue.rebuild_tail
    queue.fill_current
  end

  def current_pitcher
    queue = Actor[:"queue_#{@game_uuid}"]
    Actor[:"player_#{queue.first}"]
  end

  def queue
    Actor[:"queue_#{@game_uuid}"]
  end
end
