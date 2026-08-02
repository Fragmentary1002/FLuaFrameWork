local FIProgress = FClass("FIProgress", FIWidget)

function FIProgress:set_value(value)
    self:_assert_valid()
    if type(value) ~= "number" or value < 0 or value > 1 then
        error(FError:new("INVALID_PROGRESS_VALUE", "progress value must be a number between 0 and 1", {
            binding = self.id,
            value = value,
        }), 0)
    end
    self.ops.set_value(value)
end

function FIProgress:get_value()
    self:_assert_valid()
    return self.ops.get_value()
end

return FIProgress
