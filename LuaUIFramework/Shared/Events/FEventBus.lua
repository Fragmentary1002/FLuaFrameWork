local FError = require("LuaUIFramework.Shared.Core.FError")

local FEventBus = {}
FEventBus.__index = FEventBus

function FEventBus.new()
    return setmetatable({
        listeners = {},
    }, FEventBus)
end

local function remove_binding(bus, binding)
    if not binding.active then
        return
    end

    binding.active = false
    local event_listeners = bus.listeners[binding.event_name]
    if event_listeners == nil then
        return
    end

    for index, candidate in ipairs(event_listeners) do
        if candidate == binding then
            table.remove(event_listeners, index)
            break
        end
    end

    if #event_listeners == 0 then
        bus.listeners[binding.event_name] = nil
    end
end

function FEventBus:subscribe(event_name, callback, owner)
    local event_listeners = self.listeners[event_name]
    if event_listeners == nil then
        event_listeners = {}
        self.listeners[event_name] = event_listeners
    end

    for _, binding in ipairs(event_listeners) do
        if binding.active and binding.callback == callback and binding.owner == owner then
            error(FError.new(
                "DUPLICATE_EVENT_BINDING",
                "the callback is already subscribed to this event for the same owner",
                { event_name = event_name, owner = owner }
            ), 0)
        end
    end

    local binding = {
        active = true,
        event_name = event_name,
        callback = callback,
        owner = owner,
    }
    table.insert(event_listeners, binding)

    local subscription = {}
    function subscription:unsubscribe()
        remove_binding(self._bus, self._binding)
    end
    subscription._bus = self
    subscription._binding = binding
    return subscription
end

function FEventBus:emit(event_name, ...)
    local event_listeners = self.listeners[event_name]
    if event_listeners == nil then
        return
    end

    local snapshot = {}
    for index, binding in ipairs(event_listeners) do
        snapshot[index] = binding
    end

    for _, binding in ipairs(snapshot) do
        if binding.active then
            binding.callback(...)
        end
    end
end

function FEventBus:unsubscribe_owner(owner)
    local owned_bindings = {}
    for _, event_listeners in pairs(self.listeners) do
        for _, binding in ipairs(event_listeners) do
            if binding.active and binding.owner == owner then
                table.insert(owned_bindings, binding)
            end
        end
    end

    for _, binding in ipairs(owned_bindings) do
        remove_binding(self, binding)
    end
end

return FEventBus

