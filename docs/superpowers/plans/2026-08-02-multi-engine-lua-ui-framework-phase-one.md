# 多引擎 Lua UI 框架阶段一：最小闭环 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有纯 Lua 测试基线上，实现同一个 `LoginPresenter.lua` 通过 Unreal/Unity 两套最小 Runtime Adapter 完成页面异步打开、事件绑定、登录反馈和安全关闭的可测试闭环。

**Architecture:** `Shared` 只依赖注入的 Runtime、页面注册表和 Lua 契约包装对象；`Adapters/Common` 负责绑定校验与控件包装，`Adapters/Unreal`、`Adapters/Unity` 只把不同宿主桥接 API 归一化。`FUIManager` 以显式生命周期和递增请求版本管理异步打开，用 Presenter 的订阅袋保证 `on_bind`/`on_unbind` 对称，关闭加载中页面时取消请求并忽略迟到回调。

**Tech Stack:** Lua 5.3 兼容语法、Fengari Node CLI、npm、仓库内轻量 Lua 测试运行器；UnLua/xLua 宿主桥接通过依赖注入模拟和验证。

---

## 实施边界与文件结构

当前基线已有 `FError`、`FEventBus`、`FStore`、`FCommand`、`FValidation` 及 14 个通过的测试，本计划不重复创建或重构它们。阶段一不实现 `FUIRouter`、层级系统、`FIInput`、资源通用 `AssetRef`、列表、动画、热重载和真实 UE/Unity 二进制资源；这些保持在设计文档的后续阶段。

Login 最小示例使用 `open("LoginPanel", { account = ... })` 传入账号，覆盖以下稳定绑定：

```lua
{
    title = "Text",
    account_text = "Text",
    login_button = "Button",
    status_text = "Text",
    avatar = "Image",
}
```

这让阶段一严格只依赖 `View/Text/Button/Image`。真实账号和密码输入在阶段二加入 `FIInput` 后扩展，阶段一不伪装输入控件。

计划结束后的目录职责如下：

```text
LuaUIFramework/
├─ Shared/
│  ├─ Contracts/
│  │  ├─ FIWidget.lua          # 控件有效性与显隐基础行为
│  │  ├─ FIText.lua            # 文本读写
│  │  ├─ FIButton.lua          # 点击订阅
│  │  ├─ FIImage.lua           # 图片 source 写入
│  │  └─ FIView.lua            # 按逻辑 ID 和类型获取控件
│  └─ Core/
│     ├─ FBasePresenter.lua    # 订阅句柄集中释放
│     ├─ FLifecycle.lua        # 页面状态机
│     └─ FUIManager.lua        # 注册、加载、打开、关闭与实例查询
├─ Adapters/
│  ├─ Common/FViewBinder.lua   # requiredBindings 校验及包装对象创建
│  ├─ Unreal/FUnrealRuntime.lua# UnLua/UMG 桥接函数归一化
│  └─ Unity/FUnityRuntime.lua  # xLua/UGUI 桥接函数归一化
├─ App/UI/Login/LoginPresenter.lua
└─ Config/FPages.lua
Tests/
├─ Fixtures/FFakePlatformBridge.lua
├─ Unit/
│  ├─ FLifecycleSpec.lua
│  ├─ FBasePresenterSpec.lua
│  └─ FViewBinderSpec.lua
├─ Contract/FRuntimeContractSpec.lua
└─ Integration/
   ├─ FUIManagerSpec.lua
   └─ LoginPanelSpec.lua
```

### Task 1: 扩展测试入口与断言能力

**Files:**
- Modify: `Tests/TestHelper.lua`
- Modify: `Tests/run.lua`

- [ ] **Step 1: 为后续诊断测试写入缺失断言**

在 `Tests/TestHelper.lua` 的 `assert_nil` 后加入以下完整实现：

```lua
function FTestHelper:assert_not_nil(value)
    if value == nil then
        error("expected a non-nil value", 2)
    end
end

function FTestHelper:assert_contains(expected_fragment, actual)
    local text = tostring(actual)
    if string.find(text, expected_fragment, 1, true) == nil then
        error(string.format("expected %s to contain %s", text, expected_fragment), 2)
    end
end
```

- [ ] **Step 2: 运行基线测试，确认辅助断言没有破坏现有行为**

Run: `npm test`

Expected: 退出码为 0，结尾为 `14 passed, 0 failed`。

- [ ] **Step 3: 将阶段一测试文件登记到测试入口**

把 `Tests/run.lua` 中的 `specs` 替换为：

```lua
local specs = {
    "Tests/Unit/FEventBusSpec.lua",
    "Tests/Unit/FStoreSpec.lua",
    "Tests/Unit/FLifecycleSpec.lua",
    "Tests/Unit/FBasePresenterSpec.lua",
    "Tests/Unit/FViewBinderSpec.lua",
    "Tests/Contract/FRuntimeContractSpec.lua",
    "Tests/Integration/FUIManagerSpec.lua",
    "Tests/Integration/LoginPanelSpec.lua",
}
```

- [ ] **Step 4: 运行测试并确认新增测试文件尚不存在**

Run: `npm test`

Expected: 非零退出，错误包含 `cannot open Tests/Unit/FLifecycleSpec.lua`。这是本任务的 RED 状态，后续任务逐个补齐这些文件。

### Task 2: 实现显式生命周期与 Presenter 订阅释放

**Files:**
- Create: `Tests/Unit/FLifecycleSpec.lua`
- Create: `Tests/Unit/FBasePresenterSpec.lua`
- Create: `LuaUIFramework/Shared/Core/FLifecycle.lua`
- Create: `LuaUIFramework/Shared/Core/FBasePresenter.lua`

- [ ] **Step 1: 写生命周期失败测试**

创建 `Tests/Unit/FLifecycleSpec.lua`：

```lua
local FTestHelper = require("Tests.TestHelper")
local FLifecycle = require("LuaUIFramework.Shared.Core.FLifecycle")

FTestHelper:test("lifecycle follows the page open and destroy path", function()
    local lifecycle = FLifecycle.new()
    FTestHelper:assert_equal("Unloaded", lifecycle:get_state())
    lifecycle:transition_to("Loading")
    lifecycle:transition_to("Created")
    lifecycle:transition_to("Opened")
    lifecycle:transition_to("Closing")
    lifecycle:transition_to("Destroyed")
    FTestHelper:assert_equal("Destroyed", lifecycle:get_state())
end)

FTestHelper:test("loading can return to unloaded when an open is cancelled", function()
    local lifecycle = FLifecycle.new()
    lifecycle:transition_to("Loading")
    lifecycle:transition_to("Unloaded")
    FTestHelper:assert_equal("Unloaded", lifecycle:get_state())
end)

FTestHelper:test("lifecycle rejects invalid transitions with state context", function()
    local lifecycle = FLifecycle.new()
    local succeeded, failure = pcall(function()
        lifecycle:transition_to("Opened")
    end)
    FTestHelper:assert_false(succeeded)
    FTestHelper:assert_equal("INVALID_LIFECYCLE_TRANSITION", failure.code)
    FTestHelper:assert_equal("Unloaded", failure.context.from)
    FTestHelper:assert_equal("Opened", failure.context.to)
end)
```

