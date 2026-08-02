local FTestHelper = require("Tests.TestHelper")
local Class = require("LuaUIFramework.Shared.Core.FClass")

FTestHelper:test("class creates instances and runs constructors from parent to child", function()
    local calls = {}
    local Animal = Class("Animal")
    local Dog = Class("Dog", Animal)

    function Animal:ctor(name)
        table.insert(calls, "animal:" .. name)
        self.name = name
    end

    function Dog:ctor(name, breed)
        table.insert(calls, "dog:" .. breed)
        self.breed = breed
    end

    local dog = Dog:new("Lucky", "Corgi")

    FTestHelper:assert_equal("animal:Lucky,dog:Corgi", table.concat(calls, ","))
    FTestHelper:assert_equal("Lucky", dog.name)
    FTestHelper:assert_equal("Corgi", dog.breed)
    FTestHelper:assert_equal("Dog", Dog:get_name())
    FTestHelper:assert_equal("Dog", dog:get_class_name())
    FTestHelper:assert_equal(Dog, dog:get_class())
end)

FTestHelper:test("class supports dynamic inheritance overrides and explicit super", function()
    local Animal = Class("Animal")
    local Dog = Class("Dog", Animal)

    function Animal:speak()
        return "animal"
    end

    function Dog:speak()
        return Dog.super.speak(self) .. ":dog"
    end

    function Animal:describe()
        return "added-after-subclass"
    end

    local dog = Dog:new()
    FTestHelper:assert_equal("animal:dog", dog:speak())
    FTestHelper:assert_equal("added-after-subclass", dog:describe())
end)

FTestHelper:test("class and instance type queries follow a multi-level hierarchy", function()
    local Animal = Class("Animal")
    local Dog = Class("Dog", Animal)
    local Corgi = Class("Corgi", Dog)
    local dog = Dog:new()

    FTestHelper:assert_true(dog:is_a(Dog))
    FTestHelper:assert_true(dog:is_a(Animal))
    FTestHelper:assert_false(dog:is_a(Corgi))
    FTestHelper:assert_true(Dog:is_subclass(Dog))
    FTestHelper:assert_true(Corgi:is_subclass(Animal))
    FTestHelper:assert_false(Animal:is_subclass(Dog))
    FTestHelper:assert_true(Animal:is_instance(dog))
    FTestHelper:assert_true(Dog:is_instance(dog))
    FTestHelper:assert_false(Corgi:is_instance(dog))
    FTestHelper:assert_false(Dog:is_instance({}))
end)

FTestHelper:test("destroy runs destructors child first and is recursive-safe and idempotent", function()
    local calls = {}
    local Resource = Class("Resource")
    local Socket = Class("Socket", Resource)

    function Resource:dtor()
        table.insert(calls, "resource")
    end

    function Socket:dtor()
        table.insert(calls, "socket")
        FTestHelper:assert_false(self:destroy())
    end

    function Socket:send()
        return "sent"
    end

    local socket = Socket:new()
    FTestHelper:assert_false(socket:is_destroyed())
    FTestHelper:assert_true(socket:destroy())
    FTestHelper:assert_false(socket:destroy())
    FTestHelper:assert_equal("socket,resource", table.concat(calls, ","))
    FTestHelper:assert_true(socket:is_destroyed())
    FTestHelper:assert_true(socket:is_a(Resource))
    FTestHelper:assert_equal(Socket, socket:get_class())
    FTestHelper:assert_equal("Socket", socket:get_class_name())
    FTestHelper:assert_true(Resource:is_instance(socket))
    FTestHelper:assert_error_code("OBJECT_DESTROYED", function() socket:send() end)
end)

FTestHelper:test("class rejects invalid names bases and type-query targets", function()
    FTestHelper:assert_error_code("INVALID_CLASS_NAME", function() Class("") end)
    FTestHelper:assert_error_code("INVALID_CLASS_NAME", function() Class(42) end)
    FTestHelper:assert_error_code("INVALID_BASE_CLASS", function() Class("Broken", {}) end)

    local Value = Class("Value")
    local value = Value:new()
    FTestHelper:assert_error_code("INVALID_CLASS", function() value:is_a({}) end)
    FTestHelper:assert_error_code("INVALID_CLASS", function() Value:is_subclass({}) end)
end)

FTestHelper:test("constructor errors propagate without returning an instance", function()
    local Broken = Class("Broken")
    function Broken:ctor()
        error("ctor failed")
    end

    local succeeded, failure = pcall(function() return Broken:new() end)
    FTestHelper:assert_false(succeeded)
    FTestHelper:assert_contains("ctor failed", failure)
end)

FTestHelper:test("destructor errors propagate once and leave the object destroyed", function()
    local calls = 0
    local Broken = Class("Broken")
    function Broken:dtor()
        calls = calls + 1
        error("dtor failed")
    end

    local value = Broken:new()
    local succeeded, failure = pcall(function() value:destroy() end)
    FTestHelper:assert_false(succeeded)
    FTestHelper:assert_contains("dtor failed", failure)
    FTestHelper:assert_true(value:is_destroyed())
    FTestHelper:assert_false(value:destroy())
    FTestHelper:assert_equal(1, calls)
end)

FTestHelper:test("class dispatches tostring to the concrete class", function()
    local Value = Class("Value")
    function Value:ctor(text) self.text = text end
    function Value:__tostring() return "Value(" .. self.text .. ")" end
    FTestHelper:assert_equal("Value(ok)", tostring(Value:new("ok")))
end)

FTestHelper:test("class-defined methods override default object methods while alive", function()
    local View = Class("View")
    function View:ctor() self.calls = 0 end
    function View:destroy()
        self.calls = self.calls + 1
        return "custom"
    end
    local view = View:new()
    FTestHelper:assert_equal("custom", view:destroy())
    FTestHelper:assert_equal(1, view.calls)
    FTestHelper:assert_false(view:is_destroyed())
end)

FTestHelper:test("class validation still raises structured errors through lazy FError loading", function()
    local succeeded, failure = pcall(function() Class("") end)
    FTestHelper:assert_false(succeeded)
    FTestHelper:assert_equal("INVALID_CLASS_NAME", failure.code)
    FTestHelper:assert_equal("[INVALID_CLASS_NAME] class name must be a non-empty string", tostring(failure))
end)
