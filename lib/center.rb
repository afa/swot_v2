class Center
  def initialize
    def @control = Control.new
  end

  def run
    @control.async.run
    p 'ce-ok'
  end
end
