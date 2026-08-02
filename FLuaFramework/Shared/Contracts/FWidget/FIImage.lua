local FIImage = FClass("FIImage", FIWidget)

function FIImage:set_source(source)
    self:_assert_valid()
    if type(source) == "table" and FAssetHandle:is_instance(source) then
        source = source:_native_for_adapter()
    end
    self.ops.set_source(source)
end

return FIImage
