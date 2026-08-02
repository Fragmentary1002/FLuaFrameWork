# FLuaFramework 启动入口 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 增加根目录 `init.lua` 与 `main.lua`，通过现有 Register 组装双引擎 UI Manager，并在正式启动时自动打开 `LoginPanel`。

**Architecture:** `init.lua` 是无状态工厂，先加载 `FLuaFramework.register`，再按 `platform` 选择已注册 Runtime 并创建 `FUIManager`。`main.lua` 只负责调用工厂、打开登录页并返回 Manager；原生能力始终由宿主 bridge 注入。

**Tech Stack:** Lua、Fengari、现有 `FClass`/`FError`/`FUIManager`、自定义 Lua 测试工具、Node.js require 边界检查。

---

## 文件结构

- Create: `init.lua` — 校验启动参数并组装 Runtime、页面注册表和 Manager。
- Create: `main.lua` — 调用初始化工厂并自动打开 `LoginPanel`。
- Create: `Tests/Unit/FInitSpec.lua` — 验证双平台装配和结构化输入错误。
- Create: `Tests/Integration/FMainSpec.lua` — 验证启动入口打开登录页并透传参数。
- Modify: `Tests/run.lua` — 注册两个新测试文件。
- Modify: `Tests/check.lua` — 将两个入口加入模块解析检查。
- Modify: `README.md` — 把宿主启动示例更新为正式入口 API。

### Task 1: `init.lua` 装配工厂

**Files:**
- Create: `Tests/Unit/FInitSpec.lua`
- Modify: `Tests/run.lua`
- Create: `init.lua`

- [ ] **Step 1: 写入失败测试并注册测试文件**

在 `Tests/Unit/FInitSpec.lua` 写入：

```lua
local FTestHelper = require("Tests.TestHelper")
local FFakePlatformBridge = require("Tests.Fixtures.FFakePlatformBridge")
local init = require("init")

local cases = {
    { platform = "unreal", bridge = "as_unreal", runtime = FUnrealRuntime },
    { platform = "unity", bridge = "as_unity", runtime = FUnityRuntime },
}

for _, case in ipairs(cases) do
    FTestHelper:test("init creates a manager for " .. case.platform, function()
        local fake = FFakePlatformBridge:new(case.platform)
        local services = {}
        local manager = init.create({
            platform = case.platform,
            bridge = fake[case.bridge](fake),
            services = services,
        })

        FTestHelper:assert_true(case.runtime:is_instance(manager.runtime))
        FTestHelper:assert_equal(case.platform, manager.runtime.platform)
        FTestHelper:assert_equal(services, manager.services)
        FTestHelper:assert_not_nil(manager.pages.LoginPanel)
    end)
end

FTestHelper:test("init rejects missing options", function()
    FTestHelper:assert_error_code("INVALID_ARGUMENT", function()
        init.create()
    end)
end)

FTestHelper:test("init rejects a missing bridge", function()
    FTestHelper:assert_error_code("INVALID_ARGUMENT", function()
        init.create({ platform = "unreal" })
    end)
end)

FTestHelper:test("init rejects a missing platform", function()
    FTestHelper:assert_error_code("INVALID_ARGUMENT", function()
        init.create({ bridge = {} })
    end)
end)

FTestHelper:test("init rejects an unsupported platform", function()
    FTestHelper:assert_error_code("UNSUPPORTED_PLATFORM", function()
        init.create({ platform = "unknown", bridge = {} })
    end)
end)
```

在 `Tests/run.lua` 的 unit specs 中加入：

```lua
"Tests/Unit/FInitSpec.lua",
```

- [ ] **Step 2: 运行测试并确认因缺少入口模块而失败**

Run: `npm test`

Expected: FAIL，错误包含找不到模块 `init`；失败原因必须是生产入口尚未实现，而不是测试语法错误。

- [ ] **Step 3: 写入最小 `init.lua` 实现**

