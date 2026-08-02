local FTestHelper = require("Tests.TestHelper")

FTestHelper:test("register exposes every framework module as a global", function()
    local registered = require("FLuaFramework.register")
    local expected_names = {
        "FClass", "FError", "FBasePresenter", "FLifecycle", "FUIManager",
        "FIWidget", "FIText", "FIButton", "FIImage", "FIView",
        "FEventBus", "FStore", "FCommand", "FValidation", "FViewBinder",
        "FUnrealRuntime", "FUnityRuntime",
    }

    for _, name in ipairs(expected_names) do
        FTestHelper:assert_not_nil(registered[name])
        FTestHelper:assert_equal(registered[name], _G[name])
    end
end)

FTestHelper:test("register returns the same table when required twice", function()
    local first = require("FLuaFramework.register")
    local second = require("FLuaFramework.register")
    FTestHelper:assert_equal(first, second)
end)
