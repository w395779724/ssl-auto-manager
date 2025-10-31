#!/bin/bash

echo "=== SSL证书自动管理系统测试脚本 ==="
echo "当前用户: $(whoami)"
echo "当前目录: $(pwd)"
echo "操作系统: $OSTYPE"
echo "Shell: $0"
echo ""

# 测试基本的curl下载
echo "测试从GitHub下载文件..."
if curl -fsSL https://raw.githubusercontent.com/w395779724/ssl-auto-manager/main/README.md | head -5; then
    echo "✅ GitHub连接正常"
else
    echo "❌ GitHub连接失败"
    exit 1
fi

echo ""
echo "=== 开始安装 ==="

# 创建安装目录
INSTALL_DIR="$HOME/ssl-auto-manager"
echo "创建安装目录: $INSTALL_DIR"

if [ -d "$INSTALL_DIR" ]; then
    echo "删除旧版本..."
    rm -rf "$INSTALL_DIR"
fi

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 克隆仓库
echo "克隆项目..."
if git clone https://github.com/w395779724/ssl-auto-manager.git .; then
    echo "✅ 克隆成功"
else
    echo "❌ 克隆失败"
    exit 1
fi

# 设置权限
echo "设置权限..."
chmod +x install.sh
chmod +x scripts/*.sh

echo ""
echo "🎉 安装完成！"
echo "项目位置: $INSTALL_DIR"
echo ""
echo "下一步："
echo "cd $INSTALL_DIR"
echo "./install.sh"