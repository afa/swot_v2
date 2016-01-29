module Hashing
  def as_json(*vars)
    v = instance_variables.inject({}){|r, i| r.merge(instance_variable_get(i)) }
    v.merge(vars.inject({}){|r, i| r.merge(i => send(i)) })
  end
end
