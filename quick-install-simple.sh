#!/bin/bash

# SSL证书自动管理系统 - 简化一键安装脚本
# 使用方法: curl -fsSL https://raw.githubusercontent.com/w395779724/ssl-auto-manager/main/quick-install-simple.sh | bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 版本信息
VERSION="1.0.0"
REPO_URL="https://github.com/w395779724/ssl-auto-manager.git"

# 打印函数
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_title() {
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}  SSL证书自动管理系统 v${VERSION}${NC}"
    echo -e "${BLUE}  简化一键安装脚本${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo ""
}

# 主安装流程
main() {
    print_title

    print_info "开始安装SSL证书自动管理系统..."
    print_info "当前用户: $(whoami)"
    print_info "当前目录: $(pwd)"
    print_info "操作系统: $OSTYPE"
    echo ""

    # 创建安装目录
    local install_dir="$HOME/ssl-auto-manager"
    print_info "创建安装目录: $install_dir"

    if [ -d "$install_dir" ]; then
        print_info "安装目录已存在，删除旧版本..."
        rm -rf "$install_dir"
    fi

    mkdir -p "$install_dir"
    cd "$install_dir"

    # 克隆仓库
    print_info "从GitHub克隆项目..."
    if command -v git &> /dev/null; then
        git clone "$REPO_URL" . 2>/dev/null || {
            print_error "Git克隆失败，尝试手动下载..."
            exit 1
        }
        print_info "项目克隆成功"
    else
        print_error "未安装git，请先安装git"
        print_info "Ubuntu/Debian: apt-get install git"
        print_info "CentOS/RHEL: yum install git"
        exit 1
    fi

    # 设置权限
    print_info "设置文件权限..."
    chmod +x install.sh
    chmod +x scripts/*.sh

    # 创建必要目录
    mkdir -p certs/{live,archive} logs

    print_info ""
    print_info "🎉 安装完成！"
    echo ""
    print_info "📁 项目已安装到: $install_dir"
    echo ""
    print_info "🚀 下一步操作："
    print_info "1. cd $install_dir"
    print_info "2. ./install.sh"
    echo ""
    print_info "📖 或者查看快速开始指南:"
    print_info "cat QUICKSTART.md"
    echo ""
    print_info "🔗 项目主页: $REPO_URL"
}

# 直接执行主函数
main "$@"