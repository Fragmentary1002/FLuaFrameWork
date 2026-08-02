local Class = require("LuaUIFramework.Shared.Core.FClass")
local FIWidget = require("LuaUIFramework.Shared.Contracts.FIWidget")
local FIText = Class("FIText", FIWidget)

function FIText:set_text(value)
    self:_assert_valid()
    self.ops.set_text(value == nil and "" or tostring(value))
end

function FIText:get_text()
    self:_assert_valid()
    return self.ops.get_text()
end

return FIText
