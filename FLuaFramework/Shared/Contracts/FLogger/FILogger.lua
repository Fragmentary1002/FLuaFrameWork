local FILogger = FClass("FILogger")

local function merge(...)
    local result = {}
    for index = 1, select("#", ...) do
        local source = select(index, ...)
        if source ~= nil then
            for key, value in pairs(source) do result[key] = value end
        end
    end
    return result
end

function FILogger:ctor(platform, sink, base_context)
    self.platform = platform
    self.sink = sink or function() end
    self.base_context = merge(base_context)
end

function FILogger:with_context(context)
    return FILogger:new(self.platform, self.sink, merge(self.base_context, context))
end

function FILogger:log(level, message, context)
    local record = merge(self.base_context, context)
    record.level = level
    record.message = tostring(message)
    record.platform = self.platform
    self.sink(record)
    return record
end

function FILogger:debug(message, context) return self:log("debug", message, context) end
function FILogger:info(message, context) return self:log("info", message, context) end
function FILogger:warn(message, context) return self:log("warn", message, context) end

function FILogger:error(failure, context)
    local merged = merge(context, { traceback = debug.traceback("", 2) })
    if type(failure) == "table" and failure.code ~= nil then
        merged = merge(failure.context, merged, { errorCode = failure.code })
        return self:log("error", failure.message, merged)
    end
    return self:log("error", tostring(failure), merged)
end

return FILogger
