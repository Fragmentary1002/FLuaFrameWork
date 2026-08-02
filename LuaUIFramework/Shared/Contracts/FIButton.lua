local FIButton = FClass("FIButton", FIWidget)

function FIButton:on_click(callback)
    self:_assert_valid()
    return self.ops.on_click(callback)
end

return FIButton
