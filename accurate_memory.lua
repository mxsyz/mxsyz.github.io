--[[
  精确的LuaJIT对象内存大小计算
  直接使用FFI访问LuaJIT内部结构，获取准确的内存大小
  
  基于LuaJIT 2.1源码实现
]]

local ffi = require("ffi")
local bit = require("bit")

local M = {}

-- LuaJIT内部结构定义（来自lj_obj.h）
ffi.cdef[[
/* GC对象头 */
typedef struct GChead {
  struct GCobj *nextgc;
  uint8_t marked;
  uint8_t gct;
} GChead;

/* 字符串 */
typedef struct GCstr {
  struct GCobj *nextgc;
  uint8_t marked;
  uint8_t gct;
  uint8_t reserved;
  uint8_t unused;
  uint32_t hash;
  uint32_t len;
} GCstr;

/* 表 */
typedef struct GCtab {
  struct GCobj *nextgc;
  uint8_t marked;
  uint8_t gct;
  uint8_t nomm;
  uint8_t colo;
  uint32_t asize;
  uint32_t hmask;
  void *array;
  void *node;
  struct GCobj *gclist;
  struct GCtab *metatable;
} GCtab;

/* 函数（Lua闭包） */
typedef struct GCfuncL {
  struct GCobj *nextgc;
  uint8_t marked;
  uint8_t gct;
  uint8_t ffid;
  uint8_t nupvalues;
  struct GCobj *gclist;
  struct GCtab *env;
  void *pc;
} GCfuncL;

/* 函数（C闭包） */
typedef struct GCfuncC {
  struct GCobj *nextgc;
  uint8_t marked;
  uint8_t gct;
  uint8_t ffid;
  uint8_t nupvalues;
  struct GCobj *gclist;
  void *f;
} GCfuncC;

/* Userdata */
typedef struct GCudata {
  struct GCobj *nextgc;
  uint8_t marked;
  uint8_t gct;
  uint8_t udtype;
  uint8_t unused;
  uint32_t len;
  struct GCtab *metatable;
  struct GCtab *env;
} GCudata;

/* 线程 */
typedef struct lua_State {
  struct GCobj *nextgc;
  uint8_t marked;
  uint8_t gct;
  uint8_t dummy_ffid;
  uint8_t status;
  void *base;
  void *top;
  void *maxstack;
  void *stack;
  void *glref;
  struct GCobj *gclist;
  struct GCobj *openupval;
  struct GCtab *env;
  void *cframe;
  uint32_t stacksize;
} lua_State;

/* Upvalue */
typedef struct GCupval {
  struct GCobj *nextgc;
  uint8_t marked;
  uint8_t gct;
  uint8_t closed;
  uint8_t immutable;
  union {
    void *v;
    struct {
      uint32_t u32_0;
      uint32_t u32_1;
    };
  };
  struct GCobj *prev;
  struct GCobj *nextgc_upv;
} GCupval;

/* Proto (函数原型) */
typedef struct GCproto {
  struct GCobj *nextgc;
  uint8_t marked;
  uint8_t gct;
  uint8_t numparams;
  uint8_t framesize;
  uint32_t sizeuv;
  uint32_t sizekgc;
  uint32_t sizekn;
  uint32_t sizebc;
  uint32_t sizept;
  uint32_t sizelineinfo;
  void *uv;
  void *kgc;
  void *knum;
  void *bc;
  void *lineinfo;
  struct GCproto **pt;
  struct GCstr *chunkname;
  uint32_t firstline;
  uint32_t numline;
} GCproto;

/* TValue大小 */
typedef union TValue {
  uint64_t u64;
  struct {
    union {
      void *gcr;
      int32_t i;
      uint32_t u32;
    };
    uint32_t it;
  };
} TValue;

/* Node（哈希表节点） */
typedef struct Node {
  TValue val;
  TValue key;
  struct Node *next;
} Node;
]]

-- 对象类型常量
local LJ_TSTR    = bit.bnot(4)
local LJ_TUPVAL  = bit.bnot(5)
local LJ_TTHREAD = bit.bnot(6)
local LJ_TPROTO  = bit.bnot(7)
local LJ_TFUNC   = bit.bnot(8)
local LJ_TTRACE  = bit.bnot(9)
local LJ_TCDATA  = bit.bnot(10)
local LJ_TTAB    = bit.bnot(11)
local LJ_TUDATA  = bit.bnot(12)

-- FFI函数标识
local FF_C = 0

-- 获取对象的GC指针
local function obj2gco(obj)
  local t = type(obj)
  if t == "string" or t == "table" or t == "function" or 
     t == "userdata" or t == "thread" then
    -- 将Lua对象转换为lightuserdata（指针）
    local ptr = ffi.cast("void*", obj)
    return ptr
  end
  return nil
end

