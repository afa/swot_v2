class Statements
  include Celluloid
  include Celluloid::IO
  include Celluloid::Notifications
  include Celluloid::Internals::Logger

  attr_accessor :statements, :current, :game_uuid
  attr :voting
  def initialize params = {}
    @game_uuid = params[:game_uuid]
    @statements = []
    @current = []
    @voting = nil
  end

  def find(uuid)
    @statements.detect{|s| s.uuid == uuid }
  end

  def voting
    return nil unless @voting
    find(@voting)
  end

  def validate_statement params = {}
    repl_count = params.has_key?(:to_replace) ? params[:to_replace].size : 0
    if active.size - repl_count > 6
      return { error: 'to_many' }
    end
    if @current.detect{|s| params[:value] == s[:value] }
      return { error: 'duplicate' }
    end
    if params[:value].force_encoding('UTF-8').size > 75
      return { error: 'too_long' }
    end
    {}
  end

  def add params = {}
    uuid = UUID.new.generate
    state = Actor[:"state_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    replace = []
    if params[:to_replace]
      info "to replace #{params[:to_replace].inspect}"
      params[:to_replace].each{|idx| replace << @current.detect{|c| find(c).position == idx.to_i} }
    end

    statement = Statement.new value: params[:value], author: queue.pitcher.uuid, replaces: replace.compact, uuid: uuid, game_uuid: @game_uuid, stage: state.stage, step: state.step
    @statements << statement
    @current << uuid
    replace.map{|s| find s }.compact.each{|s| s.replaced_by! uuid }
    active.each_with_index{|s, i| s.position = i + 1 }
    statement.set_contribution
    @voting = uuid
  end

  def mapped_current
    @current.map{|s| find s }
  end

  def find_for_stage st
    mapped_current.detect{|s| s.stage == st }
  end

  def active_js(player = nil)
    active.map{|s| s.as_json(player) }
  end

  def active
    mapped_current.select(&:visible?)
  end

  def all
    mapped_current.map(&:as_json)
  end

  def by(sym, val)
    @statements.select{|s| s.send(sym) == val }
  end

  def clean_current
    @current = []
  end

end
