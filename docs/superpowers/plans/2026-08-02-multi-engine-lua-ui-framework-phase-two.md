# 多引擎 Lua UI 框架阶段二：常用能力 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不实现或修改 Unreal/Unity Adapter 的前提下，为 Shared Lua 层补齐 Router、逻辑层级、Input/Toggle/Progress、可取消资源加载、统一日志和 Mock View 测试能力，并用独立文档定义后续 Adapter 必须实现的接入协议。

**Architecture:** `FIWidget` 及其子类集中到 `Shared/Contracts/FWidget/`，资源契约集中到 `Shared/Contracts/FAssetLoader/`，日志契约集中到 `Shared/Contracts/FLogger/`；`FIView` 因不继承 `FIWidget` 继续留在 Contracts 根目录。阶段二只依赖纯 Lua `FMockView`、`FFakeRuntime` 和 `FFakeAssetBackend` 验证 Shared 行为，现有 `FLuaFramework/Adapters/**` 完全不改；UMG/UGUI 后续需要补齐的控件映射、层级挂载、资源后端和日志落点统一记录在 `docs/myDocs/phase-two-adapter-requirements.md`。

**Tech Stack:** Lua 5.3 兼容语法、FClass、Fengari Node CLI、npm、仓库内轻量 Lua 测试运行器；UnLua/xLua Adapter 仅形成接口需求文档，不在本阶段编码。

---

## 实施边界与文件结构

执行基线为 `51 passed, 0 failed`。当前工作区另有未提交的启动入口和其他阶段计划；执行时必须保留这些改动，只对本计划列出的文件做增量修改。

本阶段明确不修改：

```text
FLuaFramework/Adapters/Common/FViewBinder.lua
FLuaFramework/Adapters/Unreal/FUnrealRuntime.lua
FLuaFramework/Adapters/Unity/FUnityRuntime.lua
Tests/Fixtures/FFakePlatformBridge.lua
Tests/Contract/FRuntimeContractSpec.lua
```

因此阶段二新增控件不会立即进入现有 `FViewBinder`，逻辑层不会立即映射为 UMG ZOrder 或 Unity Canvas Sorting Order，资源加载也不会由现有 Runtime 直接实现。这些差距不是隐式遗留项，而是 Task 7 要写清楚的 Adapter 接入协议。

目标目录如下：

```text
FLuaFramework/Shared/
├─ Contracts/
│  ├─ FIView.lua
│  ├─ FWidget/
│  │  ├─ FIWidget.lua
│  │  ├─ FIText.lua
│  │  ├─ FIButton.lua
│  │  ├─ FIImage.lua
│  │  ├─ FIInput.lua
│  │  ├─ FIToggle.lua
│  │  └─ FIProgress.lua
│  ├─ FAssetLoader/
│  │  ├─ FAssetHandle.lua
│  │  └─ FIAssetLoader.lua
│  └─ FLogger/
│     └─ FILogger.lua
├─ Core/
│  ├─ FUIManager.lua
│  └─ FUIRouter.lua
└─ ...
FLuaFramework/Config/
├─ FLayers.lua
└─ FAssets.lua
Tests/Fixtures/
├─ FMockView.lua
├─ FFakeRuntime.lua
└─ FFakeAssetBackend.lua
docs/myDocs/
└─ phase-two-adapter-requirements.md
```

阶段二公共语义固定为：

```lua
view:input("account_input"):set_text("alice")
view:input("account_input"):on_changed(function(value) end)
view:toggle("remember_toggle"):set_checked(true)
view:progress("loading_progress"):set_value(0.5) -- 只接受 [0, 1]

router:push("MainPanel", params)
router:replace("SettingsPanel", params)
router:back(result)
router:reset("LoginPanel", params)
router:present("ConfirmDialog", params) -- 只接受 Modal 页面

local request = asset_loader:load(
    { id = "avatar/default", type = "texture" },
    function(handle) image:set_source(handle) end,
    function(err) logger:error(err) end
)
request:cancel() -- 幂等；取消后的迟到成功结果会被立即释放
```

### Task 1: 归档 FIWidget 家族并建立无引擎 Mock View

**Files:**
- Move: `FLuaFramework/Shared/Contracts/FIWidget.lua` → `FLuaFramework/Shared/Contracts/FWidget/FIWidget.lua`
- Move: `FLuaFramework/Shared/Contracts/FIText.lua` → `FLuaFramework/Shared/Contracts/FWidget/FIText.lua`
- Move: `FLuaFramework/Shared/Contracts/FIButton.lua` → `FLuaFramework/Shared/Contracts/FWidget/FIButton.lua`
- Move: `FLuaFramework/Shared/Contracts/FIImage.lua` → `FLuaFramework/Shared/Contracts/FWidget/FIImage.lua`
- Create: `Tests/Fixtures/FMockView.lua`
- Create: `Tests/Unit/LoginPresenterSpec.lua`
- Modify: `FLuaFramework/register.lua`

- [ ] **Step 1: 写 LoginPresenter 的无引擎失败测试**

创建 `Tests/Unit/LoginPresenterSpec.lua`：

```lua
local FTestHelper = require("Tests.TestHelper")
local FMockView = require("Tests.Fixtures.FMockView")
local LoginPresenter = require("FLuaFramework.App.UI.Login.LoginPresenter")

local bindings = {
    title = "Text",
    account_text = "Text",
    login_button = "Button",
    status_text = "Text",
    avatar = "Image",
}

FTestHelper:test("LoginPresenter renders and submits through a mock view", function()
    local mock = FMockView:new(bindings)
    local calls = 0
    local presenter = LoginPresenter:new({ login = function(account)
        calls = calls + 1
        return account == "alice"
    end })
    presenter:on_create(mock.view, { account = "alice", avatar = "avatar/alice" })
    presenter:on_bind()
    presenter:on_open({ account = "alice", avatar = "avatar/alice" })
    FTestHelper:assert_equal("登录", mock:get("title").text)
    FTestHelper:assert_equal("alice", mock:get("account_text").text)
    FTestHelper:assert_equal("avatar/alice", mock:get("avatar").source)
    mock:click("login_button")
    FTestHelper:assert_equal(1, calls)
    FTestHelper:assert_equal("登录成功", mock:get("status_text").text)
end)

FTestHelper:test("LoginPresenter unbind removes mock button callbacks", function()
    local mock = FMockView:new(bindings)
    local presenter = LoginPresenter:new({ login = function() return true end })
    presenter:on_create(mock.view, {})
    presenter:on_bind()
    presenter:on_unbind()
    FTestHelper:assert_nil(mock:get("login_button").click)
end)
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `node_modules/.bin/fengari -e "require('FLuaFramework.register'); dofile('Tests/Unit/LoginPresenterSpec.lua')"`

Expected: 非零退出，错误包含 `module 'Tests.Fixtures.FMockView' not found`。

- [ ] **Step 3: 用 apply_patch 移动 FIWidget 及其现有子类**

在同一个 `apply_patch` 中删除四个 Contracts 根目录源文件，并按以下完整内容创建目标文件。创建 `FWidget/FIWidget.lua`：

```lua
local FIWidget = FClass("FIWidget")

function FIWidget:ctor(id, native, ops)
    self.id = id
    self.native = native
    self.ops = ops
end

function FIWidget:_assert_valid()
    if self.native == nil or self.ops.is_valid() ~= true then
        error(FError:new("NATIVE_OBJECT_INVALID", "native widget is no longer valid", {
            binding = self.id,
        }), 0)
    end
end

function FIWidget:set_visible(value)
    self:_assert_valid()
    self.ops.set_visible(value == true)