- [ ] **Step 2: 运行生命周期测试并确认 RED**

Run: `node_modules/.bin/fengari Tests/Unit/FLifecycleSpec.lua`

Expected: 非零退出，错误包含 `module 'LuaUIFramework.Shared.Core.FLifecycle' not found`。

- [ ] **Step 3: 写生命周期最小实现**

创建 `LuaUIFramework/Shared/Core/FLifecycle.lua`：

```lua
local FError = require("LuaUIFramework.Shared.Core.FError")

local FLifecycle = {}
FLifecycle.__index = FLifecycle

local transitions = {
    Unloaded = { Loading = true },
    Loading = { Created = true, Unloaded = true },
    Created = { Opened = true, Closing = true },
    Opened = { Hidden = true, Closing = true },
    Hidden = { Opened = true, Closing = true },
    Closing = { Hidden = true, Destroyed = true },
    Destroyed = {},
}

function FLifecycle.new()
    return setmetatable({ state = "Unloaded" }, FLifecycle)
end

function FLifecycle:get_state()
    return self.state
end

function FLifecycle:transition_to(next_state)
    if transitions[self.state] == nil or transitions[self.state][next_state] ~= true then
        error(FError.new(
            "INVALID_LIFECYCLE_TRANSITION",
            string.format("cannot transition page lifecycle from %s to %s", self.state, tostring(next_state)),
            { from = self.state, to = next_state }
        ), 0)
    end
    self.state = next_state
    return next_state
end

return FLifecycle
```

- [ ] **Step 4: 写 Presenter 订阅袋失败测试**

创建 `Tests/Unit/FBasePresenterSpec.lua`：

```lua
local FTestHelper = require("Tests.TestHelper")
local FBasePresenter = require("LuaUIFramework.Shared.Core.FBasePresenter")

FTestHelper:test("presenter unbind releases every tracked subscription once", function()
    local presenter = FBasePresenter.new()
    local first_calls = 0
    local second_calls = 0
    presenter:track({ unsubscribe = function() first_calls = first_calls + 1 end })
    presenter:track({ unsubscribe = function() second_calls = second_calls + 1 end })

    presenter:on_unbind()
    presenter:on_unbind()

    FTestHelper:assert_equal(1, first_calls)
    FTestHelper:assert_equal(1, second_calls)
end)

FTestHelper:test("presenter rejects invalid subscription handles", function()
    FTestHelper:assert_error_code("INVALID_SUBSCRIPTION", function()
        FBasePresenter.new():track({})
    end)
end)
```

- [ ] **Step 5: 写 Presenter 最小实现**

创建 `LuaUIFramework/Shared/Core/FBasePresenter.lua`：

```lua
local FError = require("LuaUIFramework.Shared.Core.FError")

local FBasePresenter = {}
FBasePresenter.__index = FBasePresenter

function FBasePresenter.new()
    return setmetatable({ subscriptions = {}, unbound = false }, FBasePresenter)
end

function FBasePresenter.initialize(instance)
    instance.subscriptions = {}
    instance.unbound = false
    return instance
end

function FBasePresenter:track(subscription)
    if type(subscription) ~= "table" or type(subscription.unsubscribe) ~= "function" then
        error(FError.new("INVALID_SUBSCRIPTION", "subscription must expose unsubscribe", {}), 0)
    end
    table.insert(self.subscriptions, subscription)
    return subscription
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

function FBasePresenter:on_unbind()
    if self.unbound then
        return
    end
    self.unbound = true
    for index = #self.subscriptions, 1, -1 do
        self.subscriptions[index]:unsubscribe()
        self.subscriptions[index] = nil
    end
end

function FBasePresenter:on_destroy()
    self.view = nil
    self.params = nil
end

return FBasePresenter
```

- [ ] **Step 6: 运行两个单元测试并确认 GREEN**

Run: `node_modules/.bin/fengari -e "dofile('Tests/Unit/FLifecycleSpec.lua'); dofile('Tests/Unit/FBasePresenterSpec.lua'); local h=require('Tests.TestHelper'); for _,c in ipairs(h.tests) do assert(pcall(c.body)) end"`

Expected: 退出码为 0，无输出。

### Task 3: 实现基础 View/Text/Button/Image 契约和绑定校验

**Files:**
- Create: `Tests/Unit/FViewBinderSpec.lua`
- Create: `LuaUIFramework/Shared/Contracts/FIWidget.lua`
- Create: `LuaUIFramework/Shared/Contracts/FIText.lua`
- Create: `LuaUIFramework/Shared/Contracts/FIButton.lua`
- Create: `LuaUIFramework/Shared/Contracts/FIImage.lua`
- Create: `LuaUIFramework/Shared/Contracts/FIView.lua`
- Create: `LuaUIFramework/Adapters/Common/FViewBinder.lua`

- [ ] **Step 1: 写缺失绑定、类型错误和已销毁对象的失败测试**

创建 `Tests/Unit/FViewBinderSpec.lua`：

