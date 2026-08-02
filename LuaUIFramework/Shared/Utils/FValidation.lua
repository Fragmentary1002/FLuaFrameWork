local Class = require("LuaUIFramework.Shared.Core.FClass")
local FValidation = Class("FValidation")

function FValidation:required(message)
    return function(value)
        if value == nil or value == "" then
            return false, message
        end
        return true
    end
end

function FValidation:min_length(minimum, message)
    return function(value)
        if type(value) ~= "string" or #value < minimum then
            return false, message
        end
        return true
    end
end

function FValidation:combine(...)
    local validators = { ... }
    return function(value)
        for _, validator in ipairs(validators) do
            local valid, message = validator(value)
            if not valid then
                return false, message
            end
        end
        return true
    end
end

return FValidation
