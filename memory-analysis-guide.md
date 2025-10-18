# 使用 collectgarbage 分析对象内存大小

## 概述

`collectgarbage` 是 Lua 的内置函数，用于控制垃圾回收器并获取内存使用信息。本指南将介绍如何使用它来分析对象的内存大小。

## 基本用法

### 1. 获取内存使用量

```lua
local memory = collectgarbage("count")  -- 返回当前内存使用量（KB）
print(string.format("当前内存: %.2f KB", memory))
```

### 2. 测量对象内存大小的基本方法

```lua
-- 强制执行垃圾回收
collectgarbage("collect")
collectgarbage("collect")  -- 调用两次确保完全清理

-- 记录创建对象前的内存
local memBefore = collectgarbage("count")

-- 创建对象
local myObject = {data = string.rep("x", 1000)}

-- 记录创建对象后的内存
local memAfter = collectgarbage("count")

-- 计算内存差值
local memUsed = memAfter - memBefore
print(string.format("对象占用内存: %.2f KB", memUsed))
```

## collectgarbage 的主要命令

| 命令 | 说明 | 返回值 |
|------|------|--------|
| `"collect"` | 执行完整的垃圾回收循环 | 0 |
| `"count"` | 返回 Lua 使用的内存量 | 内存量（KB） |
| `"stop"` | 停止垃圾回收器 | 0 |
| `"restart"` | 重启垃圾回收器 | 0 |
| `"step"` | 执行一步垃圾回收 | true（完成一个周期）或 false |
| `"isrunning"` | 检查回收器是否在运行 | true 或 false |
| `"setpause"` | 设置回收器暂停参数 | 之前的值 |
| `"setstepmul"` | 设置回收器步进倍率 | 之前的值 |

## 最佳实践

### 1. 精确测量的技巧

```lua
-- 停止自动垃圾回收以获得更精确的测量
collectgarbage("stop")

-- 清理现有垃圾
collectgarbage("collect")
collectgarbage("collect")

-- 进行测量
local before = collectgarbage("count")
-- ... 创建对象 ...
local after = collectgarbage("count")

-- 重启垃圾回收器
collectgarbage("restart")

local size = after - before
```

### 2. 监控内存泄漏

```lua
local function monitorMemory()
    collectgarbage("collect")
    collectgarbage("collect")
    
    local mem = collectgarbage("count")
    print(string.format("当前内存: %.2f KB", mem))
    return mem
end

-- 在程序的不同阶段调用
monitorMemory()  -- 阶段1
-- ... 执行操作 ...
monitorMemory()  -- 阶段2
-- ... 执行操作 ...
monitorMemory()  -- 阶段3
```

### 3. 创建通用测量函数

```lua
local function measureObjectSize(createFunc)
    collectgarbage("collect")
    collectgarbage("collect")
    
    local memBefore = collectgarbage("count")
    local obj = createFunc()
    local memAfter = collectgarbage("count")
    
    return memAfter - memBefore, obj
end

-- 使用示例
local size, myTable = measureObjectSize(function()
    local t = {}
    for i = 1, 1000 do
        t[i] = i * i
    end
    return t
end)

print(string.format("表占用: %.2f KB", size))
```

## 注意事项

1. **多次调用 collect**: 由于 Lua 的垃圾回收是增量式的，建议调用两次 `collectgarbage("collect")` 确保完全清理。

2. **测量误差**: 由于 Lua 内部的内存分配机制，测量结果可能不是完全精确的，但可以提供很好的估计。

3. **性能影响**: 频繁调用 `collectgarbage("collect")` 会影响性能，在生产环境中谨慎使用。

4. **字符串特殊性**: Lua 对字符串进行内部化（interning），相同的字符串可能共享内存。

5. **LuaJIT 差异**: 如果使用 LuaJIT，某些行为可能略有不同。

## 运行示例

要运行提供的示例文件：

```bash
lua memory_analysis.lua
```

## 实际应用场景

1. **性能优化**: 识别占用大量内存的对象
2. **内存泄漏检测**: 监控内存使用趋势
3. **数据结构选择**: 比较不同数据结构的内存效率
4. **缓存管理**: 决定缓存大小和清理策略

## 参考资源

- [Lua 5.4 参考手册 - collectgarbage](http://www.lua.org/manual/5.4/manual.html#pdf-collectgarbage)
- [Lua 性能优化技巧](http://www.lua.org/gems/)
