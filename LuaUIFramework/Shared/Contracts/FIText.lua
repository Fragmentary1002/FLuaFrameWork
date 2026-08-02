local FIText = FClass("FIText", FIWidget)

function FIText:set_text(value)
    self:_assert_valid()
    self.ops.set_text(value == nil and "" or tostring(value))
end

function FIText:get_text()
    self:_assert_valid()
    return self.ops.get_text()
end

return FIText
