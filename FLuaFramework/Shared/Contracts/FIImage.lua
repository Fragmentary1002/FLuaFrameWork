local FIImage = FClass("FIImage", FIWidget)

function FIImage:set_source(source)
    self:_assert_valid()
    self.ops.set_source(source)
end

return FIImage