```lua
local FTestHelper = require("Tests.TestHelper")
local FViewBinder = require("LuaUIFramework.Adapters.Common.FViewBinder")

local function make_bridge(bindings)
    return {
        resolve = function(_, id) return bindings[id] end,
        kind = function(widget) return widget.kind end,
        widget_ops = function(widget)
            return {
                is_valid = function() return widget.valid end,
                set_visible = function(value) widget.visible = value end,
                set_text = function(value) widget.text = value end,
                get_text = function() return widget.text end,
                on_click = function(callback)
                    widget.click = callback
                    return { unsubscribe = function() widget.click = nil end }
                end,
                set_source = function(value) widget.source = value end,
            }
        end,
        view_ops = function(root)
            return {
                is_valid = function() return root.valid end,
                set_visible = function(value) root.visible = value end,
                destroy = function() root.valid = false end,
            }
        end,
    }
end

FTestHelper:test("view binder reports a missing binding with diagnostics", function()
    local bridge = make_bridge({})
    local succeeded, failure = pcall(function()
        FViewBinder.bind("LoginPanel", "unreal", { valid = true }, { title = "Text" }, bridge)
    end)
    FTestHelper:assert_false(succeeded)
    FTestHelper:assert_equal("BINDING_NOT_FOUND", failure.code)
    FTestHelper:assert_equal("LoginPanel", failure.context.page)
    FTestHelper:assert_equal("unreal", failure.context.platform)
    FTestHelper:assert_equal("title", failure.context.binding)
end)

FTestHelper:test("view binder rejects a binding type mismatch", function()
    local bridge = make_bridge({ title = { kind = "Button", valid = true } })
    local succeeded, failure = pcall(function()
        FViewBinder.bind("LoginPanel", "unity", { valid = true }, { title = "Text" }, bridge)
    end)
    FTestHelper:assert_false(succeeded)
    FTestHelper:assert_equal("BINDING_TYPE_MISMATCH", failure.code)
    FTestHelper:assert_equal("Text", failure.context.expected)
    FTestHelper:assert_equal("Button", failure.context.actual)
end)

FTestHelper:test("view exposes typed widgets and rejects access after destroy", function()
    local title = { kind = "Text", valid = true, text = "" }
    local button = { kind = "Button", valid = true }
    local avatar = { kind = "Image", valid = true }
    local root = { valid = true }
    local view = FViewBinder.bind("LoginPanel", "unreal", root, {
        title = "Text", login_button = "Button", avatar = "Image",
    }, make_bridge({ title = title, login_button = button, avatar = avatar }))

    view:text("title"):set_text("登录")
    view:image("avatar"):set_source("avatar/default")
    local calls = 0
    local subscription = view:button("login_button"):on_click(function() calls = calls + 1 end)
    button.click()
    subscription:unsubscribe()
    FTestHelper:assert_equal("登录", title.text)
    FTestHelper:assert_equal("avatar/default", avatar.source)
    FTestHelper:assert_equal(1, calls)

    view:destroy()
    FTestHelper:assert_error_code("NATIVE_OBJECT_INVALID", function() view:text("title") end)
end)
```

- [ ] **Step 2: 运行绑定测试并确认 RED**

Run: `node_modules/.bin/fengari Tests/Unit/FViewBinderSpec.lua`

Expected: 非零退出，错误包含 `module 'LuaUIFramework.Adapters.Common.FViewBinder' not found`。

- [ ] **Step 3: 实现基础控件及三个专用控件**

创建 `LuaUIFramework/Shared/Contracts/FIWidget.lua`：

```lua
local FError = require("LuaUIFramework.Shared.Core.FError")
local FIWidget = {}
FIWidget.__index = FIWidget

function FIWidget.new(id, native, ops)
    return setmetatable({ id = id, native = native, ops = ops }, FIWidget)
end

function FIWidget:_assert_valid()
    if self.native == nil or self.ops.is_valid() ~= true then
        error(FError.new("NATIVE_OBJECT_INVALID", "native widget is no longer valid", { binding = self.id }), 0)
    end
end

function FIWidget:set_visible(value)
    self:_assert_valid()
    self.ops.set_visible(value == true)
end

return FIWidget
```

创建 `LuaUIFramework/Shared/Contracts/FIText.lua`：

```lua
local FIWidget = require("LuaUIFramework.Shared.Contracts.FIWidget")
local FIText = {}
FIText.__index = FIText
setmetatable(FIText, { __index = FIWidget })

function FIText.new(id, native, ops)
    return setmetatable(FIWidget.new(id, native, ops), FIText)
end

function FIText:set_text(value)
    self:_assert_valid()
    self.ops.set_text(value == nil and "" or tostring(value))
end

function FIText:get_text()
    self:_assert_valid()
    return self.ops.get_text()
end

return FIText
```

创建 `LuaUIFramework/Shared/Contracts/FIButton.lua`：

```lua
local FIWidget = require("LuaUIFramework.Shared.Contracts.FIWidget")
local FIButton = {}
FIButton.__index = FIButton
setmetatable(FIButton, { __index = FIWidget })

function FIButton.new(id, native, ops)
    return setmetatable(FIWidget.new(id, native, ops), FIButton)
end

function FIButton:on_click(callback)
    self:_assert_valid()
    return self.ops.on_click(callback)
end

return FIButton
```

创建 `LuaUIFramework/Shared/Contracts/FIImage.lua`：

```lua
local FIWidget = require("LuaUIFramework.Shared.Contracts.FIWidget")
local FIImage = {}
FIImage.__index = FIImage
setmetatable(FIImage, { __index = FIWidget })

function FIImage.new(id, native, ops)
    return setmetatable(FIWidget.new(id, native, ops), FIImage)
end

function FIImage:set_source(source)
    self:_assert_valid()
    self.ops.set_source(source)
end

return FIImage
```

- [ ] **Step 4: 实现 View 的类型安全访问与销毁语义**

创建 `LuaUIFramework/Shared/Contracts/FIView.lua`：

```lua
local FError = require("LuaUIFramework.Shared.Core.FError")
local FIView = {}
FIView.__index = FIView

function FIView.new(page, platform, native, root_ops, widgets)
    return setmetatable({
        page = page,
        platform = platform,
        native = native,
        root_ops = root_ops,
        widgets = widgets,
        destroyed = false,
    }, FIView)
end

function FIView:_assert_valid()
    if self.destroyed or self.native == nil or self.root_ops.is_valid() ~= true then
        error(FError.new("NATIVE_OBJECT_INVALID", "native view is no longer valid", {
            page = self.page, platform = self.platform,
        }), 0)
    end
end

function FIView:_get(id, expected)
    self:_assert_valid()
    local entry = self.widgets[id]
    if entry == nil or entry.kind ~= expected then
        error(FError.new("BINDING_TYPE_MISMATCH", "view binding was requested with the wrong type", {
            page = self.page, platform = self.platform, binding = id,
            expected = expected, actual = entry and entry.kind or nil,
        }), 0)
    end
    return entry.widget
end

function FIView:text(id) return self:_get(id, "Text") end
function FIView:button(id) return self:_get(id, "Button") end
function FIView:image(id) return self:_get(id, "Image") end

function FIView:set_visible(value)
    self:_assert_valid()
    self.root_ops.set_visible(value == true)
end

function FIView:destroy()
    if self.destroyed then return end
    self.destroyed = true
    self.root_ops.destroy()
    self.native = nil
end

return FIView
```

- [ ] **Step 5: 实现声明绑定与启动校验**

创建 `LuaUIFramework/Adapters/Common/FViewBinder.lua`：

