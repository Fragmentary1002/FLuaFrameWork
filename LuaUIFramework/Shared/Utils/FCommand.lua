local Class = require("LuaUIFramework.Shared.Core.FClass")
local FCommand = Class("FCommand")

function FCommand:ctor(execute, can_execute)
    self.execute_callback = execute
    self.can_execute_callback = can_execute
end

function FCommand:can_execute(...)
    if self.can_execute_callback == nil then
        return true
    end
    return self.can_execute_callback(...) == true
end

function FCommand:execute(...)
    if not self:can_execute(...) then
        return nil
    end
    return self.execute_callback(...)
end

return FCommand
