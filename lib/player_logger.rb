class PlayerLogger

  field :step, type: Integer
  field :statement, type: String
  field :replace, type: String
  field :pro_percent, type: Integer
  field :scores_deltas, type: Hash
  field :votes, type: Hash
  field :player_name, type: String
  field :stage_title, type: String
  field :missed_pitching, type: Boolean, default: false
end
