# 多引擎 Lua UI 框架设计

## 1. 背景与目标

本框架面向以下两套运行环境：

- Unreal Engine + UMG + UnLua
- Unity + UGUI + xLua

框架的核心目标是复用 Lua UI 业务逻辑，同时保留 UMG Widget Blueprint 和 UGUI Prefab 各自的原生制作流程。

预期复用的内容包括：

- 页面打开、关闭和返回逻辑
- Presenter、ViewModel 和页面状态
- 表单校验、按钮行为和业务流程
- 页面路由、弹窗管理和分层规则
- 跨页面状态、事件和错误处理

不要求复用的内容包括：

- UMG 与 UGUI 的布局资源
- 引擎特有的材质、动画和渲染能力
- 两个引擎的编辑器工作流

## 2. 核心设计原则

### 2.1 共享行为，不共享原生视图资源

同一个页面分别制作 UMG Widget Blueprint 和 UGUI Prefab，但使用同一组逻辑控件 ID，并由同一个 Lua Presenter 驱动。

### 2.2 依赖倒置

共享 Lua 层只能依赖框架定义的接口，不能直接访问 `UE.*`、`CS.*`、`UnityEngine.*` 或原生控件对象。

### 2.3 小接口优先

框架只抽象业务实际需要的控件能力，不追求完整映射 UMG 和 UGUI 的全部 API。

### 2.4 显式生命周期

页面、事件、异步任务和资源都必须在明确的生命周期节点创建与释放，避免 Lua GC、UE GC 和 C# GC 之间产生悬挂引用。

### 2.5 平台能力允许扩展

跨平台能力走统一接口；引擎独有能力通过可查询的 Capability 扩展，不污染公共接口。

### 2.6 框架脚本命名规范

所有由框架提供的 Lua 模块、模块文件和公开模块表统一使用 `F` 前缀：

```text
FUIManager.lua       → FUIManager
FUIRouter.lua        → FUIRouter
FBasePresenter.lua   → FBasePresenter
FLifecycle.lua       → FLifecycle
FStore.lua           → FStore
FEventBus.lua        → FEventBus
```

`F` 前缀只用于框架代码。具体游戏业务脚本不强制添加该前缀，例如 `LoginPresenter.lua`、`InventoryViewModel.lua`。框架接口采用 `FI` 组合前缀，其中 `F` 表示框架模块、`I` 表示接口，例如 `FIView`、`FIButton` 和 `FIAssetLoader`。

## 3. 总体架构

```text
┌──────────────────────────────────────────────┐
│            Shared Lua Application            │
│ Presenter / ViewModel / FUIManager/FUIRouter │
│ FStore / FEventBus / FCommand / FValidation │
└──────────────────────┬───────────────────────┘
                       │ 仅依赖抽象接口
┌──────────────────────▼───────────────────────┐
│                 UI Contracts                 │
│ Runtime / View / Widget / Asset / Timer      │
│ Logger / Localization / Input / Capability   │
└───────────────┬────────────────┬─────────────┘
                │                │
┌───────────────▼──────┐ ┌───────▼────────────┐
│ Unreal Adapter       │ │ Unity Adapter       │
│ UnLua Runtime Bridge │ │ xLua Runtime Bridge │
│ UMG View Binder      │ │ UGUI View Binder    │
│ UE Asset/Event       │ │ Unity Asset/Event   │
└───────────────┬──────┘ └───────┬────────────┘
                │                │
       UMG Widget BP         UGUI Prefab
```

依赖方向必须保持为：原生视图 → 平台适配层 → 公共接口 → 共享业务层。共享业务层不得反向依赖具体引擎。

## 4. 模块职责

### 4.1 Shared Application

#### FUIManager

负责：

- 创建、打开、隐藏和销毁页面
- 页面实例缓存
- 页面互斥和重复打开策略
- UI 层级管理
- 维护活动页面集合

建议公开以下概念接口：

```lua
FUIManager:open("LoginPanel", params)
FUIManager:close("LoginPanel", result)
FUIManager:get("LoginPanel")
FUIManager:is_open("LoginPanel")
FUIManager:close_layer("Modal")
```

#### FUIRouter

负责页面导航语义，不负责创建原生视图：

- `push`：进入新页面并压入返回栈
- `replace`：替换当前页面
- `back`：返回上一个页面
- `reset`：重置导航栈
- `present`：显示模态页面

#### Presenter

每个页面对应一个共享 Presenter。Presenter：

- 处理用户输入
- 调用游戏业务 Service
- 更新 ViewModel
- 驱动 View 展示状态
- 不直接访问引擎对象

#### ViewModel

