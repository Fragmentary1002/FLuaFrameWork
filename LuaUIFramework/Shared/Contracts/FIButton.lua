local Class = require("LuaUIFramework.Shared.Core.FClass")
local FIWidget = require("LuaUIFramework.Shared.Contracts.FIWidget")
local FIButton = Class("FIButton", FIWidget)

function FIButton:on_click(callback)
    self:_assert_valid()
    return self.ops.on_click(callback)
end

return FIButton
