# 全局 Register Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增唯一的 `LuaUIFramework.register` 启动入口，将通用框架模块注册为全局变量，并移除其他框架文件中的 `require`。

**Architecture:** `register.lua` 按依赖顺序立即加载通用模块，每加载一个模块就同时写入返回表和 `_G`，从而让后续模块在执行阶段直接使用已注册的全局依赖。业务 Presenter 与页面配置不进入注册表，但由宿主在 Register 完成后按现有流程动态加载。

**Tech Stack:** Lua 5.3 语义、Fengari、PowerShell、npm scripts、项目自带轻量测试框架

---

## 文件结构

- Create: `LuaUIFramework/register.lua` — 唯一的通用框架 `require` 汇总入口，负责加载顺序、全局赋值和返回注册表。
- Create: `Tests/Unit/FRegisterSpec.lua` — 验证注册结果和重复加载。
- Create: `Tests/check-requires.js` — 递归检查 Register 之外的生产 Lua 文件不存在静态 `require(...)`。
- Modify: `package.json` — 将静态依赖检查接入 `npm test`。
- Modify: `Tests/run.lua` — 在所有 Spec 前启动 Register，并纳入 Register 测试。
- Modify: `Tests/check.lua` — 通过 Register 解析通用框架，只单独加载业务 Presenter 和配置。
- Modify: `LuaUIFramework/Shared/**/*.lua` — 删除局部依赖加载，改用 `FClass`、`FError` 等全局变量。
- Modify: `LuaUIFramework/Adapters/**/*.lua` — 删除局部依赖加载，改用全局框架类型。
- Modify: `LuaUIFramework/App/UI/Login/LoginPresenter.lua` — 删除框架依赖加载，保留业务模块返回值。
- Modify: `Tests/Unit/FClassSpec.lua` — 更新循环依赖测试名称，使其描述注册后的 `FError` 来源。
- Modify: `README.md` — 记录宿主必须先加载 Register 的启动契约。

### Task 1: 建立 Register 的可观察行为

**Files:**
- Create: `Tests/Unit/FRegisterSpec.lua`
- Modify: `Tests/run.lua`
- Create: `LuaUIFramework/register.lua`

- [ ] **Step 1: 编写缺少 Register 时会失败的测试**

创建 `Tests/Unit/FRegisterSpec.lua`，先只描述注册行为：

```lua
local FTestHelper = require("Tests.TestHelper")

FTestHelper:test("register exposes every framework module as a global", function()
    local registered = require("LuaUIFramework.register")
    local expected_names = {
        "FClass", "FError", "FBasePresenter", "FLifecycle", "FUIManager",
        "FIWidget", "FIText", "FIButton", "FIImage", "FIView",
        "FEventBus", "FStore", "FCommand", "FValidation", "FViewBinder",
        "FUnrealRuntime", "FUnityRuntime",
    }

    for _, name in ipairs(expected_names) do
        FTestHelper:assert_not_nil(registered[name])
        FTestHelper:assert_equal(registered[name], _G[name])
    end
end)

FTestHelper:test("register returns the same table when required twice", function()
    local first = require("LuaUIFramework.register")
    local second = require("LuaUIFramework.register")
    FTestHelper:assert_equal(first, second)
end)
```

将 `"Tests/Unit/FRegisterSpec.lua"` 加到 `Tests/run.lua` 的 `specs` 第一项；此时不要在 runner 顶部预加载 Register，确保测试能捕获模块缺失。

- [ ] **Step 2: 运行测试并确认按预期失败**

Run: `npm test`

Expected: `register exposes every framework module as a global` 失败，错误包含找不到 `LuaUIFramework.register`；现有用例继续执行。

- [ ] **Step 3: 写入最小 Register 实现**

创建 `LuaUIFramework/register.lua`：