```lua
local FError = require("LuaUIFramework.Shared.Core.FError")
local FIText = require("LuaUIFramework.Shared.Contracts.FIText")
local FIButton = require("LuaUIFramework.Shared.Contracts.FIButton")
local FIImage = require("LuaUIFramework.Shared.Contracts.FIImage")
local FIView = require("LuaUIFramework.Shared.Contracts.FIView")

local FViewBinder = {}
local factories = { Text = FIText.new, Button = FIButton.new, Image = FIImage.new }

function FViewBinder.bind(page, platform, native_view, required_bindings, bridge)
    local widgets = {}
    for id, expected in pairs(required_bindings) do
        local native_widget = bridge.resolve(native_view, id)
        if native_widget == nil then
            error(FError.new("BINDING_NOT_FOUND", "required view binding was not found", {
                page = page, platform = platform, binding = id, expected = expected,
            }), 0)
        end
        local actual = bridge.kind(native_widget)
        if actual ~= expected or factories[expected] == nil then
            error(FError.new("BINDING_TYPE_MISMATCH", "view binding type does not match", {
                page = page, platform = platform, binding = id, expected = expected, actual = actual,
            }), 0)
        end
        widgets[id] = {
            kind = actual,
            widget = factories[actual](id, native_widget, bridge.widget_ops(native_widget, actual)),
        }
    end
    return FIView.new(page, platform, native_view, bridge.view_ops(native_view), widgets)
end

return FViewBinder
```

- [ ] **Step 6: 运行绑定测试并确认 GREEN**

Run: `node_modules/.bin/fengari -e "dofile('Tests/Unit/FViewBinderSpec.lua'); local h=require('Tests.TestHelper'); for _,c in ipairs(h.tests) do local ok,e=pcall(c.body); if not ok then error(e) end end"`

Expected: 退出码为 0，无输出。

### Task 4: 注入 Runtime 并让 Unreal/Unity 通过同一契约

**Files:**
- Create: `Tests/Fixtures/FFakePlatformBridge.lua`
- Create: `Tests/Contract/FRuntimeContractSpec.lua`
- Create: `LuaUIFramework/Adapters/Unreal/FUnrealRuntime.lua`
- Create: `LuaUIFramework/Adapters/Unity/FUnityRuntime.lua`

- [ ] **Step 1: 创建可控异步加载和原生控件行为的测试桥接器**

创建 `Tests/Fixtures/FFakePlatformBridge.lua`，对外提供以下接口和确定行为：

```lua
local FFakePlatformBridge = {}
FFakePlatformBridge.__index = FFakePlatformBridge

function FFakePlatformBridge.new(platform)
    return setmetatable({ platform = platform, pending = {}, destroyed = 0 }, FFakePlatformBridge)
end

function FFakePlatformBridge:make_native_view()
    local widgets = {}
    local function add(id, kind)
        widgets[id] = { id = id, kind = kind, valid = true, visible = true, text = "", source = nil }
    end
    add("title", "Text")
    add("account_text", "Text")
    add("login_button", "Button")
    add("status_text", "Text")
    add("avatar", "Image")
    return { valid = true, visible = false, widgets = widgets }
end

function FFakePlatformBridge:_load(asset, callback)
    local request = { asset = asset, callback = callback, cancelled = false }
    table.insert(self.pending, request)
    return { cancel = function() request.cancelled = true end }
end

function FFakePlatformBridge:complete_next(deliver_cancelled)
    local request = table.remove(self.pending, 1)
    if request ~= nil and (not request.cancelled or deliver_cancelled == true) then
        request.callback(self:make_native_view())
    end
end

function FFakePlatformBridge:_resolve(root, id) return root.widgets[id] end
function FFakePlatformBridge:_kind(widget) return widget.kind end

function FFakePlatformBridge:_widget_ops(widget)
    return {
        is_valid = function() return widget.valid end,
        set_visible = function(value) widget.visible = value end,
        set_text = function(value) widget.text = value end,
        get_text = function() return widget.text end,
        on_click = function(callback)
            widget.click = callback
            local active = true
            return { unsubscribe = function()
                if active then active = false; widget.click = nil end
            end }
        end,
        set_source = function(source) widget.source = source end,
    }
end

function FFakePlatformBridge:_view_ops(root)
    return {
        is_valid = function() return root.valid end,
        set_visible = function(value) root.visible = value end,
        destroy = function()
            if root.valid then root.valid = false; self.destroyed = self.destroyed + 1 end
            for _, widget in pairs(root.widgets) do widget.valid = false; widget.click = nil end
        end,
    }
end

function FFakePlatformBridge:as_unreal()
    return {
        load_widget = function(asset, callback) return self:_load(asset, callback) end,
        find_widget = function(root, id) return self:_resolve(root, id) end,
        get_widget_type = function(widget) return self:_kind(widget) end,
        make_widget_ops = function(widget) return self:_widget_ops(widget) end,
        make_view_ops = function(root) return self:_view_ops(root) end,
    }
end

function FFakePlatformBridge:as_unity()
    return {
        load_prefab = function(asset, callback) return self:_load(asset, callback) end,
        find_component = function(root, id) return self:_resolve(root, id) end,
        get_component_type = function(widget) return self:_kind(widget) end,
        make_component_ops = function(widget) return self:_widget_ops(widget) end,
        make_view_ops = function(root) return self:_view_ops(root) end,
    }
end

return FFakePlatformBridge
```

- [ ] **Step 2: 写两个 Runtime 必须共同通过的契约测试**

创建 `Tests/Contract/FRuntimeContractSpec.lua`：

```lua
local FTestHelper = require("Tests.TestHelper")
local FFakePlatformBridge = require("Tests.Fixtures.FFakePlatformBridge")
local FUnrealRuntime = require("LuaUIFramework.Adapters.Unreal.FUnrealRuntime")
local FUnityRuntime = require("LuaUIFramework.Adapters.Unity.FUnityRuntime")

local cases = {
    { platform = "unreal", runtime = FUnrealRuntime, bridge = "as_unreal" },
    { platform = "unity", runtime = FUnityRuntime, bridge = "as_unity" },
}

for _, case in ipairs(cases) do
    FTestHelper:test(case.platform .. " runtime loads and binds the same view contract", function()
        local fake = FFakePlatformBridge.new(case.platform)
        local runtime = case.runtime.new(fake[case.bridge](fake))
        local received = nil
        local request = runtime:load_view("asset/login", function(native) received = native end)
        FTestHelper:assert_not_nil(request.cancel)
        fake:complete_next()
        local view = runtime:bind_view("LoginPanel", received, {
            title = "Text", login_button = "Button", avatar = "Image",
        })
        view:text("title"):set_text("Login")
        view:image("avatar"):set_source("avatar/default")
        FTestHelper:assert_equal("Login", received.widgets.title.text)
        FTestHelper:assert_equal("avatar/default", received.widgets.avatar.source)
    end)
end
```

