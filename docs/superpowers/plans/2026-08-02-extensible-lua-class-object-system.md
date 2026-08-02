# 可扩展 Lua 类与对象机制 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增一套 Lua 5.3 兼容的单继承类与对象机制，提供自动构造/析构链、显式 `super`、类型查询和安全幂等销毁。

**Architecture:** `FClass.lua` 使用模块私有的弱键注册表识别真实类与实例，避免普通 table 伪装类型；类 metatable 负责动态静态继承，实例 metatable 负责方法查找和销毁状态守卫。构造与析构通过直接父类链和 `rawget` 保证每一级实现只执行一次。

**Tech Stack:** Lua 5.3 兼容语法、Fengari Node CLI、仓库现有 `FError` 与轻量 `FTestHelper`。

---

## 实施边界与文件职责

- Create: `FLuaFramework/Shared/Core/FClass.lua`：类定义、实例创建、继承、类型查询与销毁机制。
- Create: `Tests/Unit/FClassSpec.lua`：该机制的独立单元规格。
- 不修改 `Tests/run.lua`、`Tests/check.lua` 或任何现有 UI/Runtime/Presenter 文件。

### Task 1: 写完整行为规格并确认 RED

**Files:**
- Create: `Tests/Unit/FClassSpec.lua`

- [ ] **Step 1: 写类定义、继承、类型和生命周期规格**

创建 `Tests/Unit/FClassSpec.lua`：

```lua
local FTestHelper = require("Tests.TestHelper")
local Class = require("FLuaFramework.Shared.Core.FClass")

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
```

- [ ] **Step 2: 执行规格并确认模块缺失的 RED**

Run:

```powershell
node_modules/.bin/fengari -e "dofile('Tests/Unit/FClassSpec.lua')"
```

Expected: 退出码非 0，错误包含 `module 'FLuaFramework.Shared.Core.FClass' not found`。

### Task 2: 实现类与对象机制并确认 GREEN

**Files:**
- Create: `FLuaFramework/Shared/Core/FClass.lua`
- Test: `Tests/Unit/FClassSpec.lua`

- [ ] **Step 1: 写最小完整实现**

创建 `FLuaFramework/Shared/Core/FClass.lua`：

```lua
local FError = require("FLuaFramework.Shared.Core.FError")

local FClass = {}
local class_info = setmetatable({}, { __mode = "k" })
local instance_info = setmetatable({}, { __mode = "k" })
local class_methods = {}
local object_methods = {}

local function raise(code, message, context)
    error(FError.new(code, message, context or {}), 0)
end

local function assert_class(value, code)
    local info = class_info[value]
    if info == nil then
        raise(code or "INVALID_CLASS", "value is not a class created by FClass", {
            class = tostring(value),
        })
    end
    return info
end

local function is_subclass_of(class, target)
    local current = class
    while current ~= nil do
        if current == target then
            return true
        end
        current = class_info[current].base
    end
    return false
end

local function find_instance_member(class, key)
    local current = class
    while current ~= nil do
        local value = rawget(current, key)
        if value ~= nil then
            return value
        end
        current = class_info[current].base
    end
    return nil
end

local function instance_index(instance, key)
    local method = object_methods[key]
    if method ~= nil then
        return method
    end

    local info = instance_info[instance]
    if info.destroyed then
        raise("OBJECT_DESTROYED", "cannot access a method on a destroyed object", {
            class = class_info[info.class].name,
            member = key,
        })
    end
    return find_instance_member(info.class, key)
end

local instance_metatable = { __index = instance_index }

function class_methods:new(...)
    assert_class(self)
    local instance = setmetatable({}, instance_metatable)
    instance_info[instance] = { class = self, destroyed = false }

    local chain = {}
    local current = self
    while current ~= nil do
        table.insert(chain, 1, current)
        current = class_info[current].base
    end
    for _, class in ipairs(chain) do
        local ctor = rawget(class, "ctor")
        if type(ctor) == "function" then
            ctor(instance, ...)
        end
    end
    return instance
end

function class_methods:get_name()
    return assert_class(self).name
end

function class_methods:is_subclass(target)
    assert_class(self)
    assert_class(target)
    return is_subclass_of(self, target)
end

function class_methods:is_instance(value)
    assert_class(self)
    local info = instance_info[value]
    return info ~= nil and is_subclass_of(info.class, self)
end

function object_methods:get_class()
    return instance_info[self].class
end

function object_methods:get_class_name()
    local class = instance_info[self].class
    return class_info[class].name
end

function object_methods:is_a(target)
    assert_class(target)
    return is_subclass_of(instance_info[self].class, target)
end

function object_methods:is_destroyed()
    return instance_info[self].destroyed
end

function object_methods:destroy()
    local info = instance_info[self]
    if info.destroyed then
        return false
    end
    info.destroyed = true

    local current = info.class
    while current ~= nil do
        local dtor = rawget(current, "dtor")
        if type(dtor) == "function" then
            dtor(self)
        end
        current = class_info[current].base
    end
    return true
end

local function define_class(name, base)
    if type(name) ~= "string" or name == "" then
        raise("INVALID_CLASS_NAME", "class name must be a non-empty string", {
            class = name,
        })
    end
    if base ~= nil and class_info[base] == nil then
        raise("INVALID_BASE_CLASS", "base must be a class created by FClass", {
            class = name,
            base = tostring(base),
        })
    end

    local class = { super = base }
    class_info[class] = { name = name, base = base }
    setmetatable(class, {
        __index = function(_, key)
            local method = class_methods[key]
            if method ~= nil then
                return method
            end
            if base ~= nil then
                return base[key]
            end
            return nil
        end,
    })
    return class
end

return setmetatable(FClass, {
    __call = function(_, name, base)
        return define_class(name, base)
    end,
})
```

