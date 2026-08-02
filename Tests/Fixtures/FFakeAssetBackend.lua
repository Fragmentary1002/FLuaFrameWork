local FClass = require("FLuaFramework.Shared.Core.FClass")
local FFakeAssetBackend = FClass("FFakeAssetBackend")

function FFakeAssetBackend:ctor()
    self.pending = {}
    self.released = 0
end

function FFakeAssetBackend:load(address, asset_type, on_success, on_error)
    local pending = {
        address = address, asset_type = asset_type,
        on_success = on_success, on_error = on_error, cancelled = false,
    }
    table.insert(self.pending, pending)
    return { cancel = function() pending.cancelled = true end }
end

function FFakeAssetBackend:complete_next(deliver_cancelled)
    local pending = table.remove(self.pending, 1)
    if pending ~= nil and (not pending.cancelled or deliver_cancelled == true) then
        pending.on_success({ address = pending.address, type = pending.asset_type, valid = true })
    end
end

function FFakeAssetBackend:fail_next(cause)
    local pending = table.remove(self.pending, 1)
    if pending ~= nil and not pending.cancelled then pending.on_error(cause) end
end

function FFakeAssetBackend:release(asset)
    if asset.valid then
        asset.valid = false
        self.released = self.released + 1
    end
end

return FFakeAssetBackend
