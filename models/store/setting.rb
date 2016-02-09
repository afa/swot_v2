require 'ostruct'
# require 'store/setting/string'
# require 'store/setting/integer'
# require 'store/setting/boolean'
# require 'store/setting/decimal'
class Store::Setting < Ohm::Model
  include Ohm::DataTypes
  attr_accessor :current

  attribute :data, Type::Hash
  attribute :game_uuid
  index :game_uuid

  def self.defaults
    {
      min_players: 4,
      max_players: 12,
      max_statements: 7,
      default_url_host: 'localhost:3000',
      default_invitation_template: '%{admin_name} invites you to take part in swot analysis session. the session will be held online',
      default_reminding_template: 'We remind you that you are invited to play "%{game_name}"',
      random_enabled: false,
      countries: %w( Russia USA Pakistan),
      industries: %w( IT Medicine Trade),
      min_games_for_benchmark: 100,
      prepare_at_seconds: 300,

      # pitcher scores
      pitcher_no_replace_score: 1,
      pitcher_single_replace_score: 0.30,
      pitcher_double_replace_score: 0.50,

      # pitcher's ranks
      pitcher_rank_multiplier_accepted: 1.2,
      pitcher_rank_multiplier_declined: 0.8,
      pitcher_rank_multiplier_pass: 0.9,
      pitcher_rank_multiplier_disconnected: 0.9,
      pitcher_minimum_rank: 0.3,

      # catcher zone borders
      catcher_low_border: 0.25,
      catcher_high_border: 0.75,

      # catcher scores
      catcher_pro_zone_1_score: -1.5,
      catcher_pro_zone_2_score: -1.0,
      catcher_pro_zone_3_score: +1.0,
      catcher_pro_zone_4_score: +1.5,
      catcher_contra_zone_1_score: +1.5,
      catcher_contra_zone_2_score: +1.0,
      catcher_contra_zone_3_score: -1.0,
      catcher_contra_zone_4_score: -1.5,
      catcher_abstainer_score: -0.5,

      # ranging scores
      ranging_importance_0_score: +0.3,
      ranging_importance_1_score: +0.5,
      ranging_importance_2_score: +1.0,
      ranging_importance_3_score: +2.0,
      ranging_importance_4_score: +3.0,

      stage_timeout: 1500,
      voting_quorum_timeout: 60,
      voting_tail_timeout: 15,
      results_timeout: 5,
      between_stages_timeout: 10,
      max_steps: 60,
      first_pitching_timeout: 120,
      pitching_timeout: 20,
      ranging_timeout: 30,
      # disconnect_timeout:
      terminate_timeout: 10,

      amnesty: false,

      declined_in_row_statements: 3
    }

  end

  def [] key
    data[key]
  end

  def initialize params = {}
    self.game_uuid = params.delete :game_uuid
    self.data = Store::Setting.defaults.merge params
    # @current = OpenStruct.new params
  end
end
