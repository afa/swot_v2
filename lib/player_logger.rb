class PlayerLogRecord < OpenStruct
  def as_json
    marshal_dump
  end
end

class PlayerLogger
  include Celluloid
  include Celluloid::IO
  include Celluloid::Notifications
  include Celluloid::Internals::Logger

  attr_accessor :guid, :records
  # :step, :statement, :replace, :pro_percent, :scores_delta, :votes, :player_name, :stage_title, :missed_pitching

  def initialize(params = {})
    @uuid = params[:player_uuid]
    sleep 1
    player = Actor[:"player_#{@uuid}"]
    @guid = player.game_uuid
    @records = []
    subscribe :player_log_push, :push
    # TODO: restore on fixed sync player log
    # subscribe :save_game_data, :save_game_data
    subscribe :pitch_pass, :mklog_pass
    subscribe :pitch_timeout, :mklog_timeout
  end

  def save_game_data(_topic, game_id)
    return unless game_id == @guid
    sync_player_log
    publish :game_data_saved, @guid, :player_log
  end

  def sync_player_log
    store = Store::PlayerLog.find(game_uuid: @guid).sort(by: :created_at).to_a
    rcrds = @records.select { |res| res.redis_id.nil? || !store.any? { |st| st.id == res.redis_id } }
    rcrds.each do |rc|
      r = Store::PlayerLog.create game_uuid: @guid, data: rc, created_at: rc.created_at
      rc.redis_id = r.id
    end
  end

  def push(_topic, game_id, statement_id)
    return unless game_id == @guid
    mklog(statement_id)
  end

  def mklog_pass(_topic, guid, pl_id)
    return unless guid == @guid
    state = Actor[:"state_#{@guid}"]
    players = Actor[:"players_#{@guid}"]
    pitcher = players.find(pl_id)
    rec = PlayerLogRecord.new(
      step: state.step,
      statement: nil,
      stage_title: State::STAGES[state.stage][:name],
      replace: [],
      pro_percent: nil,
      player_name: pitcher.uglify_name(state.stage), # chng to player(pl_id)
      scores_deltas: nil,
      player_id: @uuid,
      votes: nil,
      missed_pitching: true,
      passed: true
    )
    @records << rec
    player = Actor[:"player_#{@uuid}"]
    return unless player && player.alive? && player.online
    player.async.publish_msg type: 'log', values: @records.last(12).reverse.map(&:as_json)
  end

  def mklog_timeout(_topic, guid, pl_id)
    return unless guid == @guid
    state = Actor[:"state_#{@guid}"]
    players = Actor[:"players_#{@guid}"]
    pitcher = players.find(pl_id)
    rec = PlayerLogRecord.new(
      step: state.step,
      statement: nil,
      stage_title: State::STAGES[state.stage][:name],
      replace: [],
      pro_percent: nil,
      player_name: pitcher.uglify_name(state.stage), # chng to player(pl_id)
      scores_deltas: nil,
      player_id: @uuid,
      votes: nil,
      missed_pitching: true,
      passed: false
    )
    @records << rec
    player = Actor[:"player_#{@uuid}"]
    return unless player && player.alive? && player.online
    player.async.publish_msg type: 'log', values: @records.last(12).reverse.map(&:as_json)
  end

  def mklog(statement_id)
    statements = Actor[:"statements_#{@guid}"]
    return unless statements && statements.alive?
    statement = statements.find(statement_id)
    return unless statement
    state = Actor[:"state_#{@guid}"]
    players = Actor[:"players_#{@guid}"]
    pitcher = players.find(statement.author)

    replace = statement.replaces.map do |st_id|
      statements.find(st_id).try(:value)
    end.compact.join('. ')

    log_votes = statement.votes.inject({}) { |rez, vl| rez.merge vl.player.to_s => statement.format_value(vl.result) }

    pc = per = (statement.result * 100)
    per = 100.0 - per if statement.status != 'accepted'
    rec = PlayerLogRecord.new(
      step: state.step,
      statement: statement.value,
      stage_title: State::STAGES[state.stage][:name],
      replace: replace,
      pro_percent: format('%.1f', pc),
      percent: !statement.quorum? ? 'no quorum' : format('%.1f', per),
      player_name: pitcher.uglify_name(state.stage),
      scores_deltas: players.players.inject({}) { |rez, pl| rez.merge(pl.uuid => format('%+.1f', pl.delta)) },
      player_id: @uuid,
      votes: log_votes,
      missed_pitching: false,
      passed: false
    )
    @records << rec
    player = Actor[:"player_#{@uuid}"]
    return unless player && player.alive? && player.online
    player.async.publish_msg type: 'log', values: @records.last(12).reverse.map(&:as_json)
  end
end
