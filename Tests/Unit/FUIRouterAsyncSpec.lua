local FTestHelper = require("Tests.TestHelper")
local FFakeRuntime = require("Tests.Fixtures.FFakeRuntime")

local Presenter = FClass("AsyncRoutePresenter", FBasePresenter)

local function page(asset)
    return {
        presenter = "AsyncRoutePresenter",
        singleton = true,
        layer = "Normal",
        assets = { test = asset },
        requiredBindings = {},
    }
end

FTestHelper:test("router can push again before the current route finishes loading", function()
    local runtime = FFakeRuntime:new("test")
    local manager = FUIManager:new({
        runtime = runtime,
        layers = { Normal = { order = 200, blocksInput = false } },
        pages = { Main = page("main"), Detail = page("detail") },
        require_module = function() return Presenter end,
    })
    local router = FUIRouter:new(manager)

    router:push("Main")
    router:push("Detail")
    runtime:complete_next()
    runtime:complete_next()

    FTestHelper:assert_equal("Hidden", manager:get("Main").lifecycle:get_state())
    FTestHelper:assert_equal("Opened", manager:get("Detail").lifecycle:get_state())
    FTestHelper:assert_true(router:back())
    FTestHelper:assert_equal("Opened", manager:get("Main").lifecycle:get_state())
end)
