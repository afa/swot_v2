# # catcher zone borders
# catcher_low_border:
#   type: BigDecimal
#   val: 0.25
# catcher_high_border:
#   type: BigDecimal
#   val: 0.75
#
# # catcher scores
# catcher_pro_zone_1_score:
#   type: BigDecimal
#   val: -1.5
# catcher_pro_zone_2_score:
#   type: BigDecimal
#   val: -1.0
# catcher_pro_zone_3_score:
#   type: BigDecimal
#   val: +1.0
# catcher_pro_zone_4_score:
#   type: BigDecimal
#   val: +1.5
# catcher_contra_zone_1_score:
#   type: BigDecimal
#   val: +1.5
# catcher_contra_zone_2_score:
#   type: BigDecimal
#   val: +1.0
# catcher_contra_zone_3_score:
#   type: BigDecimal
#   val: -1.0
# catcher_contra_zone_4_score:
#   type: BigDecimal
#   val: -1.5
# catcher_abstainer_score:
#   type: BigDecimal
#   val: -0.5
#
# # pitcher's ranks
# pitcher_rank_multiplier_accepted:
#   type: BigDecimal
#   val: 1.2
# pitcher_rank_multiplier_declined:
#   type: BigDecimal
#   val: 0.8
# pitcher_rank_multiplier_pass:
#   type: BigDecimal
#   val: 0.9
# pitcher_rank_multiplier_disconnected:
#   type: BigDecimal
#   val: 0.9
# pitcher_minimum_rank:
#   type: BigDecimal
#   val: 0.3
#
# # кол-во принятых утверждений
# field :pitcher, type: BigDecimal, default: 0
# # score.pitcher = all_contributions.sum {|x| x[player.id.to_s] || BigDecimal.new('0')}
#
# # рейтинг катчера
# field :catcher, type: BigDecimal, default: 0
# # рейтинг питчера
# field :rank,    type: BigDecimal, default: 1
# # последнее изменение рейтинга катчера
# field :delta,   type: BigDecimal, default: 0
# # эти два я хз
# field :pitcher_before_ranging, type: BigDecimal, default: 0
# field :catcher_first_half, type: BigDecimal, default: 0
#===============================================================================#
class Score
  attr_accessor :catcher, :pitcher

  def initialize(pitcher = 1, catcher = 0)
    @pitcher = pitcher
    @catcher = catcher
  end

  def catcher_apply_delta(delta)
    @catcher += delta
  end

  # conclusion = [accepted, declined, pass, disconnected]
  def pitcher_update(conclusion)
    mult = Store::Setting.defaults["pitcher_rank_multiplier_#{conclusion}".to_sym]
    min = Store::Setting.defaults[:pitcher_minimum_rank]
    raise "pitcher_rank_multiplier_#{conclusion} not in Settings" unless (mult && min)
    temp = @pitcher * mult
    @pitcher = [temp, min].max
  end
end

# def update_rank key
#   reload
#   settings = player.game.settings
#   multiplier = settings.send(:"pitcher_rank_multiplier_#{key}")
#   new_rank  = rank
#   new_rank  *= multiplier
#   update_attribute :rank, [new_rank, settings.send(:pitcher_minimum_rank)].max
# end
