# 多引擎 Lua UI 框架阶段三：Shared 常用能力收口 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 基于已完成的阶段二 Shared 能力，在完全不修改或执行 Adapter 功能的前提下，补齐 Presenter 资源所有权、本地化、Loading 页面可见性意图和页面状态恢复，并建立独立的 Shared 测试门禁。

**Architecture:** 阶段三只修改 `Shared`、`Config`、纯 Lua Fixture 和 Shared 测试入口；`FBasePresenter` 统一释放订阅、异步请求和资源句柄，`FILocalization` 管理纯 Lua 语言表，`FUIManager` 保存 Loading 期间的期望可见性并承载 Presenter 状态，`FUIRouter` 负责导航栈快照与恢复。Unreal/Unity Runtime、`FViewBinder`、原生控件映射和 Adapter 契约测试全部保持现状。

**Tech Stack:** Lua 5.3 兼容语法、FClass、Fengari Node CLI、npm、纯 Lua Fake Runtime/Mock View、仓库内轻量测试运行器。

---

## 当前基线与修订依据

阶段二已在提交 `d1482aa feat: 完成阶段二共享 UI 能力` 中落地。开始阶段三前必须确认：

```text
npm test          -> 73 passed, 0 failed
npm run check:lua -> parsed 24 registered framework modules, 4 config/app modules and 2 entry modules
```

已经完成、阶段三不得重复实现：

- `FIInput`、`FIToggle`、`FIProgress` 及 Mock View；
- `FLayers`、`FUIManager:close_layer` 和可选 `runtime:mount_view` 委托；
- `FUIRouter` 的 `push/replace/back/reset/present`；
- `FIAssetLoader`、`FAssetHandle`、`FILogger`；
- Shared 层对应单元测试。

## 强制排除范围

阶段三不修改以下路径：

```text
FLuaFramework/Adapters/**
Tests/Contract/**
Tests/Unit/FViewBinderSpec.lua
Tests/Unit/FInitSpec.lua
Tests/Unit/FRegisterSpec.lua
Tests/Integration/FUIManagerSpec.lua
Tests/Integration/LoginPanelSpec.lua
Tests/Integration/FMainSpec.lua
init.lua
main.lua
```

阶段三执行过程中不使用 `npm test` 作为循环测试命令，因为它会执行 Adapter 契约和双平台集成测试。Task 1 建立 `npm run test:shared` 与 `npm run check:shared` 后，后续任务只使用这两个入口。

虚拟列表/对象池、原生动画和 Adapter 契约测试工具无法在“不运行 Adapters”的约束下形成真实可用闭环，因此本计划明确延期；后续需要平台接入时再依据 `docs/myDocs/phase-two-adapter-requirements.md` 单独编写 Adapter 计划。

## 文件结构与职责

```text
FLuaFramework/
├─ Shared/
│  ├─ Core/
│  │  ├─ FBasePresenter.lua     # 订阅、请求、资源三类清理袋
│  │  ├─ FUIManager.lua         # Loading 可见性与 Presenter 状态入口
│  │  └─ FUIRouter.lua          # 导航快照和恢复
│  └─ Localization/
│     └─ FILocalization.lua     # 语言切换、回退、插值和缺失诊断
├─ Config/
│  └─ FLocales.lua              # 示例中英语言表
└─ register.lua                 # 只登记新增 Shared 模块
Tests/
├─ SharedTestBootstrap.lua      # 不加载 Adapters 的测试全局注册
├─ run-shared.lua               # Shared-only 测试 runner
├─ check-shared.lua             # Shared-only 模块加载检查
├─ Fixtures/
│  ├─ FFakeRuntime.lua
│  └─ FMockView.lua
└─ Unit/
   ├─ FBasePresenterSpec.lua
   ├─ FILocalizationSpec.lua
   ├─ FUILayerSpec.lua
   ├─ FUIRouterAsyncSpec.lua
   └─ FUIStateRecoverySpec.lua
```

### Task 1: 建立不执行 Adapters 的 Shared 测试入口

**Files:**
- Create: `Tests/SharedTestBootstrap.lua`
- Create: `Tests/run-shared.lua`
- Create: `Tests/check-shared.lua`
- Modify: `package.json`

- [ ] **Step 1: 创建 Shared-only 全局注册**

创建 `Tests/SharedTestBootstrap.lua`：

