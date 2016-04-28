class PlayerStats
  include Celluloid
  include Celluloid::Internals::Logger
  include Celluloid::Notifications

  # attribute :uuid
  # attribute :stage
  # index :uuid
  # index :stage

  # attribute :total
  # attr

  attr :uuid, :guid, :stage
  attr :analyst, :analyst_offline, :analyst_timeout, :analyst_voted
  attr :pitcher, :pitcher_offline, :pitcher_timeout, :pitcher_pitched, :pitcher_passed
  attr :total, :offline, :timeout, :active, :resultative

  def initialize params = {}
    @analyst = @analyst_offline = @analyst_timeout = @analyst_voted = 0
    @pitcher = @pitcher_offline = @pitcher_timeout = @pitcher_pitched = @pitcher_passed = 0
    @total = @offline = @timeout = @active = @resultative = 0
    @uuid = params[:uuid]
    player = Actor[:"player_#{@uuid}"]
    @guid = player.game_uuid
    @stage = params.fetch(:stage, false)

    subscribe :analyst_offline, :analyst_offline
    subscribe :analyst_timeout, :analyst_timeout
    subscribe :analyst_voted, :analyst_voted
    subscribe :pitcher_offline, :pitcher_offline
    subscribe :pitcher_timeout, :pitcher_timeout
    subscribe :pitcher_pitched, :pitcher_pitched
    subscribe :pitcher_passed, :pitcher_passed
  end

  def analyst_offline topic, pl_id, st
    return unless pl_id == @uuid
    return if @stage && @stage != st
    @analyst_offline += 1
    @analyst += 1
    @offline += 1
    @total += 1
  end

  def analyst_timeout topic, pl_id, st
    return unless pl_id == @uuid
    return if @stage && @stage != st
    @analyst_timeout += 1
    @analyst += 1
    @timeout += 1
    @total += 1
  end

  def analyst_voted topic, pl_id, st
    return unless pl_id == @uuid
    return if @stage && @stage != st
    @analyst_voted += 1
    @analyst += 1
    @active += 1
    @resultative += 1
    @total += 1
  end

  def pitcher_offline topic, pl_id, st
    return unless pl_id == @uuid
    return if @stage && @stage != st
    @pitcher_offline += 1
    @pitcher += 1
    @offline += 1
    @total += 1
  end

  def pitcher_timeout topic, pl_id, st
    return unless pl_id == @uuid
    return if @stage && @stage != st
    @pitcher_timeout += 1
    @pitcher += 1
    @timeout += 1
    @total += 1
  end

  def pitcher_pitched topic, pl_id, st
    return unless pl_id == @uuid
    return if @stage && @stage != st
    @pitcher_pitched += 1
    @pitcher += 1
    @active += 1
    @resultative += 1
    @total += 1
  end

  def pitcher_passed topic, pl_id, st
    return unless pl_id == @uuid
    return if @stage && @stage != st
    @pitcher_passed += 1
    @pitcher += 1
    @active += 1
    @total += 1
  end

end
  # player Денис 1 
  # Analyst role: 5 of 7 
  # Was offline: 0 
  # Missed by timeout: 0 
  # Voted: 5

  # Contributor role: 2 of 7 
  # Was offline: 0
  # Missed by timeout: 0 
  # Pitched: 2
  # Passed: 0
                                    
  # Total: 7
  # Was offline: 0
  # Missed by timeout: 0 
  # Voted/Pitched/Passed: 7 
  # Voted/Pitched: 7