end

return FIWidget
```

创建 `FWidget/FIText.lua`：

```lua
local FIText = FClass("FIText", FIWidget)

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

创建 `FWidget/FIButton.lua`：

```lua
local FIButton = FClass("FIButton", FIWidget)

function FIButton:on_click(callback)
    self:_assert_valid()
    return self.ops.on_click(callback)
end

return FIButton
```

创建 `FWidget/FIImage.lua`：

```lua
local FIImage = FClass("FIImage", FIWidget)

function FIImage:set_source(source)
    self:_assert_valid()
    self.ops.set_source(source)
end

return FIImage
```

`FIView.lua` 不继承 `FIWidget`，所以不移动。

- [ ] **Step 4: 更新 Register 的模块路径**

把 `FLuaFramework/register.lua` 中四个注册路径替换为：

```lua
register("FIWidget", "FLuaFramework.Shared.Contracts.FWidget.FIWidget")
register("FIText", "FLuaFramework.Shared.Contracts.FWidget.FIText")
register("FIButton", "FLuaFramework.Shared.Contracts.FWidget.FIButton")
register("FIImage", "FLuaFramework.Shared.Contracts.FWidget.FIImage")
```

- [ ] **Step 5: 实现只组装公共契约的 FMockView**

创建 `Tests/Fixtures/FMockView.lua`：

```lua
local FClass = require("FLuaFramework.Shared.Core.FClass")
local FMockView = FClass("FMockView")

local factories = {
    Text = function(...) return FIText:new(...) end,
    Button = function(...) return FIButton:new(...) end,
    Image = function(...) return FIImage:new(...) end,
}

local function subscription(widget, field, callback)
    widget[field] = callback
    local active = true
    return { unsubscribe = function()
        if active then
            active = false
            widget[field] = nil
        end
    end }
end

function FMockView:ctor(required_bindings)
    self.native = { valid = true, visible = false, widgets = {} }
    local entries = {}
    for id, kind in pairs(required_bindings) do
        local widget = {
            id = id,
            kind = kind,
            valid = true,
            visible = true,
            text = "",
            source = nil,
            checked = false,
            value = 0,
        }
        self.native.widgets[id] = widget
        local ops = {
            is_valid = function() return widget.valid end,
            set_visible = function(value) widget.visible = value end,
            set_text = function(value) widget.text = value end,
            get_text = function() return widget.text end,
            set_source = function(value) widget.source = value end,
            on_click = function(callback) return subscription(widget, "click", callback) end,
        }
        entries[id] = { kind = kind, widget = factories[kind](id, widget, ops) }
    end
    self.view = FIView:new("MockPage", "mock", self.native, {
        is_valid = function() return self.native.valid end,
        set_visible = function(value) self.native.visible = value end,
        destroy = function()
            self.native.valid = false
            for _, widget in pairs(self.native.widgets) do
                widget.valid = false
                widget.click = nil
                widget.changed = nil
            end
        end,
    }, entries)
end

function FMockView:get(id)
    return self.native.widgets[id]
end

function FMockView:click(id)
    local callback = self:get(id).click
    if callback ~= nil then callback() end
end

return FMockView
```

- [ ] **Step 6: 更新解析检查并确认旧路径消失**

`Tests/check.lua` 仍通过 Register 加载框架模块，不新增分散 `require`。运行：

Run: `rg -n "Shared\.Contracts\.(FIWidget|FIText|FIButton|FIImage)" . -g '*.lua'`

Expected: 退出码为 1 且无匹配；四个模块只由 Register 的新路径加载。

- [ ] **Step 7: 运行 Mock、原有 ViewBinder 和 Login 回归**

Run: `node_modules/.bin/fengari -e "require('FLuaFramework.register'); dofile('Tests/Unit/LoginPresenterSpec.lua'); dofile('Tests/Unit/FViewBinderSpec.lua'); dofile('Tests/Integration/LoginPanelSpec.lua'); local h=require('Tests.TestHelper'); for _,c in ipairs(h.tests) do local ok,e=pcall(c.body); if not ok then error(e) end end"`

Expected: 退出码为 0；现有 Adapter 不修改也能通过原有 Text/Button/Image 回归，新增 Mock Presenter 两个用例通过。

### Task 2: 在 FWidget 下新增 Input、Toggle 与 Progress

**Files:**
- Create: `FLuaFramework/Shared/Contracts/FWidget/FIInput.lua`
- Create: `FLuaFramework/Shared/Contracts/FWidget/FIToggle.lua`
- Create: `FLuaFramework/Shared/Contracts/FWidget/FIProgress.lua`
- Create: `Tests/Unit/FCommonControlsSpec.lua`
- Modify: `FLuaFramework/Shared/Contracts/FIView.lua`
- Modify: `Tests/Fixtures/FMockView.lua`
- Modify: `FLuaFramework/register.lua`

- [ ] **Step 1: 写三类控件的 Mock View 失败测试**

创建 `Tests/Unit/FCommonControlsSpec.lua`：

```lua
local FTestHelper = require("Tests.TestHelper")
local FMockView = require("Tests.Fixtures.FMockView")

local function make_mock()
    return FMockView:new({
        account_input = "Input",
        remember_toggle = "Toggle",
        loading_progress = "Progress",
    })
end

FTestHelper:test("input normalizes nil and releases changed callbacks", function()
    local mock = make_mock()
    local received = nil
    local handle = mock.view:input("account_input"):on_changed(function(value) received = value end)
    mock.view:input("account_input"):set_text(nil)
    FTestHelper:assert_equal("", mock.view:input("account_input"):get_text())
    mock:change("account_input", "alice")
    FTestHelper:assert_equal("alice", received)
    handle:unsubscribe()
    FTestHelper:assert_nil(mock:get("account_input").changed)
end)

FTestHelper:test("toggle exposes strict boolean state and changed callbacks", function()
    local mock = make_mock()
    local received = nil
    mock.view:toggle("remember_toggle"):on_changed(function(value) received = value end)
    mock.view:toggle("remember_toggle"):set_checked(1)
    FTestHelper:assert_false(mock.view:toggle("remember_toggle"):is_checked())
    mock:change("remember_toggle", true)
    FTestHelper:assert_true(received)
end)

FTestHelper:test("progress accepts only normalized numeric values", function()
    local mock = make_mock()
    mock.view:progress("loading_progress"):set_value(0.75)
    FTestHelper:assert_equal(0.75, mock.view:progress("loading_progress"):get_value())
    FTestHelper:assert_error_code("INVALID_PROGRESS_VALUE", function()
        mock.view:progress("loading_progress"):set_value(2)
    end)
    FTestHelper:assert_error_code("INVALID_PROGRESS_VALUE", function()
        mock.view:progress("loading_progress"):set_value("0.5")
    end)
end)
```

- [ ] **Step 2: 运行控件测试并确认 RED**

Run: `node_modules/.bin/fengari -e "require('FLuaFramework.register'); dofile('Tests/Unit/FCommonControlsSpec.lua')"`

Expected: 非零退出，错误包含 `attempt to call a nil value (method 'input')`。

- [ ] **Step 3: 实现三个 FIWidget 子类**

创建 `FLuaFramework/Shared/Contracts/FWidget/FIInput.lua`：

```lua
local FIInput = FClass("FIInput", FIWidget)

function FIInput:set_text(value)
    self:_assert_valid()
    self.ops.set_text(value == nil and "" or tostring(value))
end

function FIInput:get_text()
    self:_assert_valid()
    return self.ops.get_text()
end

function FIInput:on_changed(callback)
    self:_assert_valid()
    return self.ops.on_changed(callback)
end

return FIInput
```

