class PlayerLogRecord < OpenStruct
  # field :step, type: Integer
  # field :statement, type: String
  # field :replace, type: String
  # field :pro_percent, type: Integer
  # field :scores_deltas, type: Hash
  # field :votes, type: Hash
  # field :player_name, type: String
  # field :stage_title, type: String
  # field :missed_pitching, type: Boolean, default: false
end

class PlayerLogger

  include Celluloid
  include Celluloid::IO
  include Celluloid::Notifications
  include Celluloid::Internals::Logger

  attr_accessor :guid, :records
  # :step, :statement, :replace, :pro_percent, :scores_delta, :votes, :player_name, :stage_title, :missed_pitching

  def initialize params = {}
    @uuid = params[:player_uuid]
    player = Actor[:"plyer_#{@uuid}"]
    @guid = player.game_uuid
    @records = []
    subscribe :player_log_push, :push
  end

  def push topic, player_id, statement_id
    return unless player_id == @uuid
    mklog(statement_id)

  end

  def mklog statement_id
    statements = Actor[:"statements_#{@guid}"]
    return unless statements && statements.alive?
    statement = statements.find(statement_id)
    return unless statement
    state = Actor[:"state_#{@guid}"]
    queue = Actor[:"queue_#{@guid}"]
    replace = statement.replaces.map do |st_id|
      statements.find(st_id).try(:statement)
    end.compact.join('. ')

    log_votes = statement.votes.inject({}){|r, v| r.merge v.player.to_s => v.result }

    rec = PlayerLogRecord.new step: state.step,
      statement: statement.value,
      stage_title: State::STAGES[:state.stage].name,
      replace: replace,
      pro_percent: (statement.result*100).round,
      player_name: queue.pitcher.uglify_name(state.stage),
      scores_deltas: players.players.inject({}){|r, (k, v)| r.merge(k => v.delta)},
      votes: log_votes
    @records << rec

  end

  # def players_stats
  #   players.inject({}){|r, v| r.merge v.score.to_player_stat }
  # end
  # class Score
  #   include Mongoid::Document
  #   embedded_in :player

  #   field :pitcher, type: BigDecimal, default: 0
  #   field :pitcher_before_ranging, type: BigDecimal, default: 0
  #   field :catcher, type: BigDecimal, default: 0
  #   field :rank,    type: BigDecimal, default: 1
  #   field :delta,   type: BigDecimal, default: 0
  #   field :catcher_first_half, type: BigDecimal, default: 0

  #   def count_catcher! val
  #     reload
  #     self.delta = val
  #     self.catcher += self.delta
  #     save
  #   end

  #   def to_player_stat
  #     { player.id.to_s => { pitcher: pitcher, catcher: catcher, delta: delta } }
  #   end

  #   def update_rank key
  #     reload
  #     settings = player.game.settings
  #     multiplier = settings.send(:"pitcher_rank_multiplier_#{key}")
  #     new_rank  = rank
  #     new_rank  *= multiplier
  #     update_attribute :rank, [new_rank, settings.send(:pitcher_minimum_rank)].max
  #   end
  # end
end
