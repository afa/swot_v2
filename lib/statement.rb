class Statement
  include Celluloid::Internals::Logger

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
                :importances,
                :status,
                :result,
                :contribution
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
    # [{ player: 'id', result: 'accepted | declined' }, ...]
    @votes = []
    @result = 0.0
    @importances = []
    @status = false
  end

  def to_store
    {author: @author, game_uuid: @game_uuid, uuid: @uuid, stage: @stage, step: @step, value: @value, votes: @votes, status: @status, importances: @importances}
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
    @votes << Vote.new(player: params[:player], result: params[:result], active: true)
  end

  def voted_count
    @votes.map(&:player).uniq.size
  end

  def score_for(player_id)
    @contribution[player_id]
  end

  def quorum?
    players = Celluloid::Actor[:"players_#{@game_uuid}"]
    queue = Celluloid::Actor[:"queue_#{@game_uuid}"]
    (voted_count.to_f * 2) > (players.players.select(&:online) - [queue.pitcher]).size
    #TODO ??
  end

  def calc_result
    return 'no_quorum' if @votes.empty?
    p = @votes.map(&:result).select{|v| v == 'accepted' }.size
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

  def set_contribution
    state = Celluloid::Actor[:"state_#{@game_uuid}"]
    cfg = state.setting
    replaces_amount = @replaces.size
    raise ArgumentError, 'to much replaces (> 2)' unless (0..2).include?(replaces_amount)
    share = case replaces_amount
            when 0 then cfg[:pitcher_no_replace_score]
            when 1 then cfg[:pitcher_single_replace_score]
            when 2 then cfg[:pitcher_double_replace_score]
            end.to_f
    contributors_hash = { @author => share }
    unless replaces_amount.zero?
      statements = Celluloid::Actor[:"statements_#{@game_uuid}"]
      others_share_part = ( 1 - share ).to_f / replaces_amount
      # FIXME: найти утвержения с текущим стеджом в текущей игре с ид в массиве @replaces
      replaced = @replaces.map{|r| statements.find(r) }.compact.select{|s| s.stage == state.to_swot(state.stage) }

      replaced.each do |statement|
        statement.contribution.each do |player, share|
          player_share = contributors_hash.fetch player, 0.0
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

  def count_pitcher_score
    state = Celluloid::Actor[:"state_#{@game_uuid}"]
    player = Celluloid::Actor[:"player_#{@author}"]
    cfg = state.setting
    typ = @status
    mult = cfg[:"pitcher_rank_multiplier_#{typ}"].to_f
    rank = player.pitcher_rank
    rank *= mult
    player.pitcher_rank = [rank, cfg[:pitcher_minimum_rank].to_f].max
    statements = Celluloid::Actor[:"statements_#{@game_uuid}"]
    statements.count_pitchers_score
  end

  def count_catchers_score
    state = Celluloid::Actor[:"state_#{@game_uuid}"]
    cfg = state.setting
    rslt = conclusion
    catcher_zone =  if    @result < cfg[:catcher_low_border].to_f  ; 1
                    elsif @result <  0.5                      ; 2
                    elsif @result < cfg[:catcher_high_border].to_f ; 3
                    else                                      ; 4
                    end
    @votes.each do |vote|
      zone = "catcher_#{format_value(vote.result)}_zone_#{catcher_zone}_score"
      delta = cfg[zone.to_sym].to_f
      # FIXME:  ищем плееров с ид в текущей игре.
      player = Celluloid::Actor[:"player_#{vote.player}"]
      player.async.catcher_apply_delta(delta)
    end
  end

  def calc_votes
    v_count = @votes.map(&:player).uniq.size
    if v_count == 0
      @result = 0.0
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
    # return 'accepted' if pro && !contra
    # return 'declined' if contra && !pro
    @result = pro.size.to_f / (contra + pro).size.to_f
    @result >= 0.5 ? 'accepted' : 'declined'
  end

  def vote_results! options={}
    if @status == 'no_quorum'
      @result = 0.0
      decline!
    else
      @result = @votes.inject(0){|r, v| r += v.result == 'accepted' ? 1 : 0 }.to_f / @votes.size.to_f
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

  # private
  # def count_pitchers_score opts={}
  #   all_contributions = accepted_statements.map &:contributors

  #   players.each do |player|
  #     player.score.pitcher_before_ranging = player.score.pitcher if opts[:save_before]
  #     player.score.pitcher = all_contributions.sum {|x| x[player.id.to_s] || BigDecimal.new('0')}
  #     player.save
  #   end
  # end

  # def count_ranging

  #   # nonranged_players = self.players.active.all.select(&:gaming?) - accepted_statements.map(&:importances).flatten.map(&:player_id).uniq.map{|x| Player.find(x) }
  #   accepted_statements.each do |s|
  #     nonranged_players = self.players.active.all.select(&:gaming?) - s.importances.map(&:player_id).uniq.map{|x| Player.find(x) }
  #     nonranged_players.each do |p|
  #       Rails.logger.info "---add importance for stat #{s.id.to_s} #{s.statement.to_s} player #{p.name}: #{p.id.to_s}"
  #       v = s.importances.create player: p, value: Importance::MID_VALUE, auto: true
  #       self.game_logger.write :importance_added, v
  #     end
  #   end
  #   zero_imps = accepted_statements.map(&:importances).flatten.select{|i| i.value.nil? }
  #   Rails.logger.info "---add imps for #{zero_imps.size}"
  #   zero_imps.each do |i|
  #     i.update_attributes value: Importance::MID_VALUE, auto: true
  #       self.game_logger.write :importance_added, i
  #   end
  #   accepted_statements.map &:update_importance_score
  #   scores_sum = accepted_statements.sum{|s| s.reload.importance_score_raw}

  #   accepted_statements.each do |statement|
  #     score = statement.importance_score_raw * 100.0 / scores_sum
  #     statement.update_attribute :importance_score, score
  #   end

  #   count_pitchers_score save_before: true
  # end