- [ ] **Step 3: 运行契约测试并确认 RED**

Run: `node_modules/.bin/fengari Tests/Contract/FRuntimeContractSpec.lua`

Expected: 非零退出，错误包含 `module 'LuaUIFramework.Adapters.Unreal.FUnrealRuntime' not found`。

- [ ] **Step 4: 实现 Unreal Runtime 归一化层**

创建 `LuaUIFramework/Adapters/Unreal/FUnrealRuntime.lua`：

```lua
local FViewBinder = require("LuaUIFramework.Adapters.Common.FViewBinder")
local FUnrealRuntime = {}
FUnrealRuntime.__index = FUnrealRuntime

function FUnrealRuntime.new(bridge)
    return setmetatable({ platform = "unreal", bridge = bridge }, FUnrealRuntime)
end


function FUnrealRuntime:load_view(asset, callback)
    return self.bridge.load_widget(asset, callback)
end


function FUnrealRuntime:bind_view(page, native_view, required_bindings)
    local bridge = self.bridge
    return FViewBinder.bind(page, self.platform, native_view, required_bindings, {
        resolve = bridge.find_widget,
        kind = bridge.get_widget_type,
        widget_ops = bridge.make_widget_ops,
        view_ops = bridge.make_view_ops,
    })
end

return FUnrealRuntime
```

- [ ] **Step 5: 实现 Unity Runtime 归一化层**

创建 `LuaUIFramework/Adapters/Unity/FUnityRuntime.lua`：

```lua
local FViewBinder = require("LuaUIFramework.Adapters.Common.FViewBinder")
local FUnityRuntime = {}
FUnityRuntime.__index = FUnityRuntime

function FUnityRuntime.new(bridge)
    return setmetatable({ platform = "unity", bridge = bridge }, FUnityRuntime)
end

function FUnityRuntime:load_view(asset, callback)
    return self.bridge.load_prefab(asset, callback)
end

function FUnityRuntime:bind_view(page, native_view, required_bindings)
    local bridge = self.bridge
    return FViewBinder.bind(page, self.platform, native_view, required_bindings, {
        resolve = bridge.find_component,
        kind = bridge.get_component_type,
        widget_ops = bridge.make_component_ops,
        view_ops = bridge.make_view_ops,
    })
end

return FUnityRuntime
```

- [ ] **Step 6: 运行 Runtime 契约测试并确认 GREEN**

Run: `node_modules/.bin/fengari -e "dofile('Tests/Contract/FRuntimeContractSpec.lua'); local h=require('Tests.TestHelper'); for _,c in ipairs(h.tests) do local ok,e=pcall(c.body); if not ok then error(e) end end"`

Expected: 退出码为 0，无输出。

### Task 5: 实现页面注册表与 FUIManager 打开/关闭闭环

**Files:**
- Create: `Tests/Integration/FUIManagerSpec.lua`
- Create: `LuaUIFramework/Shared/Core/FUIManager.lua`
- Create: `LuaUIFramework/Config/FPages.lua`

- [ ] **Step 1: 创建阶段一页面注册表**

创建 `LuaUIFramework/Config/FPages.lua`：

```lua
return {
    LoginPanel = {
        presenter = "LuaUIFramework.App.UI.Login.LoginPresenter",
        singleton = true,
        cachePolicy = "DestroyOnClose",
        assets = {
            unreal = "/Game/UI/Login/WBP_LoginPanel",
            unity = "UI/Login/LoginPanel",
        },
        requiredBindings = {
            title = "Text",
            account_text = "Text",
            login_button = "Button",
            status_text = "Text",
            avatar = "Image",
        },
    },
}
```

- [ ] **Step 2: 写页面管理失败测试**

创建 `Tests/Integration/FUIManagerSpec.lua`：

```lua
local FTestHelper = require("Tests.TestHelper")
local FFakePlatformBridge = require("Tests.Fixtures.FFakePlatformBridge")
local FUnrealRuntime = require("LuaUIFramework.Adapters.Unreal.FUnrealRuntime")
local FUIManager = require("LuaUIFramework.Shared.Core.FUIManager")

local function presenter_module(events)
    return { new = function()
        local presenter = {}
        for _, name in ipairs({ "create", "bind", "open", "show", "hide", "close", "unbind", "destroy" }) do
            presenter["on_" .. name] = function() table.insert(events, name) end
        end
        return presenter
    end }
end

local function make_manager()
    local fake = FFakePlatformBridge.new("unreal")
    local events = {}
    local manager = FUIManager.new({
        runtime = FUnrealRuntime.new(fake:as_unreal()),
        pages = { LoginPanel = {
            presenter = "FakePresenter", singleton = true, cachePolicy = "DestroyOnClose",
            assets = { unreal = "WBP_LoginPanel" }, requiredBindings = {
                title = "Text", account_text = "Text", login_button = "Button",
                status_text = "Text", avatar = "Image",
            },
        } },
        require_module = function() return presenter_module(events) end,
    })
    return manager, fake, events
end

FTestHelper:test("manager opens a registered page in lifecycle order", function()
    local manager, fake, events = make_manager()
    manager:open("LoginPanel", { account = "alice" })
    FTestHelper:assert_equal("Loading", manager:get("LoginPanel").lifecycle:get_state())
    fake:complete_next()
    FTestHelper:assert_equal("Opened", manager:get("LoginPanel").lifecycle:get_state())
    FTestHelper:assert_equal("create,bind,open,show", table.concat(events, ","))
    FTestHelper:assert_true(manager:is_open("LoginPanel"))
end)

FTestHelper:test("manager hides and shows an opened page", function()
    local manager, fake, events = make_manager()
    manager:open("LoginPanel")
    fake:complete_next()
    local native = manager:get("LoginPanel").view.native
    FTestHelper:assert_true(manager:hide("LoginPanel"))
    FTestHelper:assert_equal("Hidden", manager:get("LoginPanel").lifecycle:get_state())
    FTestHelper:assert_false(native.visible)
    FTestHelper:assert_true(manager:show("LoginPanel"))
    FTestHelper:assert_equal("Opened", manager:get("LoginPanel").lifecycle:get_state())
    FTestHelper:assert_true(native.visible)
    FTestHelper:assert_equal("create,bind,open,show,hide,show", table.concat(events, ","))
end)

FTestHelper:test("closing an opened page unbinds before destroying", function()
    local manager, fake, events = make_manager()
    manager:open("LoginPanel")
    fake:complete_next()
    manager:close("LoginPanel", "done")
    FTestHelper:assert_nil(manager:get("LoginPanel"))
    FTestHelper:assert_equal("create,bind,open,show,hide,close,unbind,destroy", table.concat(events, ","))
    FTestHelper:assert_equal(1, fake.destroyed)
end)

FTestHelper:test("closing a loading page cancels and ignores a late callback", function()
    local manager, fake, events = make_manager()
    manager:open("LoginPanel")
    manager:close("LoginPanel")
    fake:complete_next(true)
    FTestHelper:assert_nil(manager:get("LoginPanel"))
    FTestHelper:assert_equal("", table.concat(events, ","))
end)

FTestHelper:test("manager rejects an unknown page with a unified error", function()
    local manager = make_manager()
    FTestHelper:assert_error_code("PAGE_NOT_REGISTERED", function() manager:open("MissingPanel") end)
end)
```

