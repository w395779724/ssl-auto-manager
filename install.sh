#!/bin/bash

# SSL证书自动申请和续签脚本安装器
# 支持腾讯云DNS API，配合xray面板使用
# 交互式配置安装

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
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
    echo -e "${BLUE}  SSL证书自动管理系统安装器${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo ""
}

print_step() {
    echo ""
    echo -e "${GREEN}=== 步骤 $1: $2 ===${NC}"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_warn "检测到root用户，建议使用普通用户运行"
        read -p "是否继续？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# 安装必要的依赖
install_dependencies() {
    print_info "安装必要的依赖..."

    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y curl wget socat openssl cron
    elif command -v yum &> /dev/null; then
        sudo yum update -y
        sudo yum install -y curl wget socat openssl cron
    elif command -v pacman &> /dev/null; then
        sudo pacman -Sy --noconfirm curl wget socat openssl cronie
    else
        print_error "不支持的包管理器，请手动安装: curl, wget, socat, openssl, cron"
        exit 1
    fi
}

# 安装acme.sh
install_acme() {
    print_info "安装acme.sh..."

    # 检查是否已安装acme.sh
    if [ -f "$HOME/.acme.sh/acme.sh" ]; then
        print_warn "acme.sh已经安装，正在更新..."
        "$HOME/.acme.sh/acme.sh" --upgrade
    else
        # 下载并安装acme.sh
        curl https://get.acme.sh | sh -s email=your-email@example.com

        # 重新加载环境变量
        source ~/.bashrc
    fi

    # 创建软链接
    if [ ! -L "/usr/local/bin/acme.sh" ]; then
        sudo ln -s "$HOME/.acme.sh/acme.sh" /usr/local/bin/ || {
            print_warn "无法创建系统软链接，将使用用户安装"
        }
    fi
}

# 创建目录结构
create_directories() {
    print_info "创建目录结构..."

    mkdir -p {config,logs,scripts,certs}
    mkdir -p certs/{live,archive}
}

# 交互式配置收集
collect_configuration() {
    print_step "2" "配置信息收集"

    print_info "请按照提示填写配置信息，这些信息将用于自动申请SSL证书"
    echo ""

    # 收集腾讯云API信息
    print_info "🔑 腾讯云API配置"
    print_info "请在腾讯云控制台获取API密钥: https://console.cloud.tencent.com/cam/capi"
    echo ""

    while true; do
        read -p "请输入腾讯云 SecretId: " DP_Id
        if [ -n "$DP_Id" ]; then
            break
        else
            print_error "SecretId不能为空，请重新输入"
        fi
    done

    while true; do
        read -s -p "请输入腾讯云 SecretKey: " DP_Key
        echo ""
        if [ -n "$DP_Key" ]; then
            break
        else
            print_error "SecretKey不能为空，请重新输入"
        fi
    done

    echo ""

    # 收集域名信息
    print_info "🌐 域名配置"
    while true; do
        read -p "请输入域名 (支持多个域名，用空格分隔): " domain_input
        if [ -n "$domain_input" ]; then
            DOMAINS="$domain_input"
            break
        else
            print_error "域名不能为空，请重新输入"
        fi
    done

    # 验证域名格式
    for domain in $DOMAINS; do
        if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
            print_error "域名格式无效: $domain"
            exit 1
        fi
    done

    echo ""

    # 收集邮箱信息
    print_info "📧 邮箱配置"
    while true; do
        read -p "请输入邮箱地址 (用于证书通知): " email_input
        if [[ "$email_input" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            EMAIL="$email_input"
            break
        else
            print_error "邮箱格式无效，请重新输入"
        fi
    done

    echo ""

    # 收集xray配置
    print_info "⚙️ xray服务配置"
    read -p "xray配置文件路径 (默认: /usr/local/etc/xray/config.json): " xray_config_input
    XRAY_CONFIG_PATH="${xray_config_input:-/usr/local/etc/xray/config.json}"

    read -p "是否自动重启xray服务 (y/n，默认: y): " auto_restart_input
    case "$auto_restart_input" in
        [nN][oO]|[nN])
            AUTO_RESTART_XRAY="no"
            ;;
        *)
            AUTO_RESTART_XRAY="yes"
            ;;
    esac

    echo ""

    # 收集高级配置
    print_info "🔧 高级配置"
    read -p "续签提醒天数 (默认: 30): " remind_days_input
    RENEW_REMIND_DAYS="${remind_days_input:-30}"

    read -p "强制续签天数 (默认: 15): " force_renew_input
    FORCE_RENEW_DAYS="${force_renew_input:-15}"

    read -p "使用ECC证书 (y/n，默认: n): " ecc_input
    case "$ecc_input" in
        [yY][eE][sS]|[yY])
            USE_ECC="yes"
            ;;
        *)
            USE_ECC="no"
            ;;
    esac

    echo ""
    print_info "✅ 配置信息收集完成"
}

