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
    p = @current.first
    return nil unless p
    Actor[:"player_#{p}"]
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
      next if @current.size >= 3
      p = @tail.shift
      @current << p if p
    end
  end

  def ids
    @current + @tail
  end

  def first
    @current.first # || @tail.first
  end

  def rebuild_tail
    players = Actor[:"players_#{@game_uuid}"]
    list = players.players.sort_by(&:order)
    p 'pl list before', list.map(&:uuid)
    @tail = []
    last = Actor[:"player_#{@current.last}"]
    list.delete_if{|l| @current.include? l.uuid || l.order.to_i < 1 }
    p 'pl list after', list.map(&:uuid)
    idx = list.index{|l| l.order > last.order }
    p 'pos for last order', last.order, idx
    if idx
      @tail += list[idx..-1].map(&:uuid)
      list = list[0, idx]
    end
    p @tail
    @tail += list[idx..-1].map(&:uuid)
    p @tail, (@current + @tail).size


    # (@current + @tail).each{|i| list.delete_if{|s| s.uuid == i } }
    # mx = Actor[:"player_#{@tail.last}"].try(:order)
    # mx ||= Actor[:"player_#{@current.last}"].try(:order)
    # @tail += list.select{|l| l.order.to_i > mx.to_i }.map(&:uuid)
    # (@tail).each{|i| list.delete_if{|s| s.uuid == i } }
    # @tail += list.map(&:uuid)
    # info "size #{ids.size}"
  end

  def index(pl_id)
    info "queue index #{pl_id.inspect} size #{ids.size}"
    @current.index(pl_id)
  end

end
