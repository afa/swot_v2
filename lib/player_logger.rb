class PlayerLogger

  include Celluloid
  include Celluloid::IO
  include Celluloid::Notifications
  include Celluloid::Internals::Logger

  attr_accessor :guid, :records, :step, :statement, :replace, :pro_percent, :scores_delta, :votes, :player_name, :stage_title, :missed_pitching

  # field :step, type: Integer
  # field :statement, type: String
  # field :replace, type: String
  # field :pro_percent, type: Integer
  # field :scores_deltas, type: Hash
  # field :votes, type: Hash
  # field :player_name, type: String
  # field :stage_title, type: String
  # field :missed_pitching, type: Boolean, default: false
  def mklog
    replace = statement.to_replace.map do |st_id|
      statement.stage.statements.find(st_id).statement
    end.join('. ')

    log_votes = statement.votes.inject({}){|r, v| r.merge v.player_id.to_s => v.result }

    rec = game.log_records.create step: game.reload.current_stage.step,
      statement: statement.statement,
      stage_title: game.reload.current_stage.name,
      replace: replace,
      pro_percent: (statement.result*100).round,
      player_name: begin game.players_queue.current_pitcher.name_by_stage; rescue PlayersQueue::ErrorQueueEmpty; '' end,
      scores_deltas: game.players_stats.inject({}){|r, (k, v)| r.merge(k => v[:delta])},
      votes: log_votes

  end

  def players_stats
    players.inject({}){|r, v| r.merge v.score.to_player_stat }
  end
  class Score
    include Mongoid::Document
    embedded_in :player

    field :pitcher, type: BigDecimal, default: 0
    field :pitcher_before_ranging, type: BigDecimal, default: 0
    field :catcher, type: BigDecimal, default: 0
    field :rank,    type: BigDecimal, default: 1
    field :delta,   type: BigDecimal, default: 0
    field :catcher_first_half, type: BigDecimal, default: 0

    def count_catcher! val
      reload
      self.delta = val
      self.catcher += self.delta
      save
    end

    def to_player_stat
      { player.id.to_s => { pitcher: pitcher, catcher: catcher, delta: delta } }
    end

    def update_rank key
      reload
      settings = player.game.settings
      multiplier = settings.send(:"pitcher_rank_multiplier_#{key}")
      new_rank  = rank
      new_rank  *= multiplier
      update_attribute :rank, [new_rank, settings.send(:pitcher_minimum_rank)].max
    end
  end
end
