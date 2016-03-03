class Statements
  include Celluloid
  include Celluloid::IO
  include Celluloid::Notifications
  include Celluloid::Internals::Logger

  attr_accessor :statements, :current, :game_uuid
  attr :voting, :last_stat
  def initialize params = {}
    @game_uuid = params[:game_uuid]
    @statements = []
    @current = []
    @voting = nil
    @visible = []
  end

  def find(uuid)
    @statements.detect{|s| s.uuid == uuid }
  end

  def voting
    return nil unless @voting
    find(@voting)
  end

  def last_stat
    return nil unless @last_stat
    find(@last_stat)
  end

  def visible
    v = @visible.map{|s| find s }
    v.each_with_index{|s, i| s.position = i + 1 }
    v
  end

  def validate_statement params = {}
    repl_count = params.has_key?(:to_replace) && params[:to_replace] ? params[:to_replace].size : 0
    if @visible.size - repl_count > 6
      return { error: 'to_many' }
    end
    if @current.detect{|s| params[:value] == find(s).value }
      return { error: 'duplicate' }
    end
    if params[:value].force_encoding('UTF-8').size > 75
      return { error: 'too_long' }
    end
    if params[:value].strip.size == 0
      return { error: 'empty' }
    end
    {}
  end

  def check_triple_decline
    state = Actor[:"state_#{@game_uuid}"]
    dec_count = [state.setting[:declined_in_row_statements].to_i, @statements.size].min
    return false if dec_count < state.setting[:declined_in_row_statements].to_i
    # dec_count = state.setting[:declined_in_row_statements].to_i
    !@statements[-dec_count, dec_count].select{|s| s.stage == state.stage }.detect{|s| s.status != 'declined' }
  end

  def range_for params = {}
    #value, index, stage, player
  end

  def add params = {}
    er = validate_statement params
    return er unless er.empty?
    uuid = UUID.new.generate
    state = Actor[:"state_#{@game_uuid}"]
    queue = Actor[:"queue_#{@game_uuid}"]
    replace = []
    if params[:to_replace]
      info "to replace #{params[:to_replace].inspect}"
      params[:to_replace].each{|idx| replace << @visible[idx - 1] }
    end

    statement = Statement.new value: params[:value], author: queue.pitcher.uuid, replaces: replace.compact, uuid: uuid, game_uuid: @game_uuid, stage: state.stage, step: state.step
    @statements << statement
    @current << uuid
    replace.map{|s| find s }.compact.each{|s| s.replaced_by! uuid }
    active.each_with_index{|s, i| s.position = i + 1 }
    statement.set_contribution
    @voting = uuid
    {}
  end

  def update_visible
    return unless @voting
    s = find(@voting)
    unless s
      @voting = nil
      @last_stat = nil
      return
    end
    if s.status == 'accepted'
      s.replaces.each{|s| @visible.delete s }
      @visible << s.uuid
    end
    @last_stat = @voting
    @voting = nil
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
    visible
    # mapped_current.select(&:visible?)
  end

  def all
    mapped_current.map(&:as_json)
  end

  def by(sym, val)
    @statements.select{|s| s.send(sym) == val }
  end

  def clean_current
    @current = []
    @visible = []
    @last_stat = nil
    @voting = nil
  end

end