保存页面可展示的数据，例如：

```lua
{
    title = "登录",
    account = "",
    password = "",
    isLoading = false,
    errorMessage = nil,
}
```

第一版建议采用显式更新，而不是实现复杂的全自动响应式系统。Presenter 修改状态后，调用明确的 `render` 或局部更新方法，行为更容易调试。

#### FStore 与 FEventBus

- FStore 保存跨页面共享且有明确所有权的数据。
- FEventBus 用于接收业务事件，例如货币变化、断线重连。
- 页面内部事件优先直接调用 Presenter，避免所有交互都绕行全局 FEventBus。

### 4.2 UI Contracts

公共接口建议分为以下几组。

#### 运行时接口

```lua
FIRuntime
FIAssetLoader
FITimer
FILogger
FILocalization
```

#### 视图接口

```lua
FIView
FIText
FIButton
FIImage
FIToggle
FIInput
FIProgress
FIList
FIAnimation
```

概念用法：

```lua
view:set_visible(true)
view:text("title"):set_text("Hello")
view:button("confirm"):on_click(callback)
view:image("avatar"):set_source(assetRef)
view:list("items"):set_items(items, renderer)
view:play_animation("show")
```

接口需要统一：

- 参数含义
- 空值行为
- 返回值
- 事件订阅返回的解绑句柄
- 对已销毁原生对象的处理方式

#### Capability 接口

引擎独有能力不应进入基础控件接口：

```lua
if view:has_capability("background_blur") then
    view:invoke_capability("background_blur", options)
end
```

业务不得依赖 Capability 才能完成页面的核心流程；它应只用于增强表现。

### 4.3 Platform Adapter

Unreal Adapter 负责：

- 将 `UUserWidget` 和 UMG 子控件包装为公共接口
- 将 UE Delegate 转换为统一事件订阅
- 通过软引用或项目约定加载 Widget Blueprint
- 检查 UObject 是否有效
- 在页面销毁时解绑委托并释放 Lua 引用

Unity Adapter 负责：

- 将 `GameObject` 和 UGUI Component 包装为公共接口
- 将 UnityEvent 转换为统一事件订阅
- 通过 Addressables、AssetBundle 或项目约定加载 Prefab
- 检查 Unity Object 的特殊空值语义
- 在页面销毁时移除 Listener 并释放 xLua 引用

适配层对外只返回框架包装对象，不泄漏原生控件。

### 4.4 Native View

同一页面在两个引擎中独立制作：

```text
LoginPanel
├─ Unreal: /Game/UI/Login/WBP_LoginPanel
└─ Unity:  UI/Login/LoginPanel.prefab
```

二者都需要暴露相同的逻辑控件 ID：

```text
title
account_input
password_input
login_button
error_text
loading_indicator
```

控件 ID 是共享 Presenter 与原生资源之间的稳定协议。资源层级、节点名称可以不同，但绑定清单必须一致。

## 5. 页面注册

页面通过注册表声明共享逻辑和平台资源：

```lua
LoginPanel = {
    presenter = "App.UI.Login.LoginPresenter",
    layer = "Normal",
    cachePolicy = "DestroyOnClose",
    inputMode = "UIOnly",
    assets = {
        unreal = "/Game/UI/Login/WBP_LoginPanel",
        unity = "UI/Login/LoginPanel",
    },
}
```

建议支持以下配置：

- `presenter`：共享 Presenter 模块
- `layer`：页面层级
- `cachePolicy`：关闭时销毁、保留或进入对象池
- `singleton`：是否只允许一个实例
- `inputMode`：输入模式
- `assets`：各平台资源标识
- `requiredBindings`：必须存在的控件及类型
- `capabilities`：可选的平台增强能力

## 6. 生命周期设计

推荐页面状态机：

```text
Unloaded
   │ open
   ▼
Loading ──失败──> Unloaded
   │ 创建完成
   ▼
Created
   │ 绑定控件和事件
   ▼
Opened
   │ hide/show
   ▼
Hidden
   │ close
   ▼
Closing
   ├─缓存──> Hidden
   └─销毁──> Destroyed
```

Presenter 生命周期建议为：

```lua
on_create(view, params) -- 只执行一次
on_bind()               -- 注册 UI 和业务事件
on_open(params)         -- 每次打开执行
on_show()
on_hide()
on_close(result)
on_unbind()             -- 对称注销所有事件
on_destroy()            -- 清理最终引用
```

规则：

1. `on_bind` 与 `on_unbind` 必须严格对称。
2. `on_destroy` 后任何 View 调用都应失败并记录明确错误。
3. 异步加载完成时必须检查页面请求是否仍然有效。
4. 页面关闭时取消由页面发起且不再需要的异步任务。
5. Lua 层不能依赖 GC 自动完成事件解绑。