# 创建配置文件
create_config_file() {
    print_step "3" "生成配置文件"

    cat > config/dnsapi.conf << EOF
# 腾讯云DNS API配置文件
# 自动生成于 $(date '+%Y-%m-%d %H:%M:%S')

# SecretId (必填) - 腾讯云API密钥ID
DP_Id="$DP_Id"

# SecretKey (必填) - 腾讯云API密钥Key
DP_Key="$DP_Key"

# 域名列表 (多个域名用空格分隔)
DOMAINS="$DOMAINS"

# 邮箱地址 (用于证书通知和账户注册)
EMAIL="$EMAIL"

# 证书存储路径
CERT_PATH="$HOME/腾讯云域名证书/certs"

# 日志路径
LOG_PATH="$HOME/腾讯云域名证书/logs"

# xray配置路径
XRAY_CONFIG_PATH="$XRAY_CONFIG_PATH"

# 是否自动重启xray (yes/no)
AUTO_RESTART_XRAY="$AUTO_RESTART_XRAY"

# 续签提醒天数 (提前多少天提醒)
RENEW_REMIND_DAYS="$RENEW_REMIND_DAYS"

# 强制续签天数 (到期前多少天强制续签)
FORCE_RENEW_DAYS="$FORCE_RENEW_DAYS"

# 是否使用ECC证书 (yes/no)
USE_ECC="$USE_ECC"

# ACME服务器 (默认: Let's Encrypt)
ACME_SERVER="https://acme-v02.api.letsencrypt.org/directory"

# 证书RSA密钥长度 (2048或4096)
RSA_KEY_SIZE="2048"

# DNS解析TTL (秒)
DNS_TTL="600"

# 腾讯云DNS API请求超时时间 (秒)
API_TIMEOUT="30"
EOF

    print_info "✅ 配置文件已创建: config/dnsapi.conf"
}

# 创建主脚本
create_main_script() {
    print_info "创建主证书管理脚本..."

    cat > scripts/cert-manager.sh << 'EOF'
#!/bin/bash

# SSL证书自动管理脚本
# 支持申请、续签、安装SSL证书

set -e

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 加载配置
if [ -f "$PROJECT_DIR/config/dnsapi.conf" ]; then
    source "$PROJECT_DIR/config/dnsapi.conf"
else
    echo "错误: 配置文件不存在 $PROJECT_DIR/config/dnsapi.conf"
    exit 1
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 日志函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_PATH/cert-manager.log"
}

# 检查配置
check_config() {
    print_info "检查配置..."

    if [ "$DP_Id" = "your-secret-id-here" ] || [ "$DP_Key" = "your-secret-key-here" ]; then
        print_error "请先配置腾讯云API密钥"
        exit 1
    fi

    if [ "$DOMAINS" = "" ]; then
        print_error "请配置域名列表"
        exit 1
    fi

    # 设置腾讯云DNS API环境变量
    export DP_Id="$DP_Id"
    export DP_Key="$DP_Key"

    print_info "配置检查通过"
}

# 申请证书
issue_certificate() {
    print_info "开始申请SSL证书..."
    log "开始申请SSL证书"

    # 将域名转换为数组
    read -ra DOMAIN_ARRAY <<< "$DOMAINS"
    MAIN_DOMAIN="${DOMAIN_ARRAY[0]}"

    # 构建域名参数
    DOMAIN_PARAMS=""
    for domain in "${DOMAIN_ARRAY[@]}"; do
        DOMAIN_PARAMS="$DOMAIN_PARAMS -d $domain"
    done

    # 使用acme.sh申请证书
    if command -v acme.sh &> /dev/null; then
        acme.sh --issue --dns dp $DOMAIN_PARAMS \
            --certpath "$CERT_PATH/live/$MAIN_DOMAIN/cert.pem" \
            --keypath "$CERT_PATH/live/$MAIN_DOMAIN/key.pem" \
            --fullchainpath "$CERT_PATH/live/$MAIN_DOMAIN/fullchain.pem" \
            --reloadcmd "bash $SCRIPT_DIR/install-cert.sh" || {
            print_error "证书申请失败"
            log "证书申请失败"
            exit 1
        }
    else
        # 使用用户安装的acme.sh
        "$HOME/.acme.sh/acme.sh" --issue --dns dp $DOMAIN_PARAMS \
            --certpath "$CERT_PATH/live/$MAIN_DOMAIN/cert.pem" \
            --keypath "$CERT_PATH/live/$MAIN_DOMAIN/key.pem" \
            --fullchainpath "$CERT_PATH/live/$MAIN_DOMAIN/fullchain.pem" \
            --reloadcmd "bash $SCRIPT_DIR/install-cert.sh" || {
            print_error "证书申请失败"
            log "证书申请失败"
            exit 1
        }
    fi

    print_info "证书申请成功"
    log "证书申请成功"
}

