local Class = require("LuaUIFramework.Shared.Core.FClass")
local FIWidget = require("LuaUIFramework.Shared.Contracts.FIWidget")
local FIImage = Class("FIImage", FIWidget)

function FIImage:set_source(source)
    self:_assert_valid()
    self.ops.set_source(source)
end

return FIImage