- [ ] **Step 3: 运行 Manager 测试并确认 RED**

Run: `node_modules/.bin/fengari Tests/Integration/FUIManagerSpec.lua`

Expected: 非零退出，错误包含 `module 'LuaUIFramework.Shared.Core.FUIManager' not found`。

- [ ] **Step 4: 实现注册查询、异步打开、迟到结果隔离和对称关闭**

创建 `LuaUIFramework/Shared/Core/FUIManager.lua`：

```lua
local FError = require("LuaUIFramework.Shared.Core.FError")
local FLifecycle = require("LuaUIFramework.Shared.Core.FLifecycle")

local FUIManager = {}
FUIManager.__index = FUIManager

function FUIManager.new(options)
    return setmetatable({
        runtime = options.runtime,
        pages = options.pages,
        services = options.services or {},
        require_module = options.require_module or require,
        instances = {},
        next_request_version = 0,
    }, FUIManager)
end

function FUIManager:get(page_name)
    return self.instances[page_name]
end

function FUIManager:is_open(page_name)
    local instance = self.instances[page_name]
    return instance ~= nil and instance.lifecycle:get_state() == "Opened"
end

function FUIManager:hide(page_name)
    local instance = self.instances[page_name]
    if instance == nil or instance.lifecycle:get_state() ~= "Opened" then
        return false
    end
    instance.presenter:on_hide()
    instance.view:set_visible(false)
    instance.lifecycle:transition_to("Hidden")
    return true
end

function FUIManager:show(page_name)
    local instance = self.instances[page_name]
    if instance == nil or instance.lifecycle:get_state() ~= "Hidden" then
        return false
    end
    instance.lifecycle:transition_to("Opened")
    instance.view:set_visible(true)
    instance.presenter:on_show()
    return true
end

function FUIManager:open(page_name, params)
    local definition = self.pages[page_name]
    if definition == nil then
        error(FError.new("PAGE_NOT_REGISTERED", "page is not registered", { page = page_name }), 0)
    end
    local existing = self.instances[page_name]
    if existing ~= nil and definition.singleton then
        return existing
    end
    local asset = definition.assets[self.runtime.platform]
    if asset == nil then
        error(FError.new("ASSET_LOAD_FAILED", "page has no asset for the active platform", {
            page = page_name, platform = self.runtime.platform,
        }), 0)
    end

    self.next_request_version = self.next_request_version + 1
    local instance = {
        name = page_name,
        definition = definition,
        lifecycle = FLifecycle.new(),
        request_version = self.next_request_version,
        params = params or {},
    }
    instance.lifecycle:transition_to("Loading")
    self.instances[page_name] = instance
    local expected_version = instance.request_version
    instance.request = self.runtime:load_view(asset, function(native_view)
        if self.instances[page_name] ~= instance or instance.request_version ~= expected_version then
            return
        end
        instance.view = self.runtime:bind_view(page_name, native_view, definition.requiredBindings)
        instance.lifecycle:transition_to("Created")
        local presenter_module = self.require_module(definition.presenter)
        instance.presenter = presenter_module.new(self.services)
        instance.presenter:on_create(instance.view, instance.params)
        instance.presenter:on_bind()
        instance.lifecycle:transition_to("Opened")
        instance.presenter:on_open(instance.params)
        instance.view:set_visible(true)
        instance.presenter:on_show()
    end)
    return instance
end

function FUIManager:close(page_name, result)
    local instance = self.instances[page_name]
    if instance == nil then return false end
    local state = instance.lifecycle:get_state()
    instance.request_version = instance.request_version + 1
    if state == "Loading" then
        if instance.request ~= nil then instance.request:cancel() end
        instance.lifecycle:transition_to("Unloaded")
        self.instances[page_name] = nil
        return true
    end
    if state == "Opened" or state == "Hidden" or state == "Created" then
        if state == "Opened" then instance.presenter:on_hide() end
        instance.lifecycle:transition_to("Closing")
        instance.presenter:on_close(result)
        instance.presenter:on_unbind()
        instance.presenter:on_destroy()
        instance.view:destroy()
        instance.lifecycle:transition_to("Destroyed")
        self.instances[page_name] = nil
        return true
    end
    return false
end

return FUIManager
```

- [ ] **Step 5: 运行 Manager 测试并确认 GREEN**

Run: `node_modules/.bin/fengari -e "dofile('Tests/Integration/FUIManagerSpec.lua'); local h=require('Tests.TestHelper'); for _,c in ipairs(h.tests) do local ok,e=pcall(c.body); if not ok then error(e) end end"`

Expected: 退出码为 0，无输出。

- [ ] **Step 6: 补充绑定失败清理用例并实现清理保护**

在 `Tests/Integration/FUIManagerSpec.lua` 追加：

```lua
FTestHelper:test("binding failure removes the half-open page and destroys native view", function()
    local manager, fake = make_manager()
    manager.pages.LoginPanel.requiredBindings.missing = "Text"
    manager:open("LoginPanel")
    local succeeded, failure = pcall(function() fake:complete_next() end)
    FTestHelper:assert_false(succeeded)
    FTestHelper:assert_equal("BINDING_NOT_FOUND", failure.code)
    FTestHelper:assert_nil(manager:get("LoginPanel"))
end)
```

在 `Tests/Fixtures/FFakePlatformBridge.lua` 的 `as_unreal()` 和 `as_unity()` 返回表中分别加入：

```lua
destroy_native_view = function(root) return self:_view_ops(root).destroy() end,
```

