local FError = {}
FError.__index = FError

function FError.new(code, message, context)
    return setmetatable({
        code = code,
        message = message,
        context = context,
    }, FError)
end

function FError:__tostring()
    return string.format("[%s] %s", tostring(self.code), tostring(self.message))
end

return FError