```lua
local registered = {}

local function register(name, module_name)
    local module = require(module_name)
    registered[name] = module
    _G[name] = module
end

register("FClass", "FLuaFramework.Shared.Core.FClass")
register("FError", "FLuaFramework.Shared.Core.FError")
register("FBasePresenter", "FLuaFramework.Shared.Core.FBasePresenter")
register("FLifecycle", "FLuaFramework.Shared.Core.FLifecycle")

register("FIWidget", "FLuaFramework.Shared.Contracts.FWidget.FIWidget")
register("FIText", "FLuaFramework.Shared.Contracts.FWidget.FIText")
register("FIButton", "FLuaFramework.Shared.Contracts.FWidget.FIButton")
register("FIImage", "FLuaFramework.Shared.Contracts.FWidget.FIImage")
register("FIInput", "FLuaFramework.Shared.Contracts.FWidget.FIInput")
register("FIToggle", "FLuaFramework.Shared.Contracts.FWidget.FIToggle")
register("FIProgress", "FLuaFramework.Shared.Contracts.FWidget.FIProgress")
register("FIView", "FLuaFramework.Shared.Contracts.FIView")

register("FAssetHandle", "FLuaFramework.Shared.Contracts.FAssetLoader.FAssetHandle")
register("FIAssetLoader", "FLuaFramework.Shared.Contracts.FAssetLoader.FIAssetLoader")
register("FILogger", "FLuaFramework.Shared.Contracts.FLogger.FILogger")

register("FEventBus", "FLuaFramework.Shared.Events.FEventBus")
register("FStore", "FLuaFramework.Shared.State.FStore")
register("FCommand", "FLuaFramework.Shared.Utils.FCommand")
register("FValidation", "FLuaFramework.Shared.Utils.FValidation")
register("FUIManager", "FLuaFramework.Shared.Core.FUIManager")
register("FUIRouter", "FLuaFramework.Shared.Core.FUIRouter")

return registered
```

- [ ] **Step 2: 创建 Shared-only runner**

创建 `Tests/run-shared.lua`：

```lua
require("Tests.SharedTestBootstrap")
local FTestHelper = require("Tests.TestHelper")

local specs = {
    "Tests/Unit/FEventBusSpec.lua",
    "Tests/Unit/FStoreSpec.lua",
    "Tests/Unit/FClassSpec.lua",
    "Tests/Unit/FLifecycleSpec.lua",
    "Tests/Unit/FBasePresenterSpec.lua",
    "Tests/Unit/LoginPresenterSpec.lua",
    "Tests/Unit/FCommonControlsSpec.lua",
    "Tests/Unit/FUILayerSpec.lua",
    "Tests/Unit/FUIRouterSpec.lua",
    "Tests/Unit/FIAssetLoaderSpec.lua",
    "Tests/Unit/FILoggerSpec.lua",
    "Tests/Unit/FUIManagerLoggingSpec.lua",
}

for _, spec_path in ipairs(specs) do dofile(spec_path) end

local passed = 0
local failed = 0
for _, case in ipairs(FTestHelper.tests) do
    local succeeded, failure = pcall(case.body)
    if succeeded then
        passed = passed + 1
        print("PASS " .. case.name)
    else
        failed = failed + 1
        print("FAIL " .. case.name)
        print("  " .. tostring(failure))
    end
end

print(string.format("\n%d shared passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
```

- [ ] **Step 3: 创建 Shared-only 加载检查**

创建 `Tests/check-shared.lua`：

```lua
local registered = require("Tests.SharedTestBootstrap")
require("FLuaFramework.App.UI.Login.LoginPresenter")
require("FLuaFramework.Config.FPages")
require("FLuaFramework.Config.FLayers")
require("FLuaFramework.Config.FAssets")

local count = 0
for _ in pairs(registered) do count = count + 1 end
print(string.format(
    "parsed %d shared framework modules and 4 config/app modules",
    count
))
```

- [ ] **Step 4: 登记 npm 命令**

把 `package.json` 的 `scripts` 替换为：

```json
"scripts": {
  "test": "node Tests/check-requires.js && fengari Tests/run.lua",
  "test:shared": "node Tests/check-requires.js && fengari Tests/run-shared.lua",
  "check:lua": "fengari Tests/check.lua",
  "check:shared": "fengari Tests/check-shared.lua"
}
```

- [ ] **Step 5: 验证 Shared runner 没有执行 Adapter 用例**

Run: `npm run test:shared`