## 7. 打开页面的数据流

```text
业务调用 FUIManager:open
          │
          ▼
查询页面注册信息和打开策略
          │
          ▼
调用平台 AssetLoader 异步加载原生资源
          │
          ▼
平台 Adapter 创建 View 并绑定逻辑控件 ID
          │
          ▼
创建共享 Presenter 和 ViewModel
          │
          ▼
on_create → on_bind → on_open → on_show
          │
          ▼
Presenter 根据 ViewModel 更新 View
```

按钮事件则沿相反方向流动：

```text
原生按钮 → Adapter → FIButton 回调 → Presenter
          → Service/FStore → ViewModel → View
```

## 8. 控件绑定

推荐采用“声明绑定 + 启动校验”，不要在共享层按原生层级路径查找节点。

```lua
local bindings = {
    title = "Text",
    account_input = "Input",
    login_button = "Button",
    error_text = "Text",
}
```

平台 Binder 负责把 ID 映射到实际原生控件。开发环境下，在页面创建阶段检查：

- 缺失的控件
- 重复 ID
- 控件类型不匹配
- 平台资源和共享绑定清单不一致

校验失败时应阻止页面继续打开，并输出页面名、平台、控件 ID、期望类型和实际类型。

## 9. UI 层级与输入

建议第一版固定定义：

```text
Background  背景页面
Normal      普通页面
Popup       非模态弹窗
Modal       模态窗口和遮罩
Guide       新手引导
System      Loading、断线提示等系统界面
Debug       调试界面
```

由各平台 Adapter 把逻辑层映射到：

- Unreal 的 ZOrder、Viewport 容器和输入模式
- Unity Canvas、Sorting Order 和 Raycast 规则

共享层只描述意图，例如是否模态、是否阻挡下层输入、是否响应返回键。

## 10. 列表与对象复用

列表是两个 UI 系统差异较大的区域，应单独抽象 `FIList`，不要让 Presenter 操作具体 Item Widget。

首版建议提供：

```lua
list:set_items(data)
list:set_renderer(renderer)
list:refresh_item(index)
list:scroll_to(index)
list:on_select(callback)
```

虚拟化、对象池和复用由平台适配层实现。共享 renderer 只接收通用 Item View 和数据：

```lua
function renderer(itemView, itemData, index)
    itemView:text("name"):set_text(itemData.name)
end
```

## 11. 异步与资源管理

资源引用建议使用逻辑 `AssetRef`，避免共享层直接传递 UE 路径或 Unity Object：

```lua
{
    id = "avatar/default",
    type = "texture",
}
```

各平台维护从逻辑资源 ID 到原生资源地址的映射。

每个异步操作返回可取消句柄：

```lua
local request = assetLoader:load(assetRef, callback)
request:cancel()
```

完成回调必须验证：

- 请求未取消
- 页面尚未销毁
- 控件仍然有效
- 本次结果仍对应当前请求版本

这样可以避免快速切页、重复刷新头像等场景中的过期结果覆盖。

## 12. 错误处理与日志

建议定义统一错误码：

- `PAGE_NOT_REGISTERED`
- `ASSET_LOAD_FAILED`
- `BINDING_NOT_FOUND`
- `BINDING_TYPE_MISMATCH`
- `NATIVE_OBJECT_INVALID`
- `DUPLICATE_EVENT_BINDING`
- `INVALID_LIFECYCLE_TRANSITION`
- `CAPABILITY_NOT_SUPPORTED`

日志统一包含：

- 引擎平台
- 页面名和实例 ID
- 生命周期状态
- 控件 ID
- 资源 ID
- Lua 调用栈
- 原生异常摘要

开发环境采用快速失败策略；发布环境可降级为隐藏控件、使用占位资源或关闭异常页面，但必须保留错误上报。

## 13. 热重载边界

第一版只保证共享 Lua Presenter 和纯 Lua 模块能够重载，不承诺在不重建页面实例的情况下替换完整生命周期逻辑。

推荐流程：

1. 保存当前页面路由和必要 ViewModel 状态。
2. 关闭并销毁受影响页面。
3. 重载 Lua 模块。
4. 重新创建页面并恢复允许恢复的状态。

这比原地替换闭包、事件回调和元表更稳定。

## 14. 目录建议

