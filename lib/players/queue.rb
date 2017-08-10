require 'randoms'
class Queue
  include Celluloid
  include Celluloid::IO
  include Celluloid::Internals::Logger
  include Celluloid::Notifications

  def initialize(params = {})
    @game_uuid = params[:game_uuid]
    @current = []
    @tail = []
    game = Actor[:"game_#{@game_uuid}"]
    if game.try(:alive?)
      rebuild_tail
      fill_current
    else
      info 'no queue rebuild, game died'
    end
  end

  def log_info
    hsh = {
      base_queue: {
        names: ids.map { |id| Actor[:"player_#{id}"] }.map { |pl| pl && pl.alive? ? pl : nil }.try(:map, &:name),
        scores: ids.map { |id| Actor[:"player_#{id}"] }.map { |pl| pl && pl.alive? ? pl : nil }.try(:map. &:pitcher_score),
        orders: ids.map { |id| Actor[:"player_#{id}"] }.map { |pl| pl && pl.alive? ? pl : nil }.try(:map, &:order)
      },
      tail_queue: {
        names: ids.map { |id| Actor[:"player_#{id}"] }.map { |pl| pl && pl.alive? ? pl : nil }.try(:map, &:name),
        scores: ids.map { |id| Actor[:"player_#{id}"] }.map { |pl| pl && pl.alive? ? pl : nil }.try(:map. &:pitcher_score),
        orders: ids.map { |id| Actor[:"player_#{id}"] }.map { |pl| pl && pl.alive? ? pl : nil }.try(:map, &:order)
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
    skip! while pitcher && pitcher.alive? && !pitcher.online
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
    @tail = if c.size > 3
              c.last(c.size - 3)
            else
              []
            end
  end

  def ids
    @current + @tail
  end

  def list
    players = Actor[:"players_#{@game_uuid}"]
    ids.map { |i| players.find(i) }
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
    return random_rebuild_tail if setting[:random_enabled]
    players = Actor[:"players_#{@game_uuid}"]
    lst = players.players.sort_by(&:order)
    @tail = []
    last_order = Actor[:"player_#{@current.last}"].try(:order)
    last_order ||= 0
    lst.delete_if { |ll| ids.include?(ll.uuid) || ll.order.to_i < 1 }
    idx = lst.index { |ll| ll.order > last_order }
    if idx
      @tail += lst[idx..-1].map(&:uuid)
      lst = lst[0, idx]
      @tail += lst.map(&:uuid)
    else
      @tail = lst.map(&:uuid)
    end
  end

  def index(pl_id)
    @current.index(pl_id)
  end
end
