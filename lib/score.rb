# score игроков
# :reek:TooManyInstanceVariables
class Score
  attr_reader :pitcher_score, :pitcher_rank, :catcher_score, :delta, :pitcher_score_first_half, :uuid, :guid
  attr_reader :catcher_score_first_half, :pitcher_score_before_ranging, :catcher_score_before_ranging
  attr_reader :player

  def initialize(player)
    @player = player.uuid
    @guid = player.game_uuid
    @pitcher_rank = 1.0
    @catcher_score = 0.0
    @delta = 0.0
  end

  def count_pitcher_score(typ)
    state = Celluloid::Actor[:"state_#{guid}"]
    cfg = state.setting
    mult = cfg[:"pitcher_rank_multiplier_#{typ}"].to_f
    rank = pitcher_rank
    rank *= mult if mult > 0.0
    @pitcher_rank = [rank, cfg[:pitcher_minimum_rank].to_f].max
    @pitcher_score = count_single_score(self)
  end

  def count_single_score(player)
    stats = Celluloid::Actor[:"statements_#{guid}"]
    all_contributions = stats.statements.select { |st| st.status == 'accepted' }.map { |stat| stat.score.contribution }
    all_contributions.inject(0.0) { |res, hsh| res + hsh[player.uuid.to_s].to_f }
  end

  def count_pitchers_score
    stats = Celluloid::Actor[:"statements_#{guid}"]
    all_contributions = stats.statements
                             .select { |stat| stat.status == 'accepted' }
                             .map { |stat| stat.score.contribution }

    players = Celluloid::Actor[:"players_#{@guid}"]
    players.players.each do |player|
      # player.score.pitcher_before_ranging = player.score.pitcher if opts[:save_before]
      player.scores.pitcher_score = all_contributions.inject(0.0) {|r, x| r + x[player.uuid.to_s].to_f }
    end
  end

  def copy_half
    self.catcher_score_first_half = catcher_score
    self.pitcher_score_first_half = pitcher_score
  end

  def copy_before
    self.catcher_score_before_ranging = catcher_score
    self.pitcher_score_before_ranging = pitcher_score
  end
end