```lua
local registered = {}

local function register(name, module_name)
    local module = require(module_name)
    registered[name] = module
    _G[name] = module
end

register("FClass", "LuaUIFramework.Shared.Core.FClass")
register("FError", "LuaUIFramework.Shared.Core.FError")
register("FBasePresenter", "LuaUIFramework.Shared.Core.FBasePresenter")
register("FLifecycle", "LuaUIFramework.Shared.Core.FLifecycle")
register("FIWidget", "LuaUIFramework.Shared.Contracts.FIWidget")
register("FIText", "LuaUIFramework.Shared.Contracts.FIText")
register("FIButton", "LuaUIFramework.Shared.Contracts.FIButton")
register("FIImage", "LuaUIFramework.Shared.Contracts.FIImage")
register("FIView", "LuaUIFramework.Shared.Contracts.FIView")
register("FEventBus", "LuaUIFramework.Shared.Events.FEventBus")
register("FStore", "LuaUIFramework.Shared.State.FStore")
register("FCommand", "LuaUIFramework.Shared.Utils.FCommand")
register("FValidation", "LuaUIFramework.Shared.Utils.FValidation")
register("FViewBinder", "LuaUIFramework.Adapters.Common.FViewBinder")
register("FUIManager", "LuaUIFramework.Shared.Core.FUIManager")
register("FUnrealRuntime", "LuaUIFramework.Adapters.Unreal.FUnrealRuntime")
register("FUnityRuntime", "LuaUIFramework.Adapters.Unity.FUnityRuntime")

return registered
```

- [ ] **Step 4: 运行测试并确认 Register 行为通过**

Run: `npm test`

Expected: 两个 Register 用例均为 `PASS`，完整测试输出为 `44 passed, 0 failed`（当前基线动态展开后为 42 例；如果基线用例数量变化，以新增两例且零失败为准）。

### Task 2: 移除生产模块中的分散 require

**Files:**
- Create: `Tests/check-requires.js`
- Modify: `package.json`
- Modify: `Tests/Unit/FClassSpec.lua`
- Modify: `LuaUIFramework/Shared/Core/FClass.lua`
- Modify: `LuaUIFramework/Shared/Core/FError.lua`
- Modify: `LuaUIFramework/Shared/Core/FBasePresenter.lua`
- Modify: `LuaUIFramework/Shared/Core/FLifecycle.lua`
- Modify: `LuaUIFramework/Shared/Core/FUIManager.lua`
- Modify: `LuaUIFramework/Shared/Contracts/FIWidget.lua`
- Modify: `LuaUIFramework/Shared/Contracts/FIText.lua`
- Modify: `LuaUIFramework/Shared/Contracts/FIButton.lua`
- Modify: `LuaUIFramework/Shared/Contracts/FIImage.lua`
- Modify: `LuaUIFramework/Shared/Contracts/FIView.lua`
- Modify: `LuaUIFramework/Shared/Events/FEventBus.lua`
- Modify: `LuaUIFramework/Shared/State/FStore.lua`
- Modify: `LuaUIFramework/Shared/Utils/FCommand.lua`
- Modify: `LuaUIFramework/Shared/Utils/FValidation.lua`
- Modify: `LuaUIFramework/Adapters/Common/FViewBinder.lua`
- Modify: `LuaUIFramework/Adapters/Unreal/FUnrealRuntime.lua`
- Modify: `LuaUIFramework/Adapters/Unity/FUnityRuntime.lua`
- Modify: `LuaUIFramework/App/UI/Login/LoginPresenter.lua`

- [ ] **Step 1: 增加静态依赖约束测试**

Fengari 不提供 `io.open`，因此创建 `Tests/check-requires.js`，使用项目现有 Node/npm 运行环境递归扫描整个生产目录：

```js
const fs = require("node:fs");
const path = require("node:path");

const frameworkRoot = path.join(process.cwd(), "LuaUIFramework");
const registerPath = path.join(frameworkRoot, "register.lua");
const violations = [];

function visit(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      visit(entryPath);
    } else if (entryPath.endsWith(".lua") && entryPath !== registerPath) {
      const source = fs.readFileSync(entryPath, "utf8");
      if (/\brequire\s*\(/.test(source)) {
        violations.push(path.relative(process.cwd(), entryPath));
      }
    }
  }
}

visit(frameworkRoot);

if (violations.length > 0) {
  console.error("Only LuaUIFramework/register.lua may require framework dependencies:");
  for (const violation of violations) console.error(`- ${violation}`);
  process.exit(1);
}

console.log("framework require check passed");
```

把 `package.json` 的测试命令改为：

```json
"test": "node Tests/check-requires.js && fengari Tests/run.lua"
```

- [ ] **Step 2: 运行测试并确认静态约束失败**

Run: `npm test`

Expected: Node 检查以退出码 1 失败，并列出所有仍包含静态 `require(...)` 的生产文件；Fengari 用例此时不会启动。

- [ ] **Step 3: 删除所有生产模块的局部 require**

对列出的生产模块执行以下机械改造：

```lua
-- Before
local Class = require("LuaUIFramework.Shared.Core.FClass")
local FError = require("LuaUIFramework.Shared.Core.FError")
local FLifecycle = Class("FLifecycle")

-- After
local FLifecycle = FClass("FLifecycle")
```