```lua
local registered = require("FLuaFramework.register")
local pages = require("FLuaFramework.Config.FPages")

local init = {}

local runtimes = {
    unreal = registered.FUnrealRuntime,
    unity = registered.FUnityRuntime,
}

local function raise(code, message, context)
    error(registered.FError:new(code, message, context), 0)
end

function init.create(options)
    if type(options) ~= "table" then
        raise("INVALID_ARGUMENT", "options must be a table", { argument = "options" })
    end
    if options.bridge == nil then
        raise("INVALID_ARGUMENT", "bridge is required", { argument = "bridge" })
    end
    if options.platform == nil then
        raise("INVALID_ARGUMENT", "platform is required", { argument = "platform" })
    end

    local runtime_class = runtimes[options.platform]
    if runtime_class == nil then
        raise("UNSUPPORTED_PLATFORM", "platform is not supported", {
            platform = options.platform,
        })
    end

    return registered.FUIManager:new({
        runtime = runtime_class:new(options.bridge),
        pages = pages,
        services = options.services or {},
    })
end

return init
```

- [ ] **Step 4: 运行测试并确认装配行为通过**

Run: `npm test`

Expected: PASS，新增 6 项测试通过，既有测试无回归。

### Task 2: `main.lua` 自动启动入口

**Files:**
- Create: `Tests/Integration/FMainSpec.lua`
- Modify: `Tests/run.lua`
- Create: `main.lua`

- [ ] **Step 1: 写入失败测试并注册测试文件**

在 `Tests/Integration/FMainSpec.lua` 写入：

```lua
local FTestHelper = require("Tests.TestHelper")
local FFakePlatformBridge = require("Tests.Fixtures.FFakePlatformBridge")
local main = require("main")

FTestHelper:test("main starts and opens LoginPanel", function()
    local fake = FFakePlatformBridge:new("unreal")
    local params = { account = "alice", avatar = "avatar/alice" }
    local manager = main.start({
        platform = "unreal",
        bridge = fake:as_unreal(),
        services = {},
        params = params,
    })

    local instance = manager:get("LoginPanel")
    FTestHelper:assert_not_nil(instance)
    FTestHelper:assert_equal("Loading", instance.lifecycle:get_state())
    FTestHelper:assert_equal(params, instance.params)
    FTestHelper:assert_equal("/Game/UI/Login/WBP_LoginPanel", fake.pending[1].asset)
end)
```

在 `Tests/run.lua` 的 integration specs 中加入：

```lua
"Tests/Integration/FMainSpec.lua",
```

- [ ] **Step 2: 运行测试并确认因缺少启动模块而失败**

Run: `npm test`

Expected: FAIL，错误包含找不到模块 `main`。

- [ ] **Step 3: 写入最小 `main.lua` 实现**

```lua
local init = require("init")

local main = {}

function main.start(options)
    local manager = init.create(options)
    manager:open("LoginPanel", options.params)
    return manager
end

return main
```

- [ ] **Step 4: 运行测试并确认自动启动行为通过**

Run: `npm test`

Expected: PASS，自动打开测试通过，全部既有测试无回归。

### Task 3: 解析检查与使用文档

**Files:**
- Modify: `Tests/check.lua`
- Modify: `README.md`

- [ ] **Step 1: 扩展模块解析检查**

在 `Tests/check.lua` 加载 Register 和 App 模块后加入：

```lua
require("init")
require("main")
```

并将输出改为：

```lua
print(string.format("parsed %d registered framework modules, 2 app modules and 2 entry modules", registered_count))
```

- [ ] **Step 2: 更新 README 启动示例**

把仅加载 Register 的启动片段替换为：

```lua
local main = require("main")

local manager = main.start({
    platform = "unreal", -- 或 "unity"
    bridge = platform_bridge,
    services = services,
    params = { account = "alice" },
})
```

说明 `init.lua` 会先加载 Register、`main.start` 会自动打开 `LoginPanel`，并保留 bridge 契约章节。

- [ ] **Step 3: 运行完整验证**

Run: `npm test`

Expected: PASS，0 failed。

Run: `npm run check:lua`

Expected: PASS，输出包含 `2 entry modules`。

Run: `rg -n "UE\.|UnityEngine\.|CS\." FLuaFramework/Shared FLuaFramework/App init.lua main.lua`

Expected: 无匹配，命令因无匹配返回退出码 1。

Run: `git diff --check`

Expected: 无输出，退出码 0。

- [ ] **Step 4: 完成安全本地提交**

使用 `superpowers:verification-before-completion` 复核完整验证输出，再使用 `git-commit-workflow` 检查冲突、只暂存本计划相关文件，并创建中文 Conventional Commit：

```text
feat: 添加框架统一启动入口
```

不推送远端，不创建或切换分支。
