local FError = require("LuaUIFramework.Shared.Core.FError")

local FLifecycle = {}
FLifecycle.__index = FLifecycle

local transitions = {
    Unloaded = { Loading = true },
    Loading = { Created = true, Unloaded = true },
    Created = { Opened = true, Closing = true },
    Opened = { Hidden = true, Closing = true },
    Hidden = { Opened = true, Closing = true },
    Closing = { Hidden = true, Destroyed = true },
    Destroyed = {},
}

function FLifecycle.new()
    return setmetatable({ state = "Unloaded" }, FLifecycle)
end

function FLifecycle:get_state()
    return self.state
end

function FLifecycle:transition_to(next_state)
    if transitions[self.state] == nil or transitions[self.state][next_state] ~= true then
        error(FError.new(
            "INVALID_LIFECYCLE_TRANSITION",
            string.format("cannot transition page lifecycle from %s to %s", self.state, tostring(next_state)),
            { from = self.state, to = next_state }
        ), 0)
    end
    self.state = next_state
    return next_state
end

return FLifecycle
