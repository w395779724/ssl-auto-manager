#!/bin/bash

# SSL证书自动管理系统 - 一键安装脚本
# 使用方法: curl -fsSL https://your-domain.com/quick-install.sh | bash

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 版本信息
VERSION="1.0.0"
REPO_URL="https://github.com/w395779724/ssl-auto-manager.git"
RAW_BASE_URL="https://raw.githubusercontent.com/w395779724/ssl-auto-manager/main"

# 打印函数
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_title() {
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}  SSL证书自动管理系统 v${VERSION}${NC}"
    echo -e "${BLUE}  一键安装脚本${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo ""
}

# 检查系统要求
check_system() {
    print_info "检查系统环境..."

    # 检查操作系统
    if [[ "$OSTYPE" != "linux-gnu"* ]] && [[ "$OSTYPE" != "darwin"* ]]; then
        print_error "不支持的操作系统: $OSTYPE"
        print_info "本脚本支持 Linux 和 macOS"
        exit 1
    fi

    # 检查必要的命令
    local missing_commands=()
    for cmd in curl wget tar; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done

    if [ ${#missing_commands[@]} -ne 0 ]; then
        print_error "缺少必要命令: ${missing_commands[*]}"
        print_info "请先安装这些命令后再运行安装脚本"
        exit 1
    fi

    print_info "系统环境检查通过"
}

# 检测下载方式
detect_download_method() {
    if command -v curl &> /dev/null && curl --version | grep -q "https"; then
        echo "curl"
    elif command -v wget &> /dev/null; then
        echo "wget"
    else
        print_error "需要 curl 或 wget 来下载文件"
        exit 1
    fi
}

# 下载文件
download_file() {
    local url="$1"
    local output="$2"
    local method=$(detect_download_method)

    print_info "下载文件: $url"

    case "$method" in
        "curl")
            curl -fsSL "$url" -o "$output"
            ;;
        "wget")
            wget --no-check-certificate "$url" -O "$output"
            ;;
    esac

    if [ ! -f "$output" ]; then
        print_error "下载失败: $url"
        exit 1
    fi
}

# 创建安装目录
create_install_directory() {
    local install_dir="$HOME/腾讯云域名证书"

    print_info "创建安装目录: $install_dir"

    if [ -d "$install_dir" ]; then
        print_warn "安装目录已存在，将创建备份"
        mv "$install_dir" "${install_dir}.backup.$(date +%Y%m%d_%H%M%S)"
    fi

    mkdir -p "$install_dir"
    cd "$install_dir"

    print_info "已切换到安装目录: $(pwd)"
}

# 下载项目文件
download_project_files() {
    print_info "下载项目文件..."

    # 方法1: 尝试使用Git克隆
    if command -v git &> /dev/null; then
        print_info "使用Git克隆项目..."
        if git clone "$REPO_URL" . 2>/dev/null; then
            print_info "Git克隆成功"
            return 0
        else
            print_warn "Git克隆失败，尝试手动下载"
        fi
    fi

    # 方法2: 手动下载核心文件
    print_info "手动下载项目文件..."

    local files=(
        "install.sh"
        "scripts/cert-manager.sh"
        "scripts/install-cert.sh"
        "scripts/setup-cron.sh"
        "README.md"
        "QUICKSTART.md"
    )

    for file in "${files[@]}"; do
        local dir=$(dirname "$file")
        if [ "$dir" != "." ]; then
            mkdir -p "$dir"
        fi
        download_file "${RAW_BASE_URL}/$file" "$file"
    done

    # 创建配置文件模板
    cat > config/dnsapi.conf << 'EOF'
# 腾讯云DNS API配置文件
# 请在安装过程中填写配置信息

# SecretId (必填) - 腾讯云API密钥ID
DP_Id="your-secret-id-here"

# SecretKey (必填) - 腾讯云API密钥Key
DP_Key="your-secret-key-here"

# 域名列表 (多个域名用空格分隔)
DOMAINS="your-domain.com"

# 邮箱地址 (用于证书通知和账户注册)
EMAIL="your-email@example.com"

# 其他配置将在安装过程中设置...
EOF

    print_info "项目文件下载完成"
}

# 设置执行权限
setup_permissions() {
    print_info "设置文件权限..."

    chmod +x install.sh
    chmod +x scripts/*.sh

    # 创建必要的目录
    mkdir -p {certs/{live,archive},logs}

    print_info "权限设置完成"
}

# 运行交互式安装
run_interactive_install() {
    print_info "启动交互式安装程序..."

    if [ ! -f "install.sh" ]; then
        print_error "安装脚本不存在"
        exit 1
    fi

    # 运行交互式安装
    bash install.sh
}

# 清理临时文件
cleanup() {
    print_info "清理临时文件..."
    # 这里可以添加清理逻辑
}

# 错误处理
handle_error() {
    print_error "安装过程中发生错误"
    print_info "请检查网络连接和系统权限"
    print_info "如果问题持续存在，请手动下载项目文件"
    exit 1
}

# 安装完成提示
show_completion_message() {
    print_info "🎉 一键安装完成！"
    echo ""
    print_info "项目已安装到: $(pwd)"
    echo ""
    print_info "🚀 快速开始："
    print_info "1. 申请证书: ./scripts/cert-manager.sh issue"
    print_info "2. 查看状态: ./scripts/cert-manager.sh status"
    print_info "3. 设置定时任务: ./scripts/setup-cron.sh setup"
    echo ""
    print_info "📖 查看文档: cat README.md"
    print_info "📖 快速开始: cat QUICKSTART.md"
    echo ""
    print_info "如需帮助，请访问项目主页: $REPO_URL"
}

# 主安装流程
main() {
    # 设置错误处理
    trap handle_error ERR
    trap cleanup EXIT

    print_title

    print_info "开始一键安装SSL证书自动管理系统..."
    print_info "版本: v${VERSION}"
    print_info "仓库: $REPO_URL"
    echo ""

    # 安装步骤
    check_system
    create_install_directory
    download_project_files
    setup_permissions
    run_interactive_install

    show_completion_message
}

# 检查是否直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi