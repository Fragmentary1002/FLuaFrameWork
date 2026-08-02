local FIInput = FClass("FIInput", FIWidget)

function FIInput:set_text(value)
    self:_assert_valid()
    self.ops.set_text(value == nil and "" or tostring(value))
end

function FIInput:get_text()
    self:_assert_valid()
    return self.ops.get_text()
end

function FIInput:on_changed(callback)
    self:_assert_valid()
    return self.ops.on_changed(callback)
end

return FIInput
