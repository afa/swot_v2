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

  def initialize(params = {})
    @players = []
    guid = params[:game_uuid]
    if guid
      @game_uuid = guid
      queue_wait = future.mk_queue
      async.mk_players if queue_wait.value == :ok
    end
    subscribe :save_game_data, :save_game_data
  end

  def mk_queue
    Center.current.to_supervise as: :"queue_#{@game_uuid}", type: Queue, args: [{ game_uuid: @game_uuid }]
    :ok
  end

  def mk_players
    splayers = Store::Player.find(game_uuid: @game_uuid).to_a.sort_by(&:order)
    splayers.each do |pl|
      p_id = pl.uuid
      Center.current.to_supervise(as: :"player_#{p_id}", type: Player, args: [uuid: p_id])
      async.add p_id
    end
  end

  def save_game_data(_topic, game_id)
    return unless game_id == @game_uuid
    sync_players
    publish :game_data_saved, @game_uuid, :players
  end

  def sync_players
    info 'syncing players'
  end

  def push_event(event, params = {})
    players.each { |pl| pl.send_event event, params }
  end

  def push_state(params = {})
    players.each { |pl| pl.send_state params }
  end

  def push_messages(params = {})
    players.each { |pl| pl.send_messages params }
  end

  def players
    @players.map { |id| Actor[:"player_#{id}"] }.select { |pl| pl && pl.alive? }
  end

  def player_ids
    @players
  end

  def add(player)
    ord = players.map { |pl| pl.order.to_i }.inject(0) { |rez, pl| rez >= pl ? rez : pl }
    pl_id = player.is_a?(String) ? player : player.uuid
    Actor[:"player_#{pl_id}"].order = ord + 1
    @players << pl_id
    queue.add pl_id
    Control.current.add_player(@game_uuid, pl_id)
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
    players.each(&:send_start_stage)
  end

  def push_start_step
    players.each do |pl|
      pl.catcher_apply_delta(0.0)
      pl.send_start_step
      pl.send_state
    end
  end

  def push_end_step(params = {})
    players.each do |pl|
      pl.async.send_end_step params
    end
  end

  def push_end_stage
    players.each do |pl|
      pl.async.send_end_stage
    end
  end

  def push_pitch(params = {})
    players.each do |pl|
      pl.send_pitch params
    end
  end

  def push_pass
    players.each(&:send_pass)
  end

  def push_quorum
    players.each(&:send_quorum)
  end

  def push_vote
    players.each(&:send_vote)
  end

  def push_terminated
    players.each(&:send_terminated)
  end

  def push_game_results
    players.each(&:send_game_results)
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
    return unless state.state == :started && %w(s sw w wo o ot t).include?(state.stage.to_s)
    timer = Timings::Terminate.instance(@game_uuid)
    if enough_players && timer.next_time
      timer.cancel
    else
      timer.start
    end
  end

  def find(pl_id)
    return Actor[:"player_#{pl_id}"] if @players.include? pl_id
    nil
  end

  def build_queue
    queue.rebuild_tail
    queue.fill_current
  end

  def current_pitcher
    Actor[:"player_#{queue.first}"]
  end

  def queue
    Actor[:"queue_#{@game_uuid}"]
  end
end
