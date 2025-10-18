--[[
  LuaJIT内存分析器
  提供详细的Lua对象内存统计功能
  
  用法:
    local mem = require("memory_analyzer")
    local stats = mem.analyze_memory()
    mem.print_stats(stats)
]]

local M = {}

-- 内存统计缓存，避免重复计算
local size_cache = setmetatable({}, {__mode = "k"})

-- 估算字符串大小
-- 结构: GCstr header (16字节) + len字段 + 字符数据 + '\0'
local function sizeof_string(s)
  local cached = size_cache[s]
  if cached then return cached end
  
  local size = 24 + #s  -- GCstr基础大小 + 字符串长度
  size_cache[s] = size
  return size
end

-- 估算表大小
-- 结构: GCtab header + 数组部分 + 哈希部分
local function sizeof_table(t, visited)
  if visited[t] then return 0 end
  visited[t] = true
  
  local cached = size_cache[t]
  if cached then return cached end
  
  local size = 40  -- GCtab基础大小
  local array_size = 0
  local hash_size = 0
  
  -- 检测数组部分大小
  -- LuaJIT会自动优化连续整数索引为数组
  local max_array_idx = 0
  for k, v in pairs(t) do
    if type(k) == "number" and k > 0 and k == math.floor(k) then
      if k > max_array_idx then
        max_array_idx = k
      end
    end
  end
  
  -- 数组部分内存: 每个TValue 16字节
  if max_array_idx > 0 then
    -- LuaJIT会将数组大小向上取到2的幂次
    local asize = 1
    while asize < max_array_idx do
      asize = asize * 2
    end
    array_size = asize
    size = size + asize * 16
  end
  
  -- 哈希部分内存: 每个Node 32字节
  for k, v in pairs(t) do
    local is_array_key = type(k) == "number" and k > 0 and 
                        k <= array_size and k == math.floor(k)
    if not is_array_key then
      hash_size = hash_size + 1
    end
  end
  
  if hash_size > 0 then
    -- LuaJIT会将哈希大小向上取到2的幂次
    local hsize = 1
    while hsize < hash_size do
      hsize = hsize * 2
    end
    size = size + hsize * 32
  end
  
  size_cache[t] = size
  return size
end

-- 估算函数大小
-- 结构: GCfunc header + upvalues
local function sizeof_function(f, visited)
  if visited[f] then return 0 end
  visited[f] = true
  
  local cached = size_cache[f]
  if cached then return cached end
  
  local size = 40  -- GCfunc基础大小
  
  -- 统计upvalue数量
  local upvalue_count = 0
  local i = 1
  while true do
    local name = debug.getupvalue(f, i)
    if not name then break end
    upvalue_count = upvalue_count + 1
    i = i + 1
  end
  
  -- 每个upvalue占用16字节
  size = size + upvalue_count * 16
  
  size_cache[f] = size
  return size
end

-- 估算userdata大小
local function sizeof_userdata(u)
  local cached = size_cache[u]
  if cached then return cached end
  
  -- GCudata基础大小 + 用户数据
  -- 实际大小无法精确获取，估算为48字节
  local size = 48
  
  -- 如果有FFI，可以尝试获取更精确的大小
  local ok, ffi = pcall(require, "ffi")
  if ok and ffi.typeof then
    local ok2, ctype = pcall(ffi.typeof, u)
    if ok2 then
      size = 24 + ffi.sizeof(ctype)
    end
  end
  
  size_cache[u] = size
  return size
end

-- 估算thread(协程)大小
local function sizeof_thread(th)
  local cached = size_cache[th]
  if cached then return cached end
  
  -- lua_State基础大小 + 栈空间
  -- 默认栈大小约为8KB
  local size = 200 + 8192
  
  size_cache[th] = size
  return size
end

-- 深度遍历对象树，统计所有可达对象
local function traverse_object(obj, stats, visited, depth)
  if obj == nil then return end
  if visited[obj] then return end
  
  -- 防止无限递归
  if depth > 100 then return end
  
  local t = type(obj)
  
  if t == "string" then
    stats.strings.count = stats.strings.count + 1
    stats.strings.bytes = stats.strings.bytes + sizeof_string(obj)
    visited[obj] = true
    
  elseif t == "table" then
    stats.tables.count = stats.tables.count + 1
    stats.tables.bytes = stats.tables.bytes + sizeof_table(obj, visited)
    
    -- 递归遍历表内容
    for k, v in pairs(obj) do
      traverse_object(k, stats, visited, depth + 1)
      traverse_object(v, stats, visited, depth + 1)
    end
    
    -- 遍历元表
    local mt = debug.getmetatable(obj)
    if mt then
      traverse_object(mt, stats, visited, depth + 1)
    end
    
  elseif t == "function" then
    if not visited[obj] then
      stats.functions.count = stats.functions.count + 1
      stats.functions.bytes = stats.functions.bytes + sizeof_function(obj, visited)
      
      -- 遍历upvalues
      local i = 1
      while true do
        local name, val = debug.getupvalue(obj, i)
        if not name then break end
        traverse_object(val, stats, visited, depth + 1)
        i = i + 1
      end
      
      -- 遍历函数环境
      local env = debug.getfenv(obj)
      if env then
        traverse_object(env, stats, visited, depth + 1)
      end
    end
    
  elseif t == "userdata" then
    if not visited[obj] then
      stats.userdata.count = stats.userdata.count + 1
      stats.userdata.bytes = stats.userdata.bytes + sizeof_userdata(obj)
      visited[obj] = true
      
      -- 遍历userdata的元表
      local mt = debug.getmetatable(obj)
      if mt then
        traverse_object(mt, stats, visited, depth + 1)
      end
    end
    
  elseif t == "thread" then
    if not visited[obj] then
      stats.threads.count = stats.threads.count + 1
      stats.threads.bytes = stats.threads.bytes + sizeof_thread(obj)
      visited[obj] = true
    end
  end
