local FIAssetLoader = FClass("FIAssetLoader")

local function raise(code, message, context)
    error(FError:new(code, message, context), 0)
end

function FIAssetLoader:ctor(platform, manifest, backend, logger)
    self.platform = platform
    self.manifest = manifest or {}
    self.backend = backend
    self.logger = logger
end

function FIAssetLoader:load(asset_ref, on_success, on_error)
    if type(asset_ref) ~= "table" or type(asset_ref.id) ~= "string" or type(asset_ref.type) ~= "string" then
        raise("INVALID_ASSET_REF", "asset ref must contain string id and type", { assetRef = asset_ref })
    end
    if self.backend == nil then
        raise("ASSET_BACKEND_NOT_CONFIGURED", "asset backend was not injected", {
            assetId = asset_ref.id, platform = self.platform,
        })
    end
    local definition = self.manifest[asset_ref.id]
    if definition == nil then
        raise("ASSET_NOT_REGISTERED", "logical asset is not registered", { assetId = asset_ref.id })
    end
    if definition.type ~= asset_ref.type then
        raise("ASSET_TYPE_MISMATCH", "asset ref type does not match manifest", {
            assetId = asset_ref.id, expected = definition.type, actual = asset_ref.type,
        })
    end
    local address = definition[self.platform]
    if address == nil then
        raise("ASSET_LOAD_FAILED", "asset has no address for the active platform", {
            assetId = asset_ref.id, assetType = asset_ref.type, platform = self.platform,
        })
    end

    local state = { active = true, native_request = nil }
    local request = {}
    function request:cancel()
        if not state.active then return false end
        state.active = false
        if state.native_request ~= nil then state.native_request:cancel() end
        return true
    end

    state.native_request = self.backend:load(address, asset_ref.type, function(native_asset)
        if not state.active then
            self.backend:release(native_asset, asset_ref.type)
            return
        end
        state.active = false
        on_success(FAssetHandle:new(asset_ref, native_asset, function(asset, asset_type)
            self.backend:release(asset, asset_type)
        end))
    end, function(cause)
        if not state.active then return end
        state.active = false
        local failure = FError:new("ASSET_LOAD_FAILED", "asset backend load failed", {
            assetId = asset_ref.id, assetType = asset_ref.type,
            platform = self.platform, address = address, cause = tostring(cause),
        })
        if self.logger ~= nil then self.logger:error(failure) end
        if on_error ~= nil then on_error(failure) else error(failure, 0) end
    end)
    return request
end

return FIAssetLoader