# 续签证书
renew_certificate() {
    print_info "开始续签SSL证书..."
    log "开始续签SSL证书"

    read -ra DOMAIN_ARRAY <<< "$DOMAINS"
    MAIN_DOMAIN="${DOMAIN_ARRAY[0]}"

    if command -v acme.sh &> /dev/null; then
        acme.sh --renew -d "$MAIN_DOMAIN" --force || {
            print_error "证书续签失败"
            log "证书续签失败"
            exit 1
        }
    else
        "$HOME/.acme.sh/acme.sh" --renew -d "$MAIN_DOMAIN" --force || {
            print_error "证书续签失败"
            log "证书续签失败"
            exit 1
        }
    fi

    print_info "证书续签成功"
    log "证书续签成功"
}

# 检查证书状态
check_certificate() {
    print_info "检查证书状态..."

    read -ra DOMAIN_ARRAY <<< "$DOMAINS"
    MAIN_DOMAIN="${DOMAIN_ARRAY[0]}"

    if [ ! -f "$CERT_PATH/live/$MAIN_DOMAIN/cert.pem" ]; then
        print_warn "证书文件不存在，需要重新申请"
        return 1
    fi

    # 获取证书过期时间
    EXPIRY_DATE=$(openssl x509 -in "$CERT_PATH/live/$MAIN_DOMAIN/cert.pem" -noout -enddate | cut -d= -f2)
    EXPIRY_TIMESTAMP=$(date -d "$EXPIRY_DATE" +%s)
    CURRENT_TIMESTAMP=$(date +%s)
    DAYS_LEFT=$(( (EXPIRY_TIMESTAMP - CURRENT_TIMESTAMP) / 86400 ))

    print_info "证书将在 $EXPIRY_DATE 过期 ($DAYS_LEFT 天后)"

    if [ $DAYS_LEFT -le $FORCE_RENEW_DAYS ]; then
        print_warn "证书即将在 $DAYS_LEFT 天后过期，开始续签"
        return 2
    elif [ $DAYS_LEFT -le $RENEW_REMIND_DAYS ]; then
        print_warn "证书将在 $DAYS_LEFT 天后过期，请注意续签"
        return 1
    fi

    print_info "证书状态良好"
    return 0
}

# 主函数
main() {
    case "${1:-check}" in
        "issue")
            check_config
            issue_certificate
            ;;
        "renew")
            check_config
            renew_certificate
            ;;
        "check")
            check_config
            check_certificate
            ;;
        "status")
            check_certificate
            ;;
        *)
            echo "用法: $0 {issue|renew|check|status}"
            echo "  issue  - 申请新证书"
            echo "  renew   - 续签证书"
            echo "  check   - 检查并自动续签"
            echo "  status  - 查看证书状态"
            exit 1
            ;;
    esac
}

main "$@"
EOF

    chmod +x scripts/cert-manager.sh
    print_info "主脚本已创建: scripts/cert-manager.sh"
}

# 创建证书安装脚本
create_install_script() {
    print_info "创建证书安装脚本..."

    cat > scripts/install-cert.sh << 'EOF'
#!/bin/bash

# SSL证书安装脚本
# 自动安装证书到xray并重启服务

set -e

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 加载配置
if [ -f "$PROJECT_DIR/config/dnsapi.conf" ]; then
    source "$PROJECT_DIR/config/dnsapi.conf"
else
    echo "错误: 配置文件不存在"
    exit 1
fi

# 日志函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_PATH/install-cert.log"
}

