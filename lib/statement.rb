# хранилище и воркур выражений
require 'statement_score'
class Statement
  include Celluloid::Internals::Logger

  attr_reader :value,
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
              :score,
              :status,
              :result,
              :unquorumed,
              :non_voted
  # :auto

  def initialize(params = {})
    pos = params[:position]
    @value = params[:value]
    @author = params[:author]
    @replaces = params[:replaces] || []
    @uuid = params[:uuid]
    @position = pos if pos
    @game_uuid = params[:game_uuid]
    @stage = params[:stage]
    @step = params[:step]
    @replaced = false
    @votes = []
    @result = 0.0
    @importances = []
    @importance_score = 0.0
    @status = false
    @unquorumed = false
    @visible = false
    @non_voted = 0
    @score = StatementScore.new(self)
  end

  def to_store
    { author: author, game_uuid: game_uuid, uuid: uuid, stage: stage, step: step, value: value,
      votes: votes.map(&:as_json), status: status, result: result, importances: importances,
      importance_score: importance_score, importance_score_raw: importance_score_raw,
      contribution: score.contribution, contribution_before_ranking: score.contribution_before_ranking,
      visible: visible }
  end

  def copy_before
    score.copy_before
  end

  def update_importance_score
    if importances.empty?
      importance_score_raw = 1
      return
    end
    @importance_score_raw = importances.inject(0.0) { |res, imp| res + score_value(imp) } /
                            importances.map { |imp| imp[:player] }.compact.uniq.size
    @importance_score_raw = 1 if importance_score_raw == 0

    # apply importance multiplier to contributors share
    # self.contributions_before_ranking.each do |x|
    #   self.contributions_after_ranking.build player: x.player, share: x.share * self.importance_score_raw
    # end
  end

  def score_value(hsh)
    setting = Celluloid::Actor[:"state_#{game_uuid}"].setting
    setting[:"ranging_importance_#{hsh[:value].to_i - 1}_score"].to_f
  end

  def replaced_by!(uuid)
    self.replaced = if uuid.is_a? Statement
                      uuid.uuid
                    else
                      uuid
                    end
  end

  def as_json(player_id = nil)
    # author = Celluloid::Actor[:"player_#{@author}"]
    # player = Celluloid::Actor[:"player_#{player_id}"]
    { index: position, body: value, score: score_for(player_id), player_id: player_id, author: author }
  end

  def vote(params = {})
    return if votes.detect { |vote| vote.player == params[:player] }
    votes << Vote.new(player: params[:player], result: params[:result], active: true)
  end

  def voted_count
    votes.map(&:player).uniq.size
  end

  def score_for(player_id)
    score.score_for(player_id)
  end

  def quorum?
    players = Celluloid::Actor[:"players_#{@game_uuid}"]
    queue = Celluloid::Actor[:"queue_#{@game_uuid}"]
    (voted_count.to_f * 2) >= (players.players.select(&:online) - [queue.pitcher]).size
    # TODO: ??
  end

  def accept!
    @status = 'accepted'
  end

  def decline!
    @status = 'declined'
  end

  def process_end_step_voting
    calc_votes
    vote_results
    score.set_contribution if status == 'accepted'
    score.count_pitcher_score
    publish :player_log_push, game_uuid, uuid
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
    if v_count == 0
      # @result = 0.0
      @status = 'no_quorum'
      return
    end
    # players = Celluloid::Actor[:"players_#{@game_uuid}"]
    unless quorum?
      # @result = 0.0
      @status = 'no_quorum'
      @unquorumed = true
      return
    end
    pro = @votes.select{|v| v.result == 'accepted' }.map(&:player).uniq.size
    contra = v_count - pro
    @result = pro.to_f / v_count.to_f
    if pro >= contra
      accept!
    else
      @unquorumed = false
      decline!
    end
  end

  def vote_results options={}
    if @status == 'no_quorum'
      @unquorumed = true
      @result = 0.0
      score.count_catchers_score(true)
      decline!
    else
      @unquorumed = false
      @result = @votes.inject(0){|r, v| r += v.result == 'accepted' ? 1 : 0 }.to_f / @votes.size.to_f
      @result >= 0.5 ? accept! : decline!
      score.count_catchers_score
    end
    # count_pitcher_score
  end

  def add_impo(pl_id, val, auto = false)
    idx = nil
    @importances.each_with_index{|v, i| idx = i if v[:player] == pl_id }
    @importances.delete_at(idx) if idx
    @importances << { player: pl_id, value: val.to_i, auto: auto }
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


