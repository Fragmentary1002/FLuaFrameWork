local FStore = FClass("FStore")

function FStore:ctor(initial_values)
    self.values = {}
    for key, value in pairs(initial_values or {}) do
        self.values[key] = value
    end
    self.subscribers = {}
end

function FStore:get(key)
    return self.values[key]
end

function FStore:set(key, value)
    local old_value = self.values[key]
    if old_value == value then
        return value
    end

    self.values[key] = value
    local key_subscribers = self.subscribers[key]
    if key_subscribers ~= nil then
        local snapshot = {}
        for index, subscriber in ipairs(key_subscribers) do
            snapshot[index] = subscriber
        end
        for _, subscriber in ipairs(snapshot) do
            if subscriber.active then
                subscriber.callback(value, old_value, key)
            end
        end
    end

    return value
end

function FStore:update(key, updater)
    return self:set(key, updater(self:get(key)))
end

function FStore:subscribe(key, callback)
    local key_subscribers = self.subscribers[key]
    if key_subscribers == nil then
        key_subscribers = {}
        self.subscribers[key] = key_subscribers
    end

    local subscriber = {
        active = true,
        callback = callback,
    }
    table.insert(key_subscribers, subscriber)

    local subscription = {}
    function subscription:unsubscribe()
        if not self._subscriber.active then
            return
        end
        self._subscriber.active = false
        for index, candidate in ipairs(self._subscribers) do
            if candidate == self._subscriber then
                table.remove(self._subscribers, index)
                break
            end
        end
    end
    subscription._subscriber = subscriber
    subscription._subscribers = key_subscribers
    return subscription
end

return FStore
