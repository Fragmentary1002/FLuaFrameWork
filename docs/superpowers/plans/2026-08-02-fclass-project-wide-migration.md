# FClass 全项目迁移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将生产代码与测试 Fixture 的 17 个手写 Lua 类全部迁移到 FClass，并强制项目内部只使用 `Type:new(...)`。

**Architecture:** 先以失败测试增强 FClass 的延迟错误加载、`__tostring` 分发和用户方法优先级，再分层迁移 Core、Contracts、Adapters、App 与测试。最终通过行为回归和静态扫描同时证明功能不变且旧类写法已清除。

**Tech Stack:** Lua 5.3、Fengari Node CLI、FClass、FError、仓库轻量测试框架、ripgrep。

---

## 文件结构与迁移规则

- `FClass.lua`：保留唯一合法的类系统 metatable 实现。
- 根类统一写成 `local Type = Class("Type")`。
- 子类统一写成 `local Child = Class("Child", Parent)`。
- 原 `function Type.new(...)` 的初始化体移入 `function Type:ctor(...)`。
- 所有构造调用统一由 `Type.new(...)` 改为 `Type:new(...)`。
- 临时订阅句柄和纯数据 table 不迁移。

### Task 1: 增强 FClass 以承载全部现有类行为

**Files:**
- Modify: `Tests/Unit/FClassSpec.lua`
- Modify: `FLuaFramework/Shared/Core/FClass.lua`

- [ ] **Step 1: 追加失败规格**

在 `Tests/Unit/FClassSpec.lua` 末尾追加：

```lua
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
```

- [ ] **Step 2: 运行新增规格并确认 RED**

Run:

```powershell
node_modules/.bin/fengari -e "dofile('Tests/Unit/FClassSpec.lua'); local h=require('Tests.TestHelper'); for _,c in ipairs(h.tests) do local ok,e=pcall(c.body); if not ok then error(e) end end"
```

Expected: 非零退出，首先失败于 `class dispatches tostring to the concrete class`。

- [ ] **Step 3: 实现延迟 FError、tostring 分发和用户方法优先**

在 `FClass.lua` 中删除顶层 `FError` require，把 `raise` 改为：

```lua
local function raise(code, message, context)
    local FError = require("FLuaFramework.Shared.Core.FError")
    error(FError:new(code, message, context or {}), 0)
end
```

把 `instance_index` 和共享实例 metatable 替换为：

```lua
local function instance_index(instance, key)
    local info = instance_info[instance]
    if not info.destroyed then
        local member = find_instance_member(info.class, key)
        if member ~= nil then
            return member
        end
    end

    local method = object_methods[key]
    if method ~= nil then
        return method
    end
    if info.destroyed then
        raise("OBJECT_DESTROYED", "cannot access a method on a destroyed object", {
            class = class_info[info.class].name,
            member = key,
        })
    end
    return nil
end

local function instance_tostring(instance)
    local info = instance_info[instance]
    local handler = find_instance_member(info.class, "__tostring")
    if type(handler) == "function" then
        return handler(instance)
    end
    return "<" .. class_info[info.class].name .. ">"
end

local instance_metatable = {
    __index = instance_index,
    __tostring = instance_tostring,
}
```

- [ ] **Step 4: 运行 FClass 规格并确认 GREEN**

运行 Step 2 命令。Expected: 退出码 0，10 个 FClass 用例通过。

### Task 2: 迁移 Shared Core、Events、State 与 Utils

**Files:**
- Modify: `FLuaFramework/Shared/Core/FError.lua`
- Modify: `FLuaFramework/Shared/Core/FBasePresenter.lua`
- Modify: `FLuaFramework/Shared/Core/FLifecycle.lua`
- Modify: `FLuaFramework/Shared/Core/FUIManager.lua`
- Modify: `FLuaFramework/Shared/Events/FEventBus.lua`
- Modify: `FLuaFramework/Shared/State/FStore.lua`
- Modify: `FLuaFramework/Shared/Utils/FCommand.lua`
- Modify: `FLuaFramework/Shared/Utils/FValidation.lua`
- Modify: `Tests/Unit/FEventBusSpec.lua`
- Modify: `Tests/Unit/FStoreSpec.lua`
- Modify: `Tests/Unit/FLifecycleSpec.lua`
- Modify: `Tests/Unit/FBasePresenterSpec.lua`

- [ ] **Step 1: 将相关单元测试构造调用改为冒号并确认 RED**

执行以下精确替换：

```text
FError.new(       -> FError:new(
FEventBus.new(    -> FEventBus:new(
FStore.new(       -> FStore:new(
FCommand.new(     -> FCommand:new(
FValidation.new(  -> FValidation:new(
FLifecycle.new(   -> FLifecycle:new(
FBasePresenter.new( -> FBasePresenter:new(
```

Run: `npm test`

Expected: 非零退出；旧手写构造函数收到错误的类 self，证明测试已切换到新 API。