Expected: `51 shared passed, 0 failed`；输出中不得出现 `unreal runtime loads`、`unity runtime loads` 或 `LoginPresenter completes login on unreal/unity`。

Run: `npm run check:shared`

Expected: `parsed 21 shared framework modules and 4 config/app modules`。

### Task 2: 让 Presenter 对订阅、请求和资源拥有对称清理

**Files:**
- Modify: `FLuaFramework/Shared/Core/FBasePresenter.lua`
- Modify: `Tests/Unit/FBasePresenterSpec.lua`

- [ ] **Step 1: 写请求、资源和失败清理规格**

在 `Tests/Unit/FBasePresenterSpec.lua` 末尾追加：

```lua
FTestHelper:test("presenter unbind cancels tracked requests once", function()
    local presenter = FBasePresenter:new()
    local calls = 0
    presenter:track_request({ cancel = function() calls = calls + 1 end })
    presenter:on_unbind()
    presenter:on_unbind()
    FTestHelper:assert_equal(1, calls)
end)

FTestHelper:test("presenter unbind releases tracked resources once", function()
    local presenter = FBasePresenter:new()
    local calls = 0
    presenter:track_resource({ release = function() calls = calls + 1 end })
    presenter:on_unbind()
    presenter:on_unbind()
    FTestHelper:assert_equal(1, calls)
end)

FTestHelper:test("presenter rejects invalid request handles", function()
    FTestHelper:assert_error_code("INVALID_CANCELABLE", function()
        FBasePresenter:new():track_request({})
    end)
end)

FTestHelper:test("presenter rejects invalid resource handles", function()
    FTestHelper:assert_error_code("INVALID_RESOURCE", function()
        FBasePresenter:new():track_resource({})
    end)
end)

FTestHelper:test("presenter continues cleanup after one handle fails", function()
    local presenter = FBasePresenter:new()
    local released = 0
    presenter:track_resource({ release = function() released = released + 1 end })
    presenter:track_resource({ release = function() error("release failed") end })

    local succeeded, failure = pcall(function() presenter:on_unbind() end)

    FTestHelper:assert_false(succeeded)
    FTestHelper:assert_contains("release failed", failure)
    FTestHelper:assert_equal(1, released)
end)
```

- [ ] **Step 2: 运行规格并确认 RED**

Run: `npm run test:shared`

Expected: 非零退出，首个新增用例失败于 `attempt to call a nil value (method 'track_request')`。

- [ ] **Step 3: 实现三类清理袋**

将 `FLuaFramework/Shared/Core/FBasePresenter.lua` 替换为：

```lua
local FBasePresenter = FClass("FBasePresenter")

local function dispose_reverse(items, method)
    local first_failure = nil
    for index = #items, 1, -1 do
        local handle = items[index]
        items[index] = nil
        local succeeded, failure = pcall(handle[method], handle)
        if not succeeded and first_failure == nil then first_failure = failure end
    end
    return first_failure
end

function FBasePresenter:ctor()
    self.subscriptions = {}
    self.requests = {}
    self.resources = {}
    self.unbound = false
end

function FBasePresenter:track(subscription)
    if type(subscription) ~= "table" or type(subscription.unsubscribe) ~= "function" then
        error(FError:new("INVALID_SUBSCRIPTION", "subscription must expose unsubscribe", {}), 0)
    end
    table.insert(self.subscriptions, subscription)
    return subscription
end

function FBasePresenter:track_request(request)
    if type(request) ~= "table" or type(request.cancel) ~= "function" then
        error(FError:new("INVALID_CANCELABLE", "request must expose cancel", {}), 0)
    end
    table.insert(self.requests, request)
    return request
end

function FBasePresenter:track_resource(resource)
    if type(resource) ~= "table" or type(resource.release) ~= "function" then
        error(FError:new("INVALID_RESOURCE", "resource must expose release", {}), 0)
    end
    table.insert(self.resources, resource)
    return resource
end

function FBasePresenter:on_create(view, params)
    self.view = view
    self.params = params or {}
end

function FBasePresenter:on_bind() end
function FBasePresenter:on_open(params) self.params = params or {} end
function FBasePresenter:on_show() end
function FBasePresenter:on_hide() end
function FBasePresenter:on_close(result) self.close_result = result end
function FBasePresenter:on_save_state() return {} end
function FBasePresenter:on_restore_state(_) end

function FBasePresenter:on_unbind()
    if self.unbound then return end
    self.unbound = true
    local failure = dispose_reverse(self.subscriptions, "unsubscribe")
    local request_failure = dispose_reverse(self.requests, "cancel")
    local resource_failure = dispose_reverse(self.resources, "release")
    failure = failure or request_failure or resource_failure
    if failure ~= nil then error(failure, 0) end
end

function FBasePresenter:on_destroy()
    self.view = nil
    self.params = nil
end

return FBasePresenter
```

