local FTestHelper = require("Tests.TestHelper")
local FFakeRuntime = require("Tests.Fixtures.FFakeRuntime")

local StatePresenter = FClass("StatePresenter", FBasePresenter)

function StatePresenter:ctor()
    self.value = nil
    self.restored = nil
    self.saved = { value = nil, nested = { count = 1 } }
end

function StatePresenter:on_save_state()
    self.saved.value = self.value
    return self.saved
end

function StatePresenter:on_restore_state(state)
    self.restored = state
    self.saved = state
    self.value = state.value
end

local function page(asset)
    return {
        presenter = "StatePresenter",
        singleton = true,
        layer = "Normal",
        assets = { test = asset },
        requiredBindings = {},
    }
end

local function make_system()
    local runtime = FFakeRuntime:new("test")
    local manager = FUIManager:new({
        runtime = runtime,
        layers = { Normal = { order = 200, blocksInput = false } },
        pages = { Main = page("main"), Detail = page("detail") },
        require_module = function() return StatePresenter end,
    })
    return manager, FUIRouter:new(manager), runtime
end

FTestHelper:test("manager captures presenter state only after creation", function()
    local manager, _, runtime = make_system()
    manager:open("Main")
    FTestHelper:assert_nil(manager:capture_state("Main"))
    runtime:complete_next()
    manager:get("Main").presenter.value = "ready"
    FTestHelper:assert_equal("ready", manager:capture_state("Main").value)
end)

FTestHelper:test("router snapshot is isolated from presenter tables", function()
    local manager, router, runtime = make_system()
    router:push("Main", { source = "boot" })
    runtime:complete_next()
    manager:get("Main").presenter.value = "saved"
    local snapshot = router:snapshot()
    snapshot.routes[1].state.nested.count = 9
    FTestHelper:assert_equal(1, manager:capture_state("Main").nested.count)
end)

FTestHelper:test("router restores route params visibility and presenter state", function()
    local manager, router, runtime = make_system()
    router:push("Main", { source = "boot" })
    runtime:complete_next()
    manager:get("Main").presenter.value = "main-state"
    router:push("Detail", { id = 7 })
    runtime:complete_next()
    manager:get("Detail").presenter.value = "detail-state"
    local snapshot = router:snapshot()

    router:restore(snapshot)
    runtime:complete_next()
    runtime:complete_next()

    FTestHelper:assert_equal("Hidden", manager:get("Main").lifecycle:get_state())
    FTestHelper:assert_equal("Opened", manager:get("Detail").lifecycle:get_state())
    FTestHelper:assert_equal("main-state", manager:get("Main").presenter.restored.value)
    FTestHelper:assert_equal("detail-state", manager:get("Detail").presenter.restored.value)
    FTestHelper:assert_equal(7, router:current().params.id)
end)

FTestHelper:test("router rejects invalid snapshots before mutating current history", function()
    local _, router, runtime = make_system()
    router:push("Main")
    runtime:complete_next()
    FTestHelper:assert_error_code("INVALID_ROUTE_SNAPSHOT", function()
        router:restore({ version = 2, routes = {} })
    end)
    FTestHelper:assert_equal("Main", router:current().page)
end)
