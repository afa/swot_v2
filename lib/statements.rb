class Statements
  include Celluloid
  include Celluloid::Internals::Logger

  attr_accessor :statements, :current, :game_uuid
  def initialize params = {}
    @game_uuid = params[:game_uuid]
    @statements = []
    @current = []
  end

  def find(uuid)
    @statements.detect{|s| s.uuid == uuid }
  end

  def add params = {}
    uuid = UUID.new.generate
    state = Actor[:"state_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    replace = []
    if params[:to_replace]
      params[:to_replace].each{|idx| replace << @current[idx.to_i - 1] }
      replace.each{|s| @current.delete(s) }
    end

    statement = Statement.new value: params[:value], author: queue.pitcher, replaces: replace, uuid: uuid, game_uuid: @game_uuid, stage: state.stage, step: state.step
    @statements << statement
    @current << uuid
    @current.each_with_index{|s, i| find(s).position = i + 1 }
  end

  def all
    @current.map{|s| find s }
  end

  def by(sym, val)
    @statements.select{|s| s.send(sym) == val }
  end

  def clean_current
    @current = []
  end

end