创建 `FLuaFramework/Shared/Contracts/FWidget/FIToggle.lua`：

```lua
local FIToggle = FClass("FIToggle", FIWidget)

function FIToggle:set_checked(value)
    self:_assert_valid()
    self.ops.set_checked(value == true)
end

function FIToggle:is_checked()
    self:_assert_valid()
    return self.ops.is_checked() == true
end

function FIToggle:on_changed(callback)
    self:_assert_valid()
    return self.ops.on_changed(callback)
end

return FIToggle
```

创建 `FLuaFramework/Shared/Contracts/FWidget/FIProgress.lua`：

```lua
local FIProgress = FClass("FIProgress", FIWidget)

function FIProgress:set_value(value)
    self:_assert_valid()
    if type(value) ~= "number" or value < 0 or value > 1 then
        error(FError:new("INVALID_PROGRESS_VALUE", "progress value must be a number between 0 and 1", {
            binding = self.id,
            value = value,
        }), 0)
    end
    self.ops.set_value(value)
end

function FIProgress:get_value()
    self:_assert_valid()
    return self.ops.get_value()
end

return FIProgress
```

- [ ] **Step 4: 注册新控件并增加 FIView 访问器**

在 `FLuaFramework/register.lua` 的 `FIImage` 后加入：

```lua
register("FIInput", "FLuaFramework.Shared.Contracts.FWidget.FIInput")
register("FIToggle", "FLuaFramework.Shared.Contracts.FWidget.FIToggle")
register("FIProgress", "FLuaFramework.Shared.Contracts.FWidget.FIProgress")
```

在 `FIView.lua` 的 `image` 访问器后加入：

```lua
function FIView:input(id) return self:_get(id, "Input") end
function FIView:toggle(id) return self:_get(id, "Toggle") end
function FIView:progress(id) return self:_get(id, "Progress") end
```

- [ ] **Step 5: 扩展 FMockView 的工厂和操作集**

在 `FMockView.lua` 的 `factories` 中加入：

```lua
Input = function(...) return FIInput:new(...) end,
Toggle = function(...) return FIToggle:new(...) end,
Progress = function(...) return FIProgress:new(...) end,
```

在控件 `ops` 中加入：

```lua
on_changed = function(callback) return subscription(widget, "changed", callback) end,
set_checked = function(value) widget.checked = value end,
is_checked = function() return widget.checked end,
set_value = function(value) widget.value = value end,
get_value = function() return widget.value end,
```

在 `click` 方法后加入：

```lua
function FMockView:change(id, value)
    local widget = self:get(id)
    if widget.kind == "Input" then widget.text = value == nil and "" or tostring(value) end
    if widget.kind == "Toggle" then widget.checked = value == true end
    if widget.changed ~= nil then widget.changed(value) end
end
```

- [ ] **Step 6: 运行 Shared 控件测试并确认 GREEN**

Run: `node_modules/.bin/fengari -e "require('FLuaFramework.register'); dofile('Tests/Unit/FCommonControlsSpec.lua'); dofile('Tests/Unit/LoginPresenterSpec.lua'); local h=require('Tests.TestHelper'); for _,c in ipairs(h.tests) do local ok,e=pcall(c.body); if not ok then error(e) end end"`

Expected: 退出码为 0；三个新控件只通过 Mock View 验证，现有 Adapter 未参与。

### Task 3: 实现逻辑层级和按层关闭

**Files:**
- Create: `FLuaFramework/Config/FLayers.lua`
- Create: `Tests/Fixtures/FFakeRuntime.lua`
- Create: `Tests/Unit/FUILayerSpec.lua`
- Modify: `FLuaFramework/Config/FPages.lua`
- Modify: `FLuaFramework/Shared/Core/FUIManager.lua`
- Modify: `init.lua`
- Modify: `Tests/Integration/FUIManagerSpec.lua`
- Modify: `Tests/Integration/LoginPanelSpec.lua`

- [ ] **Step 1: 写纯 Lua 层级测试**

创建 `Tests/Unit/FUILayerSpec.lua`：

```lua
local FTestHelper = require("Tests.TestHelper")
local FFakeRuntime = require("Tests.Fixtures.FFakeRuntime")
local FUIManager = require("FLuaFramework.Shared.Core.FUIManager")

local function presenter_module()
    local Presenter = FClass("LayerPresenter", FBasePresenter)
    return Presenter
end

local function make_manager()
    local runtime = FFakeRuntime:new("test")
    local manager = FUIManager:new({
        runtime = runtime,
        layers = {
            Normal = { order = 200, blocksInput = false },
            Modal = { order = 400, blocksInput = true },
        },
        pages = {
            MainPanel = {
                presenter = "LayerPresenter", singleton = true,
                layer = "Normal", inputMode = "UIOnly",
                assets = { test = "main" }, requiredBindings = {},
            },
            ConfirmDialog = {
                presenter = "LayerPresenter", singleton = true,
                layer = "Modal", inputMode = "UIOnly",
                assets = { test = "confirm" }, requiredBindings = {},
            },
        },
        require_module = function() return presenter_module() end,
    })
    return manager, runtime
end

FTestHelper:test("manager records layer metadata and delegates optional mounting", function()
    local manager, runtime = make_manager()
    manager:open("MainPanel")
    runtime:complete_next()
    local instance = manager:get("MainPanel")
    FTestHelper:assert_equal("Normal", instance.layer)
    FTestHelper:assert_equal("Normal", runtime.mounts[1].layer)
    FTestHelper:assert_equal(200, runtime.mounts[1].order)
    FTestHelper:assert_false(runtime.mounts[1].blocksInput)
end)

FTestHelper:test("manager rejects an unknown logical layer before loading", function()
    local manager, runtime = make_manager()
    manager.pages.MainPanel.layer = "Missing"
    FTestHelper:assert_error_code("LAYER_NOT_FOUND", function() manager:open("MainPanel") end)
    FTestHelper:assert_equal(0, #runtime.pending)
end)

FTestHelper:test("close_layer closes only matching instances", function()
    local manager, runtime = make_manager()
    manager:open("MainPanel")
    runtime:complete_next()
    manager:open("ConfirmDialog")
    runtime:complete_next()
    FTestHelper:assert_equal(1, manager:close_layer("Modal"))
    FTestHelper:assert_not_nil(manager:get("MainPanel"))
    FTestHelper:assert_nil(manager:get("ConfirmDialog"))
end)
```

- [ ] **Step 2: 运行层级测试并确认 RED**

Run: `node_modules/.bin/fengari -e "require('FLuaFramework.register'); dofile('Tests/Unit/FUILayerSpec.lua')"`

Expected: 非零退出，错误包含 `module 'Tests.Fixtures.FFakeRuntime' not found`。

- [ ] **Step 3: 创建纯 Lua FFakeRuntime**

创建 `Tests/Fixtures/FFakeRuntime.lua`：