- [ ] **Step 4: 运行 Shared 回归**

Run: `npm run test:shared`

Expected: `56 shared passed, 0 failed`。

### Task 3: 实现纯 Lua 本地化与语言切换

**Files:**
- Create: `FLuaFramework/Shared/Localization/FILocalization.lua`
- Create: `FLuaFramework/Config/FLocales.lua`
- Create: `Tests/Unit/FILocalizationSpec.lua`
- Modify: `FLuaFramework/register.lua`
- Modify: `Tests/SharedTestBootstrap.lua`
- Modify: `Tests/run-shared.lua`
- Modify: `Tests/check-shared.lua`

- [ ] **Step 1: 写本地化的六个失败规格**

创建 `Tests/Unit/FILocalizationSpec.lua`：

```lua
local FTestHelper = require("Tests.TestHelper")
local FILocalization = require("FLuaFramework.Shared.Localization.FILocalization")

local function make_localization()
    local logs = {}
    local logger = {
        warn = function(_, message, context)
            table.insert(logs, { message = message, context = context })
        end,
    }
    local localization = FILocalization:new({
        locale = "zh-CN",
        fallback = "en-US",
        catalogs = {
            ["zh-CN"] = { greeting = "你好，{name}", only_zh = "仅中文" },
            ["en-US"] = { greeting = "Hello, {name}", fallback_key = "Fallback" },
        },
        logger = logger,
    })
    return localization, logs
end

FTestHelper:test("localization translates and interpolates current locale", function()
    local localization = make_localization()
    FTestHelper:assert_equal("你好，Alice", localization:t("greeting", { name = "Alice" }))
end)

FTestHelper:test("localization falls back to configured locale", function()
    local localization = make_localization()
    FTestHelper:assert_equal("Fallback", localization:t("fallback_key"))
end)

FTestHelper:test("localization returns a visible marker and logs a missing key", function()
    local localization, logs = make_localization()
    FTestHelper:assert_equal("[missing]", localization:t("missing"))
    FTestHelper:assert_equal("missing", logs[1].context.key)
    FTestHelper:assert_equal("zh-CN", logs[1].context.locale)
end)

FTestHelper:test("localization notifies locale changes and unsubscribe is idempotent", function()
    local localization = make_localization()
    local received = {}
    local subscription = localization:on_locale_changed(function(locale)
        table.insert(received, locale)
    end)
    localization:set_locale("en-US")
    subscription:unsubscribe()
    subscription:unsubscribe()
    localization:set_locale("zh-CN")
    FTestHelper:assert_equal("en-US", received[1])
    FTestHelper:assert_equal(1, #received)
end)

FTestHelper:test("localization rejects an unknown locale", function()
    local localization = make_localization()
    FTestHelper:assert_error_code("LOCALE_NOT_REGISTERED", function()
        localization:set_locale("ja-JP")
    end)
end)

FTestHelper:test("localization rejects missing interpolation parameters", function()
    local localization = make_localization()
    FTestHelper:assert_error_code("LOCALIZATION_PARAM_MISSING", function()
        localization:t("greeting", {})
    end)
end)
```

- [ ] **Step 2: 登记规格并确认 RED**

在 `Tests/run-shared.lua` 的 `FILoggerSpec.lua` 后加入：

```lua
"Tests/Unit/FILocalizationSpec.lua",
```

Run: `npm run test:shared`

Expected: 非零退出，错误包含 `module 'FLuaFramework.Shared.Localization.FILocalization' not found`。

- [ ] **Step 3: 实现 FILocalization**

创建 `FLuaFramework/Shared/Localization/FILocalization.lua`：

