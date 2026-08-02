local FCommand = {}
FCommand.__index = FCommand

function FCommand.new(execute, can_execute)
    return setmetatable({
        execute_callback = execute,
        can_execute_callback = can_execute,
    }, FCommand)
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