```lua
local FClass = require("FLuaFramework.Shared.Core.FClass")
local FMockView = require("Tests.Fixtures.FMockView")
local FFakeRuntime = FClass("FFakeRuntime")

function FFakeRuntime:ctor(platform)
    self.platform = platform
    self.pending = {}
    self.mounts = {}
    self.destroyed = 0
end

function FFakeRuntime:load_view(asset, callback)
    local pending = { asset = asset, callback = callback, cancelled = false }
    table.insert(self.pending, pending)
    return { cancel = function() pending.cancelled = true end }
end

function FFakeRuntime:complete_next(deliver_cancelled)
    local pending = table.remove(self.pending, 1)
    if pending ~= nil and (not pending.cancelled or deliver_cancelled == true) then
        pending.callback({ valid = true })
    end
end

function FFakeRuntime:mount_view(native_view, layer_name, layer, input_mode)
    table.insert(self.mounts, {
        native = native_view,
        layer = layer_name,
        order = layer.order,
        blocksInput = layer.blocksInput,
        inputMode = input_mode,
    })
end

function FFakeRuntime:bind_view(page, native_view, required_bindings)
    local mock = FMockView:new(required_bindings)
    native_view.mock = mock
    return mock.view
end

function FFakeRuntime:destroy_native_view(native_view)
    if native_view.valid then
        native_view.valid = false
        self.destroyed = self.destroyed + 1
    end
end

return FFakeRuntime
```

- [ ] **Step 4: 创建七个固定逻辑层并登记 LoginPanel**

创建 `FLuaFramework/Config/FLayers.lua`：

```lua
return {
    Background = { order = 100, blocksInput = false },
    Normal = { order = 200, blocksInput = false },
    Popup = { order = 300, blocksInput = false },
    Modal = { order = 400, blocksInput = true },
    Guide = { order = 500, blocksInput = true },
    System = { order = 600, blocksInput = true },
    Debug = { order = 700, blocksInput = false },
}
```

在 `FPages.lua` 的 `LoginPanel` 中加入：

```lua
layer = "Normal",
inputMode = "UIOnly",
```

- [ ] **Step 5: 扩展 Manager 的逻辑层状态**

在 `FUIManager:ctor` 中加入：

```lua
self.layers = options.layers or {}
self.next_instance_id = 0
```

在 `open` 取得页面定义后加入：

```lua
local layer_name = definition.layer or "Normal"
local layer = self.layers[layer_name]
if layer == nil then
    error(FError:new("LAYER_NOT_FOUND", "page layer is not configured", {
        page = page_name,
        layer = layer_name,
        platform = self.runtime.platform,
    }), 0)
end
```

创建实例前递增 ID，并在实例表中加入字段：

```lua
self.next_instance_id = self.next_instance_id + 1
```

```lua
id = self.next_instance_id,
layer = layer_name,
open_order = self.next_instance_id,
```

在 `_finish_open` 绑定 View 前加入可选挂载调用；现有 Adapter 没有该方法时保持阶段一行为：

```lua
if type(self.runtime.mount_view) == "function" then
    self.runtime:mount_view(
        native_view,
        instance.layer,
        self.layers[instance.layer],
        instance.definition.inputMode or "UIOnly"
    )
end
```

在 `return FUIManager` 前加入：

```lua
function FUIManager:close_layer(layer_name)
    if self.layers[layer_name] == nil then
        error(FError:new("LAYER_NOT_FOUND", "UI layer is not configured", {
            layer = layer_name,
            platform = self.runtime.platform,
        }), 0)
    end
    local targets = {}
    for page_name, instance in pairs(self.instances) do
        if instance.layer == layer_name then
            table.insert(targets, { page = page_name, order = instance.open_order })
        end
    end
    table.sort(targets, function(left, right) return left.order > right.order end)
    local count = 0
    for _, target in ipairs(targets) do
        if self:close(target.page) then count = count + 1 end
    end
    return count
end
```

- [ ] **Step 6: 为现有 Manager 调用点注入 FLayers**

在 `init.lua` 和 `Tests/Integration/LoginPanelSpec.lua` 顶部加入：

```lua
local layers = require("FLuaFramework.Config.FLayers")
```

在两处 Manager options 中加入：

```lua
layers = layers,
```

在 `FUIManagerSpec.lua` 的页面定义中加入 `layer = "Normal"`、`inputMode = "UIOnly"`，Manager options 加入：

```lua
layers = { Normal = { order = 200, blocksInput = false } },
```

- [ ] **Step 7: 运行层级与全量阶段一回归**

Run: `node_modules/.bin/fengari -e "require('FLuaFramework.register'); dofile('Tests/Unit/FUILayerSpec.lua'); dofile('Tests/Integration/FUIManagerSpec.lua'); dofile('Tests/Integration/LoginPanelSpec.lua'); dofile('Tests/Integration/FMainSpec.lua'); local h=require('Tests.TestHelper'); for _,c in ipairs(h.tests) do local ok,e=pcall(c.body); if not ok then error(e) end end"`

Expected: 退出码为 0；纯 Lua Runtime 验证挂载意图，未修改的 Unreal/Unity Adapter 仍通过阶段一回归。

### Task 4: 实现 FUIRouter

**Files:**
- Create: `FLuaFramework/Shared/Core/FUIRouter.lua`
- Create: `Tests/Unit/FUIRouterSpec.lua`
- Modify: `FLuaFramework/register.lua`

- [ ] **Step 1: 写 Router 行为测试**

创建 `Tests/Unit/FUIRouterSpec.lua`，定义一个只记录 `open/close/hide/show/get` 调用的 Lua manager，并覆盖以下六个完整用例：

```lua
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
```

- [ ] **Step 2: 运行 Router 测试并确认 RED**

Run: `node_modules/.bin/fengari -e "require('FLuaFramework.register'); dofile('Tests/Unit/FUIRouterSpec.lua')"`

Expected: 非零退出，错误包含 `module 'FLuaFramework.Shared.Core.FUIRouter' not found`。

- [ ] **Step 3: 实现 Router**

创建 `FLuaFramework/Shared/Core/FUIRouter.lua`：

```lua
local FUIRouter = FClass("FUIRouter")

function FUIRouter:ctor(manager)
    self.manager = manager
    self.stack = {}
end

function FUIRouter:current() return self.stack[#self.stack] end

function FUIRouter:get_stack()
    local copy = {}
    for index, entry in ipairs(self.stack) do
        copy[index] = { page = entry.page, params = entry.params }
    end
    return copy
end

function FUIRouter:_definition(page_name)
    local definition = self.manager.pages[page_name]
    if definition == nil then
        error(FError:new("PAGE_NOT_REGISTERED", "route page is not registered", { page = page_name }), 0)
    end
    if definition.singleton ~= true then
        error(FError:new("ROUTE_REQUIRES_SINGLETON", "route pages must be singleton", { page = page_name }), 0)
    end
    return definition
end

function FUIRouter:push(page_name, params)
    self:_definition(page_name)
    local current = self:current()
    if current ~= nil and current.page == page_name then return self.manager:get(page_name) end
    if current ~= nil and not self.manager:hide(current.page) then
        error(FError:new("ROUTE_NOT_READY", "current route cannot be hidden", { page = current.page }), 0)
    end
    local succeeded, result = pcall(self.manager.open, self.manager, page_name, params)
    if not succeeded then
        if current ~= nil then self.manager:show(current.page) end
        error(result, 0)
    end
    table.insert(self.stack, { page = page_name, params = params or {} })
    return result
end

function FUIRouter:replace(page_name, params)
    self:_definition(page_name)
    local current = self:current()
    if current ~= nil then
        self.manager:close(current.page)
        table.remove(self.stack)
    end
    local result = self.manager:open(page_name, params)
    table.insert(self.stack, { page = page_name, params = params or {} })
    return result
end

function FUIRouter:back(result)
    if #self.stack <= 1 then return false end
    local current = table.remove(self.stack)
    self.manager:close(current.page, result)
    local previous = self:current()
    if not self.manager:show(previous.page) then
        error(FError:new("ROUTE_NOT_READY", "previous route cannot be shown", { page = previous.page }), 0)
    end
    return true
end

function FUIRouter:reset(page_name, params)
    self:_definition(page_name)
    for index = #self.stack, 1, -1 do
        self.manager:close(self.stack[index].page)
        self.stack[index] = nil
    end
    local result = self.manager:open(page_name, params)
    table.insert(self.stack, { page = page_name, params = params or {} })
    return result
end

function FUIRouter:present(page_name, params)
    local definition = self:_definition(page_name)
    if definition.layer ~= "Modal" then
        error(FError:new("INVALID_MODAL_PAGE", "present requires a page in the Modal layer", {
            page = page_name, layer = definition.layer,
        }), 0)
    end
    return self.manager:open(page_name, params)
end

return FUIRouter
```