print_info() {
    echo -e "\033[0;32m[INFO]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

print_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 安装证书到xray
install_to_xray() {
    print_info "安装证书到xray..."
    log "开始安装证书到xray"

    read -ra DOMAIN_ARRAY <<< "$DOMAINS"
    MAIN_DOMAIN="${DOMAIN_ARRAY[0]}"

    CERT_FILE="$CERT_PATH/live/$MAIN_DOMAIN/fullchain.pem"
    KEY_FILE="$CERT_PATH/live/$MAIN_DOMAIN/key.pem"

    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        print_error "证书文件不存在"
        log "证书文件不存在: $CERT_FILE 或 $KEY_FILE"
        exit 1
    fi

    # 备份原证书
    if [ -f "/etc/xray/cert.pem" ]; then
        cp /etc/xray/cert.pem "/etc/xray/cert.pem.backup.$(date +%Y%m%d%H%M%S)"
    fi
    if [ -f "/etc/xray/key.pem" ]; then
        cp /etc/xray/key.pem "/etc/xray/key.pem.backup.$(date +%Y%m%d%H%M%S)"
    fi

    # 创建证书目录
    sudo mkdir -p /etc/xray

    # 复制证书
    sudo cp "$CERT_FILE" /etc/xray/cert.pem
    sudo cp "$KEY_FILE" /etc/xray/key.pem

    # 设置权限
    sudo chmod 644 /etc/xray/cert.pem
    sudo chmod 600 /etc/xray/key.pem

    print_info "证书安装完成"
    log "证书安装完成"
}

# 重启xray服务
restart_xray() {
    if [ "$AUTO_RESTART_XRAY" = "yes" ]; then
        print_info "重启xray服务..."
        log "重启xray服务"

        if systemctl is-active --quiet xray; then
            sudo systemctl restart xray && {
                print_info "xray服务重启成功"
                log "xray服务重启成功"
            } || {
                print_error "xray服务重启失败"
                log "xray服务重启失败"
                exit 1
            }
        else
            print_warn "xray服务未运行，尝试启动..."
            sudo systemctl start xray && {
                print_info "xray服务启动成功"
                log "xray服务启动成功"
            } || {
                print_error "xray服务启动失败"
                log "xray服务启动失败"
                exit 1
            }
        fi
    else
        print_info "自动重启已禁用，请手动重启xray服务"
    fi
}

# 主函数
main() {
    install_to_xray
    restart_xray
    print_info "证书安装和配置完成"
}

main "$@"
EOF

    chmod +x scripts/install-cert.sh
    print_info "证书安装脚本已创建: scripts/install-cert.sh"
}

# 创建定时任务脚本
create_cron_script() {
    print_info "创建定时任务配置脚本..."

    cat > scripts/setup-cron.sh << 'EOF'
#!/bin/bash

# 定时任务配置脚本
# 设置自动续签定时任务

set -e

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 加载配置
if [ -f "$PROJECT_DIR/config/dnsapi.conf" ]; then
    source "$PROJECT_DIR/config/dnsapi.conf"
else
    echo "错误: 配置文件不存在"
    exit 1
fi

print_info() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

print_warn() {
    echo -e "\033[1;33m[WARN]\033[0m $1"
}

# 设置定时任务
setup_cron() {
    print_info "设置定时任务..."

    # 创建定时任务脚本
    cat > "$PROJECT_DIR/scripts/cron-renew.sh" << 'CRON_EOF'
#!/bin/bash
# 自动续签定时任务脚本

PROJECT_DIR="$HOME/腾讯云域名证书"
LOG_FILE="$PROJECT_DIR/logs/cron.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始执行定时续签检查" >> "$LOG_FILE"

# 执行证书检查和续签
bash "$PROJECT_DIR/scripts/cert-manager.sh" check >> "$LOG_FILE" 2>&1

echo "$(date '+%Y-%m-%d %H:%M:%S') - 定时续签检查完成" >> "$LOG_FILE"
CRON_EOF

    chmod +x "$PROJECT_DIR/scripts/cron-renew.sh"

    # 添加到crontab
    (crontab -l 2>/dev/null; echo "0 2 * * * $PROJECT_DIR/scripts/cron-renew.sh") | crontab -

    print_info "定时任务已设置：每天凌晨2点自动检查并续签证书"
    print_info "定时任务日志: $PROJECT_DIR/logs/cron.log"
}

# 移除定时任务
remove_cron() {
    print_info "移除定时任务..."

    # 创建临时文件
    TEMP_CRON=$(mktemp)

    # 获取当前crontab并移除相关行
    crontab -l 2>/dev/null | grep -v "腾讯云域名证书" > "$TEMP_CRON" || true

    # 重新设置crontab
    crontab "$TEMP_CRON"

    # 删除临时文件
    rm "$TEMP_CRON"

    # 删除定时任务脚本
    rm -f "$PROJECT_DIR/scripts/cron-renew.sh"

    print_info "定时任务已移除"
}

# 主函数
main() {
    case "${1:-setup}" in
        "setup")
            setup_cron
            ;;
        "remove")
            remove_cron
            ;;
        *)
            echo "用法: $0 {setup|remove}"
            echo "  setup  - 设置定时任务"
            echo "  remove - 移除定时任务"
            exit 1
            ;;
    esac
}