```text
LuaUIFramework/
├─ Shared/
│  ├─ Core/
│  │  ├─ FUIManager.lua
│  │  ├─ FUIRouter.lua
│  │  ├─ FBasePresenter.lua
│  │  └─ FLifecycle.lua
│  ├─ Contracts/
│  │  ├─ FIRuntime.lua
│  │  ├─ FIView.lua
│  │  ├─ FIWidget.lua
│  │  └─ FIAssetLoader.lua
│  ├─ State/
│  │  └─ FStore.lua
│  ├─ Events/
│  │  └─ FEventBus.lua
│  └─ Utils/
│     ├─ FCommand.lua
│     └─ FValidation.lua
├─ Adapters/
│  ├─ Unreal/
│  │  ├─ FUnrealRuntime.lua
│  │  ├─ FUMGViewBinder.lua
│  │  └─ FUEAssetLoader.lua
│  └─ Unity/
│     ├─ FUnityRuntime.lua
│     ├─ FUGUIViewBinder.lua
│     └─ FUnityAssetLoader.lua
├─ App/
│  └─ UI/
│     ├─ Login/
│     └─ Main/
├─ Config/
│  ├─ FPages.lua
│  ├─ FLayers.lua
│  └─ FAssets.lua
└─ Tests/
   ├─ Unit/
   ├─ Contract/
   └─ Integration/
```

建议把框架本体、平台适配和具体游戏页面分开，防止框架逐渐混入项目业务。

## 15. 测试策略

### 15.1 纯 Lua 单元测试

使用 Mock View 验证：

- Presenter 行为
- 页面路由和返回栈
- 生命周期状态机
- 表单校验
- FStore 和 FEventBus
- 异步请求取消

这部分测试不依赖 Unreal 或 Unity，应作为共享逻辑的主要测试层。

### 15.2 Adapter 契约测试

为 Unreal Adapter 和 Unity Adapter 运行同一组契约用例：

- 设置文本后可得到一致结果
- 点击事件只触发一次
- 解绑后不再触发
- 原生对象销毁后调用产生统一错误
- 缺失控件和类型错误产生一致诊断

### 15.3 引擎集成测试

两个引擎分别建立最小 Demo，覆盖：

- 打开和关闭页面
- 重复打开策略
- 路由返回
- 列表复用
- 异步加载期间关闭页面
- 连续创建销毁后无残留事件和对象引用

## 16. 分阶段落地建议

### 阶段一：最小闭环

- Runtime 注入
- 页面注册
- FUIManager
- View、Text、Button、Image 基础接口
- 页面生命周期
- Unreal/Unity 最小 Adapter
- LoginPanel 双引擎示例

### 阶段二：常用能力

- Router 和层级管理
- Input、Toggle、Progress
- 异步资源加载与取消
- 统一错误和日志
- Mock View 单元测试

### 阶段三：复杂组件

- 虚拟列表和对象池
- 动画接口
- 本地化
- 页面状态恢复
- Adapter 契约测试工具

### 阶段四：工程化增强

- 编辑器绑定检查
- 控件 ID 或绑定代码生成
- 性能统计和泄漏诊断
- Lua 热重载工作流

## 17. 首版明确不做

为控制复杂度，第一版不建议实现：

- 用一份 Lua DSL 自动生成 UMG 和 UGUI 布局
- 完整响应式 UI 或虚拟 DOM
- 对 UMG/UGUI 全部 API 的一一映射
- 跨引擎统一动画时间线编辑器
- 任意存活页面的无损原地热重载
- 自动把 Widget Blueprint 转换为 Prefab，或反向转换

## 18. 验收标准

首个可用版本应满足：

1. 同一个 `LoginPresenter.lua` 能驱动 UMG 和 UGUI 两份登录界面。
2. 共享 Lua 目录中不存在 Unreal 或 Unity API 调用。
3. 两个平台使用同一套页面打开、关闭和路由语义。
4. 页面关闭后不再收到 UI 或业务事件。
5. 页面异步加载期间被关闭，不会产生幽灵页面或访问已销毁对象。
6. 控件缺失或类型错误能在开发环境给出清晰诊断。
7. 核心 Presenter 和生命周期可以在无引擎环境中完成单元测试。

## 19. 关键结论

本框架应定位为“跨引擎 Lua UI 业务框架”，而不是“跨引擎 UI 渲染系统”。

最稳定的复用边界是：

- 复用 Lua Presenter、ViewModel、路由、状态和业务行为。
- 通过 UI Contracts 隔离引擎差异。
- 分别使用 UMG 和 UGUI 制作原生表现资源。
- 由 Unreal/Unity Adapter 处理绑定、事件、资源和对象生命周期。

这种设计能获得较高的业务代码复用率，同时避免丢失两套引擎原生 UI 工具链的优势。
