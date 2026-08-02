local FIWidget = require("LuaUIFramework.Shared.Contracts.FIWidget")
local FIImage = {}
FIImage.__index = FIImage
setmetatable(FIImage, { __index = FIWidget })

function FIImage.new(id, native, ops)
    return setmetatable(FIWidget.new(id, native, ops), FIImage)
end

function FIImage:set_source(source)
    self:_assert_valid()
    self.ops.set_source(source)
end

return FIImage
