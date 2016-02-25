class Queue
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger

  def initialize params = {}
    @game_uuid = params[:game_uuid]
    @current = []
    @tail = []
    game = Actor[:"game_#{@game_uuid}"]
    players = Actor[:"players_#{@game_uuid}"]
    if game.try(:alive?)
      rebuild_tail
      fill_current
      # list = players.players.sort_by(&:order)
      # 3.times do
      #   p = list.shift
      #   @current << p.uuid if p
      # end
      # @tail += list
    else
      info "no queue rebuild, game died"
    end
  end

  def add(pl)
    players = Actor[:"players_#{@game_uuid}"]
    pl_id = pl.is_a?(String) ? pl : pl.uuid
    players.players << pl_id unless players.players.include?(pl_id)
    rebuild_tail
    fill_current
  end

  def pitcher
    Actor[:"player_#{@current.first}"]
  end

  def prev_pitcher
    return nil unless @prev_pitcher
    Actor[:"player_#{@prev_pitcher}"]
  end

  def next!
    skip!
    rebuild_tail
    fill_current
  end

  def skip!
    @prev_pither = @current.shift
    fill_current
  end

  def fill_current
    (3 - @current.size).times do
      p = @tail.shift
      @current << p if p
    end
  end

  def ids
    @current + @tail
  end

  def first
    @current.first || @tail.first
  end

  def rebuild_tail
    info "rebuild"
    players = Actor[:"players_#{@game_uuid}"]
    list = players.players.sort_by(&:order)
    (@current + @tail).each{|i| list.delete_if{|s| s.uuid == i } }
    mx = Actor[:"player_#{@tail.last}"].try(:order)
    mx ||= Actor[:"player_#{@current.last}"].try(:order)
    @tail += list.select{|l| l.order.to_i > mx.to_i }.map(&:uuid)
    (@tail).each{|i| list.delete_if{|s| s.uuid == i } }
    @tail += list.map(&:uuid)
    info "size #{ids.size}"
  end

  def index(pl_id)
    info "queue index #{pl_id.inspect} size #{ids.size}"
    @current.index(pl_id)
  end

end
