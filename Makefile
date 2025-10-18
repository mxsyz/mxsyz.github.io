# Makefile for luamem C extension

# 编译器设置
CC = gcc
CFLAGS = -Wall -O2 -fPIC -shared
LDFLAGS = 

# LuaJIT路径（根据实际安装路径修改）
LUAJIT_INC = /usr/local/include/luajit-2.1
LUAJIT_LIB = /usr/local/lib

# 如果LuaJIT在系统路径中
# LUAJIT_INC = $(shell pkg-config --cflags luajit)
# LUAJIT_LIB = $(shell pkg-config --libs luajit)

# 目标文件
TARGET = luamem.so
SOURCE = luamem.c

# 编译规则
all: $(TARGET)

$(TARGET): $(SOURCE)
	$(CC) $(CFLAGS) -I$(LUAJIT_INC) -L$(LUAJIT_LIB) -o $(TARGET) $(SOURCE) -lluajit-5.1

# 清理
clean:
	rm -f $(TARGET) *.o

# 安装（可选）
install: $(TARGET)
	@echo "Installing to system lua path..."
	@LUA_PATH=$$(luajit -e "print(package.cpath:match('([^;]+)'))") && \
	cp $(TARGET) $$LUA_PATH/

# 测试
test: $(TARGET)
	luajit -e "local m = require('luamem'); print(m.gcinfo())"

# 使用说明
help:
	@echo "LuaJIT Memory Analyzer C Extension"
	@echo ""
	@echo "Targets:"
	@echo "  all      - Build the extension (default)"
	@echo "  clean    - Remove built files"
	@echo "  install  - Install to system lua path"
	@echo "  test     - Run a simple test"
	@echo "  help     - Show this help"
	@echo ""
	@echo "Before building:"
	@echo "  1. Install LuaJIT development files"
	@echo "  2. Update LUAJIT_INC and LUAJIT_LIB paths if needed"
	@echo ""
	@echo "Example:"
	@echo "  make"
	@echo "  make test"
	@echo "  make install"

.PHONY: all clean install test help
