# LuaJIT2 对象内存占用统计详尽方法

## 目录
1. [LuaJIT2 内存管理概述](#概述)
2. [LuaJIT2 数据结构分析](#数据结构)
3. [内存统计方法](#统计方法)
4. [实现方案](#实现方案)
5. [实践示例](#示例代码)

---

## 1. LuaJIT2 内存管理概述 {#概述}

### 1.1 内存分配器

LuaJIT2 使用自定义的内存分配器，主要组件：
- **lua_Alloc**: 内存分配函数指针
- **lj_alloc.c**: 内存分配器实现
- **lj_mem.h**: 内存管理宏定义

### 1.2 内存区域

LuaJIT2 的内存主要分为：
1. **GCobj**: 垃圾回收对象（字符串、表、函数、userdata等）
2. **Stack**: Lua栈内存
3. **Global State**: 全局状态内存
4. **JIT Code**: JIT编译后的机器码

---

## 2. LuaJIT2 数据结构分析 {#数据结构}

### 2.1 GCobj 结构（src/lj_obj.h）

```c
/* GC对象头部 */
typedef struct GChead {
  GCRef nextgc;    /* 下一个GC对象 */
  uint8_t marked;  /* GC标记位 */
  uint8_t gct;     /* GC对象类型 */
} GChead;
```

### 2.2 对象类型及大小计算

#### 2.2.1 字符串 (GCstr)
```c
/* src/lj_obj.h */
typedef struct GCstr {
  GCHeader;
  uint8_t reserved;  /* 保留字段 */
  uint8_t hashlg;    /* 哈希长度的log2 */
  uint32_t len;      /* 字符串长度 */
  /* 字符数据紧随其后 */
} GCstr;

// 内存大小计算:
// sizeof(GCstr) + len + 1  (包含终止符'\0')
```

#### 2.2.2 表 (GCtab)
```c
/* src/lj_obj.h */
typedef struct GCtab {
  GCHeader;
  uint8_t nomm;      /* 没有元方法的标记 */
  int8_t colo;       /* 协同遍历标记 */
  MRef array;        /* 数组部分 */
  GCRef gclist;      /* GC列表 */
  GCRef metatable;   /* 元表 */
  MRef node;         /* 哈希部分 */
  uint32_t asize;    /* 数组部分大小 */
  uint32_t hmask;    /* 哈希掩码 (2^k - 1) */
} GCtab;

// 内存大小计算:
// sizeof(GCtab) + 
// asize * sizeof(TValue) +           // 数组部分
// (hmask + 1) * sizeof(Node)         // 哈希部分
```

#### 2.2.3 函数 (GCfunc)
```c
/* Lua闭包 */
typedef struct GCfuncL {
  GCHeader;
  uint8_t ffid;
  uint8_t nupvalues;
  GCRef gclist;
  GCRef env;
  GCRef pc;
  /* upvalues数组紧随其后 */
} GCfuncL;

// 内存大小: sizeof(GCfuncL) + nupvalues * sizeof(GCRef)
```

#### 2.2.4 Userdata (GCudata)
```c
typedef struct GCudata {
  GCHeader;
  uint8_t udtype;    /* userdata类型 */
  uint8_t align1;
  GCRef env;
  MSize len;         /* userdata大小 */
  GCRef metatable;
  /* 用户数据紧随其后 */
} GCudata;

// 内存大小: sizeof(GCudata) + len
```

#### 2.2.5 线程 (lua_State)
```c
typedef struct lua_State {
  GCHeader;
  uint8_t dummy_ffid;
  uint8_t status;
  MRef glref;        /* global_State引用 */
  GCRef gclist;
  TValue *base;      /* 栈基址 */
  TValue *top;       /* 栈顶 */
  TValue *maxstack;  /* 栈最大地址 */
  MRef stack;        /* 栈起始地址 */
  GCRef openupval;   /* 打开的upvalue链表 */
  GCRef env;
  // ... 更多字段
} lua_State;

// 内存大小: sizeof(lua_State) + stacksize * sizeof(TValue)
```

---

## 3. 内存统计方法 {#统计方法}

### 3.1 基于GC遍历的方法

LuaJIT2的GC维护了所有可回收对象的链表，通过遍历GC链表可以统计所有对象：

```c
/* src/lj_gc.h */
#define GC_SWEEPSTR  0  /* 正在扫描字符串 */
#define GC_SWEEP     1  /* 正在扫描其他对象 */
#define GC_FINALIZE  2  /* 正在执行finalizer */
#define GC_PAUSE     3  /* GC暂停状态 */
```

### 3.2 遍历策略

#### 3.2.1 遍历全局状态的GC链表
```c
global_State *g = G(L);
GCobj *o = gcref(g->gc.root);
while (o != NULL) {
  // 根据对象类型计算大小
  o = gcnext(o);
}
```

#### 3.2.2 按类型分类统计
```c
/* 对象类型枚举 (src/lj_obj.h) */
#define LJ_TSTR      (~4u)   /* 字符串 */
#define LJ_TUPVAL    (~5u)   /* upvalue */
#define LJ_TTHREAD   (~6u)   /* 线程 */
#define LJ_TPROTO    (~7u)   /* 函数原型 */
#define LJ_TFUNC     (~8u)   /* 函数 */
#define LJ_TTRACE    (~9u)   /* trace */
#define LJ_TCDATA    (~10u)  /* cdata */
#define LJ_TTAB      (~11u)  /* 表 */
#define LJ_TUDATA    (~12u)  /* userdata */
```

### 3.3 内存大小计算公式

对于不同类型的对象，内存大小计算如下：

```c
size_t lj_gc_objsize(GCobj *o) {
  switch (o->gch.gct) {
    case ~LJ_TSTR:
      return sizemulxor(sizeof(GCstr), gco2str(o)->len);
    case ~LJ_TTAB: {
      GCtab *t = gco2tab(o);
      return sizeof(GCtab) + 
             sizeof(TValue) * t->asize + 
             sizeof(Node) * (t->hmask + 1);
    }
    case ~LJ_TUDATA:
      return sizeudata(gco2ud(o));
    case ~LJ_TFUNC: {
      GCfunc *fn = gco2func(o);
      return isluafunc(fn) ? 
        sizeLfunc((GCfuncL *)fn) : sizeCfunc((GCfuncC *)fn);
    }
    case ~LJ_TTHREAD:
      return sizeof(lua_State) + sizeof(TValue) * gco2th(o)->stacksize;
    case ~LJ_TPROTO:
      return sizeof(GCproto) + /* ... 原型数据大小 */;
    case ~LJ_TUPVAL:
      return sizeof(GCupval);
    case ~LJ_TCDATA:
      return sizecdataof(gco2cd(o));
    default:
      return 0;
  }
}
```

---

## 4. 实现方案 {#实现方案}

### 4.1 方案一：使用lua_getcount扩展

**优点**: 深度集成LuaJIT内部
**缺点**: 需要修改LuaJIT源码

```c
/* 在lj_api.c中添加 */
LUA_API size_t lua_getmeminfo(lua_State *L, lua_MemInfo *info) {
  global_State *g = G(L);
  GCobj *o;
  size_t total = 0;
  
  memset(info, 0, sizeof(lua_MemInfo));
  
  /* 遍历所有GC对象 */
  for (o = gcref(g->gc.root); o != NULL; o = gcnext(o)) {
    size_t sz = lj_gc_objsize(o);
    total += sz;
    
    switch (o->gch.gct) {
      case ~LJ_TSTR:   info->str_mem += sz; info->str_count++; break;
      case ~LJ_TTAB:   info->tab_mem += sz; info->tab_count++; break;
      case ~LJ_TUDATA: info->udata_mem += sz; info->udata_count++; break;
      case ~LJ_TFUNC:  info->func_mem += sz; info->func_count++; break;
      case ~LJ_TTHREAD: info->thread_mem += sz; info->thread_count++; break;
      // ... 其他类型
    }
  }
  
  info->total_mem = total;
  return total;
}
```

### 4.2 方案二：通过Lua API实现

**优点**: 不需要修改LuaJIT源码
**缺点**: 精度较低，只能统计可访问对象

```lua
-- 使用debug库递归遍历
local function get_object_size(obj, visited)
  if visited[obj] then return 0 end
  visited[obj] = true
  
  local size = 0
  local t = type(obj)
  
  if t == "string" then
    size = #obj + 24  -- 字符串头部 + 数据
  elseif t == "table" then
    size = 40  -- 表头部
    for k, v in pairs(obj) do
      size = size + get_object_size(k, visited)
      size = size + get_object_size(v, visited)
      size = size + 32  -- Node大小
    end
  elseif t == "function" then
    size = 40  -- 函数基础大小
    -- 统计upvalue
    local i = 1
    while true do
      local name, val = debug.getupvalue(obj, i)
      if not name then break end
      size = size + get_object_size(val, visited)
      i = i + 1
    end
  elseif t == "userdata" then
    -- userdata大小需要通过FFI获取
    size = 48  -- 基础大小估计
  elseif t == "thread" then
    size = 200  -- 协程基础大小估计
  end
  
  return size
end
```

### 4.3 方案三：使用collectgarbage和FFI

最实用的方案，结合LuaJIT的FFI功能：

```lua
local ffi = require("ffi")

ffi.cdef[[
  typedef struct lua_State lua_State;
  
  size_t lua_gc(lua_State *L, int what, int data);
  
  // 定义GC常量
  enum {
    LUA_GCSTOP = 0,
    LUA_GCRESTART = 1,
    LUA_GCCOLLECT = 2,
    LUA_GCCOUNT = 3,
    LUA_GCCOUNTB = 4,
    LUA_GCSTEP = 5,
    LUA_GCSETPAUSE = 6,
    LUA_GCSETSTEPMUL = 7
  };
]]

-- 获取内存使用量（KB）
local function get_lua_memory()
  return collectgarbage("count")
end

-- 详细内存统计
local function memory_snapshot()
  local before = collectgarbage("count")
  collectgarbage("collect")
  local after = collectgarbage("count")
  
  return {
    used_kb = after,
    garbage_kb = before - after,
    total_kb = before
  }
end
```

### 4.4 方案四：内存分配器Hook

通过替换内存分配器来追踪所有内存分配：

```c
/* 自定义内存分配器 */
typedef struct MemStats {
  size_t total_alloc;
  size_t total_free;
  size_t current_usage;
  size_t peak_usage;
  size_t alloc_count;
  size_t free_count;
} MemStats;

static MemStats g_mem_stats = {0};

void *tracking_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
  MemStats *stats = (MemStats *)ud;
  
  if (nsize == 0) {
    /* 释放内存 */
    free(ptr);
    stats->current_usage -= osize;
    stats->total_free += osize;
    stats->free_count++;
    return NULL;
  } else if (ptr == NULL) {
    /* 分配新内存 */
    void *newptr = malloc(nsize);
    if (newptr) {
      stats->total_alloc += nsize;
      stats->current_usage += nsize;
      stats->alloc_count++;
      if (stats->current_usage > stats->peak_usage) {
        stats->peak_usage = stats->current_usage;
      }
    }
    return newptr;
  } else {
    /* 重新分配 */
    void *newptr = realloc(ptr, nsize);
    if (newptr) {
      stats->current_usage = stats->current_usage - osize + nsize;
      stats->total_alloc += (nsize > osize) ? (nsize - osize) : 0;
      stats->total_free += (osize > nsize) ? (osize - nsize) : 0;
      if (stats->current_usage > stats->peak_usage) {
        stats->peak_usage = stats->current_usage;
      }
    }
    return newptr;
  }
}

/* 创建带追踪的Lua状态 */
lua_State *L = lua_newstate(tracking_alloc, &g_mem_stats);
```

---

## 5. 实践示例 {#示例代码}

### 5.1 完整的Lua内存分析器

```lua
local M = {}

-- 内存统计结构
local MemStats = {
  strings = {count = 0, bytes = 0},
  tables = {count = 0, bytes = 0},
  functions = {count = 0, bytes = 0},
  userdata = {count = 0, bytes = 0},
  threads = {count = 0, bytes = 0},
  others = {count = 0, bytes = 0}
}

-- 估算字符串大小
local function sizeof_string(s)
  return 24 + #s  -- GCstr header + 字符数据
end

-- 估算表大小
local function sizeof_table(t, visited)
  if visited[t] then return 0 end
  visited[t] = true
  
  local size = 40  -- GCtab基础大小
  local array_size = 0
  local hash_size = 0
  
  -- 统计数组部分
  for i = 1, 10000 do
    if t[i] ~= nil then
      array_size = i
    else
      break
    end
  end
  size = size + array_size * 16  -- TValue大小
  
  -- 统计哈希部分
  for k, v in pairs(t) do
    if type(k) ~= "number" or k > array_size or k < 1 then
      hash_size = hash_size + 1
      size = size + 32  -- Node大小
    end
  end
  
  return size
end

-- 估算函数大小
local function sizeof_function(f)
  local size = 40  -- GCfunc基础大小
  local i = 1
  while true do
    local name = debug.getupvalue(f, i)
    if not name then break end
    size = size + 16  -- upvalue大小
    i = i + 1
  end
  return size
end

-- 遍历所有对象
function M.analyze_memory()
  local visited = {}
  local stats = {
    strings = {count = 0, bytes = 0},
    tables = {count = 0, bytes = 0},
    functions = {count = 0, bytes = 0},
    userdata = {count = 0, bytes = 0},
    threads = {count = 0, bytes = 0}
  }
  
  -- 遍历_G
  local function traverse(obj)
    if visited[obj] then return end
    local t = type(obj)
    
    if t == "string" then
      stats.strings.count = stats.strings.count + 1
      stats.strings.bytes = stats.strings.bytes + sizeof_string(obj)
      visited[obj] = true
    elseif t == "table" then
      stats.tables.count = stats.tables.count + 1
      stats.tables.bytes = stats.tables.bytes + sizeof_table(obj, visited)
      for k, v in pairs(obj) do
        traverse(k)
        traverse(v)
      end
    elseif t == "function" then
      if not visited[obj] then
        stats.functions.count = stats.functions.count + 1
        stats.functions.bytes = stats.functions.bytes + sizeof_function(obj)
        visited[obj] = true
      end
    elseif t == "userdata" then
      if not visited[obj] then
        stats.userdata.count = stats.userdata.count + 1
        stats.userdata.bytes = stats.userdata.bytes + 48
        visited[obj] = true
      end
    elseif t == "thread" then
      if not visited[obj] then
        stats.threads.count = stats.threads.count + 1
        stats.threads.bytes = stats.threads.bytes + 200
        visited[obj] = true
      end
    end
  end
  
  traverse(_G)
  
  -- 添加总内存信息
  stats.total_bytes = 0
  stats.total_count = 0
  for _, v in pairs(stats) do
    if type(v) == "table" and v.bytes then
      stats.total_bytes = stats.total_bytes + v.bytes
      stats.total_count = stats.total_count + v.count
    end
  end
  
  stats.gc_memory_kb = collectgarbage("count")
  
  return stats
end

-- 格式化输出
function M.print_stats(stats)
  print("=== Lua内存统计 ===")
  print(string.format("字符串: %d个, %.2f KB", 
    stats.strings.count, stats.strings.bytes / 1024))
  print(string.format("表: %d个, %.2f KB", 
    stats.tables.count, stats.tables.bytes / 1024))
  print(string.format("函数: %d个, %.2f KB", 
    stats.functions.count, stats.functions.bytes / 1024))
  print(string.format("Userdata: %d个, %.2f KB", 
    stats.userdata.count, stats.userdata.bytes / 1024))
  print(string.format("线程: %d个, %.2f KB", 
    stats.threads.count, stats.threads.bytes / 1024))
  print(string.format("估算总计: %.2f KB", stats.total_bytes / 1024))
  print(string.format("GC报告: %.2f KB", stats.gc_memory_kb))
end

-- 监控内存变化
function M.memory_diff(func)
  collectgarbage("collect")
  local before = collectgarbage("count")
  
  func()
  
  collectgarbage("collect")
  local after = collectgarbage("count")
  
  return after - before
end

return M
```

### 5.2 使用示例

```lua
local mem = require("memory_analyzer")

-- 分析当前内存
local stats = mem.analyze_memory()
mem.print_stats(stats)

-- 监控函数内存使用
local diff = mem.memory_diff(function()
  local t = {}
  for i = 1, 10000 do
    t[i] = string.format("item_%d", i)
  end
end)
print(string.format("函数使用了 %.2f KB", diff))
```

### 5.3 C扩展实现（最精确）

```c
/* luamem.c - LuaJIT内存分析C模块 */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

/* LuaJIT内部头文件 */
#include "lj_obj.h"
#include "lj_gc.h"
#include "lj_state.h"

typedef struct {
  size_t str_mem, str_count;
  size_t tab_mem, tab_count;
  size_t func_mem, func_count;
  size_t udata_mem, udata_count;
  size_t thread_mem, thread_count;
  size_t proto_mem, proto_count;
  size_t trace_mem, trace_count;
  size_t cdata_mem, cdata_count;
  size_t total_mem;
} MemInfo;

static size_t gc_objsize(GCobj *o) {
  switch (o->gch.gct) {
    case ~LJ_TSTR: {
      GCstr *s = gco2str(o);
      return sizemulxor(sizeof(GCstr), s->len);
    }
    case ~LJ_TTAB: {
      GCtab *t = gco2tab(o);
      return sizeof(GCtab) + 
             sizeof(TValue) * t->asize + 
             sizeof(Node) * (t->hmask + 1);
    }
    case ~LJ_TFUNC: {
      GCfunc *fn = gco2func(o);
      return isluafunc(fn) ? 
        sizeLfunc((GCfuncL *)fn) : sizeCfunc((GCfuncC *)fn);
    }
    case ~LJ_TUDATA:
      return sizeudata(gco2ud(o));
    case ~LJ_TTHREAD:
      return sizeof(lua_State) + 
             sizeof(TValue) * gco2th(o)->stacksize;
    case ~LJ_TPROTO: {
      GCproto *pt = gco2pt(o);
      return sizeof(GCproto) + pt->sizept;
    }
    case ~LJ_TUPVAL:
      return sizeof(GCupval);
    case ~LJ_TCDATA:
      return sizecdataof(gco2cd(o));
    default:
      return 0;
  }
}

static int luamem_getinfo(lua_State *L) {
  global_State *g = G(L);
  MemInfo info = {0};
  GCobj *o;
  
  /* 遍历GC链表 */
  for (o = gcref(g->gc.root); o != NULL; o = gcnext(o)) {
    size_t sz = gc_objsize(o);
    info.total_mem += sz;
    
    switch (o->gch.gct) {
      case ~LJ_TSTR:
        info.str_mem += sz; info.str_count++; break;
      case ~LJ_TTAB:
        info.tab_mem += sz; info.tab_count++; break;
      case ~LJ_TFUNC:
        info.func_mem += sz; info.func_count++; break;
      case ~LJ_TUDATA:
        info.udata_mem += sz; info.udata_count++; break;
      case ~LJ_TTHREAD:
        info.thread_mem += sz; info.thread_count++; break;
      case ~LJ_TPROTO:
        info.proto_mem += sz; info.proto_count++; break;
      case ~LJ_TCDATA:
        info.cdata_mem += sz; info.cdata_count++; break;
    }
  }
  
  /* 返回结果表 */
  lua_createtable(L, 0, 20);
  
  lua_pushinteger(L, info.str_count);
  lua_setfield(L, -2, "str_count");
  lua_pushinteger(L, info.str_mem);
  lua_setfield(L, -2, "str_mem");
  
  lua_pushinteger(L, info.tab_count);
  lua_setfield(L, -2, "tab_count");
  lua_pushinteger(L, info.tab_mem);
  lua_setfield(L, -2, "tab_mem");
  
  lua_pushinteger(L, info.func_count);
  lua_setfield(L, -2, "func_count");
  lua_pushinteger(L, info.func_mem);
  lua_setfield(L, -2, "func_mem");
  
  lua_pushinteger(L, info.udata_count);
  lua_setfield(L, -2, "udata_count");
  lua_pushinteger(L, info.udata_mem);
  lua_setfield(L, -2, "udata_mem");
  
  lua_pushinteger(L, info.thread_count);
  lua_setfield(L, -2, "thread_count");
  lua_pushinteger(L, info.thread_mem);
  lua_setfield(L, -2, "thread_mem");
  
  lua_pushinteger(L, info.total_mem);
  lua_setfield(L, -2, "total_mem");
  
  return 1;
}

static const luaL_Reg luamem_funcs[] = {
  {"getinfo", luamem_getinfo},
  {NULL, NULL}
};

LUALIB_API int luaopen_luamem(lua_State *L) {
  luaL_register(L, "luamem", luamem_funcs);
  return 1;
}
```

编译命令：
```bash
gcc -shared -fPIC -o luamem.so luamem.c -I/path/to/luajit/src -lluajit
```

使用：
```lua
local luamem = require("luamem")
local info = luamem.getinfo()

print(string.format("字符串: %d个, %d字节", info.str_count, info.str_mem))
print(string.format("表: %d个, %d字节", info.tab_count, info.tab_mem))
print(string.format("总计: %d字节", info.total_mem))
```

---

## 6. 关键源码文件

### 6.1 核心文件
- `src/lj_obj.h` - 对象定义和宏
- `src/lj_gc.h` - GC接口
- `src/lj_gc.c` - GC实现
- `src/lj_tab.c` - 表操作
- `src/lj_str.c` - 字符串操作
- `src/lj_alloc.c` - 内存分配器
- `src/lj_state.c` - 状态管理

### 6.2 重要宏定义

```c
/* 对象大小计算宏 (lj_obj.h) */
#define sizemulxor(s,l)  ((s) + (((l)+1) & ~(sizeof(void*)-1)))
#define sizeudata(u)     (sizeof(GCudata) + (u)->len)
#define sizeLfunc(n)     (sizeof(GCfuncL) + sizeof(GCRef)*((n)->nupvalues))
```

---

## 7. 最佳实践建议

### 7.1 生产环境监控

```lua
-- 定期采样
local function memory_monitor()
  local samples = {}
  local interval = 60  -- 60秒采样一次
  
  while true do
    local mem_kb = collectgarbage("count")
    table.insert(samples, {
      time = os.time(),
      memory = mem_kb
    })
    
    -- 检测内存泄漏
    if #samples > 10 then
      local growth = samples[#samples].memory - samples[1].memory
      if growth > 10000 then  -- 增长超过10MB
        print("警告: 检测到可能的内存泄漏")
      end
      table.remove(samples, 1)
    end
    
    -- 等待
    local sock = require("socket")
    sock.sleep(interval)
  end
end
```

### 7.2 性能考虑

1. **避免频繁GC**: 内存统计会触发GC，影响性能
2. **增量统计**: 大型应用应分批统计
3. **缓存结果**: 相同对象避免重复计算
4. **使用C扩展**: 精确统计用C实现

### 7.3 调试技巧

```lua
-- 查找大对象
local function find_large_objects(threshold)
  local large_objs = {}
  
  for k, v in pairs(_G) do
    if type(v) == "table" then
      local size = sizeof_table(v, {})
      if size > threshold then
        table.insert(large_objs, {
          name = k,
          type = "table",
          size = size
        })
      end
    end
  end
  
  table.sort(large_objs, function(a, b) 
    return a.size > b.size 
  end)
  
  return large_objs
end

-- 使用
local large = find_large_objects(1024 * 100)  -- 大于100KB
for _, obj in ipairs(large) do
  print(string.format("%s: %.2f KB", obj.name, obj.size / 1024))
end
```

---

## 8. 总结

统计LuaJIT2对象内存占用有以下几种方法：

1. **简单方法**: 使用`collectgarbage("count")`获取总内存
2. **Lua实现**: 通过debug库递归遍历（精度较低）
3. **FFI方法**: 使用FFI调用Lua C API（中等精度）
4. **C扩展**: 直接访问LuaJIT内部结构（最精确）
5. **分配器Hook**: 替换内存分配器追踪所有分配

选择方法时需要权衡：
- **精度** vs **实现复杂度**
- **性能开销** vs **信息详细度**
- **可移植性** vs **深度集成**

对于大多数应用，**方案三（FFI + collectgarbage）** 是最佳平衡点。
对于需要精确统计的场景，建议使用**方案四（C扩展）**。

---

## 参考资料

- [LuaJIT官方网站](https://luajit.org/)
- [LuaJIT源码](https://github.com/LuaJIT/LuaJIT)
- [Lua 5.1参考手册](https://www.lua.org/manual/5.1/)
- `src/lj_obj.h` - 对象结构定义
- `src/lj_gc.c` - 垃圾回收实现