```lua
local FILocalization = FClass("FILocalization")

function FILocalization:ctor(options)
    self.locale = options.locale
    self.fallback = options.fallback
    self.catalogs = options.catalogs or {}
    self.logger = options.logger
    self.listeners = {}
end

function FILocalization:get_locale()
    return self.locale
end

function FILocalization:set_locale(locale)
    if self.catalogs[locale] == nil then
        error(FError:new("LOCALE_NOT_REGISTERED", "locale is not registered", {
            locale = locale,
        }), 0)
    end
    if locale == self.locale then return false end
    self.locale = locale
    local snapshot = {}
    for _, callback in pairs(self.listeners) do table.insert(snapshot, callback) end
    for _, callback in ipairs(snapshot) do callback(locale) end
    return true
end

function FILocalization:on_locale_changed(callback)
    local token = {}
    self.listeners[token] = callback
    local active = true
    return {
        unsubscribe = function()
            if not active then return false end
            active = false
            self.listeners[token] = nil
            return true
        end,
    }
end

function FILocalization:t(key, params)
    local current = self.catalogs[self.locale] or {}
    local fallback = self.catalogs[self.fallback] or {}
    local template = current[key] or fallback[key]
    if template == nil then
        if self.logger ~= nil then
            self.logger:warn("localization key missing", {
                key = key,
                locale = self.locale,
                fallback = self.fallback,
            })
        end
        return "[" .. tostring(key) .. "]"
    end
    local rendered = string.gsub(template, "{([%w_]+)}", function(name)
        local value = params and params[name] or nil
        if value == nil then
            error(FError:new(
                "LOCALIZATION_PARAM_MISSING",
                "localization parameter is missing",
                { key = key, parameter = name, locale = self.locale }
            ), 0)
        end
        return tostring(value)
    end)
    return rendered
end

return FILocalization
```

- [ ] **Step 4: 创建示例语言表**

创建 `FLuaFramework/Config/FLocales.lua`：

```lua
return {
    default = "zh-CN",
    fallback = "en-US",
    catalogs = {
        ["zh-CN"] = {
            login_title = "登录",
            login_success = "登录成功",
            login_failure = "登录失败",
        },
        ["en-US"] = {
            login_title = "Login",
            login_success = "Login succeeded",
            login_failure = "Login failed",
        },
    },
}
```

- [ ] **Step 5: 注册并加载检查新增模块**

在 `FLuaFramework/register.lua` 的 `FILogger` 后加入：

```lua
register("FILocalization", "FLuaFramework.Shared.Localization.FILocalization")
```

在 `Tests/SharedTestBootstrap.lua` 的 `FILogger` 后加入相同注册：

```lua
register("FILocalization", "FLuaFramework.Shared.Localization.FILocalization")
```

在 `Tests/check-shared.lua` 的配置加载部分加入：

```lua
require("FLuaFramework.Config.FLocales")
```

并把输出替换为：

```lua
print(string.format(
    "parsed %d shared framework modules and 5 config/app modules",
    count
))
```

- [ ] **Step 6: 运行本地化与 Shared 回归**

Run: `npm run test:shared`

Expected: `62 shared passed, 0 failed`。

Run: `npm run check:shared`

Expected: `parsed 22 shared framework modules and 5 config/app modules`。

### Task 4: 保存 Loading 页面期望可见性

**Files:**
- Modify: `FLuaFramework/Shared/Core/FUIManager.lua`
- Modify: `Tests/Unit/FUILayerSpec.lua`
- Create: `Tests/Unit/FUIRouterAsyncSpec.lua`
- Modify: `Tests/run-shared.lua`

- [ ] **Step 1: 写 Loading 隐藏意图失败规格**

在 `Tests/Unit/FUILayerSpec.lua` 末尾追加：

```lua
FTestHelper:test("manager applies hide requested while page is loading", function()
    local manager, runtime = make_manager()
    manager:open("MainPanel")
    FTestHelper:assert_true(manager:hide("MainPanel"))
    runtime:complete_next()

    local instance = manager:get("MainPanel")
    FTestHelper:assert_equal("Hidden", instance.lifecycle:get_state())
    FTestHelper:assert_false(instance.view.native.visible)
    FTestHelper:assert_true(manager:show("MainPanel"))
    FTestHelper:assert_equal("Opened", instance.lifecycle:get_state())
end)
```

- [ ] **Step 2: 写 Router 连续异步 push 失败规格**

创建 `Tests/Unit/FUIRouterAsyncSpec.lua`：

```lua
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
```

在 `Tests/run-shared.lua` 的 `FUIRouterSpec.lua` 后加入：

```lua
"Tests/Unit/FUIRouterAsyncSpec.lua",
```

- [ ] **Step 3: 运行规格并确认 RED**

Run: `npm run test:shared`