main "$@"
EOF

    chmod +x scripts/setup-cron.sh
    print_info "定时任务配置脚本已创建: scripts/setup-cron.sh"
}

# 确认配置信息
confirm_configuration() {
    print_step "4" "配置确认"

    print_info "请确认以下配置信息："
    echo ""
    print_info "🔑 腾讯云API:"
    print_info "  SecretId: ${DP_Id:0:8}..."
    print_info "  SecretKey: ${DP_Key:0:8}..."
    echo ""
    print_info "🌐 域名: $DOMAINS"
    print_info "📧 邮箱: $EMAIL"
    print_info "⚙️ xray配置路径: $XRAY_CONFIG_PATH"
    print_info "🔄 自动重启xray: $AUTO_RESTART_XRAY"
    print_info "⏰ 续签提醒天数: $RENEW_REMIND_DAYS"
    print_info "⏰ 强制续签天数: $FORCE_RENEW_DAYS"
    print_info "🔐 使用ECC证书: $USE_ECC"
    echo ""

    while true; do
        read -p "配置信息是否正确？(y/n): " confirm_input
        case "$confirm_input" in
            [yY][eE][sS]|[yY])
                print_info "✅ 配置确认通过"
                break
                ;;
            [nN][oO]|[nN])
                print_error "配置信息有误，请重新运行安装脚本"
                exit 1
                ;;
            *)
                print_error "请输入 y 或 n"
                ;;
        esac
    done
}

# 测试配置
test_configuration() {
    print_step "5" "配置测试"

    print_info "测试腾讯云API连接..."

    # 设置环境变量
    export DP_Id="$DP_Id"
    export DP_Key="$DP_Key"

    # 简单的API测试
    if command -v curl &> /dev/null; then
        local timestamp=$(date +%s)
        local nonce=$RANDOM
        local response=$(curl -s -X POST "https://cns.api.qcloud.com/v2/index.php" \
            -d "Action=DomainList" \
            -d "SecretId=$DP_Id" \
            -d "Timestamp=$timestamp" \
            -d "Nonce=$nonce" \
            -d "Signature=$(echo -n "GETcns.api.qcloud.com/v2/index.php?Action=DomainList&Nonce=$nonce&SecretId=$DP_Id&Timestamp=$timestamp" | openssl dgst -sha256 -hmac "$DP_Key" | cut -d' ' -f2)" 2>/dev/null)

        if echo "$response" | grep -q '"code":0\|"totalCount"'; then
            print_info "✅ 腾讯云API连接测试成功"
        else
            print_warn "⚠️  腾讯云API连接测试失败，请检查API密钥"
            print_warn "您可以在安装完成后手动测试"
        fi
    else
        print_warn "⚠️  curl未安装，跳过API测试"
    fi
}

# 主安装流程
main() {
    print_title

    print_info "欢迎使用SSL证书自动管理系统安装器！"
    print_info "本系统将帮助您配置自动化的SSL证书申请和管理。"
    print_info ""
    print_info "安装过程包括："
    print_info "1. 系统依赖检查和安装"
    print_info "2. 交互式配置信息收集"
    print_info "3. 生成配置文件和脚本"
    print_info "4. 配置测试和验证"
    echo ""

    # 开始安装步骤
    check_root
    install_dependencies
    install_acme
    create_directories
    collect_configuration
    create_config_file
    confirm_configuration
    create_main_script
    create_install_script
    create_cron_script
    test_configuration

    print_step "6" "安装完成"

    print_info "🎉 SSL证书自动管理系统安装完成！"
    echo ""
    print_info "📁 项目文件已创建在当前目录"
    print_info ""
    print_info "🚀 下一步操作："
    print_info "1. 申请新证书: ./scripts/cert-manager.sh issue"
    print_info "2. 检查证书状态: ./scripts/cert-manager.sh status"
    print_info "3. 设置定时任务: ./scripts/setup-cron.sh setup"
    echo ""
    print_info "📖 查看帮助: ./scripts/cert-manager.sh help"
    print_info "📖 查看文档: cat README.md"
    echo ""
    print_info "💡 提示：证书文件将保存在 certs/ 目录"
    print_info "💡 提示：日志文件将保存在 logs/ 目录"
    echo ""
    print_warn "⚠️  请确保您的域名已托管在腾讯云"
    print_warn "⚠️  请确保服务器能访问外网"
}

main "$@"