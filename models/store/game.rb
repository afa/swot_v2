class Store::Game < Ohm::Model
  include Ohm::DataTypes
  attribute :name
  attribute :uuid
  attribute :company
  attribute :country
  attribute :description
  attribute :industry
  attribute :start_at, Type::Integer
  attribute :state
  attribute :time_zone
  attribute :mongo_id
  index :mongo_id
  index :uuid
  unique :uuid

  def settings
    Store::Setting.find(game_uuid: uuid).first.data
  end

  def players
    Store::Player.find(game_uuid: uuid).to_a
  end

  def accepted_statements
    Store::Statement.find(game_uuid: uuid, status: 'accepted').to_a
  end

  def as_json_params
    {
      name: name,
      settings: settings,
      players: players.map(&:as_json),
      statements: accepted_statements.map(&:as_json),
      start_at: start_at,
      time: Time.now.to_f.round(6)
    }
  end

  def as_json
    {
      name: name,
      uuid: uuid,
      start_at: start_at.to_i,
      state: state,
      mongo_id: mongo_id,
      settings: settings.as_json,
      players: players.as_json
    }
  end
end
