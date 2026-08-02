# 全局 Register 设计

## 背景

当前框架模块分别通过 `require` 加载各自依赖，宿主和测试入口也维护了不同的模块加载清单。此次改造增加唯一启动入口，把通用框架模块统一注册为全局变量，并移除其他模块中的 `require`。

## 目标

- 宿主只需在启动阶段执行一次 `require("FLuaFramework.register")`。
- Register 按明确的依赖顺序加载通用框架模块并写入 `_G`。
- 框架模块和示例业务模块不再自行执行 `require`。
- 重复加载 Register 不会重复初始化模块。

## 非目标

- 不增加分层、按需或延迟注册机制。
- 不改变现有模块的公开 API 和业务行为。
- 不把业务 Presenter 或页面配置注册为全局变量。

## 文件与接口

新增 `FLuaFramework/register.lua`。调用方式如下：

```lua
local registered = require("FLuaFramework.register")
```

加载完成后，通用模块同时可以通过全局变量访问：

```lua
local manager = FUIManager:new(options)
local presenter = FBasePresenter:new(services)
```

Register 返回一个只包含本次注册模块引用的普通 Lua 表，便于启动检查和测试。表中的键与全局名称一致。

## 注册范围

Register 注册以下通用框架模块：

- Core：`FClass`、`FError`、`FBasePresenter`、`FLifecycle`、`FUIManager`
- Contracts：`FIWidget`、`FIText`、`FIButton`、`FIImage`、`FIView`
- Events/State/Utils：`FEventBus`、`FStore`、`FCommand`、`FValidation`
- Common Adapter：`FViewBinder`
- Platform Adapter：`FUnrealRuntime`、`FUnityRuntime`

`LoginPresenter` 属于具体业务模块，`FPages` 属于项目配置，两者不会注册为全局变量。它们仍可被业务流程动态加载，但其文件内部不再加载框架依赖。

## 加载顺序

加载顺序必须满足模块在执行阶段使用的全局依赖：

1. `FClass`
2. `FError`
3. 其余 Core 基础模块和 Contracts
4. Events、State、Utils
5. `FViewBinder`
6. `FUIManager`
7. Unreal 与 Unity Runtime

`FClass` 中需要创建 `FError` 的逻辑改为运行时读取全局 `FError`，从而解除当前 `FClass` 与 `FError` 之间的循环 `require`。

## 模块改造规则

- 删除 `FLuaFramework` 下除 `register.lua` 外的全部 `require` 表达式。
- 原来名为 `Class` 的局部依赖统一替换为全局 `FClass`，避免新增含义模糊的 `_G.Class`。
- 其他类型名称保持现有 `F` / `FI` 命名。
- 模块加载前若宿主没有执行 Register，Lua 会在首次使用缺失全局变量时快速失败；这是明确的启动契约，不额外加入隐式兜底加载。

## 重复加载与全局覆盖

Lua 自身的 `package.loaded` 保证普通重复 `require("FLuaFramework.register")` 返回同一个注册表，不会再次执行模块初始化。Register 在首次执行时为约定的框架全局名称赋值。此次不增加热重载或冲突检测策略，以保持入口简单；宿主不得预先用其他值占用这些保留名称。

## 测试与验证

- 新增 Register 单元测试，验证所有约定的全局变量均已注册，返回表与对应全局引用一致。
- 验证重复 `require` 返回同一张注册表。
- 测试运行入口在加载任何 Spec 前先加载 Register。
- Lua 语法检查入口先加载 Register，再加载业务模块和配置。
- 静态检查 `FLuaFramework` 下除 `register.lua` 外不存在 `require`。
- 运行现有完整测试，确认页面、生命周期、适配器和 Presenter 行为没有回归。

## 验收标准

1. `require("FLuaFramework.register")` 后，所有列出的通用框架全局变量可直接使用。
2. `FLuaFramework/register.lua` 是框架唯一的静态 `require` 汇总入口。
3. 所有现有自动化测试通过。
4. 未先加载 Register 时不会发生隐式依赖加载。