# def count_catchers_score
#   catcher_zone =  if    result < game.settings.send(:catcher_low_border)  ; 1
#                   elsif result < BigDecimal.new('0.5')                    ; 2
#                   elsif result < game.settings.send(:catcher_high_border) ; 3
#                   else                                                    ; 4
#                   end
#
#   votes.each do |vote|
#     player = vote.player
#     key = "catcher_#{vote.result}_zone_#{catcher_zone}_score"
#     player.score.count_catcher! game.settings.send(key)
#   end
#
#   (game.players.online.to_a - votes.distinct(:player).map{|i| Player.find(i) } - begin [game.current_pitcher]; rescue PlayersQueue::ErrorEmptyQueue; [] end).each do |player|
#     player.score.count_catcher! game.settings.send(:catcher_abstainer_score)
#   end
# end

# def set_contributors
#   share, amount = case self.to_replace.size
#                   when 0 then [ game.settings.send(:pitcher_no_replace_score),     0 ]
#                   when 1 then [ game.settings.send(:pitcher_single_replace_score), 1 ]
#                   when 2 then [ game.settings.send(:pitcher_double_replace_score), 2 ]
#                   end
#
#   contributors_hash = { pitcher => share }
#
#   unless amount.zero?
#     other_share_part = ( BigDecimal.new('1.0') - share ) / amount
#
#     to_replace.each do |st_id|
#       s = stage.statements.find st_id
#
#       s.contributions_before_ranking.each do |contribution|
#         player = contribution.player
#         player_share = contributors_hash.fetch player, BigDecimal.new('0')
#         contributors_hash[player] =  player_share + contribution.share * other_share_part
#       end
#     end
#   end
#
#   contributors_hash.each {|p, v| contributions_before_ranking.build player: p, share: v }
# end


