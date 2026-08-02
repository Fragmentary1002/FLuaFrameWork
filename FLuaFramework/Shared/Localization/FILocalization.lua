local FILocalization = FClass("FILocalization")

function FILocalization:ctor(options)
    self.locale = options.locale
    self.fallback = options.fallback
    self.catalogs = options.catalogs or {}
    self.logger = options.logger
    self.listeners = {}
end

function FILocalization:get_locale()
    return self.locale
end

function FILocalization:set_locale(locale)
    if self.catalogs[locale] == nil then
        error(FError:new("LOCALE_NOT_REGISTERED", "locale is not registered", {
            locale = locale,
        }), 0)
    end
    if locale == self.locale then return false end
    self.locale = locale
    local snapshot = {}
    for _, callback in pairs(self.listeners) do table.insert(snapshot, callback) end
    for _, callback in ipairs(snapshot) do callback(locale) end
    return true
end

function FILocalization:on_locale_changed(callback)
    local token = {}
    self.listeners[token] = callback
    local active = true
    return {
        unsubscribe = function()
            if not active then return false end
            active = false
            self.listeners[token] = nil
            return true
        end,
    }
end

function FILocalization:t(key, params)
    local current = self.catalogs[self.locale] or {}
    local fallback = self.catalogs[self.fallback] or {}
    local template = current[key] or fallback[key]
    if template == nil then
        if self.logger ~= nil then
            self.logger:warn("localization key missing", {
                key = key,
                locale = self.locale,
                fallback = self.fallback,
            })
        end
        return "[" .. tostring(key) .. "]"
    end
    local rendered = string.gsub(template, "{([%w_]+)}", function(name)
        local value = params and params[name] or nil
        if value == nil then
            error(FError:new(
                "LOCALIZATION_PARAM_MISSING",
                "localization parameter is missing",
                { key = key, parameter = name, locale = self.locale }
            ), 0)
        end
        return tostring(value)
    end)
    return rendered
end

return FILocalization
