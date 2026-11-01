# 多引擎 Lua UI 框架阶段四：工程化增强 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在阶段三稳定运行的双引擎 UI 能力之上，建立可重复的绑定代码生成与编辑器校验、低侵入性能统计、显式泄漏诊断，以及“销毁并重建页面”的安全 Lua 热重载工作流。

**Architecture:** 以 Bindings/*.binding.json 作为逻辑控件 ID、类型、平台原生名称和页面资源地址的唯一事实源，由 Node 工具生成运行时 Lua 配置；编辑器检查通过 Unreal/Unity 注入的最小资源枚举桥复用同一个纯 Lua 校验器。诊断模块只接收结构化事件并使用注入时钟，FUIManager 在页面、请求、Presenter 订阅的生命周期边界埋点；热重载先事务式替换 package.loaded，再销毁受影响页面并通过 Presenter 快照重建，不尝试原地替换闭包或元表。

**Tech Stack:** Lua 5.3 兼容语法、FClass、Fengari Node CLI、Node.js 内置 fs/path/node:test、UnLua/xLua 注入桥、JSON 绑定契约。

---

## 前置条件、范围与基线

当前仓库只有阶段一实现，基线命令 npm test 的结果为 51 passed, 0 failed。执行本计划前必须先完成阶段二和阶段三，并确认它们的全量测试通过；若阶段二/三改变了 FUIManager、FBasePresenter、FPages 或 Runtime 的公开签名，先把本计划中的调用点机械对齐到最终签名，再开始 RED/GREEN 循环。

阶段四的四项能力可以分别验收，但共享以下稳定协议，因此保留为一个实施计划：

- 绑定 JSON 是运行时配置、代码生成和编辑器检查的共同输入。
- page、platform、instance_id、lifecycle 是性能、日志与泄漏诊断的共同上下文字段。
- 热重载复用 FUIManager 的关闭、打开、状态恢复和诊断边界。

前序阶段的 FILogger 继续负责错误、调用栈和人类可读日志；本阶段新增的 FDiagnostics 只承载性能样本、泄漏记录和热重载事件，两者不互相替代。前序阶段已经分配 instance.id，本阶段只把它以 instance_id 字段带入结构化事件。

本阶段明确不做：

- 不生成 UMG/UGUI 布局，不在两个引擎之间转换资源。
- 不在运行时解析 JSON；生成产物必须在提交或 CI 中提前生成。
- 不接管 Unreal/Unity 的文件监听器；宿主只需在检测到 Lua 文件变化时调用统一入口。
- 不支持 Shared、Adapters、Config、register 或 FClass 的无损热替换。
- 不尝试让任意存活页面原地替换闭包、事件回调或元表。
- 不把平台内存数字伪装成可跨引擎直接比较的统一指标；平台原生指标保留 platform 和 metric 名称。

## 文件结构与职责

计划完成后的新增或关键修改文件如下：

~~~text
Bindings/
└─ LoginPanel.binding.json                 # 页面绑定唯一事实源
Tools/Bindings/
├─ FBindingGenerator.js                    # 加载、校验、排序和渲染
└─ generate-bindings.js                    # generate/check CLI
FLuaFramework/
├─ Generated/
│  └─ FUIBindings.lua                      # 机器生成的运行时资产、ID 和绑定映射
├─ Shared/
│  ├─ Diagnostics/
│  │  ├─ FDiagnostics.lua                  # 结构化事件出口
│  │  ├─ FPerformanceStats.lua             # 耗时聚合
│  │  └─ FLeakTracker.lua                  # 显式资源令牌
│  └─ HotReload/
│     ├─ FModuleReloader.lua               # package.loaded 事务式替换
│     └─ FHotReload.lua                    # 页面快照、关闭和重建编排
├─ Tools/Editor/
│  └─ FBindingValidator.lua                # 与引擎无关的资源绑定校验
└─ Adapters/
   ├─ Unreal/FUnrealBindingInspector.lua   # Unreal 编辑器检查桥包装
   └─ Unity/FUnityBindingInspector.lua     # Unity 编辑器检查桥包装
Tests/
├─ Tools/FBindingGenerator.test.js
├─ Fixtures/
│  ├─ invalid-binding.json
│  └─ FFakeModuleLoader.lua
├─ Unit/
│  ├─ FBindingValidatorSpec.lua
│  ├─ FDiagnosticsSpec.lua
│  ├─ FPerformanceStatsSpec.lua
│  ├─ FLeakTrackerSpec.lua
│  └─ FModuleReloaderSpec.lua
└─ Integration/
   ├─ FEngineeringDiagnosticsSpec.lua
   └─ FHotReloadSpec.lua
editor.lua                                    # 编辑器检查入口
docs/engineering/
├─ binding-pipeline.md
├─ diagnostics.md
└─ hot-reload.md
~~~

生成文件 FUIBindings.lua 只承载数据，不包含引擎对象。FBindingValidator 只处理检查器返回的 name/type 列表；真实 Unreal 与 Unity 工程分别提供 inspect_widget_blueprint(asset) 和 inspect_prefab(asset)，本仓库通过假桥完成契约测试。

### Task 1: 建立绑定 JSON 唯一事实源和确定性生成器

**Files:**
- Create: Bindings/LoginPanel.binding.json
- Create: Tools/Bindings/FBindingGenerator.js
- Create: Tools/Bindings/generate-bindings.js
- Create: Tests/Tools/FBindingGenerator.test.js
- Create: FLuaFramework/Generated/FUIBindings.lua
- Modify: package.json

- [ ] **Step 1: 写生成器 RED 测试**

创建 Tests/Tools/FBindingGenerator.test.js：

~~~javascript
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {
  loadContracts,
  renderLua,
} = require("../../Tools/Bindings/FBindingGenerator");

function tempRoot() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "flua-bindings-"));
}

test("generator sorts pages and bindings and renders stable Lua", () => {
  const root = tempRoot();
  fs.writeFileSync(path.join(root, "B.binding.json"), JSON.stringify({
    schemaVersion: 1,
    page: "BPanel",
    assets: { unreal: "/Game/B", unity: "UI/B" },
    editorAssets: { unreal: "/Game/B", unity: "Assets/UI/B.prefab" },
    bindings: [
      { id: "z", constant: "Z", type: "Text", native: { unreal: "ZText", unity: "ZText" } },
      { id: "a", constant: "A", type: "Button", native: { unreal: "AButton", unity: "AButton" } }
    ]
  }));
  const output = renderLua(loadContracts(root));
  assert.ok(output.indexOf('["BPanel"]') >= 0);
  assert.ok(output.indexOf('["a"] = "Button"') < output.indexOf('["z"] = "Text"'));
  assert.equal(output, renderLua(loadContracts(root)));
});

test("generator rejects duplicate logical ids with file context", () => {
  const root = tempRoot();
  fs.writeFileSync(path.join(root, "Bad.binding.json"), JSON.stringify({
    schemaVersion: 1,
    page: "BadPanel",
    assets: { unreal: "/Game/Bad", unity: "UI/Bad" },
    editorAssets: { unreal: "/Game/Bad", unity: "Assets/UI/Bad.prefab" },
    bindings: [
      { id: "title", constant: "TITLE", type: "Text", native: { unreal: "TitleA", unity: "TitleA" } },
      { id: "title", constant: "TITLE_2", type: "Text", native: { unreal: "TitleB", unity: "TitleB" } }
    ]
  }));
  assert.throws(() => loadContracts(root), /duplicate binding id title.*Bad\.binding\.json/);
});

test("generator rejects missing platform mappings", () => {
  const root = tempRoot();
  fs.writeFileSync(path.join(root, "Bad.binding.json"), JSON.stringify({
    schemaVersion: 1,
    page: "BadPanel",
    assets: { unreal: "/Game/Bad", unity: "UI/Bad" },
    editorAssets: { unreal: "/Game/Bad", unity: "Assets/UI/Bad.prefab" },
    bindings: [
      { id: "title", constant: "TITLE", type: "Text", native: { unreal: "Title" } }
    ]
  }));
  assert.throws(() => loadContracts(root), /native\.unity/);
});
~~~

- [ ] **Step 2: 运行生成器测试并确认 RED**

Run: node --test Tests/Tools/FBindingGenerator.test.js

Expected: FAIL，错误包含 Cannot find module '../../Tools/Bindings/FBindingGenerator'。

- [ ] **Step 3: 实现完整生成器内核**

创建 Tools/Bindings/FBindingGenerator.js：

~~~javascript
const fs = require("node:fs");
const path = require("node:path");

const TYPES = new Set([
  "Text", "Button", "Image", "Input", "Toggle",
  "Progress", "List", "Animation"
]);
const PLATFORMS = ["unreal", "unity"];

function fail(file, message) {
  throw new Error(path.basename(file) + ": " + message);
}

function nonEmptyString(value, file, field) {
  if (typeof value !== "string" || value.length === 0) {
    fail(file, field + " must be a non-empty string");
  }
  return value;
}

function validateContract(value, file) {
  if (value.schemaVersion !== 1) {
    fail(file, "schemaVersion must be 1");
  }
  nonEmptyString(value.page, file, "page");
  if (!value.assets || !value.editorAssets || !Array.isArray(value.bindings)) {
    fail(file, "assets, editorAssets and bindings are required");
  }
  for (const platform of PLATFORMS) {
    nonEmptyString(value.assets[platform], file, "assets." + platform);
    nonEmptyString(
      value.editorAssets[platform],
      file,
      "editorAssets." + platform
    );
  }
  const ids = new Set();
  const constants = new Set();
  for (const binding of value.bindings) {
    nonEmptyString(binding.id, file, "binding.id");
    nonEmptyString(binding.constant, file, "binding.constant");
    if (!/^[A-Z][A-Z0-9_]*$/.test(binding.constant)) {
      fail(file, "constant must use UPPER_SNAKE_CASE: " + binding.constant);
    }
    if (!TYPES.has(binding.type)) {
      fail(file, "unsupported binding type " + String(binding.type));
    }
    if (ids.has(binding.id)) {
      fail(file, "duplicate binding id " + binding.id);
    }
    if (constants.has(binding.constant)) {
      fail(file, "duplicate binding constant " + binding.constant);
    }
    ids.add(binding.id);
    constants.add(binding.constant);
    if (!binding.native) {
      fail(file, "binding.native is required for " + binding.id);
    }
    for (const platform of PLATFORMS) {
      nonEmptyString(
        binding.native[platform],
        file,
        "binding " + binding.id + " native." + platform
      );
    }
  }
  return value;
}

function loadContracts(root) {
  const files = fs.readdirSync(root)
    .filter((name) => name.endsWith(".binding.json"))
    .sort();
  const pages = new Set();
  return files.map((name) => {
    const file = path.join(root, name);
    const value = validateContract(JSON.parse(fs.readFileSync(file, "utf8")), file);
    if (pages.has(value.page)) {
      fail(file, "duplicate page " + value.page);
    }
    pages.add(value.page);
    value.bindings.sort((left, right) => left.id.localeCompare(right.id));
    return value;
  }).sort((left, right) => left.page.localeCompare(right.page));
}

function luaString(value) {
  return JSON.stringify(value);
}

function renderMap(lines, indent, name, entries) {
  lines.push(indent + name + " = {");
  for (const entry of entries) {
    lines.push(indent + "    [" + luaString(entry[0]) + "] = " + luaString(entry[1]) + ",");
  }
  lines.push(indent + "},");
}

function renderLua(contracts) {
  const lines = [
    "-- Generated by Tools/Bindings/generate-bindings.js. Do not edit.",
    "local FUIBindings = {"
  ];
  for (const contract of contracts) {
    lines.push("    [" + luaString(contract.page) + "] = {");
    renderMap(lines, "        ", "assets", PLATFORMS.map(
      (platform) => [platform, contract.assets[platform]]
    ));
    renderMap(lines, "        ", "editorAssets", PLATFORMS.map(
      (platform) => [platform, contract.editorAssets[platform]]
    ));
    renderMap(lines, "        ", "ids", contract.bindings.map(
      (binding) => [binding.constant, binding.id]
    ));
    renderMap(lines, "        ", "requiredBindings", contract.bindings.map(
      (binding) => [binding.id, binding.type]
    ));
    lines.push("        nativeBindings = {");
    for (const platform of PLATFORMS) {
      renderMap(lines, "            ", platform, contract.bindings.map(
        (binding) => [binding.id, binding.native[platform]]
      ));
    }
    lines.push("        },");
    lines.push("    },");
  }
  lines.push("}", "", "return FUIBindings", "");
  return lines.join("\n");
}

module.exports = { loadContracts, renderLua };
~~~

- [ ] **Step 4: 实现 generate/check 命令**

创建 Tools/Bindings/generate-bindings.js：

~~~javascript
const fs = require("node:fs");
const path = require("node:path");
const { loadContracts, renderLua } = require("./FBindingGenerator");

const root = path.resolve(process.cwd(), "Bindings");
const output = path.resolve(
  process.cwd(),
  "FLuaFramework/Generated/FUIBindings.lua"
);
const expected = renderLua(loadContracts(root));
const check = process.argv.includes("--check");

if (check) {
  const actual = fs.existsSync(output)
    ? fs.readFileSync(output, "utf8").replace(/\r\n/g, "\n")
    : "";
  if (actual !== expected) {
    console.error("generated bindings are stale: " + path.relative(process.cwd(), output));
    process.exit(1);
  }
  console.log("generated bindings are current");
} else {
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, expected);
  console.log("generated " + path.relative(process.cwd(), output));
}
~~~

- [ ] **Step 5: 写 LoginPanel 的完整绑定契约**

创建 Bindings/LoginPanel.binding.json：

~~~json
{
  "schemaVersion": 1,
  "page": "LoginPanel",
  "assets": {
    "unreal": "/Game/UI/Login/WBP_LoginPanel",
    "unity": "UI/Login/LoginPanel"
  },
  "editorAssets": {
    "unreal": "/Game/UI/Login/WBP_LoginPanel",
    "unity": "Assets/UI/Login/LoginPanel.prefab"
  },
  "bindings": [
    {
      "id": "title",
      "constant": "TITLE",
      "type": "Text",
      "native": { "unreal": "TitleText", "unity": "TitleText" }
    },
    {
      "id": "account_input",
      "constant": "ACCOUNT_INPUT",
      "type": "Input",
      "native": { "unreal": "AccountInput", "unity": "AccountInput" }
    },
    {
      "id": "remember_toggle",
      "constant": "REMEMBER_TOGGLE",
      "type": "Toggle",
      "native": { "unreal": "RememberToggle", "unity": "RememberToggle" }
    },
    {
      "id": "password_input",
      "constant": "PASSWORD_INPUT",
      "type": "Input",
      "native": { "unreal": "PasswordInput", "unity": "PasswordInput" }
    },
    {
      "id": "login_progress",
      "constant": "LOGIN_PROGRESS",
      "type": "Progress",
      "native": { "unreal": "LoginProgress", "unity": "LoginProgress" }
    },
    {
      "id": "login_button",
      "constant": "LOGIN_BUTTON",
      "type": "Button",
      "native": { "unreal": "LoginButton", "unity": "LoginButton" }
    },
    {
      "id": "status_text",
      "constant": "STATUS_TEXT",
      "type": "Text",
      "native": { "unreal": "StatusText", "unity": "StatusText" }
    },
    {
      "id": "avatar",
      "constant": "AVATAR",
      "type": "Image",
      "native": { "unreal": "AvatarImage", "unity": "AvatarImage" }
    }
  ]
}
~~~

- [ ] **Step 6: 增加 npm 命令并生成产物**

在 package.json 的 scripts 中加入：

~~~json
"generate:bindings": "node Tools/Bindings/generate-bindings.js",
"check:bindings": "node Tools/Bindings/generate-bindings.js --check",
"test:tools": "node --test Tests/Tools/*.test.js"
~~~

Run: npm run generate:bindings

Expected: 退出码为 0，输出 generated FLuaFramework/Generated/FUIBindings.lua。

Run: npm run test:tools

Expected: 3 tests、0 failures。

Run: npm run check:bindings

Expected: 输出 generated bindings are current。

### Task 2: 让运行时消费生成绑定并保留逻辑 ID

**Files:**
- Modify: FLuaFramework/register.lua
- Modify: FLuaFramework/Config/FPages.lua
- Modify: FLuaFramework/Adapters/Common/FViewBinder.lua
- Modify: FLuaFramework/Adapters/Unreal/FUnrealRuntime.lua
- Modify: FLuaFramework/Adapters/Unity/FUnityRuntime.lua
- Modify: FLuaFramework/Shared/Core/FUIManager.lua
- Modify: FLuaFramework/App/UI/Login/LoginPresenter.lua
- Modify: Tests/Fixtures/FFakePlatformBridge.lua
- Modify: Tests/Unit/FViewBinderSpec.lua
- Modify: Tests/Contract/FRuntimeContractSpec.lua
- Modify: Tests/Integration/FUIManagerSpec.lua
- Modify: Tests/Integration/LoginPanelSpec.lua

- [ ] **Step 1: 先写原生名称映射的失败测试**

在 Tests/Unit/FViewBinderSpec.lua 追加：

~~~lua
FTestHelper:test("view binder resolves platform native names but reports logical ids", function()
    local native_title = { kind = "Text", valid = true, text = "" }
    local bridge = make_bridge({ TitleText = native_title })
    local view = FViewBinder.bind(
        "LoginPanel",
        "unreal",
        { valid = true },
        { title = "Text" },
        { title = "TitleText" },
        bridge
    )
    view:text("title"):set_text("Login")
    FTestHelper:assert_equal("Login", native_title.text)
end)
~~~

Run: node_modules/.bin/fengari Tests/Unit/FViewBinderSpec.lua

Expected: FAIL；现有 bind 签名把 nativeBindings 当成 bridge，错误包含 attempt to call a nil value。

- [ ] **Step 2: 修改 Binder，使查找使用原生名称、错误仍使用逻辑 ID**

把 FViewBinder.bind 的函数头和循环中的 resolve 调用改为：

~~~lua
function FViewBinder.bind(
    page,
    platform,
    native_view,
    required_bindings,
    native_bindings,
    bridge
)
    local widgets = {}
    for id, expected in pairs(required_bindings) do
        local native_id = native_bindings[id]
        local native_widget = bridge.resolve(native_view, native_id)
        if native_widget == nil then
            error(FError:new("BINDING_NOT_FOUND", "required view binding was not found", {
                page = page,
                platform = platform,
                binding = id,
                native_binding = native_id,
                expected = expected,
            }), 0)
        end
        local actual = bridge.kind(native_widget)
        if actual ~= expected or factories[expected] == nil then
            error(FError:new("BINDING_TYPE_MISMATCH", "view binding type does not match", {
                page = page,
                platform = platform,
                binding = id,
                native_binding = native_id,
                expected = expected,
                actual = actual,
            }), 0)
        end
        widgets[id] = {
            kind = actual,
            widget = factories[actual](
                id,
                native_widget,
                bridge.widget_ops(native_widget, actual)
            ),
        }
    end
    return FIView:new(
        page,
        platform,
        native_view,
        bridge.view_ops(native_view),
        widgets
    )
end
~~~

更新原有测试调用，在 bridge 参数前传入恒等映射，例如：

~~~lua
{ title = "title", login_button = "login_button", avatar = "avatar" }
~~~

- [ ] **Step 3: 注册生成模块并让页面配置只引用生成数据**

在 FLuaFramework/register.lua 的 Core 注册项之前加入：

~~~lua
register("FUIBindings", "FLuaFramework.Generated.FUIBindings")
~~~

把 FLuaFramework/Config/FPages.lua 替换为：

~~~lua
local login = FUIBindings.LoginPanel

return {
    LoginPanel = {
        presenter = "FLuaFramework.App.UI.Login.LoginPresenter",
        singleton = true,
        cachePolicy = "DestroyOnClose",
        assets = login.assets,
        layer = "Normal",
        inputMode = "UIOnly",
        requiredBindings = login.requiredBindings,
        nativeBindings = login.nativeBindings,
        hotReloadModules = {
            "FLuaFramework.App.UI.Login.LoginPresenter",
        },
    },
}
~~~

- [ ] **Step 4: 把平台映射传入 Runtime 和 Binder**

把两个 Runtime 的 bind_view 签名统一为：

~~~lua
function FUnrealRuntime:bind_view(
    page,
    native_view,
    required_bindings,
    native_bindings
)
    local bridge = self.bridge
    return FViewBinder.bind(
        page,
        self.platform,
        native_view,
        required_bindings,
        native_bindings,
        {
            resolve = bridge.find_widget,
            kind = bridge.get_widget_type,
            widget_ops = bridge.make_widget_ops,
            view_ops = bridge.make_view_ops,
        }
    )
end
~~~

把 FLuaFramework/Adapters/Unity/FUnityRuntime.lua 中的 bind_view 完整替换为：

~~~lua
function FUnityRuntime:bind_view(
    page,
    native_view,
    required_bindings,
    native_bindings
)
    local bridge = self.bridge
    return FViewBinder.bind(
        page,
        self.platform,
        native_view,
        required_bindings,
        native_bindings,
        {
            resolve = bridge.find_component,
            kind = bridge.get_component_type,
            widget_ops = bridge.make_component_ops,
            view_ops = bridge.make_view_ops,
        }
    )
end
~~~

在 FUIManager:_finish_open 的 bind_view 调用增加第四个参数：

~~~lua
instance.definition.nativeBindings[self.runtime.platform]
~~~

- [ ] **Step 5: 让业务 Presenter 使用生成常量**

前序“常用能力”阶段完成后，把 LoginPresenter.lua 完整替换为：

~~~lua
local ids = FUIBindings.LoginPanel.ids

local LoginPresenter = FClass("LoginPresenter", FBasePresenter)

function LoginPresenter:ctor(services)
    self.services = services
end

function LoginPresenter:on_create(view, params)
    FBasePresenter.on_create(self, view, params)
    self.avatar_request = nil
end

function LoginPresenter:on_bind()
    self:track(self.view:button(ids.LOGIN_BUTTON):on_click(function()
        local account = self.view:input(ids.ACCOUNT_INPUT):get_text()
        local password = self.view:input(ids.PASSWORD_INPUT):get_text()
        local remember = self.view:toggle(ids.REMEMBER_TOGGLE):is_checked()
        self.view:progress(ids.LOGIN_PROGRESS):set_value(0.25)
        local succeeded, message = self.services.login(
            account,
            password,
            remember
        )
        self.view:progress(ids.LOGIN_PROGRESS):set_value(1)
        self.view:text(ids.STATUS_TEXT):set_text(
            succeeded and "登录成功" or (message or "登录失败")
        )
    end))
end

function LoginPresenter:_load_avatar(resource_id)
    if self.avatar_request ~= nil then self.avatar_request:cancel() end
    self.avatar_request = self:track_request(self.services.asset_loader:load({
        id = resource_id,
        type = "texture",
    }, function(asset, failure)
        if failure ~= nil then
            self.view:text(ids.STATUS_TEXT):set_text("头像加载失败")
            return
        end
        self.view:image(ids.AVATAR):set_source(asset)
    end))
end

function LoginPresenter:on_open(params)
    FBasePresenter.on_open(self, params)
    self.view:text(ids.TITLE):set_text("登录")
    self.view:input(ids.ACCOUNT_INPUT):set_text(self.params.account or "")
    self.view:input(ids.PASSWORD_INPUT):set_text("")
    self.view:toggle(ids.REMEMBER_TOGGLE):set_checked(
        self.params.remember == true
    )
    self.view:text(ids.STATUS_TEXT):set_text("")
    self.view:progress(ids.LOGIN_PROGRESS):set_value(0)
    self:_load_avatar(self.params.avatar or "avatar/default")
end

return LoginPresenter
~~~

- [ ] **Step 6: 更新假桥和契约测试**

在 FFakePlatformBridge:make_native_view 中使用生成后的原生名称：

~~~lua
add("TitleText", "Text")
add("AccountInput", "Input")
add("PasswordInput", "Input")
add("RememberToggle", "Toggle")
add("LoginButton", "Button")
add("LoginProgress", "Progress")
add("StatusText", "Text")
add("AvatarImage", "Image")
~~~

Tests/Contract/FRuntimeContractSpec.lua 调用 runtime:bind_view 时同时传：

~~~lua
FUIBindings.LoginPanel.requiredBindings,
FUIBindings.LoginPanel.nativeBindings[case.platform]
~~~

并把断言访问改为 received.widgets.TitleText 与 received.widgets.AvatarImage。同步修改 Tests/Integration/FUIManagerSpec.lua 与 Tests/Integration/LoginPanelSpec.lua 中所有 requiredBindings、native.widgets 和测试点击路径：requiredBindings/nativeBindings 均从 FUIBindings.LoginPanel 取得，原生访问分别使用 AccountInput、PasswordInput、RememberToggle、LoginButton、LoginProgress、StatusText 和 AvatarImage。

Run: npm test

Expected: 所有既有 Lua 测试和新增 Binder 用例通过，0 failed。

### Task 3: 实现可在两个编辑器复用的绑定检查

**Files:**
- Create: FLuaFramework/Tools/Editor/FBindingValidator.lua
- Create: FLuaFramework/Adapters/Unreal/FUnrealBindingInspector.lua
- Create: FLuaFramework/Adapters/Unity/FUnityBindingInspector.lua
- Create: Tests/Unit/FBindingValidatorSpec.lua
- Create: editor.lua
- Modify: FLuaFramework/register.lua
- Modify: Tests/run.lua

- [ ] **Step 1: 写批量诊断 RED 测试**

创建 Tests/Unit/FBindingValidatorSpec.lua：

~~~lua
local FTestHelper = require("Tests.TestHelper")

local function inspector(entries)
    return {
        inspect = function(_, asset)
            return entries[asset]
        end,
    }
end

FTestHelper:test("binding validator reports missing mismatch and duplicate nodes", function()
    local contract = {
        assets = { unreal = "/Game/Login" },
        editorAssets = { unreal = "/Game/Login" },
        requiredBindings = {
            title = "Text",
            login_button = "Button",
        },
        nativeBindings = {
            unreal = {
                title = "TitleText",
                login_button = "LoginButton",
            },
        },
    }
    local issues = FBindingValidator.validate_page(
        "LoginPanel",
        "unreal",
        contract,
        inspector({
            ["/Game/Login"] = {
                { name = "TitleText", type = "Button" },
                { name = "TitleText", type = "Button" },
            },
        })
    )
    FTestHelper:assert_equal(3, #issues)
    FTestHelper:assert_equal("BINDING_NOT_FOUND", issues[1].code)
    FTestHelper:assert_equal("DUPLICATE_NATIVE_BINDING", issues[2].code)
    FTestHelper:assert_equal("BINDING_TYPE_MISMATCH", issues[3].code)
end)

FTestHelper:test("binding validator returns no issues for a valid asset", function()
    local contract = FUIBindings.LoginPanel
    local entries = {}
    for id, expected in pairs(contract.requiredBindings) do
        table.insert(entries, {
            name = contract.nativeBindings.unity[id],
            type = expected,
        })
    end
    local issues = FBindingValidator.validate_page(
        "LoginPanel",
        "unity",
        contract,
        inspector({ [contract.editorAssets.unity] = entries })
    )
    FTestHelper:assert_equal(0, #issues)
end)
~~~

先把该文件加入 Tests/run.lua。

Run: npm test

Expected: FAIL，错误包含 attempt to index a nil value (global 'FBindingValidator')。

- [ ] **Step 2: 实现纯 Lua 校验器**

创建 FLuaFramework/Tools/Editor/FBindingValidator.lua：

~~~lua
local FBindingValidator = {}

local function issue(code, page, platform, fields)
    fields.code = code
    fields.page = page
    fields.platform = platform
    return fields
end

function FBindingValidator.validate_page(page, platform, contract, inspector)
    local asset = contract.editorAssets[platform]
    local entries = inspector:inspect(asset)
    if entries == nil then
        return {
            issue("ASSET_LOAD_FAILED", page, platform, { asset = asset }),
        }
    end

    local by_name = {}
    for _, entry in ipairs(entries) do
        local bucket = by_name[entry.name] or {}
        table.insert(bucket, entry)
        by_name[entry.name] = bucket
    end

    local issues = {}
    local ids = {}
    for id in pairs(contract.requiredBindings) do
        table.insert(ids, id)
    end
    table.sort(ids)

    for _, id in ipairs(ids) do
        local expected = contract.requiredBindings[id]
        local native_name = contract.nativeBindings[platform][id]
        local matches = by_name[native_name] or {}
        if #matches > 1 then
            table.insert(issues, issue(
                "DUPLICATE_NATIVE_BINDING",
                page,
                platform,
                {
                    binding = id,
                    native_binding = native_name,
                    count = #matches,
                }
            ))
        end
        if #matches == 0 then
            table.insert(issues, issue(
                "BINDING_NOT_FOUND",
                page,
                platform,
                {
                    binding = id,
                    native_binding = native_name,
                    expected = expected,
                }
            ))
        elseif matches[1].type ~= expected then
            table.insert(issues, issue(
                "BINDING_TYPE_MISMATCH",
                page,
                platform,
                {
                    binding = id,
                    native_binding = native_name,
                    expected = expected,
                    actual = matches[1].type,
                }
            ))
        end
    end
    return issues
end

function FBindingValidator.validate_all(platform, bindings, inspector)
    local pages = {}
    for page in pairs(bindings) do
        table.insert(pages, page)
    end
    table.sort(pages)
    local issues = {}
    for _, page in ipairs(pages) do
        local page_issues = FBindingValidator.validate_page(
            page,
            platform,
            bindings[page],
            inspector
        )
        for _, value in ipairs(page_issues) do
            table.insert(issues, value)
        end
    end
    return issues
end

return FBindingValidator
~~~

- [ ] **Step 3: 实现两个薄检查器适配器**

创建 FLuaFramework/Adapters/Unreal/FUnrealBindingInspector.lua：

~~~lua
local FUnrealBindingInspector = FClass("FUnrealBindingInspector")

function FUnrealBindingInspector:ctor(bridge)
    self.bridge = bridge
end

function FUnrealBindingInspector:inspect(asset)
    return self.bridge.inspect_widget_blueprint(asset)
end

return FUnrealBindingInspector
~~~

创建 FLuaFramework/Adapters/Unity/FUnityBindingInspector.lua：

~~~lua
local FUnityBindingInspector = FClass("FUnityBindingInspector")

function FUnityBindingInspector:ctor(bridge)
    self.bridge = bridge
end

function FUnityBindingInspector:inspect(asset)
    return self.bridge.inspect_prefab(asset)
end

return FUnityBindingInspector
~~~

在 register.lua 注册 FBindingValidator、FUnrealBindingInspector 和 FUnityBindingInspector。

- [ ] **Step 4: 添加编辑器统一入口**

创建根目录 editor.lua：

~~~lua
local registered = require("FLuaFramework.register")

local editor = {}

local inspectors = {
    unreal = registered.FUnrealBindingInspector,
    unity = registered.FUnityBindingInspector,
}

function editor.check_bindings(options)
    local inspector_class = inspectors[options.platform]
    if inspector_class == nil then
        error(registered.FError:new(
            "UNSUPPORTED_PLATFORM",
            "editor binding check platform is not supported",
            { platform = options.platform }
        ), 0)
    end
    local inspector = inspector_class:new(options.bridge)
    return registered.FBindingValidator.validate_all(
        options.platform,
        registered.FUIBindings,
        inspector
    )
end

return editor
~~~

Run: npm test

Expected: 新增两个校验用例通过；全量 0 failed。

### Task 4: 建立结构化诊断和可注入时钟的性能统计

**Files:**
- Create: FLuaFramework/Shared/Diagnostics/FDiagnostics.lua
- Create: FLuaFramework/Shared/Diagnostics/FPerformanceStats.lua
- Create: Tests/Unit/FDiagnosticsSpec.lua
- Create: Tests/Unit/FPerformanceStatsSpec.lua
- Modify: FLuaFramework/register.lua
- Modify: Tests/run.lua

- [ ] **Step 1: 写诊断和性能 RED 测试**

创建 Tests/Unit/FDiagnosticsSpec.lua：

~~~lua
local FTestHelper = require("Tests.TestHelper")

FTestHelper:test("diagnostics enriches and forwards structured events", function()
    local received = {}
    local diagnostics = FDiagnostics:new(function(event)
        table.insert(received, event)
    end)
    diagnostics:emit("page_opened", {
        page = "LoginPanel",
        platform = "unreal",
        instance_id = 7,
    })
    FTestHelper:assert_equal(1, #received)
    FTestHelper:assert_equal("page_opened", received[1].kind)
    FTestHelper:assert_equal(7, received[1].instance_id)
end)

FTestHelper:test("diagnostics keeps a bounded in-memory buffer", function()
    local diagnostics = FDiagnostics:new(nil, { max_events = 2 })
    diagnostics:emit("first")
    diagnostics:emit("second")
    diagnostics:emit("third")
    local events = diagnostics:events()
    FTestHelper:assert_equal(2, #events)
    FTestHelper:assert_equal("second", events[1].kind)
    FTestHelper:assert_equal("third", events[2].kind)
end)
~~~

创建 Tests/Unit/FPerformanceStatsSpec.lua：

~~~lua
local FTestHelper = require("Tests.TestHelper")

FTestHelper:test("performance stats aggregates count total and max duration", function()
    local now = 10
    local diagnostics = FDiagnostics:new()
    local stats = FPerformanceStats:new(function() return now end, diagnostics)
    local first = stats:begin("page_open", { page = "LoginPanel" })
    now = 18
    stats:finish(first)
    local second = stats:begin("page_open", { page = "LoginPanel" })
    now = 23
    stats:finish(second)

    local value = stats:snapshot().page_open
    FTestHelper:assert_equal(2, value.count)
    FTestHelper:assert_equal(13, value.total_ms)
    FTestHelper:assert_equal(8, value.max_ms)
end)

FTestHelper:test("performance token cannot be finished twice", function()
    local stats = FPerformanceStats:new(function() return 1 end, FDiagnostics:new())
    local token = stats:begin("bind_view", {})
    stats:finish(token)
    FTestHelper:assert_error_code("INVALID_PERFORMANCE_TOKEN", function()
        stats:finish(token)
    end)
end)
~~~

把两个文件加入 Tests/run.lua。

Run: npm test

Expected: FAIL，缺少 FDiagnostics 全局。

- [ ] **Step 2: 实现诊断出口**

创建 FLuaFramework/Shared/Diagnostics/FDiagnostics.lua：

~~~lua
local FDiagnostics = FClass("FDiagnostics")

function FDiagnostics:ctor(sink, options)
    self.sink = sink
    self.buffer = {}
    self.max_events = options and options.max_events or 256
end

function FDiagnostics:emit(kind, fields)
    local event = { kind = kind }
    for key, value in pairs(fields or {}) do
        event[key] = value
    end
    if self.max_events > 0 then
        table.insert(self.buffer, event)
        if #self.buffer > self.max_events then
            table.remove(self.buffer, 1)
        end
    end
    if self.sink ~= nil then
        self.sink(event)
    end
    return event
end

function FDiagnostics:events(kind)
    local result = {}
    for _, event in ipairs(self.buffer) do
        if kind == nil or event.kind == kind then
            table.insert(result, event)
        end
    end
    return result
end

function FDiagnostics:clear()
    self.buffer = {}
end

return FDiagnostics
~~~

- [ ] **Step 3: 实现性能聚合器**

创建 FLuaFramework/Shared/Diagnostics/FPerformanceStats.lua：

~~~lua
local FPerformanceStats = FClass("FPerformanceStats")

function FPerformanceStats:ctor(clock, diagnostics)
    self.clock = clock or function() return os.clock() * 1000 end
    self.diagnostics = diagnostics
    self.values = {}
end

function FPerformanceStats:begin(operation, fields)
    return {
        operation = operation,
        fields = fields or {},
        started_at = self.clock(),
        active = true,
    }
end

function FPerformanceStats:finish(token, extra_fields)
    if type(token) ~= "table" or token.active ~= true then
        error(FError:new(
            "INVALID_PERFORMANCE_TOKEN",
            "performance token is missing or already finished",
            {}
        ), 0)
    end
    token.active = false
    local duration = self.clock() - token.started_at
    local value = self.values[token.operation]
    if value == nil then
        value = { count = 0, total_ms = 0, max_ms = 0 }
        self.values[token.operation] = value
    end
    value.count = value.count + 1
    value.total_ms = value.total_ms + duration
    value.max_ms = math.max(value.max_ms, duration)

    local fields = {}
    for key, item in pairs(token.fields) do fields[key] = item end
    for key, item in pairs(extra_fields or {}) do fields[key] = item end
    fields.operation = token.operation
    fields.duration_ms = duration
    self.diagnostics:emit("performance_sample", fields)
    return duration
end

function FPerformanceStats:snapshot()
    local result = {}
    for operation, value in pairs(self.values) do
        result[operation] = {
            count = value.count,
            total_ms = value.total_ms,
            max_ms = value.max_ms,
        }
    end
    return result
end

return FPerformanceStats
~~~

在 register.lua 中按依赖顺序先注册 FDiagnostics，再注册 FPerformanceStats。

Run: npm test

Expected: 两个诊断用例和两个性能用例通过；全量 0 failed。

### Task 5: 用显式令牌追踪页面、请求和 Presenter 订阅

**Files:**
- Create: FLuaFramework/Shared/Diagnostics/FLeakTracker.lua
- Create: Tests/Unit/FLeakTrackerSpec.lua
- Modify: FLuaFramework/Shared/Core/FBasePresenter.lua
- Modify: Tests/Unit/FBasePresenterSpec.lua
- Modify: FLuaFramework/register.lua
- Modify: Tests/run.lua

- [ ] **Step 1: 写泄漏追踪 RED 测试**

创建 Tests/Unit/FLeakTrackerSpec.lua：

~~~lua
local FTestHelper = require("Tests.TestHelper")

FTestHelper:test("leak tracker releases tokens idempotently", function()
    local diagnostics = FDiagnostics:new()
    local tracker = FLeakTracker:new(diagnostics)
    local token = tracker:track("request", 9, "LoginPanel.load")
    FTestHelper:assert_equal(1, #tracker:snapshot(9))
    tracker:release(token)
    tracker:release(token)
    FTestHelper:assert_equal(0, #tracker:snapshot(9))
end)

FTestHelper:test("leak tracker reports every live resource with owner context", function()
    local diagnostics = FDiagnostics:new()
    local tracker = FLeakTracker:new(diagnostics)
    tracker:track("page", 9, "LoginPanel")
    tracker:track("subscription", 9, "login_button.on_click")

    local leaks = tracker:report(9)
    FTestHelper:assert_equal(2, #leaks)
    FTestHelper:assert_equal(1, #diagnostics:events("leak_detected"))
    FTestHelper:assert_equal(9, diagnostics:events("leak_detected")[1].instance_id)
end)
~~~

把文件加入 Tests/run.lua。

Run: npm test

Expected: FAIL，缺少 FLeakTracker 全局。

- [ ] **Step 2: 实现显式资源令牌**

创建 FLuaFramework/Shared/Diagnostics/FLeakTracker.lua：

~~~lua
local FLeakTracker = FClass("FLeakTracker")

function FLeakTracker:ctor(diagnostics)
    self.diagnostics = diagnostics
    self.next_id = 0
    self.live = {}
end

function FLeakTracker:track(kind, owner_id, label)
    self.next_id = self.next_id + 1
    local token = {
        id = self.next_id,
        kind = kind,
        owner_id = owner_id,
        label = label,
        active = true,
    }
    self.live[token.id] = token
    return token
end

function FLeakTracker:release(token)
    if token == nil or token.active ~= true then
        return false
    end
    token.active = false
    self.live[token.id] = nil
    return true
end

function FLeakTracker:snapshot(owner_id)
    local result = {}
    for _, token in pairs(self.live) do
        if owner_id == nil or token.owner_id == owner_id then
            table.insert(result, {
                id = token.id,
                kind = token.kind,
                owner_id = token.owner_id,
                label = token.label,
            })
        end
    end
    table.sort(result, function(left, right) return left.id < right.id end)
    return result
end

function FLeakTracker:report(owner_id)
    local leaks = self:snapshot(owner_id)
    if #leaks > 0 then
        self.diagnostics:emit("leak_detected", {
            instance_id = owner_id,
            count = #leaks,
            resources = leaks,
        })
    end
    return leaks
end

return FLeakTracker
~~~

在 register.lua 中紧跟 FPerformanceStats 注册 FLeakTracker。

- [ ] **Step 3: 写 Presenter 订阅令牌对称释放测试**

在 Tests/Unit/FBasePresenterSpec.lua 追加：

~~~lua
FTestHelper:test("presenter releases tracked subscription leak tokens", function()
    local diagnostics = FDiagnostics:new()
    local leaks = FLeakTracker:new(diagnostics)
    local presenter = FBasePresenter:new()
    presenter:set_diagnostics_context(leaks, 12)
    presenter:track({
        unsubscribe = function() end,
        diagnostic_label = "login_button.on_click",
    })
    FTestHelper:assert_equal(1, #leaks:snapshot(12))
    presenter:on_unbind()
    FTestHelper:assert_equal(0, #leaks:snapshot(12))
end)

FTestHelper:test("presenter releases tracked request leak tokens", function()
    local diagnostics = FDiagnostics:new()
    local leaks = FLeakTracker:new(diagnostics)
    local presenter = FBasePresenter:new()
    presenter:set_diagnostics_context(leaks, 13)
    presenter:track_request({
        cancel = function() end,
        diagnostic_label = "avatar.load",
    })
    FTestHelper:assert_equal(1, #leaks:snapshot(13))
    presenter:on_unbind()
    FTestHelper:assert_equal(0, #leaks:snapshot(13))
end)
~~~

Run: node_modules/.bin/fengari Tests/Unit/FBasePresenterSpec.lua

Expected: FAIL，错误包含 attempt to call a nil value (method 'set_diagnostics_context')。

- [ ] **Step 4: 扩展 FBasePresenter 的订阅诊断上下文**

在 ctor 中增加：

~~~lua
self.subscription_tokens = {}
self.request_tokens = {}
~~~

并加入：

~~~lua
function FBasePresenter:set_diagnostics_context(leak_tracker, owner_id)
    self.leak_tracker = leak_tracker
    self.owner_id = owner_id
end
~~~

把 track 替换为：

~~~lua
function FBasePresenter:track(subscription)
    if type(subscription) ~= "table" or type(subscription.unsubscribe) ~= "function" then
        error(FError:new(
            "INVALID_SUBSCRIPTION",
            "subscription must expose unsubscribe",
            {}
        ), 0)
    end
    table.insert(self.subscriptions, subscription)
    if self.leak_tracker ~= nil then
        self.subscription_tokens[subscription] = self.leak_tracker:track(
            "subscription",
            self.owner_id,
            subscription.diagnostic_label or "presenter.subscription"
        )
    end
    return subscription
end
~~~

把前序阶段的 track_request 替换为：

~~~lua
function FBasePresenter:track_request(request)
    if type(request) ~= "table" or type(request.cancel) ~= "function" then
        error(FError:new(
            "INVALID_CANCELABLE",
            "request must expose cancel",
            {}
        ), 0)
    end
    table.insert(self.requests, request)
    if self.leak_tracker ~= nil then
        self.request_tokens[request] = self.leak_tracker:track(
            "request",
            self.owner_id,
            request.diagnostic_label or "presenter.request"
        )
    end
    return request
end
~~~

把 on_unbind 的两个清理循环替换为：

~~~lua
for index = #self.requests, 1, -1 do
    local request = self.requests[index]
    request:cancel()
    if self.leak_tracker ~= nil then
        self.leak_tracker:release(self.request_tokens[request])
    end
    self.request_tokens[request] = nil
    self.requests[index] = nil
end
for index = #self.subscriptions, 1, -1 do
    local subscription = self.subscriptions[index]
    subscription:unsubscribe()
    if self.leak_tracker ~= nil then
        self.leak_tracker:release(self.subscription_tokens[subscription])
    end
    self.subscription_tokens[subscription] = nil
    self.subscriptions[index] = nil
end
~~~

Run: npm test

Expected: 泄漏追踪和 Presenter 对称释放用例通过；全量 0 failed。

### Task 6: 在 FUIManager 生命周期边界接入性能和泄漏诊断

**Files:**
- Modify: FLuaFramework/Shared/Core/FUIManager.lua
- Modify: init.lua
- Create: Tests/Integration/FEngineeringDiagnosticsSpec.lua
- Modify: Tests/run.lua

- [ ] **Step 1: 写成功、取消和失败路径的 RED 集成测试**

创建 Tests/Integration/FEngineeringDiagnosticsSpec.lua：

~~~lua
local FTestHelper = require("Tests.TestHelper")
local FFakePlatformBridge = require("Tests.Fixtures.FFakePlatformBridge")

local function make_manager()
    local now = 0
    local diagnostics = FDiagnostics:new()
    local performance = FPerformanceStats:new(function() return now end, diagnostics)
    local leaks = FLeakTracker:new(diagnostics)
    local fake = FFakePlatformBridge:new("unreal")
    local manager = FUIManager:new({
        runtime = FUnrealRuntime:new(fake:as_unreal()),
        pages = {
            LoginPanel = {
                presenter = "FakePresenter",
                singleton = true,
                assets = FUIBindings.LoginPanel.assets,
                layer = "Normal",
                inputMode = "UIOnly",
                requiredBindings = FUIBindings.LoginPanel.requiredBindings,
                nativeBindings = FUIBindings.LoginPanel.nativeBindings,
            },
        },
        layers = {
            Normal = { order = 100, blocksInput = false },
        },
        diagnostics = diagnostics,
        performance = performance,
        leaks = leaks,
        require_module = function()
            local FakePresenter = FClass("EngineeringFakePresenter", FBasePresenter)
            return FakePresenter
        end,
    })
    return {
        manager = manager,
        fake = fake,
        diagnostics = diagnostics,
        performance = performance,
        leaks = leaks,
        advance = function(value) now = now + value end,
    }
end

FTestHelper:test("manager emits timed open and leaves no resources after close", function()
    local context = make_manager()
    local instance = context.manager:open("LoginPanel")
    FTestHelper:assert_not_nil(instance.id)
    context.advance(5)
    context.fake:complete_next()
    FTestHelper:assert_equal(1, #context.diagnostics:events("page_opened"))
    FTestHelper:assert_equal(5, context.performance:snapshot().page_open.total_ms)
    context.manager:close("LoginPanel")
    FTestHelper:assert_equal(0, #context.leaks:snapshot(instance.id))
end)

FTestHelper:test("manager releases request and page tokens when loading is cancelled", function()
    local context = make_manager()
    local instance = context.manager:open("LoginPanel")
    context.manager:close("LoginPanel")
    FTestHelper:assert_equal(0, #context.leaks:snapshot(instance.id))
    FTestHelper:assert_equal(1, #context.diagnostics:events("page_open_cancelled"))
end)

FTestHelper:test("manager diagnoses cleanup residue on a failed open", function()
    local context = make_manager()
    context.manager.pages.LoginPanel.requiredBindings.missing = "Text"
    context.manager.pages.LoginPanel.nativeBindings.unreal.missing = "Missing"
    local instance = context.manager:open("LoginPanel")
    pcall(function() context.fake:complete_next() end)
    FTestHelper:assert_equal(0, #context.leaks:snapshot(instance.id))
    FTestHelper:assert_equal(1, #context.diagnostics:events("page_open_failed"))
end)
~~~

把该文件加入 Tests/run.lua。

Run: npm test

Expected: FAIL；诊断事件和资源令牌不存在。

- [ ] **Step 2: 给 Manager 注入工程化服务并复用前序实例 ID**

在 FUIManager:ctor 中加入：

~~~lua
self.diagnostics = options.diagnostics or FDiagnostics:new()
self.performance = options.performance
    or FPerformanceStats:new(nil, self.diagnostics)
self.leaks = options.leaks or FLeakTracker:new(self.diagnostics)
~~~

前序 Manager 已经用 self.next_instance_id 生成 instance.id，不再创建第二套计数器。在 instance 表中加入：

~~~lua
open_timer = self.performance:begin("page_open", {
    page = page_name,
    platform = self.runtime.platform,
    instance_id = self.next_instance_id,
}),
page_token = self.leaks:track("page", self.next_instance_id, page_name),
~~~

load_view 返回后立即登记请求令牌：

~~~lua
instance.request_token = self.leaks:track(
    "request",
    instance.id,
    page_name .. ".load"
)
~~~

- [ ] **Step 3: 在成功打开路径完成计时并注入 Presenter 上下文**

在 _finish_open 确认 request_version 有效后首先执行：

~~~lua
self.leaks:release(instance.request_token)
instance.request_token = nil
~~~

Presenter 创建后、on_create 之前执行：

~~~lua
if type(instance.presenter.set_diagnostics_context) == "function" then
    instance.presenter:set_diagnostics_context(
        self.leaks,
        instance.id
    )
end
~~~

在 _finish_open 的 desired_visible 分支完成、页面已经处于 Opened 或 Hidden 后执行：

~~~lua
self.performance:finish(instance.open_timer, {
    lifecycle = instance.lifecycle:get_state(),
})
instance.open_timer = nil
self.diagnostics:emit("page_opened", {
    page = instance.name,
    platform = self.runtime.platform,
    instance_id = instance.id,
    lifecycle = instance.lifecycle:get_state(),
})
if instance.after_open ~= nil then
    instance.after_open(instance)
end
~~~

- [ ] **Step 4: 对取消、失败和正常关闭做对称释放**

在 Loading 关闭分支取消请求后加入：

~~~lua
self.leaks:release(instance.request_token)
self.leaks:release(instance.page_token)
instance.request_token = nil
instance.page_token = nil
self.diagnostics:emit("page_open_cancelled", {
    page = instance.name,
    platform = self.runtime.platform,
    instance_id = instance.id,
    lifecycle = "Unloaded",
})
~~~

前序 Manager 已把绑定失败与资源加载失败统一汇入 _raise_open_failure。把以下代码放在该方法的 _cleanup_failed_open 和 logger:error 之后、重新抛错之前，确保两个失败入口共用同一清理：

~~~lua
self.leaks:release(instance.request_token)
self.leaks:release(instance.page_token)
instance.request_token = nil
instance.page_token = nil
self.diagnostics:emit("page_open_failed", {
    page = instance.name,
    platform = self.runtime.platform,
    instance_id = instance.id,
    lifecycle = instance.lifecycle:get_state(),
    error_code = type(failure) == "table" and failure.code or nil,
})
self.leaks:report(instance.id)
~~~

在正常 close 的 on_destroy 和 view:destroy 之后、移除 instances 之前加入：

~~~lua
self.leaks:release(instance.page_token)
instance.page_token = nil
self.diagnostics:emit("page_closed", {
    page = instance.name,
    platform = self.runtime.platform,
    instance_id = instance.id,
    lifecycle = instance.lifecycle:get_state(),
})
self.leaks:report(instance.id)
~~~

open 的签名扩展为 function FUIManager:open(page_name, params, internal_options)，并在 instance 表保存：

~~~lua
after_open = internal_options and internal_options.after_open or nil,
~~~

第三个参数是框架内部扩展；业务侧仍使用原来的两个参数。

- [ ] **Step 5: 在 init.create 中建立同一套诊断对象**

创建 Manager 之前加入：

~~~lua
local diagnostics = registered.FDiagnostics:new(options.diagnostic_sink)
local performance = registered.FPerformanceStats:new(options.clock, diagnostics)
local leaks = registered.FLeakTracker:new(diagnostics)
~~~

传给 FUIManager:new 的 options 增加：

~~~lua
diagnostics = diagnostics,
performance = performance,
leaks = leaks,
~~~

Run: npm test

Expected: 成功、取消和失败三条诊断路径通过；每条关闭路径的泄漏快照为空；全量 0 failed。

### Task 7: 实现失败可回滚的 Lua 模块重载器

**Files:**
- Create: FLuaFramework/Shared/HotReload/FModuleReloader.lua
- Create: Tests/Unit/FModuleReloaderSpec.lua
- Modify: FLuaFramework/register.lua
- Modify: Tests/run.lua

- [ ] **Step 1: 写事务成功、失败回滚和边界拒绝测试**

创建 Tests/Unit/FModuleReloaderSpec.lua：

~~~lua
local FTestHelper = require("Tests.TestHelper")

FTestHelper:test("module reloader replaces allowed modules in order", function()
    local loaded = {
        ["Game.UI.Helper"] = { version = 1 },
        ["Game.UI.LoginPresenter"] = { version = 1 },
    }
    local order = {}
    local reloader = FModuleReloader:new({
        loaded = loaded,
        load = function(name)
            table.insert(order, name)
            local module = { version = 2 }
            loaded[name] = module
            return module
        end,
        is_allowed = function(name)
            return string.sub(name, 1, 5) == "Game."
        end,
    })
    local result = reloader:reload({
        "Game.UI.Helper",
        "Game.UI.LoginPresenter",
    })
    FTestHelper:assert_true(result.ok)
    FTestHelper:assert_equal("Game.UI.Helper,Game.UI.LoginPresenter", table.concat(order, ","))
    FTestHelper:assert_equal(2, loaded["Game.UI.LoginPresenter"].version)
end)

FTestHelper:test("module reloader restores every old module after load failure", function()
    local old = { version = 1 }
    local loaded = { ["Game.Bad"] = old }
    local reloader = FModuleReloader:new({
        loaded = loaded,
        load = function() error("syntax error") end,
        is_allowed = function() return true end,
    })
    local result = reloader:reload({ "Game.Bad" })
    FTestHelper:assert_false(result.ok)
    FTestHelper:assert_equal(old, loaded["Game.Bad"])
end)

FTestHelper:test("module reloader rejects framework infrastructure", function()
    local reloader = FModuleReloader:new({
        loaded = {},
        load = function() end,
        is_allowed = function(name)
            local prefix = "FLuaFramework.Shared."
            return string.sub(name, 1, #prefix) ~= prefix
        end,
    })
    local result = reloader:reload({ "FLuaFramework.Shared.Core.FClass" })
    FTestHelper:assert_false(result.ok)
    FTestHelper:assert_equal("HOT_RELOAD_UNSUPPORTED", result.error.code)
end)
~~~

把文件加入 Tests/run.lua。

Run: npm test

Expected: FAIL，缺少 FModuleReloader 全局。

- [ ] **Step 2: 实现事务式 package.loaded 替换**

创建 FLuaFramework/Shared/HotReload/FModuleReloader.lua：

~~~lua
local FModuleReloader = FClass("FModuleReloader")

function FModuleReloader:ctor(loader)
    self.loaded = loader.loaded
    self.load = loader.load
    self.is_allowed = loader.is_allowed
end

function FModuleReloader:reload(module_names)
    local old = {}
    for _, name in ipairs(module_names) do
        if self.is_allowed(name) ~= true then
            return {
                ok = false,
                error = FError:new(
                    "HOT_RELOAD_UNSUPPORTED",
                    "module is outside the hot reload boundary",
                    { module = name }
                ),
            }
        end
        old[name] = self.loaded[name]
    end

    for _, name in ipairs(module_names) do
        self.loaded[name] = nil
    end

    local succeeded, failure = xpcall(function()
        for _, name in ipairs(module_names) do
            local module = self.load(name)
            self.loaded[name] = module
        end
    end, function(value) return value end)

    if succeeded then
        return { ok = true }
    end

    for _, name in ipairs(module_names) do
        self.loaded[name] = old[name]
    end
    return {
        ok = false,
        error = FError:new(
            "HOT_RELOAD_FAILED",
            "module reload failed and old modules were restored",
            {
                module_count = #module_names,
                cause = tostring(failure),
            }
        ),
    }
end

return FModuleReloader
~~~

在 register.lua 中注册 FModuleReloader。

Run: npm test

Expected: 三个模块重载用例通过；全量 0 failed。

### Task 8: 编排页面状态快照、销毁和重建

**Files:**
- Create: FLuaFramework/Shared/HotReload/FHotReload.lua
- Create: Tests/Integration/FHotReloadSpec.lua
- Modify: FLuaFramework/Shared/Core/FBasePresenter.lua
- Modify: FLuaFramework/Shared/Core/FUIRouter.lua
- Modify: Tests/Unit/FUIRouterSpec.lua
- Modify: init.lua
- Modify: FLuaFramework/register.lua
- Modify: Tests/run.lua

- [ ] **Step 1: 给 Router 增加不触发导航动作的纯 Lua 快照**

在 Tests/Unit/FUIRouterSpec.lua 追加：

~~~lua
FTestHelper:test("router state snapshot is isolated and restorable", function()
    local manager = make_manager()
    local router = FUIRouter:new(manager)
    router:reset("Home")
    router:push("Detail")
    local snapshot = router:capture_state()
    snapshot[1].page = "Changed"
    FTestHelper:assert_equal("Home", router:get_stack()[1].page)
    router:restore_state({
        { page = "Home", restore_previous = false },
        { page = "Detail", restore_previous = true },
    })
    FTestHelper:assert_equal("Detail", router:current())
end)
~~~

在 FUIRouter.lua 的 return 前加入：

~~~lua
local function copy_stack(stack)
    local result = {}
    for index, entry in ipairs(stack) do
        result[index] = {
            page = entry.page,
            restore_previous = entry.restore_previous == true,
        }
    end
    return result
end

function FUIRouter:capture_state()
    return copy_stack(self.stack)
end

function FUIRouter:restore_state(state)
    if type(state) ~= "table" then
        error(FError:new(
            "INVALID_ROUTE_STATE",
            "route state must be a table",
            {}
        ), 0)
    end
    self.stack = copy_stack(state)
end
~~~

Run: npm test

Expected: Router 快照用例通过，修改返回快照不会影响当前栈。

- [ ] **Step 2: 给 Presenter 定义可选且安全的状态迁移钩子**

在 FBasePresenter.lua 的 on_destroy 前加入：

~~~lua
function FBasePresenter:on_before_reload()
    return nil
end

function FBasePresenter:on_after_reload(state)
    self.reload_state = state
end
~~~

默认实现不复制 View 或原生对象，只允许业务 Presenter 返回纯 Lua 数据。

- [ ] **Step 3: 写热重载成功、隐藏状态恢复和失败不关闭页面测试**

创建 Tests/Integration/FHotReloadSpec.lua：

~~~lua
local FTestHelper = require("Tests.TestHelper")
local FFakePlatformBridge = require("Tests.Fixtures.FFakePlatformBridge")

local function make_context()
    local fake = FFakePlatformBridge:new("unreal")
    local loaded = {}
    local version = 1
    local function presenter_class()
        local Presenter = FClass("ReloadPresenter" .. tostring(version), FBasePresenter)
        function Presenter:on_before_reload()
            return { account = "alice", version = version }
        end
        function Presenter:on_after_reload(state)
            self.restored = state
        end
        return Presenter
    end
    loaded["Game.LoginPresenter"] = presenter_class()

    local manager = FUIManager:new({
        runtime = FUnrealRuntime:new(fake:as_unreal()),
        pages = {
            LoginPanel = {
                presenter = "Game.LoginPresenter",
                singleton = true,
                layer = "Normal",
                inputMode = "UIOnly",
                assets = FUIBindings.LoginPanel.assets,
                requiredBindings = FUIBindings.LoginPanel.requiredBindings,
                nativeBindings = FUIBindings.LoginPanel.nativeBindings,
                hotReloadModules = { "Game.LoginPresenter" },
            },
        },
        layers = {
            Normal = { order = 100, blocksInput = false },
        },
        require_module = function(name) return loaded[name] end,
    })
    local reloader = FModuleReloader:new({
        loaded = loaded,
        load = function(name)
            loaded[name] = presenter_class()
            return loaded[name]
        end,
        is_allowed = function(name)
            return string.sub(name, 1, 5) == "Game."
        end,
    })
    return {
        manager = manager,
        fake = fake,
        reloader = reloader,
        set_version = function(value) version = value end,
    }
end

FTestHelper:test("hot reload rebuilds affected page and restores pure Lua state", function()
    local context = make_context()
    context.manager:open("LoginPanel", { source = "boot" })
    context.fake:complete_next()
    local old_instance = context.manager:get("LoginPanel")
    context.set_version(2)
    local result = FHotReload:new({
        manager = context.manager,
        reloader = context.reloader,
    }):reload({ "Game.LoginPresenter" })
    FTestHelper:assert_true(result.ok)
    context.fake:complete_next()
    local new_instance = context.manager:get("LoginPanel")
    FTestHelper:assert_true(new_instance.id ~= old_instance.id)
    FTestHelper:assert_equal("alice", new_instance.presenter.restored.account)
    FTestHelper:assert_equal(1, new_instance.presenter.restored.version)
end)

FTestHelper:test("hot reload restores hidden pages as hidden", function()
    local context = make_context()
    context.manager:open("LoginPanel")
    context.fake:complete_next()
    context.manager:hide("LoginPanel")
    context.set_version(2)
    FHotReload:new({
        manager = context.manager,
        reloader = context.reloader,
    }):reload({ "Game.LoginPresenter" })
    context.fake:complete_next()
    FTestHelper:assert_equal(
        "Hidden",
        context.manager:get("LoginPanel").lifecycle:get_state()
    )
end)

FTestHelper:test("failed module reload keeps current page alive", function()
    local context = make_context()
    context.manager:open("LoginPanel")
    context.fake:complete_next()
    local current = context.manager:get("LoginPanel")
    context.reloader.load = function() error("syntax error") end
    local result = FHotReload:new({
        manager = context.manager,
        reloader = context.reloader,
    }):reload({ "Game.LoginPresenter" })
    FTestHelper:assert_false(result.ok)
    FTestHelper:assert_equal(current, context.manager:get("LoginPanel"))
end)
~~~

把文件加入 Tests/run.lua。

Run: npm test

Expected: FAIL，缺少 FHotReload 全局。

- [ ] **Step 4: 实现受影响页面判定和重建编排**

创建 FLuaFramework/Shared/HotReload/FHotReload.lua：

~~~lua
local FHotReload = FClass("FHotReload")

local function contains(values, expected)
    for _, value in ipairs(values or {}) do
        if value == expected then return true end
    end
    return false
end

function FHotReload:ctor(options)
    self.manager = options.manager
    self.reloader = options.reloader
    self.navigation = options.navigation
end

function FHotReload:_affected_pages(module_names)
    local affected = {}
    for page, definition in pairs(self.manager.pages) do
        for _, module_name in ipairs(module_names) do
            if contains(definition.hotReloadModules, module_name) then
                table.insert(affected, page)
                break
            end
        end
    end
    table.sort(affected)
    return affected
end

function FHotReload:reload(module_names)
    local snapshots = {}
    for _, page in ipairs(self:_affected_pages(module_names)) do
        local instance = self.manager:get(page)
        if instance ~= nil and instance.presenter ~= nil then
            table.insert(snapshots, {
                page = page,
                params = instance.params,
                hidden = instance.lifecycle:get_state() == "Hidden",
                state = instance.presenter:on_before_reload(),
            })
        end
    end

    local navigation_state = nil
    if self.navigation ~= nil then
        navigation_state = self.navigation:capture_state()
    end

    local reload_result = self.reloader:reload(module_names)
    if not reload_result.ok then
        self.manager.diagnostics:emit("hot_reload_failed", {
            module_count = #module_names,
            error_code = reload_result.error.code,
        })
        return reload_result
    end

    local pending = #snapshots
    local completed = false
    local function finish_if_ready()
        if pending ~= 0 or completed then return end
        completed = true
        if self.navigation ~= nil then
            self.navigation:restore_state(navigation_state)
        end
        self.manager.diagnostics:emit("hot_reload_completed", {
            module_count = #module_names,
            page_count = #snapshots,
        })
    end

    for _, snapshot in ipairs(snapshots) do
        local current = snapshot
        self.manager:close(current.page)
        self.manager:open(current.page, current.params, {
            after_open = function(instance)
                instance.presenter:on_after_reload(current.state)
                if current.hidden then
                    self.manager:hide(current.page)
                end
                pending = pending - 1
                finish_if_ready()
            end,
        })
    end
    self.manager.diagnostics:emit("hot_reload_scheduled", {
        module_count = #module_names,
        page_count = #snapshots,
    })
    finish_if_ready()
    return {
        ok = true,
        pending_pages = #snapshots,
    }
end

return FHotReload
~~~

在 register.lua 中紧跟 FModuleReloader 注册 FHotReload。

- [ ] **Step 5: 在 init.create 中装配宿主模块加载器**

在创建 manager 后加入：

~~~lua
local loader = options.module_loader or {
    loaded = package.loaded,
    load = require,
    is_allowed = function(module_name)
        local framework_prefix = "FLuaFramework."
        local app_prefix = "FLuaFramework.App."
        if string.sub(module_name, 1, #framework_prefix) ~= framework_prefix then
            return true
        end
        return string.sub(module_name, 1, #app_prefix) == app_prefix
    end,
}

manager.hot_reload = registered.FHotReload:new({
    manager = manager,
    reloader = registered.FModuleReloader:new(loader),
    navigation = options.navigation or manager.router,
})
~~~

把原来直接 return registered.FUIManager:new(...) 改为先赋值 local manager，再执行上述装配，最后 return manager。

Run: npm test

Expected: 热重载成功、Hidden 恢复、加载失败保留原页面三个用例通过；全量 0 failed。

### Task 9: 补齐工程入口、CI 门禁和操作文档

**Files:**
- Modify: package.json
- Modify: Tests/check.lua
- Modify: README.md
- Create: docs/engineering/binding-pipeline.md
- Create: docs/engineering/diagnostics.md
- Create: docs/engineering/hot-reload.md

- [ ] **Step 1: 把生成一致性和工具测试加入默认门禁**

把 package.json 的 scripts 完整整理为：

~~~json
{
  "test": "node Tests/check-requires.js && npm run check:bindings && npm run test:tools && fengari Tests/run.lua",
  "test:tools": "node --test Tests/Tools/*.test.js",
  "check:lua": "fengari Tests/check.lua",
  "generate:bindings": "node Tools/Bindings/generate-bindings.js",
  "check:bindings": "node Tools/Bindings/generate-bindings.js --check"
}
~~~

保留 package.json 中 name、version、private 和 devDependencies 的原值，只替换 scripts 对象。

- [ ] **Step 2: 更新 Lua 解析检查入口**

在 Tests/check.lua 中追加：

~~~lua
require("FLuaFramework.Generated.FUIBindings")
require("editor")
~~~

并把最终输出改为：

~~~lua
print(string.format(
    "parsed %d registered framework modules, generated bindings, editor entry, 2 app modules and 2 runtime entry modules",
    registered_count
))
~~~

- [ ] **Step 3: 编写绑定流水线文档**

创建 docs/engineering/binding-pipeline.md，写入：

~~~~markdown
# 绑定生成与编辑器检查

Bindings/*.binding.json 是页面资源地址、逻辑控件 ID、控件类型和平台原生名称的唯一事实源。修改 JSON 后运行：

~~~powershell
npm run generate:bindings
npm run check:bindings
~~~

assets 是运行时加载地址，editorAssets 是编辑器资源路径；Unity 的 Addressables key 与 Assets/...prefab 路径不得混用。生成文件 FLuaFramework/Generated/FUIBindings.lua 必须提交。CI 运行 npm test；生成文件过期时 check:bindings 失败。

Unreal 编辑器桥必须提供：

- inspect_widget_blueprint(asset) -> array
- 每个数组元素为 { name = 原生 Widget 名, type = 框架控件类型 }

Unity 编辑器桥必须提供：

- inspect_prefab(asset) -> array
- 每个数组元素为 { name = 原生 GameObject/Component 绑定名, type = 框架控件类型 }

编辑器调用示例：

~~~lua
local issues = require("editor").check_bindings({
    platform = "unreal",
    bridge = unreal_editor_bridge,
})
~~~

issues 为空才允许提交资源。错误项固定包含 code、page、platform，并按错误类型包含 asset、binding、native_binding、expected、actual 或 count。
~~~~

- [ ] **Step 4: 编写性能与泄漏诊断文档**

创建 docs/engineering/diagnostics.md，写入：

~~~~markdown
# 工程诊断

启动时可通过 diagnostic_sink 接收结构化事件，通过 clock 注入毫秒时钟：

~~~lua
local manager = require("init").create({
    platform = "unity",
    bridge = unity_bridge,
    clock = function() return unity_bridge.realtime_ms() end,
    diagnostic_sink = function(event)
        unity_bridge.report_ui_event(event)
    end,
})
~~~

公共字段为 kind、page、platform、instance_id、lifecycle。性能样本使用 kind=performance_sample，并包含 operation 与 duration_ms。泄漏报告使用 kind=leak_detected，并包含 instance_id、count 和 resources。

开发构建在 page_closed 后出现 leak_detected 应使自动化测试失败；发布构建只上报，不在用户流程中抛错。平台内存、Draw Call 和 UObject/GameObject 数量通过宿主自定义 performance_sample 上报，必须保留原始 metric 名称和 platform。
~~~~

- [ ] **Step 5: 编写受控热重载文档**

创建 docs/engineering/hot-reload.md，写入：

~~~~markdown
# Lua 热重载

支持范围仅包括 FPages.hotReloadModules 显式声明的 Presenter 和纯 Lua 业务模块。Shared、Adapters、Config、register、FClass、生成绑定和原生资源不支持热重载。

宿主文件监听器把有序模块名传给：

~~~lua
local result = manager.hot_reload:reload({
    "Game.UI.Login.LoginViewModel",
    "FLuaFramework.App.UI.Login.LoginPresenter",
})
~~~

依赖模块必须排在 Presenter 前。加载失败时 package.loaded 回滚，当前页面保持存活；加载成功后，受影响 Presenter 先执行 on_before_reload，只返回字符串、数字、布尔值和普通 Lua table，再关闭并销毁页面，重新打开后执行 on_after_reload。Hidden 页面恢复为 Hidden；导航系统通过 init.create 的 navigation.capture_state/restore_state 保持路由。

禁止在快照中保存 View、Widget、UObject、GameObject、委托、UnityEvent、请求句柄、协程或函数。绑定 JSON 或原生资源改变时执行完整页面/资源重建流程，不走 Lua 热重载。
~~~~

- [ ] **Step 6: 更新 README 的工程命令和宿主桥清单**

在 README 的验证代码块中使用：

~~~powershell
npm install
npm run generate:bindings
npm test
npm run check:lua
rg -n "UE\.|UnityEngine\.|CS\." FLuaFramework/Shared FLuaFramework/App
~~~

并增加三个链接：

~~~markdown
- [绑定生成与编辑器检查](docs/engineering/binding-pipeline.md)
- [性能统计与泄漏诊断](docs/engineering/diagnostics.md)
- [Lua 热重载](docs/engineering/hot-reload.md)
~~~

- [ ] **Step 7: 执行阶段四全量验收**

Run: npm test

Expected:

- check-requires 输出 framework require check passed。
- check:bindings 输出 generated bindings are current。
- Node 工具测试全部通过。
- Lua 单元、契约和集成测试全部 PASS，结尾为 0 failed。

Run: npm run check:lua

Expected: 退出码为 0，并显示已解析生成绑定和 editor 入口。

Run: rg -n "UE\.|UnityEngine\.|CS\." FLuaFramework/Shared FLuaFramework/App

Expected: 退出码为 1 且无匹配，表示共享层和业务层没有引擎 API 泄漏。

Run: git diff --check

Expected: 退出码为 0，无尾随空格或冲突标记。

- [ ] **Step 8: 人工核对阶段四验收矩阵**

逐项确认：

- 修改 binding.json 后生成结果确定且 --check 能发现过期文件。
- LoginPresenter 不再散落裸控件 ID，运行时仍通过逻辑 ID 访问控件。
- Unreal/Unity 编辑器对同一契约返回一致的缺失、重复、类型不匹配错误。
- 页面打开产生 page_open 性能样本，关闭、取消和打开失败都释放页面与请求令牌。
- Presenter 的所有 track 订阅在 on_unbind 后没有残留令牌。
- 模块语法错误时旧 package.loaded 和当前页面保持不变。
- 模块成功更新时旧页面销毁、新页面获得新 instance.id，纯 Lua 状态和 Hidden 状态恢复。
- 热重载不允许进入 Shared、Adapters、Config、register 和 FClass 边界。

- [ ] **Step 9: 交由完成分支流程统一提交与集成**

所有任务完成后使用 superpowers:finishing-a-development-branch 重新运行 npm test、npm run check:lua、共享层依赖扫描和 git diff --check，然后选择本地合并、推送 PR、保留分支或丢弃。不要在每个任务中加入零散提交步骤。

## 自检结论

- **规格覆盖：** 编辑器绑定检查、控件 ID/绑定代码生成、性能统计、泄漏诊断和 Lua 热重载均有独立 RED/GREEN 用例及最终门禁。
- **边界清晰：** JSON 是绑定唯一事实源；Editor Inspector 只枚举原生资源；运行时只读取生成 Lua；共享层不引用 UE、CS 或 UnityEngine。
- **生命周期安全：** 页面、异步请求和 Presenter 订阅都通过显式令牌释放；取消、失败和正常关闭均覆盖。
- **热重载安全：** 先事务式加载并允许失败回滚，成功后才销毁页面；恢复对象限制为纯 Lua 数据，不保存原生引用。
- **类型一致：** 全计划统一使用 assets、editorAssets、ids、requiredBindings、nativeBindings、hotReloadModules、instance.id、instance_id、diagnostics、performance、leaks 和 after_open；instance.id 是 Lua 内部字段，instance_id 是结构化事件字段。
- **YAGNI：** 不引入响应式系统、布局生成器、跨引擎内存归一化或任意对象的原地热替换。