Expected: 两个新增用例失败；`FUIManager:hide` 对 Loading 返回 false，Router 抛出 `ROUTE_NOT_READY`。

- [ ] **Step 4: 实现 desired_visible**

把 `FUIManager:hide` 替换为：

```lua
function FUIManager:hide(page_name)
    local instance = self.instances[page_name]
    if instance == nil then return false end
    if instance.lifecycle:get_state() == "Loading" then
        instance.desired_visible = false
        return true
    end
    if instance.lifecycle:get_state() ~= "Opened" then return false end
    instance.desired_visible = false
    instance.presenter:on_hide()
    instance.view:set_visible(false)
    instance.lifecycle:transition_to("Hidden")
    return true
end
```

把 `FUIManager:show` 替换为：

```lua
function FUIManager:show(page_name)
    local instance = self.instances[page_name]
    if instance == nil then return false end
    if instance.lifecycle:get_state() == "Loading" then
        instance.desired_visible = true
        return true
    end
    if instance.lifecycle:get_state() ~= "Hidden" then return false end
    instance.desired_visible = true
    instance.lifecycle:transition_to("Opened")
    instance.view:set_visible(true)
    instance.presenter:on_show()
    return true
end
```

在 `FUIManager:open` 创建的 `instance` 中加入：

```lua
desired_visible = true,
```

把 `_finish_open` 中 `on_open` 后的显示代码替换为：

```lua
instance.presenter:on_open(instance.params)
if instance.desired_visible then
    instance.view:set_visible(true)
    instance.presenter:on_show()
else
    instance.view:set_visible(false)
    instance.lifecycle:transition_to("Hidden")
end
```

- [ ] **Step 5: 运行异步路由与 Shared 回归**

Run: `npm run test:shared`

Expected: `64 shared passed, 0 failed`。

### Task 5: 实现 Presenter 状态快照与导航栈恢复

**Files:**
- Modify: `FLuaFramework/Shared/Core/FUIManager.lua`
- Modify: `FLuaFramework/Shared/Core/FUIRouter.lua`
- Create: `Tests/Unit/FUIStateRecoverySpec.lua`
- Modify: `Tests/run-shared.lua`

- [ ] **Step 1: 写四个状态恢复失败规格**

创建 `Tests/Unit/FUIStateRecoverySpec.lua`：

```lua
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
```

在 `Tests/run-shared.lua` 的 `FUIRouterAsyncSpec.lua` 后加入：

```lua
"Tests/Unit/FUIStateRecoverySpec.lua",
```

- [ ] **Step 2: 运行状态规格并确认 RED**

Run: `npm run test:shared`

Expected: 非零退出，首个用例失败于 `attempt to call a nil value (method 'capture_state')`。

- [ ] **Step 3: 让 Manager 捕获并恢复 Presenter 状态**

在 `FUIManager` 中加入：

```lua
function FUIManager:capture_state(page_name)
    local instance = self.instances[page_name]
    if instance == nil or instance.presenter == nil then return nil end
    local state = instance.lifecycle:get_state()
    if state ~= "Opened" and state ~= "Hidden" then return nil end
    return instance.presenter:on_save_state()
end
```

把 `FUIManager:open` 签名改为：

```lua
function FUIManager:open(page_name, params, restore_state)
```

在创建的 `instance` 中加入：

```lua
restore_state = restore_state,
```

在 `_finish_open` 中，把 Presenter 创建到绑定之间的代码固定为：

```lua
instance.presenter = presenter_module:new(self.services)
instance.presenter:on_create(instance.view, instance.params)
if instance.restore_state ~= nil then
    instance.presenter:on_restore_state(instance.restore_state)
end
instance.presenter:on_bind()
```

- [ ] **Step 4: 实现 Router 快照与恢复**

在 `FUIRouter.lua` 顶部类定义后加入：

```lua
local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] ~= nil then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do
        result[copy(key, seen)] = copy(item, seen)
    end
    return result
end
```

在 `return FUIRouter` 前加入：