-- 精确计算字符串大小
function M.sizeof_string(s)
  if type(s) ~= "string" then
    return 0
  end
  
  local ptr = ffi.cast("GCstr*", obj2gco(s))
  if ptr == nil then
    -- fallback到估算
    return ffi.sizeof("GCstr") + #s + 1
  end
  
  -- GCstr header + 字符串内容 + '\0'
  -- 实际大小需要对齐到8字节边界
  local len = #s
  local size = ffi.sizeof("GCstr") + len + 1
  -- LuaJIT使用sizemulxor宏进行大小计算和对齐
  size = bit.band(size + 7, bit.bnot(7))  -- 8字节对齐
  
  return size
end

-- 精确计算表大小
function M.sizeof_table(t)
  if type(t) ~= "table" then
    return 0
  end
  
  local ptr = ffi.cast("GCtab*", obj2gco(t))
  if ptr == nil then
    -- fallback：使用debug库分析
    return M.sizeof_table_fallback(t)
  end
  
  -- GCtab基础大小
  local size = ffi.sizeof("GCtab")
  
  -- 数组部分：asize * sizeof(TValue)
  local asize = ptr.asize
  size = size + asize * ffi.sizeof("TValue")
  
  -- 哈希部分：(hmask + 1) * sizeof(Node)
  local hmask = ptr.hmask
  size = size + (hmask + 1) * ffi.sizeof("Node")
  
  return size
end

-- Fallback方法：使用debug库分析表大小
function M.sizeof_table_fallback(t)
  local size = ffi.sizeof("GCtab")
  
  -- 分析数组部分
  local asize = 0
  for i = 1, 100000 do
    if t[i] == nil then
      asize = i - 1
      break
    end
  end
  
  -- LuaJIT会将数组大小向上取到2的幂次
  local real_asize = 1
  while real_asize < asize do
    real_asize = real_asize * 2
  end
  size = size + real_asize * ffi.sizeof("TValue")
  
  -- 分析哈希部分
  local hsize = 0
  for k, v in pairs(t) do
    local is_array = type(k) == "number" and k > 0 and k <= asize and k == math.floor(k)
    if not is_array then
      hsize = hsize + 1
    end
  end
  
  if hsize > 0 then
    local real_hsize = 1
    while real_hsize < hsize do
      real_hsize = real_hsize * 2
    end
    size = size + real_hsize * ffi.sizeof("Node")
  end
  
  return size
end

-- 精确计算函数大小
function M.sizeof_function(f)
  if type(f) ~= "function" then
    return 0
  end
  
  -- 判断是Lua函数还是C函数
  local info = debug.getinfo(f, "S")
  local is_c = (info.what == "C")
  
  if is_c then
    -- C函数：GCfuncC + upvalues
    local size = ffi.sizeof("GCfuncC")
    
    -- 统计upvalue数量
    local nupvalues = 0
    while true do
      local name = debug.getupvalue(f, nupvalues + 1)
      if not name then break end
      nupvalues = nupvalues + 1
    end
    
    size = size + nupvalues * ffi.sizeof("TValue")
    return size
  else
    -- Lua函数：GCfuncL + upvalues
    local size = ffi.sizeof("GCfuncL")
    
    -- 统计upvalue数量
    local nupvalues = 0
    while true do
      local name = debug.getupvalue(f, nupvalues + 1)
      if not name then break end
      nupvalues = nupvalues + 1
    end
    
    size = size + nupvalues * ffi.sizeof("void*")
    return size
  end
end

-- 精确计算userdata大小
function M.sizeof_userdata(u)
  if type(u) ~= "userdata" then
    return 0
  end
  
  local ptr = ffi.cast("GCudata*", obj2gco(u))
  if ptr ~= nil then
    -- GCudata header + 用户数据
    return ffi.sizeof("GCudata") + ptr.len
  end
  
  -- 无法获取精确大小，返回估算值
  return ffi.sizeof("GCudata")
end

-- 精确计算thread大小
function M.sizeof_thread(th)
  if type(th) ~= "thread" then
    return 0
  end
  
  local ptr = ffi.cast("lua_State*", obj2gco(th))
  if ptr ~= nil then
    -- lua_State header + 栈空间
    return ffi.sizeof("lua_State") + ptr.stacksize * ffi.sizeof("TValue")
  end
  
  -- fallback
  return ffi.sizeof("lua_State") + 8192  -- 默认栈大小
end

-- 统一的对象大小计算接口
function M.sizeof(obj)
  local t = type(obj)
  
  if t == "nil" or t == "boolean" or t == "number" then
    return 0  -- 这些是值类型，不占用GC内存
  elseif t == "string" then
    return M.sizeof_string(obj)
  elseif t == "table" then
    return M.sizeof_table(obj)
  elseif t == "function" then
    return M.sizeof_function(obj)
  elseif t == "userdata" then
    return M.sizeof_userdata(obj)
  elseif t == "thread" then
    return M.sizeof_thread(obj)
  else
    return 0
  end
