require 'spec_helper'
require 'statements'
require 'statement'
require 'vote'
require 'players/player'
require 'players/queue'
require 'store'
require 'state'
describe Statement do
  before do
    # @author = instance_double(Player, name: 'aa', uuid: 'aa')
    @author = Player.build name: 'aa', uuid: 'aa'
    @statement = Statement.new value: 'asd', author: @author.uuid
  end
  it 'should be live' do
    expect { @author.gen_state }.not_to raise_error
  end
end

  # def send_start_step
  #   game = Actor[:"game_#{@game_uuid}"]
  #   state = Actor[:"state_#{@game_uuid}"]
  #   queue = Actor[:"queue_#{@game_uuid}"]
  #   players = Actor[:"players_#{@game_uuid}"]
  #   info "::::::ids #{ queue.ids.index(@uuid)}"
  #   msg = {type: 'event', subtype: 'start_step', turn_in: queue.ids.index(@uuid), pitcher_name: queue.pitcher.uglify_name(state.stage), timer: Timings.instance(@game_uuid).next_stamp, step: {current: state.step, total: state.total_steps, status: state.step_status}}
  #   publish_msg msg
  # end

  # def send_end_step params = {}
  #   state = Actor[:"state_#{@game_uuid}"]
  #   # queue = Actor[:"queue_#{@game_uuid}"]
  #   statements = Actor[:"statements_#{@game_uuid}"]
  #   stat = statements.voting
  #   if stat
  #     msg = {type: 'event', subtype: 'end_step', result: {status: params[:status], score: stat.author == @uuid ? @pitcher_rank : @catcher_score, delta: stat.author == @uuid ? 0 : @delta}, timer: Timings.instance(@game_uuid).next_stamp}
  #   else
  #     msg = {type: 'event', subtype: 'end_step', result: {status: params[:status], score: state.prev_pitcher.uuid == @uuid ? @pitcher_rank : @catcher_score, delta: 0.0}, timer: Timings.instance(@game_uuid).next_stamp}
  #   end
  #   publish_msg msg
  # end

  # def send_start_stage
  #   players = Actor[:"players_#{@game_uuid}"]
  #   state = Actor[:"state_#{@game_uuid}"]
  #   game = Actor[:"game_#{@game_uuid}"]
  #   msg = {type: 'event', subtype: 'start_stage', value: game.stage, turn_in: (players.queue.index(@uuid) || 3)}
  #   publish_msg msg
  # end

  # def gen_conclusion
  #   statements = Actor[:"statements_#{@game_uuid}"]
  #   queue = Actor[:"queue_#{@game_uuid}"]
  #   state = Actor[:"state_#{@game_uuid}"]
  #   players = Actor[:"players_#{@game_uuid}"]
  #   pitcher = queue.pitcher.uglify_name(state.stage)
  #   conclusion = {author: pitcher}
  #   if statements.voting
  #     vot = statements.voting
  #     conclusion.merge!(
  #       value: vot.value,
  #       author: vot.author.uglify_name(state.stage),
  #       to_replace: vot.replaces,
  #       status: vot.status,
  #       player_score: 0.0,
  #       players_voted: (100.0 * vot.votes.voted_count.to_f / (players.players.size - 1).to_f).to_i
  #     )
  #   end
  #   conclusion
  # end

  # def gen_state params = {}
  #   game = Actor[:"game_#{@game_uuid}"]
  #   players = Actor[:"players_#{@game_uuid}"]
  #   state = Actor[:"state_#{@game_uuid}"]
  #   statements = Actor[:"statements_#{@game_uuid}"]
    
  #   info "current all statements #{statements.mapped_current}"
  #   info "current statements #{statements.active_js}"
  #   msg = {
  #     type: 'status',
  #     state: state.state,
  #     game: {
  #       time: current_stamp,
  #       step: {
  #         current: game.step,
  #         total: game.total_steps,
  #         status: game.step_status
  #       },
  #       current_stage: game.stage, # one of stages
  #       conclusion: gen_conclusion,
  #       replaces: [],
  #       statements: statements.active_js,
  #       player: {
  #         turn_in: (players.queue.index(@uuid) || 3)
  #       },

  #       started_at: Timings::Start.instance(@game_uuid).at,
  #       timeout_at: Timings.instance(@game_uuid).next_stamp
  #     },
  #   }
  # end

