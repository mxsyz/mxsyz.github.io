# LuaJIT2 内存分析工具集

结合LuaJIT2源码，提供全面的Lua对象内存占用统计方法和工具。

## 📚 文档

### [luajit2-memory-analysis.md](luajit2-memory-analysis.md)
详尽的LuaJIT2内存管理和统计方法文档，包含：
- LuaJIT2内存管理机制概述
- 各种对象类型的数据结构分析
- 多种内存统计方案对比
- 源码级别的实现细节
- 最佳实践和优化建议

## 🛠️ 工具

### 1. Lua内存分析器 (`memory_analyzer.lua`)

纯Lua实现的内存分析工具，无需修改LuaJIT源码即可使用。

**主要功能：**
- ✅ 分析全局或指定对象的内存占用
- ✅ 按类型统计（字符串、表、函数、userdata等）
- ✅ 监控函数执行前后的内存变化
- ✅ 查找大内存对象
- ✅ 内存快照对比（检测内存泄漏）
- ✅ 持续内存监控

**使用示例：**
```lua
local mem = require("memory_analyzer")

-- 基本内存统计
local stats = mem.analyze_memory()
mem.print_stats(stats)

-- 监控函数内存使用
local diff = mem.memory_diff(function()
  -- 你的代码
end)

-- 查找大对象
local large_objs = mem.find_large_objects(1024)  -- >1KB
mem.print_large_objects(large_objs, 10)

-- 内存快照对比
local snap1 = mem.snapshot()
-- ... 执行一些操作 ...
local snap2 = mem.snapshot()
mem.compare_snapshots(snap1, snap2)
```

### 2. C扩展模块 (`luamem.c`)

直接访问LuaJIT内部结构，提供最精确的内存统计。

**主要功能：**
- ✅ 精确的GC对象统计
- ✅ 自定义内存分配器追踪
- ✅ 单个对象大小计算
- ✅ 详细的分配/释放统计

**编译：**
```bash
make
# 或者
gcc -shared -fPIC -o luamem.so luamem.c -I/usr/local/include/luajit-2.1 -lluajit-5.1
```

**使用示例：**
```lua
local luamem = require("luamem")

-- 获取内存信息
local info = luamem.getinfo()
print("总内存:", info.total_mem)

-- 获取对象大小
local t = {1, 2, 3}
local size = luamem.sizeof(t)
print("表大小:", size)

-- 启用分配追踪
luamem.settracking(true)
-- ... 执行代码 ...
local stats = luamem.getallocstats()
print("峰值内存:", stats.peak_usage)
```

### 3. 使用示例 (`example_usage.lua`)

包含8个详细示例，演示各种内存分析场景：
1. 基本内存统计
2. 监控函数内存使用
3. 查找大对象
4. 内存快照对比
5. 不同数据类型的内存占用测试
6. 内存分配和释放模式
7. 内存泄漏检测
8. 内存优化建议

**运行：**
```bash
luajit example_usage.lua
```

## 📊 LuaJIT2 对象内存结构

### 字符串 (GCstr)
```
大小 = sizeof(GCstr) + len + 1
     = 24 + 字符串长度 + 1
```

### 表 (GCtab)
```
大小 = sizeof(GCtab) + 数组部分 + 哈希部分
     = 40 + (asize × 16) + ((hmask+1) × 32)
```

### 函数 (GCfunc)
```
大小 = sizeof(GCfunc) + upvalues
     = 40 + (nupvalues × 16)
```

### Userdata (GCudata)
```
大小 = sizeof(GCudata) + len
     = 24 + 用户数据大小
```

### 线程 (lua_State)
```
大小 = sizeof(lua_State) + 栈空间
     = 200 + (stacksize × 16)
```

## 🔬 统计方法对比

| 方法 | 精度 | 复杂度 | 性能影响 | 可移植性 |
|------|------|--------|----------|----------|
| collectgarbage("count") | 低 | 简单 | 极小 | 最高 |
| Lua递归遍历 | 中 | 中等 | 中等 | 高 |
| FFI + collectgarbage | 中+ | 中等 | 小 | 中 |
| C扩展 | 最高 | 复杂 | 小 | 低 |
| 分配器Hook | 最高 | 复杂 | 小-中 | 最低 |

## 💡 优化建议

### 字符串优化
```lua
-- ❌ 低效
local s = ""
for i = 1, 1000 do
  s = s .. tostring(i)
end

-- ✅ 高效
local t = {}
for i = 1, 1000 do
  t[i] = tostring(i)
end
local s = table.concat(t)
```

### 表优化
```lua
-- ❌ 动态增长
local t = {}
for i = 1, 10000 do
  t[i] = i
end

-- ✅ 预分配（需要table.new）
local t = table.new(10000, 0)
for i = 1, 10000 do
  t[i] = i
end
```

### 避免内存泄漏
```lua
-- 使用弱引用表
local cache = setmetatable({}, {__mode = "k"})

-- 及时解除循环引用
obj.ref = nil

-- 定期检查内存增长
local mem = require("memory_analyzer")
local snap1 = mem.snapshot()
-- ... 运行一段时间 ...
local snap2 = mem.snapshot()
mem.compare_snapshots(snap1, snap2)
```

## 📋 关键源码文件

分析LuaJIT2内存管理需要了解以下源码：

- `src/lj_obj.h` - 对象定义和类型
- `src/lj_gc.h` / `src/lj_gc.c` - 垃圾回收
- `src/lj_tab.c` - 表操作
- `src/lj_str.c` - 字符串管理
- `src/lj_alloc.c` - 内存分配器
- `src/lj_state.c` - 状态管理

## 🚀 快速开始

1. **使用Lua分析器**（最简单）：
```bash
luajit example_usage.lua
```

2. **编译C扩展**（最精确）：
```bash
make
luajit -e "local m = require('luamem'); print(m.gcinfo())"
```

3. **集成到项目**：
```lua
-- 在你的项目中
local mem = require("memory_analyzer")

-- 定期采样
setInterval(function()
  local stats = mem.analyze_memory()
  if stats.gc_memory_kb > threshold then
    print("警告：内存使用过高")
  end
end, 60)
```

## 📖 参考资料

- [LuaJIT官方网站](https://luajit.org/)
- [LuaJIT源码](https://github.com/LuaJIT/LuaJIT)
- [Lua 5.1参考手册](https://www.lua.org/manual/5.1/)

## 📝 许可证

MIT License

## 🤝 贡献

欢迎提交Issue和Pull Request！

---

**注意**：本工具集基于LuaJIT2的内部实现，不同版本可能有差异。建议在实际使用前根据具体版本调整。
