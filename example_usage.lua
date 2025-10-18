#!/usr/bin/env luajit
--[[
  LuaJIT内存分析器使用示例
  展示如何使用memory_analyzer模块进行内存分析
]]

local mem = require("memory_analyzer")

print("=== LuaJIT内存分析器示例 ===\n")

-- 示例1: 基本内存统计
print("【示例1】基本内存统计")
print("-" .. string.rep("-", 50))
local stats = mem.analyze_memory()
mem.print_stats(stats)

-- 示例2: 监控函数内存使用
print("\n【示例2】监控函数内存使用")
print("-" .. string.rep("-", 50))

local function create_large_table()
  local t = {}
  for i = 1, 10000 do
    t[i] = string.format("item_%d", i)
  end
  return t
end

local diff, result = mem.memory_diff(create_large_table)
print(string.format("create_large_table() 使用了 %.2f KB 内存", diff))
result = nil  -- 释放
collectgarbage("collect")

-- 示例3: 查找大对象
print("\n【示例3】查找大对象")
print("-" .. string.rep("-", 50))

-- 创建一些测试数据
_G.test_data = {
  large_string = string.rep("x", 50000),
  large_array = {},
  nested_table = {}
}

for i = 1, 5000 do
  _G.test_data.large_array[i] = i
end

for i = 1, 100 do
  _G.test_data.nested_table["key" .. i] = {
    id = i,
    name = "Object " .. i,
    data = string.rep("data", 100)
  }
end

local large_objs = mem.find_large_objects(1024)  -- 找出大于1KB的对象
mem.print_large_objects(large_objs, 10)

-- 示例4: 内存快照对比
print("\n【示例4】内存快照对比")
print("-" .. string.rep("-", 50))

local snap1 = mem.snapshot()
print("创建快照1...")

-- 分配一些内存
local temp = {}
for i = 1, 5000 do
  temp[i] = {
    id = i,
    name = "Item " .. i,
    data = string.rep("x", 100)
  }
end

local snap2 = mem.snapshot()
print("创建快照2...")

mem.compare_snapshots(snap1, snap2)

-- 清理
temp = nil
_G.test_data = nil
collectgarbage("collect")

-- 示例5: 不同数据类型的内存占用
print("\n【示例5】不同数据类型的内存占用测试")
print("-" .. string.rep("-", 50))

local function test_type_memory(name, create_func, count)
  collectgarbage("collect")
  local before = collectgarbage("count")
  
  local items = {}
  for i = 1, count do
    items[i] = create_func(i)
  end
  
  collectgarbage("collect")
  local after = collectgarbage("count")
  
  local total_kb = after - before
  local per_item = (total_kb * 1024) / count
  
  print(string.format("%-20s: 总计 %8.2f KB, 平均每个 %8.2f 字节", 
    name, total_kb, per_item))
  
  items = nil
  collectgarbage("collect")
end

-- 测试不同类型
test_type_memory("空表", function() return {} end, 10000)
test_type_memory("数组(10元素)", function() 
  local t = {}
  for i = 1, 10 do t[i] = i end
  return t
end, 1000)
test_type_memory("哈希表(10键)", function()
  local t = {}
  for i = 1, 10 do t["key"..i] = i end
  return t
end, 1000)
test_type_memory("短字符串(10字节)", function(i) 
  return string.format("%010d", i) 
end, 10000)
test_type_memory("长字符串(1000字节)", function() 
  return string.rep("x", 1000)
end, 1000)
test_type_memory("闭包(无upvalue)", function()
  return function() return 42 end
end, 10000)
test_type_memory("闭包(3个upvalue)", function()
  local a, b, c = 1, 2, 3
  return function() return a + b + c end
end, 10000)

-- 示例6: 实时内存监控演示
print("\n【示例6】内存分配和释放模式")
print("-" .. string.rep("-", 50))

local function simulate_workload()
  print("\n模拟工作负载...")
  local iterations = 5
  
  for i = 1, iterations do
    -- 分配
    local data = {}
    for j = 1, 1000 do
      data[j] = string.format("data_%d_%d", i, j)
    end
    
    local mem = collectgarbage("count")
    print(string.format("  迭代 %d: %.2f KB", i, mem))
    
    -- 模拟处理
    local sum = 0
    for j = 1, 1000 do
      sum = sum + j
    end
    
    -- 释放
    data = nil
    if i % 2 == 0 then
      collectgarbage("collect")
      local mem_after = collectgarbage("count")
      print(string.format("    GC后: %.2f KB (释放 %.2f KB)", 
        mem_after, mem - mem_after))
    end
  end
end

simulate_workload()

-- 示例7: 检测内存泄漏
print("\n【示例7】内存泄漏检测示例")
print("-" .. string.rep("-", 50))

local snapshots = {}
local function simulate_leak()
  -- 模拟内存泄漏：将数据添加到全局表
  _G._leak_test = _G._leak_test or {}
  
  for round = 1, 5 do
    -- 添加数据（故意不清理）
    for i = 1, 1000 do
      table.insert(_G._leak_test, {
        id = i,
        data = string.rep("x", 100)
      })
    end
    
    local snap = mem.snapshot()
    table.insert(snapshots, snap)
    
    if #snapshots > 1 then
      local prev = snapshots[#snapshots - 1]
      local curr = snapshots[#snapshots]
      local growth = curr.memory_kb - prev.memory_kb
      print(string.format("轮次 %d: %.2f KB (+%.2f KB)", 
        round, curr.memory_kb, growth))
    end
  end
  
  print("\n分析: 内存持续增长，可能存在泄漏")
  print(string.format("总增长: %.2f KB", 
    snapshots[#snapshots].memory_kb - snapshots[1].memory_kb))
end

simulate_leak()

-- 清理
_G._leak_test = nil
collectgarbage("collect")

-- 示例8: 优化建议
print("\n【示例8】内存优化建议")
print("-" .. string.rep("-", 50))

print([[
根据LuaJIT内存分析结果，以下是一些优化建议：

1. 字符串优化:
   - 避免频繁的字符串拼接，使用table.concat
   - 重用常用字符串（LuaJIT会自动intern）
   - 对于大字符串，考虑使用FFI

2. 表优化:
   - 预分配表大小: local t = table.new(narray, nhash)
   - 避免混用数组和哈希部分
   - 及时清理不需要的表引用

3. 函数优化:
   - 减少不必要的闭包创建
   - 将常用函数提升到外层作用域
   - 考虑使用函数池复用

4. GC调优:
   - collectgarbage("setpause", 100)  -- GC暂停百分比
   - collectgarbage("setstepmul", 200) -- GC步进倍数
   - 在关键路径避免触发GC

5. 内存泄漏预防:
   - 使用弱引用表: setmetatable({}, {__mode = "k"})
   - 及时解除循环引用
   - 定期进行内存快照对比
]])

print("\n=== 示例结束 ===")

-- 最终内存统计
print("\n最终内存状态:")
collectgarbage("collect")
local final_stats = mem.analyze_memory()
mem.print_stats(final_stats)
