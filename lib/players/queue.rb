class Queue
  include Celluloid
  include Celluloid::Internals::Logger

  def initialize params = {}
    @game_uuid = params[:game_uuid]
    @current = []
    @tail = []
    game = Actor[:"game_#{@game_uuid}"]
    if game.try(:alive?)
      list = game.players.players.sort_by(&:order)
      3.times do
        p = list.shift
        @current << p.uuid if p
      end
      @tail += list
    end
  end

  def pitcher
    @current.first
  end

  def next!
    skip!
    rebuild_tail
  end

  def skip!
    @current.shift
    fill_current
  end

  def fill_current
    (3 - @current.size).times do
      p = @tail.shift
      @current << p if p
    end
  end

  def rebuild_tail
    game = Actor[:"game_#{@game_uuid}"]
    list = game.players.players.sort_by(&:order)
    list -= @current + @tail
    mx = @tail.last.try(:order)
    @tail += list.select{|l| l.order > mx }
    list -= @tail
    @tail += list
  end
end
