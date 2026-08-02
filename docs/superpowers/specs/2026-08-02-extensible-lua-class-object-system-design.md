# 可扩展 Lua 类与对象机制设计

## 目标

为 FLuaFrameWork 提供一套 Lua 5.3 兼容、可测试、无引擎依赖的单继承类与对象机制。调用方通过 `Class("Dog", Animal)` 定义类，通过 `Dog:new(...)` 创建实例，并获得自动构造链、方法继承、显式父类调用、运行时类型查询和安全析构能力。

本次不引入多继承、Mixin、抽象类、访问控制、属性描述符、运算符重载或对象池。

## 文件边界

- 新增 `LuaUIFramework/Shared/Core/FClass.lua`：唯一生产模块。
- 新增 `Tests/Unit/FClassSpec.lua`：独立单元规格。
- 不修改现有 UI、Runtime Adapter、Presenter、Store、EventBus 或其他业务模块。

## 公共 API

### 定义类与创建对象

```lua
local Class = require("LuaUIFramework.Shared.Core.FClass")

local Animal = Class("Animal")
local Dog = Class("Dog", Animal)

function Animal:ctor(name)
    self.name = name
end

function Dog:ctor(name, breed)
    self.breed = breed
end

local dog = Dog:new("Lucky", "Corgi")
```

类名必须是非空字符串。父类省略时创建根类；提供父类时，父类必须由本模块创建，否则抛出结构化错误。

### 继承、覆写与父类调用

实例方法通过类表查找，类表再通过 metatable 的 `__index` 查找父类，因此父类在子类创建后新增的方法也能被子类实例访问。

子类直接定义同名方法完成覆写。需要调用父类实现时使用明确的类引用：

```lua
function Dog:speak()
    return Dog.super.speak(self) .. " woof"
end
```

`super` 指向直接父类。该设计不依赖调试库或隐式调用栈，行为确定且便于排查。

### 构造顺序

`Class:new(...)` 收集从根类到当前类的继承链，只调用每一级类表自身定义的 `ctor`，并向每一级传入相同参数。父类构造先于子类构造，继承得到的 `ctor` 不会被重复执行。

若任一 `ctor` 抛错，`new` 原样传播错误，不返回半初始化对象。首版不自动调用已完成层级的 `dtor`，避免把“构造失败回滚”与正常对象生命周期混合。

### 类型查询

实例提供：

- `object:is_a(TargetClass)`：当前类等于或继承自目标类时返回 `true`。
- `object:get_class()`：返回实际类表。
- `object:get_class_name()`：返回实际类名。
- `object:is_destroyed()`：返回对象是否已经销毁。

类提供：

- `ClassTable:is_instance(value)`：值是该类或其子类的未销毁/已销毁实例时返回 `true`。
- `ClassTable:is_subclass(TargetClass)`：当前类等于或继承自目标类时返回 `true`。
- `ClassTable:get_name()`：返回类名。

类型查询依赖模块内部元数据，不接受仅具有相同字段的普通 table 作为类或实例。

### 销毁语义

`object:destroy()` 按当前类到根类的顺序，只调用每一级自身定义的 `dtor`。第一次调用开始时即标记对象已销毁，确保析构过程中的递归 `destroy()` 不会重复执行；后续调用直接返回 `false`，首次成功销毁返回 `true`。

销毁后仍允许调用 `destroy()`、`is_destroyed()`、`get_class()`、`get_class_name()` 和 `is_a()` 进行安全检查。访问其他通过类解析的实例方法时抛出 `OBJECT_DESTROYED`。Lua 已存在的原始实例字段仍可被直接读取；首版不使用代理表拦截所有字段访问。

若某一级 `dtor` 抛错，错误原样传播，对象保持已销毁状态，且后续 `destroy()` 不会再次执行任何析构函数。

## 内部结构

每个类表保存模块私有标记、类名和直接父类引用，并暴露只读约定字段 `super`。类表的 metatable 负责静态成员继承。每个实例保存实际类和销毁状态，实例 metatable 的 `__index` 负责生命周期检查及类成员解析。

构造链和析构链均通过直接父类引用遍历。对 `ctor`、`dtor` 使用 `rawget`，保证每一级实现至多执行一次。

## 错误模型

模块复用 `LuaUIFramework.Shared.Core.FError`，定义以下错误码：

- `INVALID_CLASS_NAME`：类名不是非空字符串。
- `INVALID_BASE_CLASS`：父类不是本模块创建的类。
- `INVALID_CLASS`：类型查询收到的目标不是本模块创建的类。
- `OBJECT_DESTROYED`：销毁后访问不允许的实例成员。

错误上下文包含适用的 `class`、`base` 或 `member` 信息。

## 测试策略

独立规格覆盖：

1. 根类和子类构造按父到子顺序执行，并共享构造参数。
2. 继承方法、方法覆写与 `Dog.super.method(self, ...)` 行为正确。
3. 类和实例类型查询在多级继承、普通 table 和已销毁对象上结果正确。
4. 析构按子到父顺序执行，`destroy()` 幂等且递归销毁安全。
5. 销毁后允许安全查询，普通实例方法访问产生 `OBJECT_DESTROYED`。
6. 非法类名、非法父类和非法类型查询产生对应的 `FError`。
7. 构造或析构异常被原样传播，且不会返回半初始化对象或重复析构。

使用现有 Fengari 环境执行该独立规格，不把本次功能耦合到 UI 集成测试。
