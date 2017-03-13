class StatementScore
  attr_reader :uuid, :guid, :contribution_before_ranking, :contribution
  def initialize(statement)
    @uuid = statement.uuid
    @guid = statement.game_uuid
    @contribution = {}
    @contribution_before_ranking = {}
  end

  def statement
    Celluloid::Actor[:"statement_#{uuid}"]
  end

  def count_pitcher_score
    players = Celluloid::Actor[:"players_#{guid}"]
    players.players.each do |player|
      player.scores.count_pitcher_score(statement.status)
    end
    # player = Celluloid::Actor[:"player_#{@author}"]
    # typ = @status
    # player.count_pitcher_score(typ)
  end

  def copy_before
    @contribution_before_ranking = contribution.dup
  end

  def score_for(player_id)
    contribution[player_id]
  end

  def format_value(str)
    return 'pro' if str == 'accepted'
    return 'contra' if str == 'declined'
    raise ArgumentError, "expect 'accepted' or 'declined', got: #{str}"
  end

  # TODO: what options?
  def conclusion(options={})
    return 'no_quorum' if @votes.empty? # minimal quorum size TODO
    # grouped_hash[:key] - nil if no objects meet condition
    # grouped_hash = me.votes.group_by { |vote| vote.result == 'accepted'}
    # pro = grouped_hash[true] || []
    # contra = grouped_hash[false] || []
    # return 'accepted' if pro && !contra
    # return 'declined' if contra && !pro
    # @result = pro.size.to_f / (contra + pro).size.to_f + (@status == 'no_quorum' ? @non_voted : 0.0)
    calc_result
    statement.result >= 0.5 ? 'accepted' : 'declined'
  end

  def calc_result
    # players = Celluloid::Actor[:"players_#{@game_uuid}"]
    # cnt = players.online.size
    me = statement
    return 'no_quorum' if me.votes.empty?
    return 'no_quorum' unless me.quorum?
    probab = me.votes.map(&:result).select { |vote| vote == 'accepted' }.size
    return 'declined' if probab == 0
    return 'accepted' if probab == voted_count
    probab.to_f / @votes.size.to_f >= 0.5 ? 'accepted' : 'declined'
  end

  def count_catchers_score(_declined = false)
    state = Celluloid::Actor[:"state_#{@game_uuid}"]
    me = statement
    cfg = state.setting
    non_voted_players = (
      Celluloid::Actor[:"players_#{guid}"].player_ids -
      [me.author] -
      me.votes.map(&:player)
    ).map { |id| Celluloid::Actor[:"player_#{id}"] }.select { |plyr| plyr.alive? && plyr.online }
    @non_voted = non_voted_players.size
    non_voted_players.each do |plyr|
      plyr.async.catcher_apply_delta(0.0)
    end
    conclusion
    # apply voted contra when no quorum

    catcher_zone = [0.5, cfg[:catcher_high_border].to_f].select { |item| me.result >= item }.size + 2
    catcher_zone = 1 if me.result <= cfg[:catcher_low_border].to_f
    # уродство. меньше или = 25% -- дельта -1.5
    # catcher_zone =  if    @result < cfg[:catcher_low_border].to_f  ; 1
    #                 elsif @result <  0.5                      ; 2
    #                 elsif @result < cfg[:catcher_high_border].to_f ; 3
    #                 else                                      ; 4
    #                 end
    me.votes.each do |vote|
      zone = "catcher_#{format_value(vote.result)}_zone_#{catcher_zone}_score"
      delta = cfg[zone.to_sym].to_f
      # delta = -(delta.abs) if [3,4].include?(catcher_zone) && @status == 'no_quorum'
      # if @status == 'no_quorum' && format_value(vote.result) == 'contra'
      #   delta = 1.5
      delta = 0.0 if me.status == 'no_quorum'
      # FIXME:  ищем плееров с ид в текущей игре.
      player = Celluloid::Actor[:"player_#{vote.player}"]
      player.async.catcher_apply_delta(delta)
    end
  end

  def calc_contribution_share(share, cnt)
    state = Celluloid::Actor[:"state_#{guid}"]
    contribution_hash = { statement.author => share }
    other_share = (1.0 - share) / cnt
    statements = Celluloid::Actor[:"statements_#{guid}"]
    statement.replaces.map { |uid| statements.find(uid) }
             .compact.select { |stat| stat.stage == state.to_swot(state.stage) }
             .each do |repl|
      repl.score.contribution.keys.each do |pl|
        contribution_hash[pl] = contribution_hash.fetch(pl, 0.0) +
                                (other_share * repl.score.contribution.delete(pl).to_f)
      end
    end
    statement.contribution = contribution_hash
  end

  def calc_contribution_no(share)
    statement.contribution = { statement.author => share }
  end

  def calc_contribution
    state = Celluloid::Actor[:"state_#{guid}"]
    cfg = state.setting
    replaces_amount = statement.replaces.size
    raise ArgumentError, 'to much replaces (> 2)' unless (0..2).cover?(replaces_amount)
    share = cfg[:"pitcher_#{%w(no single double)[replaces_amount]}_replace_score"].to_f
    case replaces_amount
    when 0 then calc_contribution_no(share)
    when 1..2 then calc_contribution_share(share, replaces_amount)
    end
  end

  def set_contribution
    return calc_contribution
    # state = Celluloid::Actor[:"state_#{@game_uuid}"]
    # cfg = state.setting
    # replaces_amount = @replaces.size
    # raise ArgumentError, 'to much replaces (> 2)' unless (0..2).include?(replaces_amount)
    # share = cfg[:"pitcher_#{%w(no single double)[replaces_amount]}_replace_score"].to_f
    # max_share = cfg[:"pitcher_no_replace_score"].to_f
    # # share = case replaces_amount
    # #         when 0 then cfg[:pitcher_no_replace_score]
    # #         when 1 then cfg[:pitcher_single_replace_score]
    # #         when 2 then cfg[:pitcher_double_replace_score]
    # #         end.to_f
    # contributors_hash = { @author => share }
    # unless replaces_amount.zero?
    #   statements = Celluloid::Actor[:"statements_#{@game_uuid}"]
    #   others_share_part = (1 - share).to_f / replaces_amount
    #   # FIXME: найти утвержения с текущим стеджом в текущей игре с ид в массиве @replaces
    #   replaced = @replaces.map { |replace| statements.find(replace) }.compact.select do |stat|
    #     stat.stage == state.to_swot(state.stage)
    #   end

    #   replaced.each do |statement|
    #     statement.contribution.each do |player, share|
    #       player_share = contributors_hash.fetch player, 0.0
    #       player_share -= max_share if player_share > 0.0 # TODO!!!!!!!!!!!
    #       contributors_hash[player] = player_share + share * others_share_part
    #     end
    #   end
    # end
    # @contribution = contributors_hash
  end

  def player_contribution
    players = Celluloid::Actor[:"players_#{guid}"]
    contribution.inject({}) { |res, (key, val)| res.merge(players.find(key).name => val) }
  end

  def contribution_for(pl_id)
    contribution.fetch pl_id, 0.0
  end
end
