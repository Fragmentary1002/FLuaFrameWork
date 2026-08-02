# FLuaFramework 启动入口设计

## 目标

为仓库增加可由 UnLua 或 xLua 宿主调用的统一启动入口。入口负责加载现有框架注册表、按平台组装 Runtime 与 `FUIManager`，并自动打开 `LoginPanel`。入口不直接访问 Unreal、Unity 或 C# API，原生能力继续由宿主通过 bridge 注入。

## 文件与职责

### 根目录 `init.lua`

`init.lua` 是框架装配入口，公开 `create(options)`：

1. 首先加载 `FLuaFramework.register`，取得已注册的核心模块。
2. 加载 `FLuaFramework.Config.FPages` 页面配置。
3. 根据 `options.platform` 选择 `FUnrealRuntime` 或 `FUnityRuntime`。
4. 使用 `options.bridge` 创建 Runtime。
5. 使用 Runtime、页面配置和 `options.services` 创建并返回 `FUIManager`。

该模块只负责装配，不主动打开页面，也不保存全局 Manager 单例。

### 根目录 `main.lua`

`main.lua` 是宿主启动入口，公开 `start(options)`：

1. 调用 `init.create(options)` 创建 Manager。
2. 调用 `manager:open("LoginPanel", options.params)` 自动打开登录页。
3. 返回 Manager，供宿主继续调用 `open`、`close`、`get` 等接口。

入口的预期用法：

```lua
local main = require("main")

local manager = main.start({
    platform = "unreal", -- 或 "unity"
    bridge = platform_bridge,
    services = services,
    params = { account = "alice" },
})
```

## Register 集成

使用现有 `FLuaFramework/register.lua`，不创建第二个注册文件，也不修改其全局注册语义。`init.lua` 必须先加载 Register，再使用其返回表中的 `FUIManager`、`FUnrealRuntime` 和 `FUnityRuntime`。

`init.lua` 与 `main.lua` 位于仓库根目录，因此不会违反 `Tests/check-requires.js` 中“`FLuaFramework` 目录内只有 `register.lua` 可以加载框架依赖”的约束。

## 输入与错误处理

`init.create(options)` 和 `main.start(options)` 使用同一组选项：

- `platform`：必填，允许 `"unreal"` 或 `"unity"`。
- `bridge`：必填，由宿主提供的平台桥接对象。
- `services`：可选，传给 Presenter 的业务服务表；省略时使用空表。
- `params`：可选，仅由 `main.start` 传给 `LoginPanel`。

缺少 options、缺少 bridge 或 platform 非法时，入口使用 Register 提供的 `FError` 立即抛出结构化错误。错误分别使用 `INVALID_ARGUMENT` 和 `UNSUPPORTED_PLATFORM`，并在 context 中包含相关字段。页面加载、控件绑定与生命周期错误继续由现有 Runtime 和 `FUIManager` 处理。

## 状态与生命周期

每次调用 `init.create` 或 `main.start` 都创建独立 Manager，不引入入口级单例。这样可保持测试隔离，也允许宿主在编辑器重载或不同 Lua 环境中自行管理实例生命周期。

`main.start` 返回时，`LoginPanel` 可能仍处于 `Loading`，因为原生资源加载由 bridge 决定是否异步完成。入口不等待加载完成，也不改变现有取消和迟到回调处理。

## 测试策略

采用 TDD 增加入口测试：

- `init.create` 为 Unreal 创建带 `FUnrealRuntime` 的 Manager。
- `init.create` 为 Unity 创建带 `FUnityRuntime` 的 Manager。
- `init.create` 拒绝缺失 bridge 和不支持的平台。
- `main.start` 自动请求打开 `LoginPanel`、传递 params，并返回 Manager。
- 将入口测试加入 `Tests/run.lua`。
- 将 `init` 和 `main` 加入 `Tests/check.lua` 的模块解析检查。
- 执行 `npm test`、`npm run check:lua` 和共享层引擎 API 扫描作为最终验证。

## 非目标

- 不实现 Unreal 或 Unity 的具体 bridge。
- 不创建全局 Manager 单例。
- 不增加页面路由、命令行参数或环境自动探测。
- 不修改现有 Register 的模块清单和全局变量行为。
