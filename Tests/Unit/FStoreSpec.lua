local FTestHelper = require("Tests.TestHelper")
local FError = require("LuaUIFramework.Shared.Core.FError")
local FStore = require("LuaUIFramework.Shared.State.FStore")
local FCommand = require("LuaUIFramework.Shared.Utils.FCommand")
local FValidation = require("LuaUIFramework.Shared.Utils.FValidation")

FTestHelper:test("unified errors expose code message context and tostring", function()
    local context = { field = "account" }
    local err = FError.new("REQUIRED", "account is required", context)

    FTestHelper:assert_equal("REQUIRED", err.code)
    FTestHelper:assert_equal("account is required", err.message)
    FTestHelper:assert_equal(context, err.context)
    FTestHelper:assert_true(tostring(err):match("REQUIRED") ~= nil)
    FTestHelper:assert_true(tostring(err):match("account is required") ~= nil)
end)

FTestHelper:test("store gets and sets values", function()
    local store = FStore.new({ coins = 1 })
    FTestHelper:assert_equal(1, store:get("coins"))

    store:set("coins", 2)
    FTestHelper:assert_equal(2, store:get("coins"))
end)

FTestHelper:test("store notifies only when a value changes", function()
    local store = FStore.new({ coins = 1 })
    local calls = 0
    local new_value = nil
    local old_value = nil

    store:subscribe("coins", function(new_coins, old_coins)
        calls = calls + 1
        new_value = new_coins
        old_value = old_coins
    end)
    store:set("coins", 1)
    store:set("coins", 2)

    FTestHelper:assert_equal(1, calls)
    FTestHelper:assert_equal(2, new_value)
    FTestHelper:assert_equal(1, old_value)
end)

FTestHelper:test("store subscription unsubscribe is idempotent", function()
    local store = FStore.new()
    local calls = 0
    local subscription = store:subscribe("coins", function()
        calls = calls + 1
    end)

    subscription:unsubscribe()
    subscription:unsubscribe()
    store:set("coins", 2)

    FTestHelper:assert_equal(0, calls)
end)

FTestHelper:test("store update applies a pure updater", function()
    local store = FStore.new({ coins = 2 })
    local updater_input = nil

    local result = store:update("coins", function(current)
        updater_input = current
        return current + 3
    end)

    FTestHelper:assert_equal(2, updater_input)
    FTestHelper:assert_equal(5, result)
    FTestHelper:assert_equal(5, store:get("coins"))
end)

FTestHelper:test("command executes when can_execute allows it", function()
    local received = nil
    local command = FCommand.new(function(value)
        received = value
        return value * 2
    end, function(value)
        return value > 0
    end)

    FTestHelper:assert_true(command:can_execute(2))
    FTestHelper:assert_equal(4, command:execute(2))
    FTestHelper:assert_equal(2, received)
end)

FTestHelper:test("command does not execute when can_execute rejects it", function()
    local calls = 0
    local command = FCommand.new(function()
        calls = calls + 1
    end, function()
        return false
    end)

    FTestHelper:assert_false(command:can_execute())
    FTestHelper:assert_nil(command:execute())
    FTestHelper:assert_equal(0, calls)
end)

FTestHelper:test("validation required rejects empty values", function()
    local validation = FValidation.new()
    local required = validation:required("value is required")

    local valid, message = required("")
    FTestHelper:assert_false(valid)
    FTestHelper:assert_equal("value is required", message)
    FTestHelper:assert_true(required("value"))
end)

FTestHelper:test("validation min_length rejects short strings", function()
    local validation = FValidation.new()
    local min_length = validation:min_length(3, "too short")

    local valid, message = min_length("ab")
    FTestHelper:assert_false(valid)
    FTestHelper:assert_equal("too short", message)
    FTestHelper:assert_true(min_length("abc"))
end)

FTestHelper:test("validation combine returns the first failure", function()
    local validation = FValidation.new()
    local validate = validation:combine(
        validation:required("required"),
        validation:min_length(3, "too short")
    )

    local valid, message = validate("")
    FTestHelper:assert_false(valid)
    FTestHelper:assert_equal("required", message)

    valid, message = validate("ab")
    FTestHelper:assert_false(valid)
    FTestHelper:assert_equal("too short", message)
    FTestHelper:assert_true(validate("abc"))
end)