- [ ] **Step 4: 注册并验证 Router**

在 Register 的 `FUIManager` 后加入：

```lua
register("FUIRouter", "FLuaFramework.Shared.Core.FUIRouter")
```

Run: `node_modules/.bin/fengari -e "require('FLuaFramework.register'); dofile('Tests/Unit/FUIRouterSpec.lua'); local h=require('Tests.TestHelper'); for _,c in ipairs(h.tests) do local ok,e=pcall(c.body); if not ok then error(e) end end"`

Expected: 退出码为 0，六个 Router 用例全部通过。

### Task 5: 在 FAssetLoader 下实现逻辑资源加载

**Files:**
- Create: `FLuaFramework/Shared/Contracts/FAssetLoader/FAssetHandle.lua`
- Create: `FLuaFramework/Shared/Contracts/FAssetLoader/FIAssetLoader.lua`
- Create: `FLuaFramework/Config/FAssets.lua`
- Create: `Tests/Fixtures/FFakeAssetBackend.lua`
- Create: `Tests/Unit/FIAssetLoaderSpec.lua`
- Modify: `FLuaFramework/Shared/Contracts/FWidget/FIImage.lua`
- Modify: `FLuaFramework/register.lua`

- [ ] **Step 1: 写资源加载的五个失败用例**

创建 `Tests/Unit/FIAssetLoaderSpec.lua`，覆盖成功释放、取消迟到结果、原生失败、非法引用/类型、缺少后端：

```lua
local FTestHelper = require("Tests.TestHelper")
local FFakeAssetBackend = require("Tests.Fixtures.FFakeAssetBackend")
local FIAssetLoader = require("FLuaFramework.Shared.Contracts.FAssetLoader.FIAssetLoader")

local manifest = {
    ["avatar/default"] = {
        type = "texture",
        unreal = "/Game/UI/Textures/T_DefaultAvatar",
        unity = "UI/Textures/DefaultAvatar",
    },
}

FTestHelper:test("asset loader resolves refs and returns a releasable handle", function()
    local backend = FFakeAssetBackend:new()
    local loader = FIAssetLoader:new("unreal", manifest, backend)
    local received = nil
    loader:load({ id = "avatar/default", type = "texture" }, function(handle) received = handle end)
    FTestHelper:assert_equal("/Game/UI/Textures/T_DefaultAvatar", backend.pending[1].address)
    backend:complete_next()
    FTestHelper:assert_equal("avatar/default", received:get_id())
    FTestHelper:assert_true(received:release())
    FTestHelper:assert_false(received:release())
    FTestHelper:assert_equal(1, backend.released)
end)

FTestHelper:test("asset request cancellation releases a late success", function()
    local backend = FFakeAssetBackend:new()
    local loader = FIAssetLoader:new("unreal", manifest, backend)
    local callbacks = 0
    local request = loader:load({ id = "avatar/default", type = "texture" }, function()
        callbacks = callbacks + 1
    end)
    FTestHelper:assert_true(request:cancel())
    FTestHelper:assert_false(request:cancel())
    backend:complete_next(true)
    FTestHelper:assert_equal(0, callbacks)
    FTestHelper:assert_equal(1, backend.released)
end)

FTestHelper:test("asset backend failure becomes ASSET_LOAD_FAILED", function()
    local backend = FFakeAssetBackend:new()
    local loader = FIAssetLoader:new("unity", manifest, backend)
    local failure = nil
    loader:load({ id = "avatar/default", type = "texture" }, function() end, function(err)
        failure = err
    end)
    backend:fail_next("missing bundle")
    FTestHelper:assert_equal("ASSET_LOAD_FAILED", failure.code)
    FTestHelper:assert_equal("unity", failure.context.platform)
    FTestHelper:assert_equal("missing bundle", failure.context.cause)
end)

FTestHelper:test("asset loader validates logical IDs and types", function()
    local loader = FIAssetLoader:new("unreal", manifest, FFakeAssetBackend:new())
    FTestHelper:assert_error_code("INVALID_ASSET_REF", function()
        loader:load("avatar/default", function() end)
    end)
    FTestHelper:assert_error_code("ASSET_NOT_REGISTERED", function()
        loader:load({ id = "missing", type = "texture" }, function() end)
    end)
    FTestHelper:assert_error_code("ASSET_TYPE_MISMATCH", function()
        loader:load({ id = "avatar/default", type = "audio" }, function() end)
    end)
end)

FTestHelper:test("asset loader reports an unconfigured backend", function()
    local loader = FIAssetLoader:new("unreal", manifest, nil)
    FTestHelper:assert_error_code("ASSET_BACKEND_NOT_CONFIGURED", function()
        loader:load({ id = "avatar/default", type = "texture" }, function() end)
    end)
end)
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `node_modules/.bin/fengari -e "require('FLuaFramework.register'); dofile('Tests/Unit/FIAssetLoaderSpec.lua')"`

Expected: 非零退出，错误包含缺少 `FAssetLoader.FIAssetLoader` 模块或 `FFakeAssetBackend`。

- [ ] **Step 3: 创建纯 Lua 资源后端 Fixture**

创建 `Tests/Fixtures/FFakeAssetBackend.lua`：

```lua
local FClass = require("FLuaFramework.Shared.Core.FClass")
local FFakeAssetBackend = FClass("FFakeAssetBackend")

function FFakeAssetBackend:ctor()
    self.pending = {}
    self.released = 0
end

function FFakeAssetBackend:load(address, asset_type, on_success, on_error)
    local pending = {
        address = address, asset_type = asset_type,
        on_success = on_success, on_error = on_error, cancelled = false,
    }
    table.insert(self.pending, pending)
    return { cancel = function() pending.cancelled = true end }
end

function FFakeAssetBackend:complete_next(deliver_cancelled)
    local pending = table.remove(self.pending, 1)
    if pending ~= nil and (not pending.cancelled or deliver_cancelled == true) then
        pending.on_success({ address = pending.address, type = pending.asset_type, valid = true })
    end
end

function FFakeAssetBackend:fail_next(cause)
    local pending = table.remove(self.pending, 1)
    if pending ~= nil and not pending.cancelled then pending.on_error(cause) end
end

function FFakeAssetBackend:release(asset)
    if asset.valid then
        asset.valid = false
        self.released = self.released + 1
    end
end

return FFakeAssetBackend
```

- [ ] **Step 4: 实现 FAssetHandle**

创建 `FLuaFramework/Shared/Contracts/FAssetLoader/FAssetHandle.lua`：

```lua
local FAssetHandle = FClass("FAssetHandle")

function FAssetHandle:ctor(asset_ref, native_asset, release_native)
    self.asset_ref = { id = asset_ref.id, type = asset_ref.type }
    self.native_asset = native_asset
    self.release_native = release_native
    self.released = false
end

function FAssetHandle:get_id() return self.asset_ref.id end
function FAssetHandle:get_type() return self.asset_ref.type end
function FAssetHandle:is_released() return self.released end

