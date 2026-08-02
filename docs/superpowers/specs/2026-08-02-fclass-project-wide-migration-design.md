# FClass 全项目迁移设计

## 目标

将生产代码和测试 Fixture 中所有手写 `__index` / `new` 类模式迁移到 `LuaUIFramework.Shared.Core.FClass`。迁移后，项目内部统一使用 `Type:new(...)`，不兼容 `Type.new(...)`，并保持现有 UI、状态、事件、Runtime Adapter 和错误行为不变。

## 迁移范围

以下 17 个类全部迁移：

1. `FError`
2. `FBasePresenter`
3. `FLifecycle`
4. `FUIManager`
5. `FEventBus`
6. `FStore`
7. `FCommand`
8. `FValidation`
9. `FIWidget`
10. `FIText`
11. `FIButton`
12. `FIImage`
13. `FIView`
14. `FUnrealRuntime`
15. `FUnityRuntime`
16. `LoginPresenter`
17. `FFakePlatformBridge`

同时迁移 `LuaUIFramework` 和 `Tests` 内所有对应构造调用，并更新 README 的公共 Runtime 示例。

以下内容不属于类迁移范围：

- `FClass.lua` 为实现类系统而使用的 metatable、`__index` 和 `class_methods:new`。
- EventBus、Store、Button 返回的订阅句柄。这些是具有单个闭包行为的临时句柄，不承担类继承或实例身份。
- 页面配置、绑定描述、桥接操作表和其他纯数据 table。
- 已提交的历史设计与实施计划文档；它们保留当时的 API 记录。

## FClass 必要增强

### 解除 FError 循环依赖

`FError` 迁移后需要加载 `FClass`，而 `FClass` 当前在模块顶层加载 `FError`。为避免 `FError → FClass → FError`，`FClass.raise` 改为在真正产生类系统错误时延迟 `require("LuaUIFramework.Shared.Core.FError")`，并使用 `FError:new(...)` 创建错误。

正常定义 `FError = Class("FError")` 不会进入错误路径，因此模块初始化能够完成。类名、父类或类型参数非法时，`FError` 此时已经可由 Lua 模块系统正常加载。

### 支持 `__tostring`

共享实例 metatable 新增 `__tostring` 分发：沿实际类到父类查找用户定义的 `__tostring`，找到函数时调用；未定义时返回 `<ClassName>`。该能力仅覆盖本次迁移需要的字符串表示，不扩展算术、比较或调用等其他元方法。

`FError:__tostring()` 保持输出 `[CODE] message`。

### 允许类方法覆写默认对象方法

存活实例的方法解析顺序调整为：

1. 当前类到父类的用户成员；
2. `FClass` 提供的 `destroy`、`is_destroyed`、`is_a`、`get_class`、`get_class_name`；
3. `nil`。

这样 `FIView:destroy()` 可保持原有的原生 View 销毁语义。实例进入 FClass 销毁状态后，安全类型查询和幂等 `destroy()` 仍由框架默认方法处理，其他成员访问继续抛出 `OBJECT_DESTROYED`。

## 类定义与构造迁移

所有根类使用：

```lua
local Class = require("LuaUIFramework.Shared.Core.FClass")
local FStore = Class("FStore")

function FStore:ctor(initial_values)
    -- 初始化实例字段
end
```

所有子类使用：

```lua
local Class = require("LuaUIFramework.Shared.Core.FClass")
local FIWidget = require("LuaUIFramework.Shared.Contracts.FIWidget")
local FIText = Class("FIText", FIWidget)
```

`FIText`、`FIButton`、`FIImage` 不再重复定义构造函数，直接使用 `FIWidget:ctor(id, native, ops)`。`LoginPresenter:ctor(services)` 在自动执行 `FBasePresenter:ctor()` 后只保存 services，删除 `FBasePresenter.initialize`。

其余原 `new` 初始化逻辑逐字迁移到 `ctor`，不改变默认值、复制行为或依赖注入方式。

## 调用点迁移

生产代码和测试统一将：

```lua
FStore.new(values)
FError.new(code, message, context)
presenter_module.new(services)
```

替换为：

```lua
FStore:new(values)
FError:new(code, message, context)
presenter_module:new(services)
```

`FViewBinder` 不保存未绑定的 `FIText.new` 等函数，而使用闭包明确调用：

```lua
local factories = {
    Text = function(...) return FIText:new(...) end,
    Button = function(...) return FIButton:new(...) end,
    Image = function(...) return FIImage:new(...) end,
}
```

Manager 测试中的 `FakePresenter` 也通过 `Class("FakePresenter")` 和 `ctor(events)` 创建，避免测试继续维护另一套类写法。

## 行为保持

- `FError` 字段和 `tostring` 输出不变。
- EventBus 与 Store 的订阅、通知和幂等取消行为不变。
- Command 与 Validation 的返回值和闭包行为不变。
- View/Text/Button/Image 的类型安全访问和原生失效错误不变。
- Unreal/Unity Runtime 的桥接 API 不变，仅构造调用改为冒号。
- Presenter 生命周期顺序、订阅释放和登录行为不变。
- FUIManager 的异步请求版本、迟到结果清理和关闭行为不变。

## 测试策略

### FClass 增强测试

在 `FClassSpec.lua` 先增加失败测试：

- 类定义的 `__tostring` 能通过实例 metatable 生效。
- 存活实例可用类方法覆写默认 `destroy`，未覆写类仍使用 FClass 幂等销毁。
- 加载已迁移的 `FError` 不产生循环依赖，非法 Class 输入仍返回结构化 `FError`。

### 迁移回归

- 将现有测试的构造调用全部改为冒号形式。
- `Tests/run.lua` 注册 `FClassSpec.lua`，全量测试由 32 项增加到 42 项（现有 32 项、原 FClass 7 项、新增增强 3 项）。
- `Tests/check.lua` 注册 `FClass`，解析模块数量由 18 增加到 19。
- README 中 `FUnrealRuntime.new`、`FUnityRuntime.new` 改为冒号形式。

### 静态迁移验收

对生产代码和测试运行扫描：

```powershell
rg -n "function\s+[A-Za-z0-9_\.]+\.new|[A-Za-z0-9_\.]+\.new\(" LuaUIFramework Tests
rg -n "__index\s*=" LuaUIFramework Tests -g "*.lua" -g "!LuaUIFramework/Shared/Core/FClass.lua"
```

两条命令都应无匹配。`FClass.lua` 内部保留类系统所必需的 metatable 实现。

## 文件改动

- Modify: `LuaUIFramework/Shared/Core/FClass.lua`
- Modify: 上述 16 个生产类模块
- Modify: `LuaUIFramework/Adapters/Common/FViewBinder.lua`
- Modify: `Tests/Fixtures/FFakePlatformBridge.lua`
- Modify: 所有使用旧点调用构造函数的现有测试
- Modify: `Tests/Unit/FClassSpec.lua`
- Modify: `Tests/run.lua`
- Modify: `Tests/check.lua`
- Modify: `README.md`

不创建兼容包装器，不保留任何手写类例外，也不改变历史设计/计划文档。
