local Class = require("LuaUIFramework.Shared.Core.FClass")
local FError = Class("FError")

function FError:ctor(code, message, context)
    self.code = code
    self.message = message
    self.context = context
end

function FError:__tostring()
    return string.format("[%s] %s", tostring(self.code), tostring(self.message))
end

return FError