function FAssetHandle:_native_for_adapter()
    if self.released then
        error(FError:new("NATIVE_OBJECT_INVALID", "asset handle has been released", {
            assetId = self.asset_ref.id, assetType = self.asset_ref.type,
        }), 0)
    end
    return self.native_asset
end

function FAssetHandle:release()
    if self.released then return false end
    self.released = true
    self.release_native(self.native_asset, self.asset_ref.type)
    self.native_asset = nil
    return true
end


return FAssetHandle
```

- [ ] **Step 5: 实现 FIAssetLoader**

创建 `FLuaFramework/Shared/Contracts/FAssetLoader/FIAssetLoader.lua`：

```lua
local FIAssetLoader = FClass("FIAssetLoader")

local function raise(code, message, context)
    error(FError:new(code, message, context), 0)
end

function FIAssetLoader:ctor(platform, manifest, backend, logger)
    self.platform = platform
    self.manifest = manifest or {}
    self.backend = backend
    self.logger = logger
end

function FIAssetLoader:load(asset_ref, on_success, on_error)
    if type(asset_ref) ~= "table" or type(asset_ref.id) ~= "string" or type(asset_ref.type) ~= "string" then
        raise("INVALID_ASSET_REF", "asset ref must contain string id and type", { assetRef = asset_ref })
    end
    if self.backend == nil then
        raise("ASSET_BACKEND_NOT_CONFIGURED", "asset backend was not injected", {
            assetId = asset_ref.id, platform = self.platform,
        })
    end
    local definition = self.manifest[asset_ref.id]
    if definition == nil then
        raise("ASSET_NOT_REGISTERED", "logical asset is not registered", { assetId = asset_ref.id })
    end
    if definition.type ~= asset_ref.type then
        raise("ASSET_TYPE_MISMATCH", "asset ref type does not match manifest", {
            assetId = asset_ref.id, expected = definition.type, actual = asset_ref.type,
        })
    end
    local address = definition[self.platform]
    if address == nil then
        raise("ASSET_LOAD_FAILED", "asset has no address for the active platform", {
            assetId = asset_ref.id, assetType = asset_ref.type, platform = self.platform,
        })
    end

    local state = { active = true, native_request = nil }
    local request = {}
    function request:cancel()
        if not state.active then return false end
        state.active = false
        if state.native_request ~= nil then state.native_request:cancel() end
        return true
    end

    state.native_request = self.backend:load(address, asset_ref.type, function(native_asset)
        if not state.active then
            self.backend:release(native_asset, asset_ref.type)
            return
        end
        state.active = false
        on_success(FAssetHandle:new(asset_ref, native_asset, function(asset, asset_type)
            self.backend:release(asset, asset_type)
        end))
    end, function(cause)
        if not state.active then return end
        state.active = false
        local failure = FError:new("ASSET_LOAD_FAILED", "asset backend load failed", {
            assetId = asset_ref.id, assetType = asset_ref.type,
            platform = self.platform, address = address, cause = tostring(cause),
        })
        if self.logger ~= nil then self.logger:error(failure) end
        if on_error ~= nil then on_error(failure) else error(failure, 0) end
    end)
    return request
end

return FIAssetLoader
```

- [ ] **Step 6: 创建资源清单、注册模块并让 FIImage 解包句柄**

创建 `FLuaFramework/Config/FAssets.lua`：

```lua
return {
    ["avatar/default"] = {
        type = "texture",
        unreal = "/Game/UI/Textures/T_DefaultAvatar",
        unity = "UI/Textures/DefaultAvatar",
    },
}
```

在 Register 中加入：

```lua
register("FAssetHandle", "FLuaFramework.Shared.Contracts.FAssetLoader.FAssetHandle")
register("FIAssetLoader", "FLuaFramework.Shared.Contracts.FAssetLoader.FIAssetLoader")
```

把 `FWidget/FIImage.lua` 的 `set_source` 替换为：

```lua
function FIImage:set_source(source)
    self:_assert_valid()
    if type(source) == "table" and FAssetHandle:is_instance(source) then
        source = source:_native_for_adapter()
    end
    self.ops.set_source(source)
end
```

- [ ] **Step 7: 运行资源测试并确认 GREEN**

Run: `node_modules/.bin/fengari -e "require('FLuaFramework.register'); dofile('Tests/Unit/FIAssetLoaderSpec.lua'); local h=require('Tests.TestHelper'); for _,c in ipairs(h.tests) do local ok,e=pcall(c.body); if not ok then error(e) end end"`

Expected: 退出码为 0；测试只使用 Shared Loader 和纯 Lua backend，不访问 Adapter。

### Task 6: 在 FLogger 下实现统一结构化日志

**Files:**
- Create: `FLuaFramework/Shared/Contracts/FLogger/FILogger.lua`
- Create: `Tests/Unit/FILoggerSpec.lua`
- Create: `Tests/Unit/FUIManagerLoggingSpec.lua`
- Modify: `FLuaFramework/Shared/Core/FError.lua`
- Modify: `FLuaFramework/Shared/Core/FUIManager.lua`
- Modify: `FLuaFramework/register.lua`

- [ ] **Step 1: 写 Logger 与 Manager 错误日志测试**

创建 `Tests/Unit/FILoggerSpec.lua`：

```lua
local FTestHelper = require("Tests.TestHelper")
local FILogger = require("FLuaFramework.Shared.Contracts.FLogger.FILogger")

FTestHelper:test("logger merges platform base and call context", function()
    local record = nil
    local logger = FILogger:new("unreal", function(value) record = value end, {
        page = "LoginPanel", instanceId = 7,
    })
    logger:info("page opened", { lifecycle = "Opened" })
    FTestHelper:assert_equal("info", record.level)
    FTestHelper:assert_equal("unreal", record.platform)
    FTestHelper:assert_equal("LoginPanel", record.page)
    FTestHelper:assert_equal("Opened", record.lifecycle)
end)

FTestHelper:test("logger flattens FError context and records traceback", function()
    local record = nil
    local logger = FILogger:new("unity", function(value) record = value end)
    logger:error(FError:new("BINDING_NOT_FOUND", "missing", { binding = "title" }))
    FTestHelper:assert_equal("BINDING_NOT_FOUND", record.errorCode)
    FTestHelper:assert_equal("title", record.binding)
    FTestHelper:assert_contains("stack traceback", record.traceback)
end)
```

创建 `Tests/Unit/FUIManagerLoggingSpec.lua`：

```lua
local FTestHelper = require("Tests.TestHelper")
local FFakeRuntime = require("Tests.Fixtures.FFakeRuntime")

FTestHelper:test("manager logs synchronous page errors with platform context", function()
    local record = nil
    local logger = FILogger:new("test", function(value) record = value end)
    local manager = FUIManager:new({
        runtime = FFakeRuntime:new("test"), pages = {}, layers = {}, logger = logger,
    })
    FTestHelper:assert_error_code("PAGE_NOT_REGISTERED", function() manager:open("Missing") end)
    FTestHelper:assert_equal("PAGE_NOT_REGISTERED", record.errorCode)
    FTestHelper:assert_equal("Missing", record.page)
    FTestHelper:assert_equal("test", record.platform)
end)
```

- [ ] **Step 2: 运行日志测试并确认 RED**

Run: `node_modules/.bin/fengari -e "require('FLuaFramework.register'); dofile('Tests/Unit/FILoggerSpec.lua')"`

Expected: 非零退出，错误包含缺少 `FLogger.FILogger` 模块。

- [ ] **Step 3: 增强 FError 序列化**

在 `FError.lua` 中加入：

```lua
function FError:to_table()
    local context = {}
    for key, value in pairs(self.context or {}) do context[key] = value end
    return { code = self.code, message = self.message, context = context }
