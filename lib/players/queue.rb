require 'randoms'
class Queue
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger
  include Celluloid::Notifications

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

  def log_info
    hsh = {
      base_queue: {
        names: @current.map { |id| Actor[:"player_#{id}"] }.map { |pl| pl && pl.alive? ? pl : nil }.map(&:name).join(', '),
        scores: @current.map { |id| Actor[:"player_#{id}"] }.map { |pl| pl && pl.alive? ? pl : nil }.map(&:pitcher_score).join(', '),
        orders: @current.map { |id| Actor[:"player_#{id}"] }.map { |pl| pl && pl.alive? ? pl : nil }.map(&:order).join(', ')
      },
      tail_queue: {
        names: @tail.map { |id| Actor[:"player_#{id}"] }.map { |pl| pl && pl.alive? ? pl : nil }.map(&:name).join(', '),
        scores: @tail.map { |id| Actor[:"player_#{id}"] }.map { |pl| pl && pl.alive? ? pl : nil }.map(&:pitcher_score).join(', '),
        orders: @tail.map { |id| Actor[:"player_#{id}"] }.map { |pl| pl && pl.alive? ? pl : nil }.map(&:order).join(', ')
      }
    }
    publish :random_queue, @game_uuid, hsh
    info "random_queue: #{hsh.inspect}"
  end

  # def adm_log
  #   Actor[:"admin_logger_#{@game_uuid}"]
  # end

  def add(_pl)
    # TODO: !!!!! проверить места вызовов
    # players = Actor[:"players_#{@game_uuid}"]
    # pl_id = pl.is_a?(String) ? pl : pl.uuid
    # players.player_ids << pl_id unless players.player_ids.include?(pl_id)
    rebuild_tail
    fill_current
  end

  def pitcher_id
    @current.first
  end

  def pitcher
    p = pitcher_id
    return nil unless p
    Actor[:"player_#{p}"]
  end

  def prev_pitcher
    return nil unless @prev_pitcher
    Actor[:"player_#{@prev_pitcher}"]
  end

  def next!
    skip!
    while pitcher && pitcher.alive? && !pitcher.online
      skip!
    end
    rebuild_tail
    fill_current
  end

  def skip!
    @prev_pitcher = @current.shift
    fill_current
  end

  def fill_current
    c = (@current + @tail).uniq
    @current = c.first(3)
    if c.size > 3
      @tail = c.last(c.size - 3)
    else
      @tail = []
    end
  end

  def ids
    @current + @tail
  end

  def list
    players = Actor[:"players_#{@game_uuid}"]
    ids.map{|i| players.find(i) }
  end

  def first
    @current.first
  end

  def random_rebuild_tail
    players = Actor[:"players_#{@game_uuid}"]
    lst = players.players.sort_by(&:order)
    lst -= lst.select { |pl| @current.include?(pl.uuid) }
    sortable = lst.map { |item| [item.pitcher_rank.to_f, item.uuid] }
    @tail = Randoms.ranged_shuffle(sortable).map(&:last)
  end

  def rebuild_tail
    state = Actor[:"state_#{@game_uuid}"]
    setting = state.setting
    # return random_rebuild_tail if setting[:random_enabled]
    return random_rebuild_tail
    players = Actor[:"players_#{@game_uuid}"]
    lst = players.players.sort_by(&:order)
    @tail = []
    last_order = Actor[:"player_#{@current.last}"].try(:order)
    last_order ||= 0
    lst.delete_if{|l| self.ids.include?(l.uuid) || l.order.to_i < 1 }
    idx = lst.index{|l| l.order > last_order }
    if idx
      @tail += lst[idx..-1].map(&:uuid)
      lst = lst[0, idx]
      @tail += lst.map(&:uuid)
    else
      @tail = lst.map(&:uuid)
    end

    # (@current + @tail).each{|i| list.delete_if{|s| s.uuid == i } }
    # mx = Actor[:"player_#{@tail.last}"].try(:order)
    # mx ||= Actor[:"player_#{@current.last}"].try(:order)
    # @tail += list.select{|l| l.order.to_i > mx.to_i }.map(&:uuid)
    # (@tail).each{|i| list.delete_if{|s| s.uuid == i } }
    # @tail += list.map(&:uuid)
    # info "size #{ids.size}"
  end

  def index(pl_id)
    # info "queue index #{pl_id.inspect} size #{ids.size}"
    @current.index(pl_id)
  end

end
