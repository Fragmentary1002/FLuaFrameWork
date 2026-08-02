local FError = FClass("FError")

function FError:ctor(code, message, context)
    self.code = code
    self.message = message
    self.context = context
end

function FError:__tostring()
    return string.format("[%s] %s", tostring(self.code), tostring(self.message))
end

function FError:to_table()
    local context = {}
    for key, value in pairs(self.context or {}) do context[key] = value end
    return { code = self.code, message = self.message, context = context }
end

return FError