- [ ] **Step 2: 迁移八个根类定义**

每个文件加入 `local Class = require("FLuaFramework.Shared.Core.FClass")`，并使用以下定义与构造器：

```lua
-- FError.lua
local FError = Class("FError")
function FError:ctor(code, message, context)
    self.code = code
    self.message = message
    self.context = context
end

-- FBasePresenter.lua
local FBasePresenter = Class("FBasePresenter")
function FBasePresenter:ctor()
    self.subscriptions = {}
    self.unbound = false
end

-- FLifecycle.lua
local FLifecycle = Class("FLifecycle")
function FLifecycle:ctor() self.state = "Unloaded" end

-- FUIManager.lua
local FUIManager = Class("FUIManager")
function FUIManager:ctor(options)
    self.runtime = options.runtime
    self.pages = options.pages
    self.services = options.services or {}
    self.require_module = options.require_module or require
    self.instances = {}
    self.next_request_version = 0
end

-- FEventBus.lua
local FEventBus = Class("FEventBus")
function FEventBus:ctor() self.listeners = {} end

-- FStore.lua
local FStore = Class("FStore")
function FStore:ctor(initial_values)
    self.values = {}
    for key, value in pairs(initial_values or {}) do self.values[key] = value end
    self.subscribers = {}
end

-- FCommand.lua
local FCommand = Class("FCommand")
function FCommand:ctor(execute, can_execute)
    self.execute_callback = execute
    self.can_execute_callback = can_execute
end

-- FValidation.lua
local FValidation = Class("FValidation")
```

删除各文件原有的 `{}`、`__index`、`function Type.new` 和 `setmetatable` 构造代码。删除 `FBasePresenter.initialize`。

- [ ] **Step 3: 将生产调用点切换到冒号**

在本任务文件中把所有 `FError.new(`、`FLifecycle.new(`、`presenter_module.new(` 改为 `FError:new(`、`FLifecycle:new(`、`presenter_module:new(`。

- [ ] **Step 4: 运行单元与全量回归**

Run: `npm test`

Expected: 相关单元用例恢复通过；若尚未迁移模块的旧调用仍在测试中，则失败只允许来自后续任务列出的模块。

### Task 3: 迁移 Contracts、Adapters 与 Presenter 继承

**Files:**
- Modify: `FLuaFramework/Shared/Contracts/FIWidget.lua`
- Modify: `FLuaFramework/Shared/Contracts/FIText.lua`
- Modify: `FLuaFramework/Shared/Contracts/FIButton.lua`
- Modify: `FLuaFramework/Shared/Contracts/FIImage.lua`
- Modify: `FLuaFramework/Shared/Contracts/FIView.lua`
- Modify: `FLuaFramework/Adapters/Common/FViewBinder.lua`
- Modify: `FLuaFramework/Adapters/Unreal/FUnrealRuntime.lua`
- Modify: `FLuaFramework/Adapters/Unity/FUnityRuntime.lua`
- Modify: `FLuaFramework/App/UI/Login/LoginPresenter.lua`
- Modify: `Tests/Unit/FViewBinderSpec.lua`
- Modify: `Tests/Contract/FRuntimeContractSpec.lua`
- Modify: `Tests/Integration/FUIManagerSpec.lua`
- Modify: `Tests/Integration/LoginPanelSpec.lua`

- [ ] **Step 1: 将集成/契约测试的 Runtime 与 Manager 调用改为冒号并观察 RED**

精确替换 `FFakePlatformBridge.new(`、`FUnrealRuntime.new(`、`FUnityRuntime.new(`、`FUIManager.new(` 为对应冒号调用。Run: `npm test`。Expected: 非零退出，失败来自尚未迁移的 Runtime、Manager 或 Fixture 构造。

- [ ] **Step 2: 建立真实 Contracts 继承**

使用以下类声明和构造器，保留各文件其余方法：

```lua
local FIWidget = Class("FIWidget")
function FIWidget:ctor(id, native, ops)
    self.id = id
    self.native = native
    self.ops = ops
end

local FIText = Class("FIText", FIWidget)
local FIButton = Class("FIButton", FIWidget)
local FIImage = Class("FIImage", FIWidget)

local FIView = Class("FIView")
function FIView:ctor(page, platform, native, root_ops, widgets)
    self.page = page
    self.platform = platform
    self.native = native
    self.root_ops = root_ops
    self.widgets = widgets
    self.destroyed = false
end
```

每个文件显式 require `FClass`；子类继续 require `FIWidget`。删除旧 `__index`、`setmetatable` 和 `new`。

- [ ] **Step 3: 迁移 Binder 工厂和两个 Runtime**

`FViewBinder` factories 改为：

```lua
local factories = {
    Text = function(...) return FIText:new(...) end,
    Button = function(...) return FIButton:new(...) end,
    Image = function(...) return FIImage:new(...) end,
}
```