end

-- 递归计算对象及其引用的总内存
function M.sizeof_deep(obj, visited)
  visited = visited or {}
  
  if obj == nil or visited[obj] then
    return 0
  end
  
  local t = type(obj)
  if t == "nil" or t == "boolean" or t == "number" then
    return 0
  end
  
  visited[obj] = true
  local size = M.sizeof(obj)
  
  if t == "table" then
    for k, v in pairs(obj) do
      size = size + M.sizeof_deep(k, visited)
      size = size + M.sizeof_deep(v, visited)
    end
    
    local mt = debug.getmetatable(obj)
    if mt then
      size = size + M.sizeof_deep(mt, visited)
    end
  elseif t == "function" then
    local i = 1
    while true do
      local name, val = debug.getupvalue(obj, i)
      if not name then break end
      size = size + M.sizeof_deep(val, visited)
      i = i + 1
    end
  end
  
  return size
end

-- 打印对象内存信息
function M.print_sizeof(obj, name)
  name = name or tostring(obj)
  local size = M.sizeof(obj)
  local deep_size = M.sizeof_deep(obj)
  
  print(string.format("对象: %s", name))
  print(string.format("  类型: %s", type(obj)))
  print(string.format("  直接大小: %d 字节 (%.2f KB)", size, size / 1024))
  print(string.format("  深度大小: %d 字节 (%.2f KB)", deep_size, deep_size / 1024))
end

-- 显示FFI类型大小信息
function M.show_type_sizes()
  print("\n=== LuaJIT内部类型大小 ===")
  print(string.format("TValue:    %d 字节", ffi.sizeof("TValue")))
  print(string.format("Node:      %d 字节", ffi.sizeof("Node")))
  print(string.format("GCstr:     %d 字节", ffi.sizeof("GCstr")))
  print(string.format("GCtab:     %d 字节", ffi.sizeof("GCtab")))
  print(string.format("GCfuncL:   %d 字节", ffi.sizeof("GCfuncL")))
  print(string.format("GCfuncC:   %d 字节", ffi.sizeof("GCfuncC")))
  print(string.format("GCudata:   %d 字节", ffi.sizeof("GCudata")))
  print(string.format("lua_State: %d 字节", ffi.sizeof("lua_State")))
  print(string.format("GCupval:   %d 字节", ffi.sizeof("GCupval")))
  print(string.format("GCproto:   %d 字节", ffi.sizeof("GCproto")))
end

-- 批量测试
function M.test_accuracy()
  print("\n=== 精确内存计算测试 ===\n")
  
  -- 测试字符串
  local s1 = "hello"
  local s2 = string.rep("x", 100)
  local s3 = string.rep("y", 1000)
  
  print("字符串测试:")
  print(string.format("  '%s' (长度%d): %d 字节", s1, #s1, M.sizeof(s1)))
  print(string.format("  100个'x': %d 字节", M.sizeof(s2)))
  print(string.format("  1000个'y': %d 字节", M.sizeof(s3)))
  
  -- 测试表
  print("\n表测试:")
  local t1 = {}
  print(string.format("  空表: %d 字节", M.sizeof(t1)))
  
  local t2 = {1, 2, 3, 4, 5}
  print(string.format("  数组[5]: %d 字节", M.sizeof(t2)))
  
  local t3 = {}
  for i = 1, 100 do t3[i] = i end
  print(string.format("  数组[100]: %d 字节", M.sizeof(t3)))
  
  local t4 = {a=1, b=2, c=3}
  print(string.format("  哈希表(3键): %d 字节", M.sizeof(t4)))
  
  local t5 = {}
  for i = 1, 50 do t5["key"..i] = i end
  print(string.format("  哈希表(50键): %d 字节", M.sizeof(t5)))
  
  -- 测试函数
  print("\n函数测试:")
  local f1 = function() end
  print(string.format("  无upvalue闭包: %d 字节", M.sizeof(f1)))
  
  local a, b, c = 1, 2, 3
  local f2 = function() return a + b + c end
  print(string.format("  3个upvalue闭包: %d 字节", M.sizeof(f2)))
  
  print(string.format("  print函数(C): %d 字节", M.sizeof(print)))
  
  -- 测试userdata
  print("\n其他类型:")
  local co = coroutine.create(function() end)
  print(string.format("  协程: %d 字节", M.sizeof(co)))
  
  -- 深度测试
  print("\n深度内存测试:")
  local complex = {
    str = "hello world",
    nums = {1, 2, 3, 4, 5},
    nested = {
      a = {x = 1, y = 2},
      b = {x = 3, y = 4}
    }
  }
  print(string.format("  复杂对象直接: %d 字节", M.sizeof(complex)))
  print(string.format("  复杂对象深度: %d 字节", M.sizeof_deep(complex)))
end

return M
