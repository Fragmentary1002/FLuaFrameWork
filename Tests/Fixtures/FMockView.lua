local FClass = require("FLuaFramework.Shared.Core.FClass")
local FMockView = FClass("FMockView")

local factories = {
    Text = function(...) return FIText:new(...) end,
    Button = function(...) return FIButton:new(...) end,
    Image = function(...) return FIImage:new(...) end,
    Input = function(...) return FIInput:new(...) end,
    Toggle = function(...) return FIToggle:new(...) end,
    Progress = function(...) return FIProgress:new(...) end,
}

local function subscription(widget, field, callback)
    widget[field] = callback
    local active = true
    return { unsubscribe = function()
        if active then
            active = false
            widget[field] = nil
        end
    end }
end

function FMockView:ctor(required_bindings)
    self.native = { valid = true, visible = false, widgets = {} }
    local entries = {}
    for id, kind in pairs(required_bindings) do
        local widget = {
            id = id,
            kind = kind,
            valid = true,
            visible = true,
            text = "",
            source = nil,
            checked = false,
            value = 0,
        }
        self.native.widgets[id] = widget
        local ops = {
            is_valid = function() return widget.valid end,
            set_visible = function(value) widget.visible = value end,
            set_text = function(value) widget.text = value end,
            get_text = function() return widget.text end,
            set_source = function(value) widget.source = value end,
            on_click = function(callback) return subscription(widget, "click", callback) end,
            on_changed = function(callback) return subscription(widget, "changed", callback) end,
            set_checked = function(value) widget.checked = value end,
            is_checked = function() return widget.checked end,
            set_value = function(value) widget.value = value end,
            get_value = function() return widget.value end,
        }
        entries[id] = { kind = kind, widget = factories[kind](id, widget, ops) }
    end
    self.view = FIView:new("MockPage", "mock", self.native, {
        is_valid = function() return self.native.valid end,
        set_visible = function(value) self.native.visible = value end,
        destroy = function()
            self.native.valid = false
            for _, widget in pairs(self.native.widgets) do
                widget.valid = false
                widget.click = nil
                widget.changed = nil
            end
        end,
    }, entries)
end

function FMockView:get(id)
    return self.native.widgets[id]
end

function FMockView:click(id)
    local callback = self:get(id).click
    if callback ~= nil then callback() end
end

function FMockView:change(id, value)
    local widget = self:get(id)
    if widget.kind == "Input" then widget.text = value == nil and "" or tostring(value) end
    if widget.kind == "Toggle" then widget.checked = value == true end
    if widget.changed ~= nil then widget.changed(value) end
end

return FMockView
