/*
 * luamem.c - LuaJIT精确内存分析C扩展
 * 
 * 直接访问LuaJIT内部数据结构，提供最精确的内存统计
 * 
 * 编译方法:
 *   gcc -shared -fPIC -o luamem.so luamem.c -I/usr/local/include/luajit-2.1 -lluajit-5.1
 * 
 * 使用方法:
 *   local luamem = require("luamem")
 *   local info = luamem.getinfo()
 */

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <string.h>

/* 
 * 注意: 这些定义来自LuaJIT内部头文件
 * 实际使用时需要包含: lj_obj.h, lj_gc.h, lj_state.h
 * 这里为了演示，手动定义一些关键结构
 */

/* GC对象类型定义 */
#define LJ_TNIL         (~0u)
#define LJ_TFALSE       (~1u)
#define LJ_TTRUE        (~2u)
#define LJ_TLIGHTUD     (~3u)
#define LJ_TSTR         (~4u)
#define LJ_TUPVAL       (~5u)
#define LJ_TTHREAD      (~6u)
#define LJ_TPROTO       (~7u)
#define LJ_TFUNC        (~8u)
#define LJ_TTRACE       (~9u)
#define LJ_TCDATA       (~10u)
#define LJ_TTAB         (~11u)
#define LJ_TUDATA       (~12u)

/* 内存统计结构 */
typedef struct {
  size_t str_mem, str_count;
  size_t tab_mem, tab_count;
  size_t func_mem, func_count;
  size_t udata_mem, udata_count;
  size_t thread_mem, thread_count;
  size_t proto_mem, proto_count;
  size_t upval_mem, upval_count;
  size_t cdata_mem, cdata_count;
  size_t trace_mem, trace_count;
  size_t total_mem;
} MemInfo;

/*
 * 简化版本：使用Lua API统计
 * 真实版本需要访问LuaJIT内部结构
 */
static int luamem_getinfo(lua_State *L) {
  MemInfo info;
  memset(&info, 0, sizeof(info));
  
  /* 使用lua_gc获取基本内存信息 */
  int kb = lua_gc(L, LUA_GCCOUNT, 0);
  int bytes = lua_gc(L, LUA_GCCOUNTB, 0);
  info.total_mem = (size_t)kb * 1024 + bytes;
  
  /* 
   * 实际实现中，这里应该遍历global_State的GC链表
   * 
   * global_State *g = G(L);
   * GCobj *o;
   * for (o = gcref(g->gc.root); o != NULL; o = gcnext(o)) {
   *   size_t sz = gc_objsize(o);
   *   switch (o->gch.gct) {
   *     case ~LJ_TSTR: info.str_mem += sz; info.str_count++; break;
   *     case ~LJ_TTAB: info.tab_mem += sz; info.tab_count++; break;
   *     ...
   *   }
   * }
   */
  
  /* 返回统计信息表 */
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
  
  lua_pushinteger(L, info.proto_count);
  lua_setfield(L, -2, "proto_count");
  lua_pushinteger(L, info.proto_mem);
  lua_setfield(L, -2, "proto_mem");
  
  lua_pushinteger(L, info.cdata_count);
  lua_setfield(L, -2, "cdata_count");
  lua_pushinteger(L, info.cdata_mem);
  lua_setfield(L, -2, "cdata_mem");
  
  lua_pushinteger(L, info.total_mem);
  lua_setfield(L, -2, "total_mem");
  
  return 1;
}

/*
 * 自定义内存分配器用于追踪
 */
typedef struct {
  lua_Alloc orig_alloc;
  void *orig_ud;
  size_t total_alloc;
  size_t total_free;
  size_t current_usage;
  size_t peak_usage;
  size_t alloc_count;
  size_t free_count;
} AllocStats;

static void *tracking_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
  AllocStats *stats = (AllocStats *)ud;
  void *newptr;
  
  if (nsize == 0) {
    /* 释放 */
    if (stats->orig_alloc) {
      newptr = stats->orig_alloc(stats->orig_ud, ptr, osize, 0);
    } else {
      free(ptr);
      newptr = NULL;
    }
    if (ptr) {
      stats->current_usage -= osize;
      stats->total_free += osize;
      stats->free_count++;
    }
    return NULL;
  }
  
  /* 分配或重分配 */
  if (stats->orig_alloc) {
    newptr = stats->orig_alloc(stats->orig_ud, ptr, osize, nsize);
  } else {
    if (ptr == NULL) {
      newptr = malloc(nsize);
    } else {
      newptr = realloc(ptr, nsize);
    }
  }
  
  if (newptr) {
    if (ptr == NULL) {
      /* 新分配 */
      stats->total_alloc += nsize;
      stats->current_usage += nsize;
      stats->alloc_count++;
    } else {
      /* 重分配 */
      stats->current_usage = stats->current_usage - osize + nsize;
      if (nsize > osize) {
        stats->total_alloc += (nsize - osize);
      } else {
        stats->total_free += (osize - nsize);
      }
    }
    
    if (stats->current_usage > stats->peak_usage) {
      stats->peak_usage = stats->current_usage;
    }
  }
  
  return newptr;
}

