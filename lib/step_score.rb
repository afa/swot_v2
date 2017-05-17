class StepScore
  class Coeff
    attr_reader :rank, :delta, :mult

    def initialize(guid)
      @guid = guid
      @rank = 1.0
      @pitcher = 0.0
      @catcher = 0.0
    end

    def set_statement
    end

    def calc_pitcher
      # (statements)
    end

    def calc_catcher
    end

    def calc_rank
      # TODO: from pl/pl count_pitcher_score
      # TODO:
    end
  end

  include Celluloid::Internals::Logger

  attr_reader :guid, :players, :statement, :replaced

  def initialize(guid, statement)
    @guid = guid
    players = Celluloid::Actor[:"players_#{guid}"]
    uids = players.player_ids
    @players = uids.inject({}) do |res, uid|
      res[uid] = Coeff.new(guid)
      res
    end
    @statement = false
  end

  def apply_statement(uid)
    @statement = uid
  end
end
