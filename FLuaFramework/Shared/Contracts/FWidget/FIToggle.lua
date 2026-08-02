local FIToggle = FClass("FIToggle", FIWidget)

function FIToggle:set_checked(value)
    self:_assert_valid()
    self.ops.set_checked(value == true)
end

function FIToggle:is_checked()
    self:_assert_valid()
    return self.ops.is_checked() == true
end

function FIToggle:on_changed(callback)
    self:_assert_valid()
    return self.ops.on_changed(callback)
end

return FIToggle