在 `LuaUIFramework/Adapters/Unreal/FUnrealRuntime.lua` 的 `return FUnrealRuntime` 前加入：

```lua
function FUnrealRuntime:destroy_native_view(native_view)
    self.bridge.destroy_native_view(native_view)
end
```

在 `LuaUIFramework/Adapters/Unity/FUnityRuntime.lua` 的 `return FUnityRuntime` 前加入：

```lua
function FUnityRuntime:destroy_native_view(native_view)
    self.bridge.destroy_native_view(native_view)
end
```

把 `FUIManager:open` 中设置 `instance.request` 的代码替换为：

```lua
instance.request = self.runtime:load_view(asset, function(native_view)
    self:_finish_open(instance, native_view, expected_version)
end)
```

在 `FUIManager:open` 之前加入以下完整方法。迟到结果会立即销毁；绑定或 Presenter 初始化失败会释放已注册的订阅、销毁 View，并保留原始统一错误：

```lua
function FUIManager:_finish_open(instance, native_view, expected_version)
    if self.instances[instance.name] ~= instance or instance.request_version ~= expected_version then
        self.runtime:destroy_native_view(native_view)
        return
    end

    local succeeded, failure = xpcall(function()
        instance.view = self.runtime:bind_view(
            instance.name,
            native_view,
            instance.definition.requiredBindings
        )
        instance.lifecycle:transition_to("Created")
        local presenter_module = self.require_module(instance.definition.presenter)
        instance.presenter = presenter_module.new(self.services)
        instance.presenter:on_create(instance.view, instance.params)
        instance.presenter:on_bind()
        instance.lifecycle:transition_to("Opened")
        instance.presenter:on_open(instance.params)
        instance.view:set_visible(true)
        instance.presenter:on_show()
    end, function(err)
        return err
    end)

    if succeeded then
        return
    end
    if instance.presenter ~= nil then
        pcall(instance.presenter.on_unbind, instance.presenter)
        pcall(instance.presenter.on_destroy, instance.presenter)
    end
    if instance.view ~= nil then
        instance.view:destroy()
    else
        self.runtime:destroy_native_view(native_view)
    end
    if self.instances[instance.name] == instance then
        self.instances[instance.name] = nil
    end
    error(failure, 0)
end
```

从旧加载回调中删除已迁入 `_finish_open` 的绑定、Presenter 创建和生命周期代码，确保初始化只执行一次。

Run: `node_modules/.bin/fengari -e "dofile('Tests/Integration/FUIManagerSpec.lua'); local h=require('Tests.TestHelper'); for _,c in ipairs(h.tests) do local ok,e=pcall(c.body); if not ok then error(e) end end"`

Expected: 退出码为 0，无输出。

### Task 6: 用同一个 LoginPresenter 驱动 Unreal 与 Unity

**Files:**
- Create: `Tests/Integration/LoginPanelSpec.lua`
- Create: `LuaUIFramework/App/UI/Login/LoginPresenter.lua`

- [ ] **Step 1: 写双平台端到端失败测试**

创建 `Tests/Integration/LoginPanelSpec.lua`：

```lua
local FTestHelper = require("Tests.TestHelper")
local FFakePlatformBridge = require("Tests.Fixtures.FFakePlatformBridge")
local FUnrealRuntime = require("LuaUIFramework.Adapters.Unreal.FUnrealRuntime")
local FUnityRuntime = require("LuaUIFramework.Adapters.Unity.FUnityRuntime")
local FUIManager = require("LuaUIFramework.Shared.Core.FUIManager")
local pages = require("LuaUIFramework.Config.FPages")

local cases = {
    { platform = "unreal", runtime = FUnrealRuntime, bridge = "as_unreal" },
    { platform = "unity", runtime = FUnityRuntime, bridge = "as_unity" },
}

for _, case in ipairs(cases) do
    FTestHelper:test("LoginPresenter completes login on " .. case.platform, function()
        local fake = FFakePlatformBridge.new(case.platform)
        local service_calls = 0
        local manager = FUIManager.new({
            runtime = case.runtime.new(fake[case.bridge](fake)),
            pages = pages,
            services = { login = function(account)
                service_calls = service_calls + 1
                return account == "alice", account == "alice" and nil or "登录失败"
            end },
        })
        manager:open("LoginPanel", { account = "alice", avatar = "avatar/alice" })
        fake:complete_next()
        local instance = manager:get("LoginPanel")
        local native = instance.view.native
        FTestHelper:assert_equal("登录", native.widgets.title.text)
        FTestHelper:assert_equal("alice", native.widgets.account_text.text)
        FTestHelper:assert_equal("avatar/alice", native.widgets.avatar.source)

        native.widgets.login_button.click()
        FTestHelper:assert_equal(1, service_calls)
        FTestHelper:assert_equal("登录成功", native.widgets.status_text.text)

        manager:close("LoginPanel")
        FTestHelper:assert_nil(native.widgets.login_button.click)
    end)
end
```

- [ ] **Step 2: 运行 Login 集成测试并确认 RED**

Run: `node_modules/.bin/fengari Tests/Integration/LoginPanelSpec.lua`

Expected: 非零退出，错误包含 `module 'LuaUIFramework.App.UI.Login.LoginPresenter' not found`。

- [ ] **Step 3: 实现只依赖公共 View 契约的 LoginPresenter**

创建 `LuaUIFramework/App/UI/Login/LoginPresenter.lua`：

```lua
local FBasePresenter = require("LuaUIFramework.Shared.Core.FBasePresenter")
local LoginPresenter = {}
LoginPresenter.__index = LoginPresenter
setmetatable(LoginPresenter, { __index = FBasePresenter })

function LoginPresenter.new(services)
    local instance = FBasePresenter.initialize({ services = services })
    return setmetatable(instance, LoginPresenter)
end

function LoginPresenter:on_create(view, params)
    FBasePresenter.on_create(self, view, params)
    self.account = self.params.account or ""
end

function LoginPresenter:on_bind()
    self:track(self.view:button("login_button"):on_click(function()
        local succeeded, message = self.services.login(self.account)
        self.view:text("status_text"):set_text(succeeded and "登录成功" or (message or "登录失败"))
    end))
end

function LoginPresenter:on_open(params)
    FBasePresenter.on_open(self, params)
    self.account = self.params.account or ""
    self.view:text("title"):set_text("登录")
    self.view:text("account_text"):set_text(self.account)
    self.view:text("status_text"):set_text("")
    self.view:image("avatar"):set_source(self.params.avatar or "avatar/default")
end

return LoginPresenter
```

- [ ] **Step 4: 运行 Login 双平台测试并确认 GREEN**

