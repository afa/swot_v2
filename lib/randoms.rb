module Randoms
  module_function

  def ranged_sample(array) # return index in - or nil when empty array
    return nil if array.empty?
    sum = array.inject(0.0) { |res, item| res + item.first }
    point = rand(sum)
    last = 0.0
    idx = -1
    while point >= last
      idx += 1
      last += array[idx].first
    end
    idx
  end

  def ranged_shuffle(array)
    before = array.dup
    [].tap do |after|
      until before.empty?
        idx = ranged_sample(before)
        after << before.delete_at(idx)
      end
    end
  end
end
