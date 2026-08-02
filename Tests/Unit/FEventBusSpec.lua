local FTestHelper = require("Tests.TestHelper")
local FEventBus = require("FLuaFramework.Shared.Events.FEventBus")

FTestHelper:test("event subscribers receive emitted arguments", function()
    local bus = FEventBus:new()
    local received_name = nil
    local received_amount = nil

    bus:subscribe("changed", function(name, amount)
        received_name = name
        received_amount = amount
    end)
    bus:emit("changed", "coins", 3)

    FTestHelper:assert_equal("coins", received_name)
    FTestHelper:assert_equal(3, received_amount)
end)

FTestHelper:test("event unsubscribe is idempotent and stops notifications", function()
    local bus = FEventBus:new()
    local count = 0
    local subscription = bus:subscribe("changed", function()
        count = count + 1
    end)

    bus:emit("changed")
    subscription:unsubscribe()
    subscription:unsubscribe()
    bus:emit("changed")

    FTestHelper:assert_equal(1, count)
end)

FTestHelper:test("event owner can unsubscribe all owned bindings", function()
    local bus = FEventBus:new()
    local owner = {}
    local owned_count = 0
    local other_count = 0

    bus:subscribe("first", function() owned_count = owned_count + 1 end, owner)
    bus:subscribe("second", function() owned_count = owned_count + 1 end, owner)
    bus:subscribe("first", function() other_count = other_count + 1 end, {})

    bus:unsubscribe_owner(owner)
    bus:emit("first")
    bus:emit("second")

    FTestHelper:assert_equal(0, owned_count)
    FTestHelper:assert_equal(1, other_count)
end)

FTestHelper:test("duplicate event binding is rejected with a unified error", function()
    local bus = FEventBus:new()
    local owner = {}
    local callback = function() end

    bus:subscribe("changed", callback, owner)

    FTestHelper:assert_error_code("DUPLICATE_EVENT_BINDING", function()
        bus:subscribe("changed", callback, owner)
    end)
end)