Run: `node_modules/.bin/fengari -e "dofile('Tests/Integration/LoginPanelSpec.lua'); local h=require('Tests.TestHelper'); for _,c in ipairs(h.tests) do local ok,e=pcall(c.body); if not ok then error(e) end end"`

Expected: 退出码为 0，无输出；同一测试分别以 `unreal` 和 `unity` Runtime 通过。

### Task 7: 文档化宿主桥接边界并完成阶段一验收

**Files:**
- Create: `README.md`
- Create: `Tests/check.lua`
- Modify: `package.json`

- [ ] **Step 1: 为语法检查增加 npm 命令**

把 `package.json` 的 `scripts` 替换为：

```json
"scripts": {
  "test": "fengari Tests/run.lua",
  "check:lua": "fengari Tests/check.lua"
}
```

创建 `Tests/check.lua`，显式加载全部生产模块，避免 Windows shell 不展开 glob：

```lua
local modules = {
    "LuaUIFramework.Shared.Core.FError",
    "LuaUIFramework.Shared.Core.FBasePresenter",
    "LuaUIFramework.Shared.Core.FLifecycle",
    "LuaUIFramework.Shared.Core.FUIManager",
    "LuaUIFramework.Shared.Contracts.FIWidget",
    "LuaUIFramework.Shared.Contracts.FIText",
    "LuaUIFramework.Shared.Contracts.FIButton",
    "LuaUIFramework.Shared.Contracts.FIImage",
    "LuaUIFramework.Shared.Contracts.FIView",
    "LuaUIFramework.Shared.Events.FEventBus",
    "LuaUIFramework.Shared.State.FStore",
    "LuaUIFramework.Shared.Utils.FCommand",
    "LuaUIFramework.Shared.Utils.FValidation",
    "LuaUIFramework.Adapters.Common.FViewBinder",
    "LuaUIFramework.Adapters.Unreal.FUnrealRuntime",
    "LuaUIFramework.Adapters.Unity.FUnityRuntime",
    "LuaUIFramework.App.UI.Login.LoginPresenter",
    "LuaUIFramework.Config.FPages",
}

for _, module_name in ipairs(modules) do
    require(module_name)
end

print(string.format("parsed %d Lua modules", #modules))
```

- [ ] **Step 2: 编写真实宿主需要提供的桥接清单**

创建 `README.md`，明确记录：

```markdown
# FLuaFrameWork

阶段一提供跨 Unreal/Unity 的 Lua UI 最小闭环。共享代码不能引用 `UE.*`、`CS.*` 或 `UnityEngine.*`。

## Unreal bridge

UnLua 宿主向 `FUnrealRuntime.new(bridge)` 注入：

- `load_widget(asset, callback) -> { cancel = function }`
- `find_widget(root, logical_id) -> UWidget|nil`
- `get_widget_type(widget) -> "Text"|"Button"|"Image"`
- `make_widget_ops(widget) -> operations`
- `make_view_ops(root) -> operations`
- `destroy_native_view(root)`

## Unity bridge

xLua 宿主向 `FUnityRuntime.new(bridge)` 注入：

- `load_prefab(asset, callback) -> { cancel = function }`
- `find_component(root, logical_id) -> Component|nil`
- `get_component_type(component) -> "Text"|"Button"|"Image"`
- `make_component_ops(component) -> operations`
- `make_view_ops(root) -> operations`
- `destroy_native_view(root)`

两个原生 Login 资源必须暴露 `title`、`account_text`、`login_button`、`status_text`、`avatar`。开发环境绑定失败时页面不会进入 Opened，错误上下文包含 page、platform、binding、expected 和 actual。

## 验证

```powershell
npm install
npm test
npm run check:lua
rg -n "UE\.|UnityEngine\.|CS\." LuaUIFramework/Shared LuaUIFramework/App
```
```

- [ ] **Step 3: 运行全量测试**

Run: `npm test`

Expected: 退出码为 0；原有 14 个测试和本计划新增的生命周期、Presenter、绑定、双 Runtime、Manager、双平台 Login 用例全部显示 `PASS`，结尾显示 `0 failed`。

- [ ] **Step 4: 运行 Lua 解析检查**

Run: `npm run check:lua`

Expected: 退出码为 0，无 Lua 语法错误，输出 `parsed 18 Lua modules`。

- [ ] **Step 5: 验证共享层没有引擎 API 泄漏**

Run: `rg -n "UE\.|UnityEngine\.|CS\." LuaUIFramework/Shared LuaUIFramework/App`

Expected: 退出码为 1 且无匹配；`rg` 的退出码 1 在这里表示没有发现禁用依赖，是成功结果。

- [ ] **Step 6: 人工核对阶段一验收矩阵**

确认以下每项都有自动化证据：

- 同一 `LoginPresenter.lua` 在 Unreal/Unity fake bridge 用例中通过。
- `FUIManager` 可以查询、异步打开和关闭注册页面。
- `on_create → on_bind → on_open → on_show` 顺序固定。
- 关闭后 `on_hide → on_close → on_unbind → on_destroy` 且按钮回调被移除。
- 关闭 Loading 页面会取消请求，迟到回调不会生成幽灵页面。
- 缺失绑定和类型错误包含 page/platform/binding/expected/actual 诊断字段。
- View 销毁后访问控件产生 `NATIVE_OBJECT_INVALID`。
- `Shared` 与 `App` 不含任何 Unreal/Unity API 调用。

- [ ] **Step 7: 交由完成分支流程统一提交与集成**

所有任务完成后使用 `superpowers:finishing-a-development-branch` 做最终测试、检查工作区差异，并选择本地合并、推送 PR、保留分支或丢弃。不要在本计划各任务中创建零散提交。

## 自检结论

- **设计覆盖：** Runtime 注入、页面注册、`FUIManager`、View/Text/Button/Image、显式生命周期、Unreal/Unity 最小 Adapter、Login 双平台示例均有对应任务；Router、层级、Input、通用资源系统明确留到后续阶段。
- **异步安全：** Manager 用请求版本和取消句柄覆盖“加载中关闭”场景；绑定失败清理用例覆盖半开页面。
- **生命周期对称：** Presenter 订阅袋和关闭顺序用单元/集成测试固定，View 销毁后访问统一报错。
- **类型一致：** 页面注册、Binder、View 访问器和双平台桥接统一使用 `Text`、`Button`、`Image`；平台键统一使用 `unreal`、`unity`。
- **现有代码保护：** 已通过的基础设施不在本阶段重建，执行从当前 `14 passed, 0 failed` 基线继续。