end
```

- [ ] **Step 4: 实现 FILogger**

创建 `FLuaFramework/Shared/Contracts/FLogger/FILogger.lua`：

```lua
local FILogger = FClass("FILogger")

local function merge(...)
    local result = {}
    for index = 1, select("#", ...) do
        local source = select(index, ...)
        if source ~= nil then
            for key, value in pairs(source) do result[key] = value end
        end
    end
    return result
end

function FILogger:ctor(platform, sink, base_context)
    self.platform = platform
    self.sink = sink or function() end
    self.base_context = merge(base_context)
end

function FILogger:with_context(context)
    return FILogger:new(self.platform, self.sink, merge(self.base_context, context))
end

function FILogger:log(level, message, context)
    local record = merge(self.base_context, context)
    record.level = level
    record.message = tostring(message)
    record.platform = self.platform
    self.sink(record)
    return record
end

function FILogger:debug(message, context) return self:log("debug", message, context) end
function FILogger:info(message, context) return self:log("info", message, context) end
function FILogger:warn(message, context) return self:log("warn", message, context) end

function FILogger:error(failure, context)
    local merged = merge(context, { traceback = debug.traceback("", 2) })
    if type(failure) == "table" and failure.code ~= nil then
        merged = merge(failure.context, merged, { errorCode = failure.code })
        return self:log("error", failure.message, merged)
    end
    return self:log("error", tostring(failure), merged)
end

return FILogger
```

- [ ] **Step 5: 注册 Logger 并接入 Manager 同步错误**

在 Register 中加入：

```lua
register("FILogger", "FLuaFramework.Shared.Contracts.FLogger.FILogger")
```

在 `FUIManager:ctor` 中加入：

```lua
self.logger = options.logger or FILogger:new(self.runtime.platform)
```

在 `FUIManager.lua` 中加入：

```lua
function FUIManager:_raise(failure, context)
    self.logger:error(failure, context)
    error(failure, 0)
end
```

把 `PAGE_NOT_REGISTERED` 分支改为：

```lua
if definition == nil then
    local failure = FError:new("PAGE_NOT_REGISTERED", "page is not registered", { page = page_name })
    self:_raise(failure, { page = page_name, platform = self.runtime.platform })
end
```

把 Task 3 的 `LAYER_NOT_FOUND` 分支和现有缺少平台 asset 的 `ASSET_LOAD_FAILED` 分支也改为先构造 `failure`，再调用：

```lua
self:_raise(failure, {
    page = page_name,
    platform = self.runtime.platform,
})
```

- [ ] **Step 6: 运行日志和 Manager 测试并确认 GREEN**

Run: `node_modules/.bin/fengari -e "require('FLuaFramework.register'); dofile('Tests/Unit/FILoggerSpec.lua'); dofile('Tests/Unit/FUIManagerLoggingSpec.lua'); local h=require('Tests.TestHelper'); for _,c in ipairs(h.tests) do local ok,e=pcall(c.body); if not ok then error(e) end end"`

Expected: 退出码为 0；Logger 只调用注入 sink，不要求 Runtime 或 Adapter 提供日志 API。

### Task 7: 装配 Shared 服务并编写 Adapter 需求文档

**Files:**
- Create: `docs/myDocs/phase-two-adapter-requirements.md`
- Modify: `init.lua`
- Modify: `Tests/Unit/FInitSpec.lua`
- Modify: `Tests/Unit/FRegisterSpec.lua`
- Modify: `Tests/run.lua`
- Modify: `Tests/check.lua`

- [ ] **Step 1: 扩展 Register 预期列表**

在 `FRegisterSpec.lua` 的 `expected_names` 中加入：

```lua
"FUIRouter",
"FIInput", "FIToggle", "FIProgress",
"FAssetHandle", "FIAssetLoader", "FILogger",
```

- [ ] **Step 2: 写启动装配失败断言**

在 `FInitSpec.lua` 的平台循环创建 Manager 后加入：

```lua
FTestHelper:assert_not_nil(manager.router)
FTestHelper:assert_not_nil(manager.asset_loader)
FTestHelper:assert_not_nil(manager.logger)
FTestHelper:assert_equal(case.platform, manager.logger.platform)
FTestHelper:assert_not_nil(manager.layers.Normal)
```

Run: `node_modules/.bin/fengari -e "require('FLuaFramework.register'); dofile('Tests/Unit/FInitSpec.lua'); local h=require('Tests.TestHelper'); for _,c in ipairs(h.tests) do local ok,e=pcall(c.body); if not ok then error(e) end end"`

Expected: 非零退出，首个新增断言报告 `manager.router` 为 nil。

- [ ] **Step 3: 在 init 中装配纯 Shared 服务**

在 `init.lua` 顶部加入：

```lua
local assets = require("FLuaFramework.Config.FAssets")
```

把创建 Manager 的尾部替换为：

```lua
local runtime = runtime_class:new(options.bridge)
local logger = registered.FILogger:new(options.platform, options.log_sink)
local manager = registered.FUIManager:new({
    runtime = runtime,
    pages = pages,
    layers = layers,
    services = options.services or {},
    logger = logger,
})
manager.router = registered.FUIRouter:new(manager)
manager.asset_loader = registered.FIAssetLoader:new(
    options.platform,
    assets,
    options.asset_backend,
    logger
)
return manager
```

`options.log_sink` 和 `options.asset_backend` 都允许为空：Logger 使用 no-op sink，AssetLoader 在真正加载时抛出 `ASSET_BACKEND_NOT_CONFIGURED`。现有 Adapter 无需改动。

- [ ] **Step 4: 把新测试加入统一运行器和解析检查**

在 `Tests/run.lua` 中加入：

```lua
"Tests/Unit/LoginPresenterSpec.lua",
"Tests/Unit/FCommonControlsSpec.lua",
"Tests/Unit/FUILayerSpec.lua",
"Tests/Unit/FUIRouterSpec.lua",
"Tests/Unit/FIAssetLoaderSpec.lua",
"Tests/Unit/FILoggerSpec.lua",
"Tests/Unit/FUIManagerLoggingSpec.lua",
```

在 `Tests/check.lua` 加入：

```lua
require("FLuaFramework.Config.FLayers")
require("FLuaFramework.Config.FAssets")
```

把输出改为：

```lua
print(string.format(
    "parsed %d registered framework modules, 4 config/app modules and 2 entry modules",
    registered_count
))
```

- [ ] **Step 5: 在 myDocs 写完整 Adapter 接入要求**

创建 `docs/myDocs/phase-two-adapter-requirements.md`，内容必须完整写为：

```markdown
# 阶段二 Adapter 接入要求

阶段二只实现 Shared Lua 能力，不修改 `FLuaFramework/Adapters/**`。本文件定义 Unreal/UMG/UnLua 与 Unity/UGUI/xLua 后续接入时必须满足的协议。

## 1. 新控件绑定

`FViewBinder` 后续需要把以下逻辑类型映射为公共包装类：

- `Input` → `FIInput`
- `Toggle` → `FIToggle`
- `Progress` → `FIProgress`

控件操作表必须提供：

