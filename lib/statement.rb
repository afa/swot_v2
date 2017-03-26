class Statement
  include Celluloid::Internals::Logger

  attr_reader   :votable
  attr_accessor :value,
                :author,
                :replaces,
                :replaced,
                :uuid,
                :position,
                :game_uuid,
                :stage,
                :step,
                :votes,
                :visible,
                :importances,
                :importance_score,
                :importance_score_raw,
                :status,
                :result,
                :contribution_before_ranking,
                :contribution,
                :non_voted
                # :auto

  def initialize params = {}
    @value = params[:value]
    @author = params[:author]
    @replaces = params[:replaces] || []
    @uuid = params[:uuid]
    @position = params[:position] if params[:position]
    @game_uuid = params[:game_uuid]
    @stage = params[:stage]
    @step = params[:step]
    @replaced = false
    # {player: 'id', share: 'float'}
    @contribution = {}
    @contribution_before_ranking = {}
    # [{ player: 'id', result: 'accepted | declined' }, ...]
    @votes = []
    @result = 0.0
    @importances = []
    @importance_score = 0.0
    @status = false
    @visible = false
    @non_voted = 0
    @votable = []
    update_quorum
  end

  def update_quorum
    players = Celluloid::Actor[:"players_#{@game_uuid}"]
    ids = players.players.select { |pl| pl&.online }.map(&:uuid).uniq.sort - [@author]
    @votable |= ids
  end

  def to_store
    {author: @author, game_uuid: @game_uuid, uuid: @uuid, stage: @stage, step: @step, value: @value, votes: @votes.map(&:as_json), status: @status, result: @result, importances: @importances, importance_score: @importance_score, importance_score_raw: @importance_score_raw, contribution: @contribution, contribution_before_ranking: @contribution_before_ranking, visible: @visible }
  end

  def copy_before
    @contribution_before_ranking = @contribution.dup
  end

  def update_importance_score
    if @importances.nil? || @importances.empty?
      @importance_score_raw = 1
      return
    end
    @importance_score_raw = @importances.inject(0.0){|r, i| r + score_value(i) } / (@importances.map{|i| i[:player] }.compact.uniq.size)
    @importance_score_raw = 1 if @importance_score_raw == 0

    # apply importance multiplier to contributors share
    # self.contributions_before_ranking.each do |x|
    #   self.contributions_after_ranking.build player: x.player, share: x.share * self.importance_score_raw
    # end
  end

  def score_key hsh
    :"ranging_importance_#{hsh[:value].to_i - 1}_score"
  end

  def score_value hsh
    setting = Celluloid::Actor[:"state_#{@game_uuid}"].setting
    setting[score_key(hsh)].to_f
  end

  def replaced_by! uuid
    if uuid.is_a? Statement
      self.replaced = uuid.uuid
    else
      self.replaced = uuid
    end
  end

  def as_json player_id = nil
    # author = Celluloid::Actor[:"player_#{@author}"]
    # player = Celluloid::Actor[:"player_#{player_id}"]
    score = score_for(player_id)
    { index: @position, body: @value, score: score, player_id: player_id, author: @author}
  end

  def vote params = {}
    return if @votes.detect{|v| v.player == params[:player] }
    update_quorum
    @votes << Vote.new(player: params[:player], result: params[:result], active: true)
  end

  def voted_count
    @votes.map(&:player).uniq.size
  end

  def score_for(player_id)
    @contribution[player_id]
  end

  def quorum?
    # кворум постоянно пересчитывается (на момент начала голосования ака создания сообщения и с каждым голосом)
    (voted_count.to_i * 2) >= @votable.size
    #TODO ??
  end

  def calc_result
    # players = Celluloid::Actor[:"players_#{@game_uuid}"]
    # cnt = players.online.size
    return 'no_quorum' if @votes.empty?
    return 'no_quorum' unless quorum?
    p = @votes.map(&:result).select{|v| v == 'accepted' }.size
    return 'no_quorum' unless quorum?
    return 'declined' if p ==0
    return 'accepted' if p == voted_count
    p.to_f / @votes.size.to_f >= 0.5 ? 'accepted' : 'declined'
  end

  def accept!
    @status = 'accepted'
  end

  def decline!
    @status = 'declined'
  end

  def calc_contribution_share(share, cnt)
    state = Celluloid::Actor[:"state_#{@game_uuid}"]
    contribution_hash = {@author => share}
    other_share = (1.0 - share) / cnt
    statements = Celluloid::Actor[:"statements_#{@game_uuid}"]
    @replaces.map{|u| statements.find(u) }.compact.select{|s| s.stage == state.to_swot(state.stage) }.each do |repl|
      repl.contribution.keys.each do |pl|
        contribution_hash[pl] = contribution_hash.fetch(pl, 0.0) + (other_share * repl.contribution.delete(pl).to_f)
      end
    end
    @contribution = contribution_hash
  end

  def calc_contribution_no(share)
    @contribution = { @author => share }
  end

  def calc_contribution
    state = Celluloid::Actor[:"state_#{@game_uuid}"]
    cfg = state.setting
    replaces_amount = @replaces.size
    raise ArgumentError, 'to much replaces (> 2)' unless (0..2).include?(replaces_amount)
    share = cfg[:"pitcher_#{%w(no single double)[replaces_amount]}_replace_score"].to_f
    case replaces_amount
    when 0 then calc_contribution_no(share)
    when 1 then calc_contribution_share(share, 1)
    when 2 then calc_contribution_share(share, 2)
    end
  end

  def set_contribution
    return calc_contribution
    state = Celluloid::Actor[:"state_#{@game_uuid}"]
    cfg = state.setting
    replaces_amount = @replaces.size
    raise ArgumentError, 'to much replaces (> 2)' unless (0..2).include?(replaces_amount)
    share = cfg[:"pitcher_#{%w(no single double)[replaces_amount]}_replace_score"].to_f
    max_share = cfg[:"pitcher_no_replace_score"].to_f
    # share = case replaces_amount
    #         when 0 then cfg[:pitcher_no_replace_score]
    #         when 1 then cfg[:pitcher_single_replace_score]
    #         when 2 then cfg[:pitcher_double_replace_score]
    #         end.to_f
    contributors_hash = { @author => share }
    unless replaces_amount.zero?
      statements = Celluloid::Actor[:"statements_#{@game_uuid}"]
      others_share_part = ( 1 - share ).to_f / replaces_amount
      # FIXME: найти утвержения с текущим стеджом в текущей игре с ид в массиве @replaces
      replaced = @replaces.map{|r| statements.find(r) }.compact.select{|s| s.stage == state.to_swot(state.stage) }

      replaced.each do |statement|
        statement.contribution.each do |player, share|
          player_share = contributors_hash.fetch player, 0.0
          player_share -= max_share if player_share > 0.0 #TODO!!!!!!!!!!!
          contributors_hash[player] = player_share + share * others_share_part
        end
      end
    end
    @contribution = contributors_hash
  end

  def player_contribution
    players = Celluloid::Actor[:"players_#{@game_uuid}"]
    @contribution.inject({}){|r, (k, v)| r.merge(players.find(k).name => v) }
  end

  def contribution_for pl_id
    @contribution.fetch pl_id, 0.0
  end

  def count_pitcher_score
    player = Celluloid::Actor[:"player_#{@author}"]
    typ = @status
    player.count_pitcher_score(typ)
  end

  def count_catchers_score(declined = false)
    state = Celluloid::Actor[:"state_#{@game_uuid}"]
    cfg = state.setting
    non_voted_players = ((Celluloid::Actor[:"players_#{@game_uuid}"].player_ids - [@author] - @votes.map(&:player)) & @votable).map{|i| Celluloid::Actor[:"player_#{i}"] }
    @non_voted = non_voted_players.size
    non_voted_players.each do |pl|
      pl.async.catcher_apply_delta(0.0)
    end
    rslt = conclusion
    #apply voted contra when no quorum

    catcher_zone = [0.5, cfg[:catcher_high_border].to_f].select{|i| @result >= i }.size + 2
    catcher_zone = 1 if @result <= cfg[:catcher_low_border].to_f
    # уродство. меньше или = 25% -- дельта -1.5
    # catcher_zone =  if    @result < cfg[:catcher_low_border].to_f  ; 1
    #                 elsif @result <  0.5                      ; 2
    #                 elsif @result < cfg[:catcher_high_border].to_f ; 3
    #                 else                                      ; 4
    #                 end
    @votes.each do |vote|
      zone = "catcher_#{format_value(vote.result)}_zone_#{catcher_zone}_score"
      delta = cfg[zone.to_sym].to_f
      # delta = -(delta.abs) if [3,4].include?(catcher_zone) && @status == 'no_quorum'
      # if @status == 'no_quorum' && format_value(vote.result) == 'contra'
        # delta = 1.5
      if @status == 'no_quorum'
        delta = 0.0
      end
      # FIXME:  ищем плееров с ид в текущей игре.
      player = Celluloid::Actor[:"player_#{vote.player}"]
      player.async.catcher_apply_delta(delta)
    end
  end

  def calc_result
    v_count = @votes.map(&:player).uniq.size
    if v_count == 0
      @result = 0.0
      return @result
    end
    pro = @votes.select{|v| v.result == 'accepted' }.map(&:player).uniq.size
    @result = pro.to_f / v_count.to_f
    @result
  end

  def calc_votes
    res = calc_result
    v_count = @votes.map(&:player).uniq.size
    unless quorum?
      @status = 'no_quorum'
      return
    end
    # players = Celluloid::Actor[:"players_#{@game_uuid}"]
    unless quorum?
      @status = 'no_quorum'
      return
    end
    pro = @votes.select{|v| v.result == 'accepted' }.map(&:player).uniq.size
    contra = v_count - pro
    @result = pro.to_f / v_count.to_f
    if pro >= contra
      accept!
    else
      decline!
    end
  end

  # TODO: what options?
  def conclusion(options={})
    return 'no_quorum' if @votes.empty? # minimal quorum size TODO
    # grouped_hash[:key] - nil if no objects meet condition
    grouped_hash = @votes.group_by { |vote| vote.result == 'accepted'}
    pro = grouped_hash[true] || []
    contra = grouped_hash[false] || []
    calc_result
    @result >= 0.5 ? 'accepted' : 'declined'
  end

  def vote_results! options={}
    if !quorum?
      @result = 0.0
      count_catchers_score(true)
      decline!
    else
      @result = @votes.inject(0) { |r, v| r += v.result == 'accepted' ? 1 : 0 }.to_f / @votes.size.to_f
      @result >= 0.5 ? accept! : decline!
      count_catchers_score
    end
    count_pitcher_score
  end

  def add_impo(pl_id, val, auto = false)
    idx = nil
    @importances.each_with_index{|v, i| idx = i if v[:player] == pl_id }
    @importances.delete_at(idx) if idx
    @importances << {player: pl_id, value: val.to_i, auto: auto}
  end

  def format_value(str)
    return 'pro' if str == 'accepted'
    return 'contra' if str == 'declined'
    raise ArgumentError, "expect 'accepted' or 'declined', got: #{str}"
  end
end
