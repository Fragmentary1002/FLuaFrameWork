local FTestHelper = require("Tests.TestHelper")
local FUIRouter = require("FLuaFramework.Shared.Core.FUIRouter")

local function make_manager()
    local manager = {
        pages = {
            LoginPanel = { singleton = true, layer = "Normal" },
            MainPanel = { singleton = true, layer = "Normal" },
            SettingsPanel = { singleton = true, layer = "Normal" },
            ConfirmDialog = { singleton = true, layer = "Modal" },
        },
        calls = {}, opened = {}, fail_page = nil,
    }
    function manager:open(page, params)
        table.insert(self.calls, "open:" .. page)
        if page == self.fail_page then
            error(FError:new("ASSET_LOAD_FAILED", "failed", { page = page }), 0)
        end
        self.opened[page] = { params = params }
        return self.opened[page]
    end
    function manager:close(page)
        table.insert(self.calls, "close:" .. page)
        self.opened[page] = nil
        return true
    end
    function manager:hide(page)
        table.insert(self.calls, "hide:" .. page)
        return self.opened[page] ~= nil
    end
    function manager:show(page)
        table.insert(self.calls, "show:" .. page)
        return self.opened[page] ~= nil
    end
    function manager:get(page) return self.opened[page] end
    return manager
end

FTestHelper:test("router push and back preserve history", function()
    local manager, router = make_manager(), nil
    router = FUIRouter:new(manager)
    router:push("LoginPanel")
    router:push("MainPanel")
    FTestHelper:assert_equal("MainPanel", router:current().page)
    FTestHelper:assert_true(router:back("done"))
    FTestHelper:assert_equal("LoginPanel", router:current().page)
end)

FTestHelper:test("router replace removes the current entry", function()
    local manager = make_manager()
    local router = FUIRouter:new(manager)
    router:push("LoginPanel")
    router:replace("MainPanel")
    FTestHelper:assert_equal(1, #router:get_stack())
    FTestHelper:assert_equal("MainPanel", router:current().page)
end)

FTestHelper:test("router reset installs one root route", function()
    local manager = make_manager()
    local router = FUIRouter:new(manager)
    router:push("LoginPanel")
    router:push("MainPanel")
    router:reset("SettingsPanel")
    FTestHelper:assert_equal(1, #router:get_stack())
    FTestHelper:assert_equal("SettingsPanel", router:current().page)
end)

FTestHelper:test("router present opens Modal without changing history", function()
    local manager = make_manager()
    local router = FUIRouter:new(manager)
    router:push("LoginPanel")
    router:present("ConfirmDialog")
    FTestHelper:assert_equal(1, #router:get_stack())
    FTestHelper:assert_not_nil(manager:get("ConfirmDialog"))
end)

FTestHelper:test("router rejects non-Modal present and back at root", function()
    local manager = make_manager()
    local router = FUIRouter:new(manager)
    router:push("LoginPanel")
    FTestHelper:assert_error_code("INVALID_MODAL_PAGE", function() router:present("MainPanel") end)
    FTestHelper:assert_false(router:back())
end)

FTestHelper:test("failed push restores the previous route", function()
    local manager = make_manager()
    local router = FUIRouter:new(manager)
    router:push("LoginPanel")
    manager.fail_page = "MainPanel"
    FTestHelper:assert_error_code("ASSET_LOAD_FAILED", function() router:push("MainPanel") end)
    FTestHelper:assert_equal("LoginPanel", router:current().page)
    FTestHelper:assert_equal("show:LoginPanel", manager.calls[#manager.calls])
end)