```lua
Input = {
    is_valid = function() return boolean end,
    set_visible = function(value) end,
    set_text = function(value) end,
    get_text = function() return string end,
    on_changed = function(callback) return { unsubscribe = function() end } end,
}

Toggle = {
    is_valid = function() return boolean end,
    set_visible = function(value) end,
    set_checked = function(value) end,
    is_checked = function() return boolean end,
    on_changed = function(callback) return { unsubscribe = function() end } end,
}

Progress = {
    is_valid = function() return boolean end,
    set_visible = function(value) end,
    set_value = function(value) end,
    get_value = function() return number end,
}
```

Unreal Adapter 应把 EditableText/EditableTextBox、CheckBox、ProgressBar 映射到上述语义；Unity Adapter 应把 InputField/TMP_InputField、Toggle、Slider 或 Image Fill 映射到上述语义。事件解绑必须幂等，原生对象失效后 `is_valid` 必须返回 false。

## 2. 逻辑层挂载

Shared Manager 会在 Runtime 存在 `mount_view` 时调用：

```lua
runtime:mount_view(native_view, layer_name, layer_definition, input_mode)
```

其中 `layer_definition` 包含 `order` 和 `blocksInput`。Unreal 后续应映射到 Viewport 容器、ZOrder、输入模式和命中测试；Unity 后续应映射到 Canvas/Transform 层、Sorting Order、GraphicRaycaster 和输入阻挡。未实现该方法时 Shared 仍维护逻辑层和 `close_layer`，但不会改变原生显示顺序。

## 3. 资源后端注入

宿主通过 `init.create({ asset_backend = backend })` 注入：

```lua
backend:load(address, asset_type, on_success, on_error)
    -> { cancel = function() end }

backend:release(native_asset, asset_type)
```

Unreal 后续应使用软引用/StreamableManager 或项目资源服务；Unity 后续应使用 Addressables、AssetBundle 或项目资源服务。取消必须幂等；若底层无法阻止迟到成功回调，Shared Loader 会立即调用 `release`。业务 Lua 只使用 `{ id, type }`，平台地址只存在于 `FAssets.lua`。

## 4. 日志落点注入

宿主可通过 `init.create({ log_sink = function(record) end })` 注入日志落点。`record` 至少可能包含：

```text
level, message, platform, page, instanceId, layer, lifecycle,
binding, assetId, assetType, errorCode, traceback
```

Unreal 后续应写入 UE_LOG/项目日志系统，Unity 后续应写入 Debug.Log 或项目日志系统。sink 不得反向抛出引擎异常破坏 Shared 清理流程。

## 5. Adapter 验收矩阵

后续实现 Adapter 时，两平台必须运行同一组契约用例：

- Input 设置、读取、变更订阅和解绑一致。
- Toggle 布尔归一化、变更订阅和解绑一致。
- Progress 使用 `[0, 1]`，无平台百分比差异。
- 七个逻辑层的顺序和输入阻挡意图一致。
- 资源成功、失败、取消、迟到释放一致。
- 原生对象销毁后统一产生 `NATIVE_OBJECT_INVALID`。
- 日志字段不因平台不同而缺失。
```

- [ ] **Step 6: 运行装配测试并确认 GREEN**

Run: `node_modules/.bin/fengari -e "require('FLuaFramework.register'); dofile('Tests/Unit/FRegisterSpec.lua'); dofile('Tests/Unit/FInitSpec.lua'); local h=require('Tests.TestHelper'); for _,c in ipairs(h.tests) do local ok,e=pcall(c.body); if not ok then error(e) end end"`

Expected: 退出码为 0；Manager 暴露 Router、AssetLoader、Logger 和 Layers，未要求 Adapter 新增任何方法。

### Task 8: 全量验收与完成分支交接

**Files:**
- Test: `FLuaFramework/Adapters/**` 保持无差异
- Test: `docs/myDocs/phase-two-adapter-requirements.md`

- [ ] **Step 1: 运行全量测试**

Run: `npm test`

Expected: 退出码为 0，结尾显示 `73 passed, 0 failed`。

- [ ] **Step 2: 运行 Lua 解析检查**

Run: `npm run check:lua`

Expected: 退出码为 0，输出 `parsed 24 registered framework modules, 4 config/app modules and 2 entry modules`。

- [ ] **Step 3: 验证 Adapter 目录没有阶段二改动**

Run: `git diff --exit-code -- FLuaFramework/Adapters`

Expected: 退出码为 0 且无输出。

- [ ] **Step 4: 验证旧 Contracts 根路径已清空**

Run: `@( 'FIWidget.lua', 'FIText.lua', 'FIButton.lua', 'FIImage.lua' ) | ForEach-Object { Test-Path -LiteralPath (Join-Path 'FLuaFramework/Shared/Contracts' $_) }`

Expected: 输出四行 `False`；对应文件都位于 `Contracts/FWidget/`。

- [ ] **Step 5: 验证目录和文档边界**

Run: `rg --files FLuaFramework/Shared/Contracts/FWidget FLuaFramework/Shared/Contracts/FAssetLoader FLuaFramework/Shared/Contracts/FLogger docs/myDocs`

Expected: 列出 7 个 FWidget Lua 文件、2 个 FAssetLoader Lua 文件、1 个 FLogger Lua 文件和 `phase-two-adapter-requirements.md`。

- [ ] **Step 6: 验证共享层无引擎 API 和分散依赖**

Run: `rg -n "UE\.|UnityEngine\.|CS\." FLuaFramework/Shared FLuaFramework/App`

Expected: 退出码为 1 且无匹配。

Run: `node Tests/check-requires.js`

Expected: 退出码为 0，输出 `framework require check passed`。

- [ ] **Step 7: 人工核对验收矩阵**

确认：

- `FIWidget` 与六个子类全部位于 `Contracts/FWidget/`，`FIView` 保留在 Contracts 根目录。
- `FIAssetLoader` 与 `FAssetHandle` 位于 `Contracts/FAssetLoader/`。
- `FILogger` 位于 `Contracts/FLogger/`。
- Router、层级、资源取消、统一日志和 Mock View 均由纯 Lua 测试覆盖。
- Login 双引擎阶段一回归仍通过，但阶段二新控件不宣称已经接入引擎。
- `FLuaFramework/Adapters/**` 没有代码差异。
- `docs/myDocs/phase-two-adapter-requirements.md` 明确列出两平台后续工作和契约验收矩阵。

- [ ] **Step 8: 交由完成分支流程统一提交与集成**

所有任务完成后使用 `superpowers:finishing-a-development-branch` 重新运行全量验证，审阅当前工作区已有改动与本阶段改动的组合差异，再选择本地合并、推送 PR、保留分支或丢弃。不要在各 Task 中创建零散提交。

## 自检结论

- **用户要求 1：** 计划不创建、不修改任何 Adapter 或 Adapter 契约测试；所有宿主侧新增处理集中写入 `docs/myDocs/phase-two-adapter-requirements.md`。
- **用户要求 2：** `FIWidget`、现有 `FIText/FIButton/FIImage` 和新增 `FIInput/FIToggle/FIProgress` 全部归档到 `Contracts/FWidget/`；不继承它的 `FIView` 保持原位。
- **用户要求 3：** `FIAssetLoader` 与 `FAssetHandle` 均创建在 `Contracts/FAssetLoader/`。
- **用户要求 4：** `FILogger` 创建在 `Contracts/FLogger/`。
- **设计覆盖：** Router、逻辑层、三类常用控件、异步资源取消、统一错误日志和 Mock View 都有独立 TDD 任务。
- **边界一致：** Shared 只暴露意图和注入接口；引擎映射、原生资源服务与日志落点不在本阶段实现。
- **类型一致：** 控件类型固定为 `Text/Button/Image/Input/Toggle/Progress`，资源字段固定为 `id/type`，平台键固定为 `unreal/unity`。