- [ ] **Step 2: 运行全部新增用例并确认 GREEN**

Run:

```powershell
node_modules/.bin/fengari -e "dofile('Tests/Unit/FClassSpec.lua'); local h=require('Tests.TestHelper'); for _,c in ipairs(h.tests) do local ok,e=pcall(c.body); if not ok then error(e) end end"
```

Expected: 退出码为 0，无输出；7 个新增用例全部执行成功。

### Task 3: 独立验收与回归检查

**Files:**
- Verify: `FLuaFramework/Shared/Core/FClass.lua`
- Verify: `Tests/Unit/FClassSpec.lua`

- [ ] **Step 1: 验证生产模块可以独立解析**

Run:

```powershell
node_modules/.bin/fengari -e "local Class=require('FLuaFramework.Shared.Core.FClass'); assert(type(Class) == 'table')"
```

Expected: 退出码为 0，无输出。

- [ ] **Step 2: 运行现有全量回归测试**

Run: `npm test`

Expected: 退出码为 0，结尾为 `32 passed, 0 failed`。

- [ ] **Step 3: 检查改动边界**

Run:

```powershell
git status --short
git diff -- FLuaFramework/Shared/Core/FClass.lua Tests/Unit/FClassSpec.lua
```

Expected: 除计划文档外，功能改动只包含新增的 `FClass.lua` 和 `FClassSpec.lua`，现有 UI/Runtime/Presenter 文件没有变化。

- [ ] **Step 4: 交由完成分支流程统一提交与集成**

所有验证通过后使用 `superpowers:finishing-a-development-branch` 创建最终本地提交、复核测试，并选择合并、推送 PR、保留或丢弃。不要创建零散实现提交。

## 自检结论

- **规格覆盖：** 单继承、父到子构造、动态方法继承、显式 `super`、类型查询、子到父析构、幂等销毁、销毁守卫及异常传播均有直接测试。
- **边界一致：** 公共 API 名称与规格一致；只新增一个生产模块和一个独立测试文件。
- **测试隔离：** 新规格使用独立 Fengari 命令执行，不修改现有测试入口；现有 32 项测试作为回归证据保留。
- **无占位内容：** 所有代码、命令和预期结果均已明确。
