local FTestHelper = require("Tests.TestHelper")
local FFakeAssetBackend = require("Tests.Fixtures.FFakeAssetBackend")
local FIAssetLoader = require("FLuaFramework.Shared.Contracts.FAssetLoader.FIAssetLoader")

local manifest = {
    ["avatar/default"] = {
        type = "texture",
        unreal = "/Game/UI/Textures/T_DefaultAvatar",
        unity = "UI/Textures/DefaultAvatar",
    },
}

FTestHelper:test("asset loader resolves refs and returns a releasable handle", function()
    local backend = FFakeAssetBackend:new()
    local loader = FIAssetLoader:new("unreal", manifest, backend)
    local received = nil
    loader:load({ id = "avatar/default", type = "texture" }, function(handle) received = handle end)
    FTestHelper:assert_equal("/Game/UI/Textures/T_DefaultAvatar", backend.pending[1].address)
    backend:complete_next()
    FTestHelper:assert_equal("avatar/default", received:get_id())
    FTestHelper:assert_true(received:release())
    FTestHelper:assert_false(received:release())
    FTestHelper:assert_equal(1, backend.released)
end)

FTestHelper:test("asset request cancellation releases a late success", function()
    local backend = FFakeAssetBackend:new()
    local loader = FIAssetLoader:new("unreal", manifest, backend)
    local callbacks = 0
    local request = loader:load({ id = "avatar/default", type = "texture" }, function()
        callbacks = callbacks + 1
    end)
    FTestHelper:assert_true(request:cancel())
    FTestHelper:assert_false(request:cancel())
    backend:complete_next(true)
    FTestHelper:assert_equal(0, callbacks)
    FTestHelper:assert_equal(1, backend.released)
end)

FTestHelper:test("asset backend failure becomes ASSET_LOAD_FAILED", function()
    local backend = FFakeAssetBackend:new()
    local loader = FIAssetLoader:new("unity", manifest, backend)
    local failure = nil
    loader:load({ id = "avatar/default", type = "texture" }, function() end, function(err)
        failure = err
    end)
    backend:fail_next("missing bundle")
    FTestHelper:assert_equal("ASSET_LOAD_FAILED", failure.code)
    FTestHelper:assert_equal("unity", failure.context.platform)
    FTestHelper:assert_equal("missing bundle", failure.context.cause)
end)

FTestHelper:test("asset loader validates logical IDs and types", function()
    local loader = FIAssetLoader:new("unreal", manifest, FFakeAssetBackend:new())
    FTestHelper:assert_error_code("INVALID_ASSET_REF", function()
        loader:load("avatar/default", function() end)
    end)
    FTestHelper:assert_error_code("ASSET_NOT_REGISTERED", function()
        loader:load({ id = "missing", type = "texture" }, function() end)
    end)
    FTestHelper:assert_error_code("ASSET_TYPE_MISMATCH", function()
        loader:load({ id = "avatar/default", type = "audio" }, function() end)
    end)
end)

FTestHelper:test("asset loader reports an unconfigured backend", function()
    local loader = FIAssetLoader:new("unreal", manifest, nil)
    FTestHelper:assert_error_code("ASSET_BACKEND_NOT_CONFIGURED", function()
        loader:load({ id = "avatar/default", type = "texture" }, function() end)
    end)
end)