所有 `Class("...")` 调用替换为 `FClass("...")`。保留模块自身的局部声明和 `return`，例如：

```lua
local FIButton = FClass("FIButton", FIWidget)
```

`FClass.lua` 的 `raise` 不再动态加载 `FError`：

```lua
local function raise(code, message, context)
    error(FError:new(code, message, context or {}), 0)
end
```

将 `Tests/Unit/FClassSpec.lua` 中原来的测试名称
`class validation still raises structured errors through lazy FError loading`
改为：

```lua
FTestHelper:test("class validation raises structured errors through registered FError", function()
```

`LoginPresenter.lua` 改为：

```lua
local LoginPresenter = FClass("LoginPresenter", FBasePresenter)
```

不要向 `_G` 注册 `LoginPresenter` 或 `FPages`。

- [ ] **Step 4: 运行测试并确认迁移通过**

Run: `npm test`

Expected: 输出 `framework require check passed`，两个 Register 用例和所有既有用例均为 `PASS`，零失败。

- [ ] **Step 5: 用独立搜索确认 Register 是唯一框架 require 汇总点**

Run: `rg -n "require\s*\(" LuaUIFramework -g "*.lua"`

Expected: 输出只包含 `LuaUIFramework/register.lua` 中的 `require(module_name)`。`FUIManager` 可以保留 `options.require_module or require` 作为业务 Presenter 的动态加载器，因为它不是通用框架静态依赖声明。

### Task 3: 统一测试与检查入口的启动顺序

**Files:**
- Modify: `Tests/run.lua`
- Modify: `Tests/check.lua`

- [ ] **Step 1: 让测试 runner 在任何 Spec 前加载 Register**

将 `Tests/run.lua` 开头改为：

```lua
require("LuaUIFramework.register")
local FTestHelper = require("Tests.TestHelper")
```

保留 `FRegisterSpec.lua` 为 `specs` 第一项。测试中的显式 `require("LuaUIFramework.register")` 会验证 Lua 缓存返回相同注册表。

- [ ] **Step 2: 让语法检查入口只通过 Register 加载通用模块**

将 `Tests/check.lua` 的通用模块清单替换为：

```lua
local registered = require("LuaUIFramework.register")
require("LuaUIFramework.App.UI.Login.LoginPresenter")
require("LuaUIFramework.Config.FPages")

local registered_count = 0
for _ in pairs(registered) do
    registered_count = registered_count + 1
end

print(string.format("parsed %d registered framework modules and 2 app modules", registered_count))
```

- [ ] **Step 3: 运行测试和 Lua 加载检查**

Run: `npm test`

Expected: 全部用例 `PASS`，零失败。

Run: `npm run check:lua`

Expected: 输出 `parsed 17 registered framework modules and 2 app modules`，进程退出码为 0。

### Task 4: 记录宿主启动契约并完成回归验证

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 在 README 增加启动示例**

在简介和引擎 bridge 说明之间加入：

```markdown
## 启动

宿主必须在加载任何框架或业务模块之前执行：

```lua
require("LuaUIFramework.register")
```

Register 会一次性加载通用框架模块，并注册 `FClass`、`FError`、`FUIManager`、平台 Runtime 等全局变量。其他框架和业务模块依赖这些全局变量，不再自行加载框架依赖。
```

- [ ] **Step 2: 运行完整验证命令**

Run: `npm test`

Expected: 全部用例通过且零失败。

Run: `npm run check:lua`

Expected: 解析 17 个注册模块和 2 个应用模块，退出码为 0。

Run: `rg -n "require\s*\(" LuaUIFramework -g "*.lua"`

Expected: 只有 `LuaUIFramework/register.lua` 命中。

Run: `rg -n "UE\.|UnityEngine\.|CS\." LuaUIFramework/Shared LuaUIFramework/App`

Expected: 无输出，退出码为 1（表示未找到平台 API 泄漏）。

Run: `git diff --check`

Expected: 无输出，退出码为 0。

- [ ] **Step 3: 检查最终差异范围**

Run: `git status --short`

Expected: 只包含本计划列出的 Register、测试入口、生产模块、README、设计说明和计划说明文件，不包含无关改动。

- [ ] **Step 4: 交接最终提交与集成**

使用 `superpowers:finishing-a-development-branch` 完成最终验证，并由用户选择保留未提交改动、创建本地提交或进行后续集成；不要在本任务中添加临时提交步骤。
