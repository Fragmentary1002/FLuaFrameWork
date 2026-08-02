local FIWidget = FClass("FIWidget")

function FIWidget:ctor(id, native, ops)
    self.id = id
    self.native = native
    self.ops = ops
end

function FIWidget:_assert_valid()
    if self.native == nil or self.ops.is_valid() ~= true then
        error(FError:new("NATIVE_OBJECT_INVALID", "native widget is no longer valid", { binding = self.id }), 0)
    end
end

function FIWidget:set_visible(value)
    self:_assert_valid()
    self.ops.set_visible(value == true)
end

return FIWidget