end

-- 主分析函数：分析从根对象可达的所有对象
function M.analyze_memory(root)
  -- 初始化统计结构
  local stats = {
    strings = {count = 0, bytes = 0},
    tables = {count = 0, bytes = 0},
    functions = {count = 0, bytes = 0},
    userdata = {count = 0, bytes = 0},
    threads = {count = 0, bytes = 0}
  }
  
  local visited = {}
  
  -- 如果没有指定根对象，从_G开始遍历
  if root == nil then
    root = _G
  end
  
  -- 开始遍历
  traverse_object(root, stats, visited, 0)
  
  -- 计算总计
  stats.total_bytes = 0
  stats.total_count = 0
  for _, v in pairs(stats) do
    if type(v) == "table" and v.bytes then
      stats.total_bytes = stats.total_bytes + v.bytes
      stats.total_count = stats.total_count + v.count
    end
  end
  
  -- 添加GC报告的内存（更准确的总内存）
  stats.gc_memory_kb = collectgarbage("count")
  
  -- 清空缓存
  size_cache = setmetatable({}, {__mode = "k"})
  
  return stats
end

-- 格式化输出统计信息
function M.print_stats(stats)
  print("\n" .. string.rep("=", 60))
  print("LuaJIT 内存统计报告")
  print(string.rep("=", 60))
  
  local function format_size(bytes)
    if bytes < 1024 then
      return string.format("%d B", bytes)
    elseif bytes < 1024 * 1024 then
      return string.format("%.2f KB", bytes / 1024)
    else
      return string.format("%.2f MB", bytes / (1024 * 1024))
    end
  end
  
  print(string.format("\n%-15s %10s %15s %10s", 
    "类型", "数量", "内存占用", "占比"))
  print(string.rep("-", 60))
  
  local total = stats.total_bytes > 0 and stats.total_bytes or 1
  
  print(string.format("%-15s %10d %15s %9.1f%%", 
    "字符串", stats.strings.count, 
    format_size(stats.strings.bytes),
    stats.strings.bytes / total * 100))
    
  print(string.format("%-15s %10d %15s %9.1f%%", 
    "表", stats.tables.count, 
    format_size(stats.tables.bytes),
    stats.tables.bytes / total * 100))
    
  print(string.format("%-15s %10d %15s %9.1f%%", 
    "函数", stats.functions.count, 
    format_size(stats.functions.bytes),
    stats.functions.bytes / total * 100))
    
  print(string.format("%-15s %10d %15s %9.1f%%", 
    "Userdata", stats.userdata.count, 
    format_size(stats.userdata.bytes),
    stats.userdata.bytes / total * 100))
    
  print(string.format("%-15s %10d %15s %9.1f%%", 
    "协程", stats.threads.count, 
    format_size(stats.threads.bytes),
    stats.threads.bytes / total * 100))
  
  print(string.rep("-", 60))
  print(string.format("%-15s %10d %15s", 
    "估算总计", stats.total_count, 
    format_size(stats.total_bytes)))
  print(string.format("%-15s %10s %15s", 
    "GC报告", "", 
    format_size(stats.gc_memory_kb * 1024)))
  print(string.rep("=", 60) .. "\n")
end

-- 监控函数执行前后的内存变化
function M.memory_diff(func, ...)
  collectgarbage("collect")
  collectgarbage("collect")  -- 执行两次确保完全回收
  
  local before = collectgarbage("count")
  
  local results = {func(...)}
  
  collectgarbage("collect")
  collectgarbage("collect")
  
  local after = collectgarbage("count")
  
  return after - before, unpack(results)
end

