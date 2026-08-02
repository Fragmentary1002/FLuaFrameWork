local FIWidget = require("LuaUIFramework.Shared.Contracts.FIWidget")
local FIButton = {}
FIButton.__index = FIButton
setmetatable(FIButton, { __index = FIWidget })

function FIButton.new(id, native, ops)
    return setmetatable(FIWidget.new(id, native, ops), FIButton)
end

function FIButton:on_click(callback)
    self:_assert_valid()
    return self.ops.on_click(callback)
end

return FIButton
