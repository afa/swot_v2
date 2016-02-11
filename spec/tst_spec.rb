class Foo
  include Celluloid
  def enabled?
    false
  end

  def do_work
    if enabled?
      do_stuff
    else
      do_other_stuff
    end
  end
end

describe Foo do
  describe "#do_work" do
    # this test hangs
    it "do stuff when enabled" do
      f = Foo.new
      f.stub(:enabled?) { true }
      f.should_receive(:do_stuff)
      f.do_work
    end

    # approach that's working for me (instance_eval on the #wrapped_object)
    it "do stuff when enabled" do
      f = Foo.new
      f.wrapped_object.instance_eval do
        def enabled?
          true
        end
      end
      f.should_receive(:do_stuff)
      f.do_work
    end
  end
end