Runtime 使用：

```lua
local FUnrealRuntime = Class("FUnrealRuntime")
function FUnrealRuntime:ctor(bridge)
    self.platform = "unreal"
    self.bridge = bridge
end

local FUnityRuntime = Class("FUnityRuntime")
function FUnityRuntime:ctor(bridge)
    self.platform = "unity"
    self.bridge = bridge
end
```

- [ ] **Step 4: 迁移 LoginPresenter 继承**

定义替换为：

```lua
local Class = require("FLuaFramework.Shared.Core.FClass")
local FBasePresenter = require("FLuaFramework.Shared.Core.FBasePresenter")
local LoginPresenter = Class("LoginPresenter", FBasePresenter)

function LoginPresenter:ctor(services)
    self.services = services
end
```

保留生命周期方法；自动构造链负责先执行 `FBasePresenter:ctor()`。

- [ ] **Step 5: 运行全量测试**

Run: `npm test`

Expected: 除测试 Fixture 或剩余点调用外，Contracts、Runtime 与 Login 集成行为通过。

### Task 4: 迁移测试 Fixture、FakePresenter 与全部剩余调用点

**Files:**
- Modify: `Tests/Fixtures/FFakePlatformBridge.lua`
- Modify: `Tests/Integration/FUIManagerSpec.lua`
- Modify: `Tests/**/*.lua`
- Modify: `FLuaFramework/**/*.lua`

- [ ] **Step 1: 迁移 FFakePlatformBridge**

文件头和构造器改为：

```lua
local Class = require("FLuaFramework.Shared.Core.FClass")
local FFakePlatformBridge = Class("FFakePlatformBridge")

function FFakePlatformBridge:ctor(platform)
    self.platform = platform
    self.pending = {}
    self.destroyed = 0
end
```

- [ ] **Step 2: 迁移 Manager 测试 FakePresenter**

将 `presenter_module(events)` 改为：

```lua
local Class = require("FLuaFramework.Shared.Core.FClass")

local function presenter_module(events)
    local FakePresenter = Class("FakePresenter")
    for _, name in ipairs({ "create", "bind", "open", "show", "hide", "close", "unbind", "destroy" }) do
        FakePresenter["on_" .. name] = function() table.insert(events, name) end
    end
    return FakePresenter
end
```

- [ ] **Step 3: 清除全部旧点调用**

对 `FLuaFramework` 和 `Tests` 中剩余构造调用逐一改为冒号。不得修改 `FClass.lua` 的 `class_methods:new`。

Run:

```powershell
rg -n "function\s+[A-Za-z0-9_\.]+\.new|[A-Za-z0-9_\.]+\.new\(" FLuaFramework Tests
```

Expected: 无匹配。

- [ ] **Step 4: 运行当前全量测试**

Run: `npm test`

Expected: 当前测试入口中的 32 项全部通过。

### Task 5: 集成 FClass 测试、解析检查和文档 API

**Files:**
- Modify: `Tests/run.lua`
- Modify: `Tests/check.lua`
- Modify: `README.md`

- [ ] **Step 1: 注册 FClass 规格**

在 `Tests/run.lua` 的 `FStoreSpec.lua` 后加入：

```lua
"Tests/Unit/FClassSpec.lua",
```

- [ ] **Step 2: 注册 FClass 解析检查**

在 `Tests/check.lua` 的 FError 前加入：

```lua
"FLuaFramework.Shared.Core.FClass",
```

- [ ] **Step 3: 更新 README 公共构造 API**

把 `FUnrealRuntime.new(bridge)` 和 `FUnityRuntime.new(bridge)` 改为 `FUnrealRuntime:new(bridge)` 和 `FUnityRuntime:new(bridge)`。

- [ ] **Step 4: 运行最终行为验收**

Run: `npm test`

Expected: `42 passed, 0 failed`。

Run: `npm run check:lua`

Expected: `parsed 19 Lua modules`。

- [ ] **Step 5: 运行静态迁移验收**

Run:

```powershell
rg -n "function\s+[A-Za-z0-9_\.]+\.new|[A-Za-z0-9_\.]+\.new\(" FLuaFramework Tests
rg -n "__index\s*=" FLuaFramework Tests -g "*.lua" -g "!FLuaFramework/Shared/Core/FClass.lua"
```

Expected: 两条命令均退出码 1 且无匹配。

- [ ] **Step 6: 交由完成分支流程统一提交**

使用 `superpowers:finishing-a-development-branch` 运行最终测试、创建一个中文本地提交，并按用户既有授权保留当前 `main` 状态。不要创建零散实现提交。

## 自检结论

- 17 个手写类均有明确迁移任务。
- FError 循环依赖、`__tostring` 与 FIView 自定义 `destroy` 均先有失败测试。
- 所有旧点调用、手写 `__index` 和 `function X.new` 均有静态验收。
- 历史规格/计划文档不参与机械替换。