```lua
function FUIRouter:snapshot()
    local routes = {}
    for index, entry in ipairs(self.stack) do
        routes[index] = {
            page = entry.page,
            params = copy(entry.params),
            state = copy(self.manager:capture_state(entry.page)),
        }
    end
    return { version = 1, routes = routes }
end

function FUIRouter:restore(snapshot)
    if type(snapshot) ~= "table"
        or snapshot.version ~= 1
        or type(snapshot.routes) ~= "table"
        or #snapshot.routes == 0 then
        error(FError:new("INVALID_ROUTE_SNAPSHOT", "route snapshot is invalid", {}), 0)
    end

    for _, route in ipairs(snapshot.routes) do
        if type(route) ~= "table" or type(route.page) ~= "string" then
            error(FError:new("INVALID_ROUTE_SNAPSHOT", "route entry is invalid", {}), 0)
        end
        self:_definition(route.page)
    end

    for index = #self.stack, 1, -1 do
        self.manager:close(self.stack[index].page, "restore")
        self.stack[index] = nil
    end

    local previous = nil
    for _, route in ipairs(snapshot.routes) do
        if previous ~= nil then self.manager:hide(previous.page) end
        self.manager:open(route.page, copy(route.params), copy(route.state))
        local entry = { page = route.page, params = copy(route.params) }
        table.insert(self.stack, entry)
        previous = entry
    end
    return self:current()
end
```

- [ ] **Step 5: 运行状态恢复与 Shared 全量测试**

Run: `npm run test:shared`

Expected: `68 shared passed, 0 failed`。

Run: `npm run check:shared`

Expected: `parsed 22 shared framework modules and 5 config/app modules`。

### Task 6: 完成 Shared-only 验收与交接

**Files:**
- Modify: `docs/myDocs/phase-three-shared-execution-guide.md`

- [ ] **Step 1: 同步实际测试数量**

执行计划后，把 `docs/myDocs/phase-three-shared-execution-guide.md` 中的目标结果固定为：

```text
npm run test:shared  -> 68 shared passed, 0 failed
npm run check:shared -> parsed 22 shared framework modules and 5 config/app modules
```

- [ ] **Step 2: 验证没有修改 Adapter 范围**

Run:

```powershell
git diff --name-only -- FLuaFramework/Adapters Tests/Contract Tests/Integration Tests/Unit/FViewBinderSpec.lua
```

Expected: 无输出。

- [ ] **Step 3: 验证 Shared 层没有平台 API 泄漏**

Run:

```powershell
rg -n "UE\.|UnityEngine\.|CS\." FLuaFramework/Shared FLuaFramework/App
```

Expected: 退出码 1 且无输出。

- [ ] **Step 4: 验证生产模块依赖和格式**

Run: `node Tests/check-requires.js`

Expected: `framework require check passed`。

Run: `git diff --check`

Expected: 退出码 0 且无输出。

- [ ] **Step 5: 人工核对验收矩阵**

确认：

- Shared runner 不包含 Adapter、Contract 或双平台 Integration Spec；
- Presenter `on_unbind` 会尝试清理全部订阅、请求和资源，即使其中一个失败；
- 本地化具备当前语言、回退语言、参数插值、缺失诊断和可解绑切换事件；
- Router 可在上一页仍 Loading 时继续 push，页面加载完成后不会同时显示；
- 快照只保存导航栈、params 和 Presenter 纯 Lua state，不保存 View、原生对象、订阅或资源句柄；
- restore 在重建 Presenter 时调用 `on_restore_state`，并恢复栈内页面显隐；
- `FLuaFramework/Adapters/**` 和 Adapter 测试没有差异。

- [ ] **Step 6: 交由完成分支流程统一提交与集成**

使用 `superpowers:finishing-a-development-branch` 重新运行 `npm run test:shared`、`npm run check:shared` 和静态检查，再选择本地合并、推送 PR、保留分支或丢弃。不要在本计划任务中创建零散提交。

## 自检结论

- **现状覆盖：** 计划以提交 `d1482aa` 和 `73 passed` 为真实基线，不重复阶段二已经完成的 Shared 模块。
- **Adapter 隔离：** 文件范围、runner、验收命令和差异检查四处同时排除 Adapters。
- **可独立交付：** Presenter 清理、本地化、异步可见性和状态恢复均可使用 Fake Runtime/Mock View 在纯 Lua 下工作。
- **延期项明确：** 虚拟列表、对象池、原生动画和 Adapter 契约测试在没有平台 Adapter 的前提下不伪装成已完成。
- **接口一致：** 状态钩子统一为 `on_save_state/on_restore_state`，快照字段统一为 `version/routes/page/params/state`，可见性字段统一为 `desired_visible`。
- **测试增量：** Shared runner 从 51 项增加 17 项到 `68 shared passed, 0 failed`。
