#!/usr/bin/env lua
-- 使用 collectgarbage 分析对象内存大小的示例

-- 辅助函数：获取当前内存使用量（KB）
local function getMemory()
    return collectgarbage("count")
end

-- 辅助函数：计算对象的内存大小
local function getObjectSize(createFunc)
    -- 强制垃圾回收，清理之前的垃圾
    collectgarbage("collect")
    collectgarbage("collect")  -- 调用两次确保完全清理
    
    -- 记录创建对象前的内存
    local memBefore = getMemory()
    
    -- 创建对象
    local obj = createFunc()
    
    -- 记录创建对象后的内存
    local memAfter = getMemory()
    
    -- 计算内存差值
    local memUsed = memAfter - memBefore
    
    return memUsed, obj
end

-- 示例1：测量字符串的内存大小
print("=== 示例1：测量字符串内存 ===")
local size1, str1 = getObjectSize(function()
    return string.rep("a", 1000)  -- 创建1000个字符的字符串
end)
print(string.format("1000个字符的字符串占用: %.2f KB", size1))

-- 示例2：测量表的内存大小
print("\n=== 示例2：测量表内存 ===")
local size2, table1 = getObjectSize(function()
    local t = {}
    for i = 1, 1000 do
        t[i] = i
    end
    return t
end)
print(string.format("包含1000个整数的表占用: %.2f KB", size2))

-- 示例3：测量复杂对象的内存大小
print("\n=== 示例3：测量复杂对象内存 ===")
local size3, obj3 = getObjectSize(function()
    local t = {}
    for i = 1, 100 do
        t[i] = {
            id = i,
            name = "对象" .. i,
            data = string.rep("x", 100),
            nested = {a = 1, b = 2, c = 3}
        }
    end
    return t
end)
print(string.format("包含100个复杂对象的表占用: %.2f KB", size3))

-- 示例4：监控内存变化
print("\n=== 示例4：监控内存变化 ===")
collectgarbage("collect")
collectgarbage("collect")

print(string.format("初始内存: %.2f KB", getMemory()))

-- 创建一些对象
local bigTable = {}
for i = 1, 10000 do
    bigTable[i] = {id = i, data = string.rep("test", 10)}
end
print(string.format("创建对象后内存: %.2f KB", getMemory()))

-- 清空引用
bigTable = nil

-- 手动触发垃圾回收前
print(string.format("清空引用后（回收前）: %.2f KB", getMemory()))

-- 手动触发垃圾回收
collectgarbage("collect")
print(string.format("垃圾回收后: %.2f KB", getMemory()))

-- 示例5：使用 collectgarbage 的不同参数
print("\n=== 示例5：collectgarbage 函数的其他用法 ===")
print(string.format("当前内存使用: %.2f KB", collectgarbage("count")))
print(string.format("垃圾回收器状态: %s", collectgarbage("isrunning") and "运行中" or "已停止"))

-- 获取垃圾回收器的步进倍率
collectgarbage("setpause", 200)  -- 设置暂停值为200%
collectgarbage("setstepmul", 200)  -- 设置步进倍率为200%
print("已设置垃圾回收器参数")

-- 示例6：精确测量单个对象
print("\n=== 示例6：精确测量单个对象 ===")
local function measureSingleObject(obj)
    collectgarbage("stop")  -- 停止自动垃圾回收
    collectgarbage("collect")
    collectgarbage("collect")
    
    local before = collectgarbage("count")
    local test = obj
    local after = collectgarbage("count")
    
    collectgarbage("restart")  -- 重启垃圾回收
    
    return after - before
end

-- 测量不同类型的对象
local testString = string.rep("Hello", 1000)
local testTable = {a = 1, b = 2, c = 3, d = 4, e = 5}
local testNumber = 123456789

print(string.format("字符串对象: %.4f KB", measureSingleObject(testString)))
print(string.format("表对象: %.4f KB", measureSingleObject(testTable)))

print("\n=== collectgarbage 常用命令 ===")
print("collectgarbage('collect')  -- 执行完整的垃圾回收循环")
print("collectgarbage('count')    -- 返回 Lua 使用的内存量（KB）")
print("collectgarbage('stop')     -- 停止垃圾回收器")
print("collectgarbage('restart')  -- 重启垃圾回收器")
print("collectgarbage('step')     -- 执行一步垃圾回收")
print("collectgarbage('isrunning')-- 返回回收器是否在运行")
print("collectgarbage('setpause') -- 设置回收器暂停参数")
print("collectgarbage('setstepmul')-- 设置回收器步进倍率")