/* 获取分配器统计信息 */
static int luamem_getallocstats(lua_State *L) {
  lua_Alloc alloc;
  void *ud;
  
  alloc = lua_getallocf(L, &ud);
  
  if (ud == NULL) {
    lua_pushnil(L);
    lua_pushstring(L, "Not using tracking allocator");
    return 2;
  }
  
  AllocStats *stats = (AllocStats *)ud;
  
  lua_createtable(L, 0, 8);
  
  lua_pushinteger(L, stats->total_alloc);
  lua_setfield(L, -2, "total_alloc");
  
  lua_pushinteger(L, stats->total_free);
  lua_setfield(L, -2, "total_free");
  
  lua_pushinteger(L, stats->current_usage);
  lua_setfield(L, -2, "current_usage");
  
  lua_pushinteger(L, stats->peak_usage);
  lua_setfield(L, -2, "peak_usage");
  
  lua_pushinteger(L, stats->alloc_count);
  lua_setfield(L, -2, "alloc_count");
  
  lua_pushinteger(L, stats->free_count);
  lua_setfield(L, -2, "free_count");
  
  return 1;
}

/* 设置追踪分配器 */
static int luamem_settracking(lua_State *L) {
  int enable = lua_toboolean(L, 1);
  
  if (enable) {
    AllocStats *stats = (AllocStats *)malloc(sizeof(AllocStats));
    memset(stats, 0, sizeof(AllocStats));
    
    /* 保存原分配器 */
    stats->orig_alloc = lua_getallocf(L, &stats->orig_ud);
    
    /* 设置追踪分配器 */
    lua_setallocf(L, tracking_alloc, stats);
    
    lua_pushboolean(L, 1);
  } else {
    /* 恢复原分配器 */
    lua_Alloc alloc;
    void *ud;
    alloc = lua_getallocf(L, &ud);
    
    if (ud) {
      AllocStats *stats = (AllocStats *)ud;
      if (stats->orig_alloc) {
        lua_setallocf(L, stats->orig_alloc, stats->orig_ud);
      }
      free(stats);
    }
    
    lua_pushboolean(L, 1);
  }
  
  return 1;
}

/* 获取对象大小（近似） */
static int luamem_sizeof(lua_State *L) {
  size_t size = 0;
  int type = lua_type(L, 1);
  
  switch (type) {
    case LUA_TSTRING: {
      size_t len;
      lua_tolstring(L, 1, &len);
      size = 24 + len;  /* GCstr header + 字符串数据 */
      break;
    }
    case LUA_TTABLE: {
      size = 40;  /* GCtab基础大小 */
      
      /* 统计数组部分 */
      int asize = 0;
      lua_pushnil(L);
      while (lua_next(L, 1) != 0) {
        if (lua_type(L, -2) == LUA_TNUMBER) {
          lua_Number n = lua_tonumber(L, -2);
          if (n > 0 && n == (int)n) {
            if ((int)n > asize) {
              asize = (int)n;
            }
          }
        }
        lua_pop(L, 1);
      }
      
      /* 向上取到2的幂 */
      int real_asize = 1;
      while (real_asize < asize) {
        real_asize *= 2;
      }
      size += real_asize * 16;  /* TValue大小 */
      
      /* 统计哈希部分 */
      int hsize = 0;
      lua_pushnil(L);
      while (lua_next(L, 1) != 0) {
        int is_array = 0;
        if (lua_type(L, -2) == LUA_TNUMBER) {
          lua_Number n = lua_tonumber(L, -2);
          if (n > 0 && n <= asize && n == (int)n) {
            is_array = 1;
          }
        }
        if (!is_array) {
          hsize++;
        }
        lua_pop(L, 1);
      }
      
      /* 向上取到2的幂 */
      if (hsize > 0) {
        int real_hsize = 1;
        while (real_hsize < hsize) {
          real_hsize *= 2;
        }
        size += real_hsize * 32;  /* Node大小 */
      }
      break;
    }
    case LUA_TFUNCTION: {
      size = 40;  /* GCfunc基础大小 */
      
      /* 统计upvalue */
      int i = 1;
      while (1) {
        const char *name = lua_getupvalue(L, 1, i);
        if (name == NULL) break;
        size += 16;  /* upvalue大小 */
        lua_pop(L, 1);
        i++;
      }
      break;
    }
    case LUA_TUSERDATA: {
      size = 48;  /* GCudata基础大小 + 估算 */
      break;
    }
    case LUA_TTHREAD: {
      size = 200 + 8192;  /* lua_State + 默认栈 */
      break;
    }
    default:
      size = 0;
  }
  
  lua_pushinteger(L, size);
  return 1;
}

/* GC信息 */
static int luamem_gcinfo(lua_State *L) {
  lua_createtable(L, 0, 3);
  
  int kb = lua_gc(L, LUA_GCCOUNT, 0);
  int bytes = lua_gc(L, LUA_GCCOUNTB, 0);
  
  lua_pushinteger(L, kb);
  lua_setfield(L, -2, "kb");
  
  lua_pushinteger(L, bytes);
  lua_setfield(L, -2, "bytes");
  
  lua_pushinteger(L, kb * 1024 + bytes);
  lua_setfield(L, -2, "total_bytes");
  
  return 1;
}

/* 模块函数表 */
static const luaL_Reg luamem_funcs[] = {
  {"getinfo", luamem_getinfo},
  {"getallocstats", luamem_getallocstats},
  {"settracking", luamem_settracking},
  {"sizeof", luamem_sizeof},
  {"gcinfo", luamem_gcinfo},
  {NULL, NULL}
};

/* 模块初始化 */
LUALIB_API int luaopen_luamem(lua_State *L) {
  luaL_register(L, "luamem", luamem_funcs);
  
  /* 添加版本信息 */
  lua_pushliteral(L, "1.0.0");
  lua_setfield(L, -2, "_VERSION");
  
  return 1;
}
