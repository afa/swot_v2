require 'spec_helper'
require 'statement'
require 'vote'

describe Statement do
  describe '#initialize' do
    it 'should build' do
      expect(Statement.new).not_to be_nil
    end
  end
end

describe 'votes' do
  before do
    @stat = Statement.new author: '1', value: 'st', game_uuid: 'gm'
  end
  describe 'conclusion' do
    it 'should calc conclusion on empty' do
      expect(@stat.conclusion).to eq('no_votes')
    end
    it 'should calc conclusion for 1 accepted' do
      @stat.vote({player: '2', result: 'accepted'})
      expect(@stat.conclusion).to eq('accepted')
    end
    it 'should calc conclusion for 1 accepted and 1 declined' do
      @stat.vote({player: '2', result: 'accepted'})
      @stat.vote({player: '3', result: 'declined'})
      expect(@stat.conclusion).to eq('accepted')
    end
    it 'should calc conclusion for 1 accepted and 2 declined' do
      @stat.vote({player: '2', result: 'accepted'})
      @stat.vote({player: '3', result: 'declined'})
      @stat.vote({player: '4', result: 'declined'})
      expect(@stat.conclusion).to eq('declined')
    end
  end
  it 'should decline nonvoted' do
    expect(@stat.result).to eq('declined')
  end
  it 'should decline one declined vote' do
    expect(@stat.result).to eq('declined')
  end

  describe 'add votes' do
    before do
      @stat.vote({player: '2', result: 'accepted'})
    end
    it 'should accept one accepted vote' do
      expect(@stat.result).to eq('accepted')
    end

    it 'should accept 2 accepted votes' do
      @stat.vote({player: '3', result: 'accepted'})
      expect(@stat.result).to eq('accepted')
    end

    it 'should accept 1 accepted and 1 declined votes' do
      @stat.vote({player: '3', result: 'declined'})
      expect(@stat.result).to eq('accepted')
    end

    it 'should decline 1 accepted and 2 declined votes' do
      @stat.vote({player: '3', result: 'declined'})
      @stat.vote({player: '4', result: 'declined'})
      expect(@stat.result).to eq('declined')
    end
  end
end




# class Foo
#   include Celluloid
#   def enabled?
#     false
#   end

#   def do_work
#     if enabled?
#       do_stuff
#     else
#       do_other_stuff
#     end
#   end
# end

# describe Foo do
#   describe "#do_work" do
#     # this test hangs
#     it "do stuff when enabled" do
#       f = Foo.new
#       f.stub(:enabled?) { true }
#       f.should_receive(:do_stuff)
#       f.do_work
#     end

#     # approach that's working for me (instance_eval on the #wrapped_object)
#     it "do stuff when enabled" do
#       f = Foo.new
#       f.wrapped_object.instance_eval do
#         def enabled?
#           true
#         end
#       end
#       f.should_receive(:do_stuff)
#       f.do_work
#     end
#   end
# end
