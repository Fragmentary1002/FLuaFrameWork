local FIView = FClass("FIView")

function FIView:ctor(page, platform, native, root_ops, widgets)
    self.page = page
    self.platform = platform
    self.native = native
    self.root_ops = root_ops
    self.widgets = widgets
    self.destroyed = false
end

function FIView:_assert_valid()
    if self.destroyed or self.native == nil or self.root_ops.is_valid() ~= true then
        error(FError:new("NATIVE_OBJECT_INVALID", "native view is no longer valid", {
            page = self.page, platform = self.platform,
        }), 0)
    end
end

function FIView:_get(id, expected)
    self:_assert_valid()
    local entry = self.widgets[id]
    if entry == nil or entry.kind ~= expected then
        error(FError:new("BINDING_TYPE_MISMATCH", "view binding was requested with the wrong type", {
            page = self.page, platform = self.platform, binding = id,
            expected = expected, actual = entry and entry.kind or nil,
        }), 0)
    end
    return entry.widget
end

function FIView:text(id) return self:_get(id, "Text") end
function FIView:button(id) return self:_get(id, "Button") end
function FIView:image(id) return self:_get(id, "Image") end

function FIView:set_visible(value)
    self:_assert_valid()
    self.root_ops.set_visible(value == true)
end

function FIView:destroy()
    if self.destroyed then return end
    self.destroyed = true
    self.root_ops.destroy()
    self.native = nil
end

return FIView