-- 查找大对象（内存占用超过阈值的对象）
function M.find_large_objects(threshold_bytes, root)
  threshold_bytes = threshold_bytes or 1024  -- 默认1KB
  local large_objs = {}
  local visited = {}
  
  local function check_object(obj, name, parent_name)
    if visited[obj] then return end
    
    local t = type(obj)
    local size = 0
    
    if t == "table" then
      size = sizeof_table(obj, {})
      visited[obj] = true
    elseif t == "string" then
      size = sizeof_string(obj)
      visited[obj] = true
    elseif t == "function" then
      size = sizeof_function(obj, {})
      visited[obj] = true
    elseif t == "userdata" then
      size = sizeof_userdata(obj)
      visited[obj] = true
    elseif t == "thread" then
      size = sizeof_thread(obj)
      visited[obj] = true
    end
    
    if size >= threshold_bytes then
      table.insert(large_objs, {
        name = name or tostring(obj),
        parent = parent_name,
        type = t,
        size = size
      })
    end
    
    -- 递归检查表内容
    if t == "table" then
      for k, v in pairs(obj) do
        local key_name = tostring(k)
        local full_name = name and (name .. "." .. key_name) or key_name
        check_object(v, full_name, name)
      end
    end
  end
  
  root = root or _G
  check_object(root, "_G", nil)
  
  -- 按大小降序排序
  table.sort(large_objs, function(a, b) 
    return a.size > b.size 
  end)
  
  return large_objs
end

-- 打印大对象列表
function M.print_large_objects(objs, limit)
  limit = limit or 20
  
  print("\n" .. string.rep("=", 70))
  print("大对象列表 (Top " .. math.min(limit, #objs) .. ")")
  print(string.rep("=", 70))
  print(string.format("%-30s %-12s %15s", "名称", "类型", "大小"))
  print(string.rep("-", 70))
  
  for i = 1, math.min(limit, #objs) do
    local obj = objs[i]
    local size_str
    if obj.size < 1024 then
      size_str = string.format("%d B", obj.size)
    elseif obj.size < 1024 * 1024 then
      size_str = string.format("%.2f KB", obj.size / 1024)
    else
      size_str = string.format("%.2f MB", obj.size / (1024 * 1024))
    end
    
    local name = obj.name
    if #name > 30 then
      name = name:sub(1, 27) .. "..."
    end
    
    print(string.format("%-30s %-12s %15s", name, obj.type, size_str))
  end
  
  print(string.rep("=", 70) .. "\n")
end

-- 内存快照对比（用于检测内存泄漏）
function M.snapshot()
  collectgarbage("collect")
  collectgarbage("collect")
  
  return {
    time = os.time(),
    memory_kb = collectgarbage("count"),
    stats = M.analyze_memory()
  }
end

function M.compare_snapshots(snap1, snap2)
  local diff = {
    time_diff = snap2.time - snap1.time,
    memory_diff_kb = snap2.memory_kb - snap1.memory_kb,
    strings_diff = snap2.stats.strings.count - snap1.stats.strings.count,
    tables_diff = snap2.stats.tables.count - snap1.stats.tables.count,
    functions_diff = snap2.stats.functions.count - snap1.stats.functions.count,
  }
  
  print("\n" .. string.rep("=", 60))
  print("内存快照对比")
  print(string.rep("=", 60))
  print(string.format("时间间隔: %d 秒", diff.time_diff))
  print(string.format("内存变化: %.2f KB (%.2f KB/s)", 
    diff.memory_diff_kb,
    diff.memory_diff_kb / math.max(diff.time_diff, 1)))
  print(string.format("字符串增量: %+d", diff.strings_diff))
  print(string.format("表增量: %+d", diff.tables_diff))
  print(string.format("函数增量: %+d", diff.functions_diff))
  print(string.rep("=", 60) .. "\n")
  
  return diff
end

-- 持续监控内存（用于长时间运行的程序）
function M.start_monitor(interval, callback)
  interval = interval or 60  -- 默认60秒
  
  local snapshots = {}
  local max_snapshots = 100
  
  local function monitor_loop()
    while true do
      local snap = M.snapshot()
      table.insert(snapshots, snap)
      
      if #snapshots > max_snapshots then
        table.remove(snapshots, 1)
      end
      
      -- 检测内存泄漏
      if #snapshots >= 10 then
        local first = snapshots[1]
        local last = snapshots[#snapshots]
        local growth_rate = (last.memory_kb - first.memory_kb) / 
                           (last.time - first.time)
        
        if growth_rate > 10 then  -- 每秒增长超过10KB
          if callback then
            callback("memory_leak", {
              growth_rate = growth_rate,
              total_growth = last.memory_kb - first.memory_kb,
              duration = last.time - first.time
            })
          else
            print(string.format(
              "警告: 检测到可能的内存泄漏 (增长率: %.2f KB/s)",
              growth_rate))
          end
        end
      end
      
      -- 使用socket.sleep或其他方式等待
      local sock = package.loaded.socket
      if sock and sock.sleep then
        sock.sleep(interval)
      else
        -- 简单的忙等待（不推荐用于生产环境）
        local start = os.time()
        while os.time() - start < interval do
          -- 等待
        end
      end
    end
  end
  
  -- 在协程中运行监控
  local co = coroutine.create(monitor_loop)
  return co
end

return M
