class Statement
  include Celluloid::Internals::Logger

  attr_accessor :value,
                :author,
                :replaces,
                :uuid,
                :position,
                :game_uuid,
                :stage,
                :step,
                :votes,
                :importances,
                :contribution

  def initialize params = {}
    @value = params[:value]
    @author = params[:author]
    @replaces = params[:replaces] || []
    @uuid = params[:uuid]
    @position = params[:position] if params[:position]
    @game_uuid = params[:game_uuid]
    @stage = params[:stage]
    @step = params[:step]
    # {player: 'id', share: 'float'}
    @contribution = {}
    # [{ player: 'id', result: 'accepted | declined' }, ...]
    @votes = []
    @importances = []
  end

  def as_json
    author = Celluloid::Actor[:"player_#{@author}"]
    { index: @position, body: @value, score: author.score, author: author.name}
  end

  def vote params = {}
    @votes << Vote.new(player: params[:player], result: params[:result], active: true)
  end

  def voted_count
    @votes.map(&:player).uniq.size
  end

  def set_contribution
    replaces_amount = @replaces.size
    raise ArgumentError, 'to much replaces (> 2)' unless (0..2).include?(replaces_amount)
    share = case replaces_amount
            when 0 then Store::Setting.defaults[:pitcher_no_replace_score]
            when 1 then Store::Setting.defaults[:pitcher_single_replace_score]
            when 2 then Store::Setting.defaults[:pitcher_double_replace_score]
            end
    contributors_hash = { @author => share }
    unless replaces_amount.zero?
      others_share_part = ( 1 - share ) / replaces_amount
      # FIXME: найти утвержения с текущим стеджом в текущей игре с ид в массиве @replaces
      replaced = Statement.find(@replaces)

      replaced.each do |statement|
        statement.contribution.each do |player, share|
          player_share = contributors_hash.fetch player, 0.0
          contributors_hash[player] = player_share + share * others_share_part
        end
      end
    end
    @contribution = contributors_hash
  end

  def count_catchers_score
    result = conclusion
    catcher_zone =  if   result < Store::Setting.defaults[:catcher_low_border]  ; 1
                    elsif result <  0.5                                         ; 2
                    elsif result < Store::Setting.defaults[:catcher_high_border]; 3
                    else                                                        ; 4
                    end
    @votes.each do |vote|
      zone = "catcher_#{format_value(vote.result)}_zone_#{catcher_zone}_score"
      delta = Store::Setting.defaults[zone.to_sym]
      # FIXME:  ищем плееров с ид в текущей игре.
      player = Celluloid::Actor[:"player_#{vote.player}"]
      player.score.catcher_apply_delta(delta)
    end
  end

  def result
    p = @votes.map(&:result).select{|v| v == 'accepted' }.size
    return 'declined' if p ==0
    return 'accepted' if p == voted_count
    p.to_f / @votes.size.to_f >= 0.5 ? 'accepted' : 'declined'
  end

  # TODO: what options?
  def conclusion(options={})
    return 'no_votes' if @votes.size.zero?
    # grouped_hash[:key] - nil if no objects meet condition
    grouped_hash = @votes.group_by { |vote| vote.result == 'accepted'}
    pro = grouped_hash[true] || []
    contra = grouped_hash[false] || []
    return 'accepted' if pro && !contra
    return 'declined' if contra && !pro
    result = pro.size.to_f / (contra + pro).size.to_f
    result >= 0.5 ? 'accepted' : 'declined'
  end

  private

  def format_value(str)
    return 'pro' if str == 'accepted'
    return 'contra' if str == 'declined'
    raise ArgumentError, "expect 'accepted' or 'declined', got: #{str}"
  end
end


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


# def vote_results options={}
#   if options[:quorum_not_reached]
#     self.result = 0
#     # update_attributes :result, 0
#     self.decline
#   else
#     self.result = votes.pro.count.to_f / votes.count.to_f
#     # update_attribute :result, votes.pro.count.to_f / votes.count.to_f
#     self.result >= 0.5 ? accept : decline
#
#     save
#     count_catchers_score
#     game.count_pitchers_score
#   end
# end
