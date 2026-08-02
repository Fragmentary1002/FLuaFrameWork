local FAssetHandle = FClass("FAssetHandle")

function FAssetHandle:ctor(asset_ref, native_asset, release_native)
    self.asset_ref = { id = asset_ref.id, type = asset_ref.type }
    self.native_asset = native_asset
    self.release_native = release_native
    self.released = false
end

function FAssetHandle:get_id() return self.asset_ref.id end
function FAssetHandle:get_type() return self.asset_ref.type end
function FAssetHandle:is_released() return self.released end

function FAssetHandle:_native_for_adapter()
    if self.released then
        error(FError:new("NATIVE_OBJECT_INVALID", "asset handle has been released", {
            assetId = self.asset_ref.id, assetType = self.asset_ref.type,
        }), 0)
    end
    return self.native_asset
end

function FAssetHandle:release()
    if self.released then return false end
    self.released = true
    self.release_native(self.native_asset, self.asset_ref.type)
    self.native_asset = nil
    return true
end

return FAssetHandle
