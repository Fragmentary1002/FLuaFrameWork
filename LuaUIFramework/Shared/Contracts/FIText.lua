local FIWidget = require("LuaUIFramework.Shared.Contracts.FIWidget")
local FIText = {}
FIText.__index = FIText
setmetatable(FIText, { __index = FIWidget })

function FIText.new(id, native, ops)
    return setmetatable(FIWidget.new(id, native, ops), FIText)
end

function FIText:set_text(value)
    self:_assert_valid()
    self.ops.set_text(value == nil and "" or tostring(value))
end

function FIText:get_text()
    self:_assert_valid()
    return self.ops.get_text()
end

return FIText
