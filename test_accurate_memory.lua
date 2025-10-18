#!/usr/bin/env luajit
--[[
  测试精确内存计算
  对比估算值和实际值
]]

local accurate = require("accurate_memory")

print("=== LuaJIT精确内存测试 ===")

-- 显示内部类型大小
accurate.show_type_sizes()

-- 运行精确测试
accurate.test_accuracy()

-- 详细对比测试
print("\n=== 详细对比测试 ===\n")

local function compare_test(name, obj)
  local size = accurate.sizeof(obj)
  local deep = accurate.sizeof_deep(obj)
  
  print(string.format("%-30s: %8d 字节 (深度: %8d 字节)", 
    name, size, deep))
end

-- 字符串对比
print("字符串大小:")
compare_test("空字符串", "")
compare_test("1个字符", "a")
compare_test("10个字符", "1234567890")
compare_test("100个字符", string.rep("x", 100))
compare_test("1000个字符", string.rep("x", 1000))
compare_test("10000个字符", string.rep("x", 10000))

-- 表大小对比
print("\n表大小:")
compare_test("空表", {})
compare_test("1元素数组", {1})
compare_test("10元素数组", {1,2,3,4,5,6,7,8,9,10})
compare_test("100元素数组", (function()
  local t = {}
  for i = 1, 100 do t[i] = i end
  return t
end)())

compare_test("1键哈希表", {a=1})
compare_test("10键哈希表", (function()
  local t = {}
  for i = 1, 10 do t["k"..i] = i end
  return t
end)())
compare_test("100键哈希表", (function()
  local t = {}
  for i = 1, 100 do t["k"..i] = i end
  return t
end)())

-- 混合表
compare_test("混合表(5数组+5哈希)", (function()
  local t = {1,2,3,4,5}
  t.a, t.b, t.c, t.d, t.e = 1,2,3,4,5
  return t
end)())

-- 嵌套表
print("\n嵌套结构:")
local nested1 = {
  a = {1, 2, 3},
  b = {4, 5, 6},
  c = {7, 8, 9}
}
compare_test("3层嵌套表", nested1)

local nested2 = {}
for i = 1, 10 do
  nested2[i] = {}
  for j = 1, 10 do
    nested2[i][j] = i * j
  end
end
compare_test("10x10嵌套数组", nested2)

-- 函数对比
print("\n函数大小:")
compare_test("空函数", function() end)
compare_test("简单函数", function(a, b) return a + b end)

local x = 10
compare_test("1个upvalue", function() return x end)

local y, z = 20, 30
compare_test("3个upvalue", function() return x + y + z end)

compare_test("C函数(print)", print)
compare_test("C函数(table.insert)", table.insert)

-- 真实场景测试
print("\n=== 真实场景测试 ===\n")

-- 场景1: 配置对象
local config = {
  server = {
    host = "localhost",
    port = 8080,
    timeout = 30
  },
  database = {
    host = "db.example.com",
    port = 3306,
    user = "admin",
    password = "secret123"
  },
  features = {
    "feature1", "feature2", "feature3"
  }
}
accurate.print_sizeof(config, "配置对象")

-- 场景2: 用户数据列表
local users = {}
for i = 1, 100 do
  users[i] = {
    id = i,
    name = string.format("User%d", i),
    email = string.format("user%d@example.com", i),
    age = 20 + (i % 50),
    active = (i % 2 == 0)
  }
end
accurate.print_sizeof(users, "100个用户数据")

-- 场景3: 缓存对象
local cache = {}
for i = 1, 1000 do
  local key = string.format("cache_key_%d", i)
  cache[key] = {
    value = string.rep("x", 50),
    timestamp = os.time(),
    hits = math.random(1, 100)
  }
end
accurate.print_sizeof(cache, "1000个缓存项")

-- 场景4: 闭包工厂
local function create_counter()
  local count = 0
  return function()
    count = count + 1
    return count
  end
end

local counters = {}
for i = 1, 100 do
  counters[i] = create_counter()
end
accurate.print_sizeof(counters, "100个闭包对象")

-- 验证测试
print("\n=== 内存验证测试 ===\n")

local function verify_with_gc(name, create_func)
  collectgarbage("collect")
  collectgarbage("collect")
  
  local before = collectgarbage("count")
  
  local obj = create_func()
  
  collectgarbage("collect")
  local after = collectgarbage("count")
  
  local gc_size = (after - before) * 1024
  local calc_size = accurate.sizeof_deep(obj)
  local diff = math.abs(gc_size - calc_size)
  local accuracy = 100 - (diff / math.max(gc_size, 1)) * 100
  
  print(string.format("%-25s: 计算=%7d, GC=%7d, 误差=%6.1f%%",
    name, calc_size, gc_size, 100 - accuracy))
  
  obj = nil
  collectgarbage("collect")
end

-- 进行验证
verify_with_gc("1000元素数组", function()
  local t = {}
  for i = 1, 1000 do t[i] = i end
  return t
end)

verify_with_gc("100键哈希表", function()
  local t = {}
  for i = 1, 100 do t["key"..i] = i end
  return t
end)

verify_with_gc("100个字符串", function()
  local t = {}
  for i = 1, 100 do
    t[i] = string.format("string_%d", i)
  end
  return t
end)

verify_with_gc("嵌套结构", function()
  local t = {}
  for i = 1, 50 do
    t[i] = {
      id = i,
      data = {a = i, b = i*2, c = i*3}
    }
  end
  return t
end)

print("\n=== 测试完成 ===")
