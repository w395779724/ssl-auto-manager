#!/bin/bash

# SSL证书自动管理脚本
# 支持申请、续签、安装SSL证书，配合腾讯云DNS API和xray面板

set -e

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 加载配置
if [ -f "$PROJECT_DIR/config/dnsapi.conf" ]; then
    source "$PROJECT_DIR/config/dnsapi.conf"
else
    echo "错误: 配置文件不存在 $PROJECT_DIR/config/dnsapi.conf"
    echo "请先运行 ./install.sh 进行安装"
    exit 1
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 打印函数
print_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

print_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 日志函数
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_PATH/cert-manager.log"
}

# 检查依赖
check_dependencies() {
    print_info "检查系统依赖..."

    local missing_deps=()

    # 检查基本命令
    for cmd in curl openssl sed awk grep date; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    # 检查acme.sh
    if ! command -v acme.sh &> /dev/null && [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
        missing_deps+=("acme.sh")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "缺少依赖: ${missing_deps[*]}"
        print_info "请运行 ./install.sh 安装依赖"
        exit 1
    fi

    print_info "依赖检查通过"
    log "INFO" "系统依赖检查通过"
}

# 检查配置
check_config() {
    print_info "检查配置文件..."

    # 检查必要配置
    if [ "$DP_Id" = "your-secret-id-here" ] || [ -z "$DP_Id" ]; then
        print_error "请配置腾讯云API SecretId"
        print_info "编辑配置文件: $PROJECT_DIR/config/dnsapi.conf"
        exit 1
    fi

    if [ "$DP_Key" = "your-secret-key-here" ] || [ -z "$DP_Key" ]; then
        print_error "请配置腾讯云API SecretKey"
        print_info "编辑配置文件: $PROJECT_DIR/config/dnsapi.conf"
        exit 1
    fi

    if [ -z "$DOMAINS" ] || [ "$DOMAINS" = "your-domain.com" ]; then
        print_error "请配置域名列表"
        print_info "编辑配置文件: $PROJECT_DIR/config/dnsapi.conf"
        exit 1
    fi

    if [ -z "$EMAIL" ] || [ "$EMAIL" = "your-email@example.com" ]; then
        print_error "请配置邮箱地址"
        print_info "编辑配置文件: $PROJECT_DIR/config/dnsapi.conf"
        exit 1
    fi

    # 创建必要的目录
    mkdir -p "$CERT_PATH/live" "$CERT_PATH/archive" "$LOG_PATH"

    # 设置腾讯云DNS API环境变量
    export DP_Id="$DP_Id"
    export DP_Key="$DP_Key"

    print_info "配置检查通过"
    log "INFO" "配置检查通过"
}

# 测试腾讯云API连接
test_dns_api() {
    print_info "测试腾讯云DNS API连接..."

    # 尝试获取域名列表
    local response=$(curl -s -X POST "https://cns.api.qcloud.com/v2/index.php" \
        -d "Action=DomainList" \
        -d "SecretId=$DP_Id" \
        -d "Timestamp=$(date +%s)" \
        -d "Nonce=$RANDOM" \
        -d "Signature=$(echo -n "GETcns.api.qcloud.com/v2/index.php?Action=DomainList&Nonce=$RANDOM&SecretId=$DP_Id&Timestamp=$(date +%s)" | openssl dgst -sha256 -hmac "$DP_Key" | cut -d' ' -f2)" 2>/dev/null)

    if echo "$response" | grep -q '"code":0'; then
        print_info "腾讯云API连接测试成功"
        log "INFO" "腾讯云API连接测试成功"
        return 0
    else
        print_error "腾讯云API连接测试失败"
        print_debug "响应: $response"
        log "ERROR" "腾讯云API连接测试失败: $response"
        return 1
    fi
}

# 申请证书
issue_certificate() {
    print_info "开始申请SSL证书..."
    log "INFO" "开始申请SSL证书，域名: $DOMAINS"

    # 将域名转换为数组
    read -ra DOMAIN_ARRAY <<< "$DOMAINS"
    MAIN_DOMAIN="${DOMAIN_ARRAY[0]}"

    # 创建证书目录
    mkdir -p "$CERT_PATH/live/$MAIN_DOMAIN"

    # 构建域名参数
    local domain_params=""
    for domain in "${DOMAIN_ARRAY[@]}"; do
        domain_params="$domain_params -d $domain"
    done

    # 构建acme.sh命令
    local acme_cmd
    if command -v acme.sh &> /dev/null; then
        acme_cmd="acme.sh"
    else
        acme_cmd="$HOME/.acme.sh/acme.sh"
    fi

    # 构建完整命令
    local full_cmd="$acme_cmd --issue --dns dp $domain_params"
    full_cmd="$full_cmd --certpath \"$CERT_PATH/live/$MAIN_DOMAIN/cert.pem\""
    full_cmd="$full_cmd --keypath \"$CERT_PATH/live/$MAIN_DOMAIN/key.pem\""
    full_cmd="$full_cmd --fullchainpath \"$CERT_PATH/live/$MAIN_DOMAIN/fullchain.pem\""
    full_cmd="$full_cmd --reloadcmd \"bash $SCRIPT_DIR/install-cert.sh\""

    # 添加ECC选项
    if [ "$USE_ECC" = "yes" ]; then
        full_cmd="$full_cmd --keylength ec-256"
    else
        full_cmd="$full_cmd --keylength $RSA_KEY_SIZE"
    fi

    # 设置服务器
    if [ "$ACME_SERVER" != "https://acme-v02.api.letsencrypt.org/directory" ]; then
        full_cmd="$full_cmd --server $ACME_SERVER"
    fi

    print_info "执行证书申请命令..."
    print_debug "命令: $full_cmd"

    # 执行证书申请
    if eval "$full_cmd"; then
        print_info "证书申请成功"
        log "INFO" "证书申请成功，主域名: $MAIN_DOMAIN"

        # 验证证书文件
        if [ -f "$CERT_PATH/live/$MAIN_DOMAIN/cert.pem" ] && [ -f "$CERT_PATH/live/$MAIN_DOMAIN/key.pem" ]; then
            print_info "证书文件已生成"
            show_certificate_info "$MAIN_DOMAIN"
        else
            print_warn "证书申请成功但文件未找到，请检查acme.sh配置"
            log "WARN" "证书申请成功但文件未找到"
        fi
    else
        print_error "证书申请失败"
        log "ERROR" "证书申请失败"
        exit 1
    fi
}

# 续签证书
renew_certificate() {
    print_info "开始续签SSL证书..."
    log "INFO" "开始续签SSL证书"

    read -ra DOMAIN_ARRAY <<< "$DOMAINS"
    MAIN_DOMAIN="${DOMAIN_ARRAY[0]}"

    # 构建acme.sh命令
    local acme_cmd
    if command -v acme.sh &> /dev/null; then
        acme_cmd="acme.sh"
    else
        acme_cmd="$HOME/.acme.sh/acme.sh"
    fi

    # 执行续签
    if $acme_cmd --renew -d "$MAIN_DOMAIN" --force; then
        print_info "证书续签成功"
        log "INFO" "证书续签成功，主域名: $MAIN_DOMAIN"
        show_certificate_info "$MAIN_DOMAIN"
    else
        print_error "证书续签失败"
        log "ERROR" "证书续签失败"
        exit 1
    fi
}

# 检查证书状态
check_certificate() {
    print_info "检查证书状态..."

    read -ra DOMAIN_ARRAY <<< "$DOMAINS"
    MAIN_DOMAIN="${DOMAIN_ARRAY[0]}"

    local cert_file="$CERT_PATH/live/$MAIN_DOMAIN/cert.pem"

    if [ ! -f "$cert_file" ]; then
        print_warn "证书文件不存在: $cert_file"
        log "WARN" "证书文件不存在: $cert_file"
        return 1
    fi

    # 检查证书格式
    if ! openssl x509 -in "$cert_file" -noout -text &> /dev/null; then
        print_error "证书文件格式无效"
        log "ERROR" "证书文件格式无效: $cert_file"
        return 1
    fi

    # 获取证书信息
    local subject=$(openssl x509 -in "$cert_file" -noout -subject | cut -d'=' -f6)
    local issuer=$(openssl x509 -in "$cert_file" -noout -issuer | cut -d'=' -f6)
    local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
    local expiry_timestamp=$(date -d "$expiry_date" +%s)
    local current_timestamp=$(date +%s)
    local days_left=$(( (expiry_timestamp - current_timestamp) / 86400 ))

    print_info "证书信息:"
    print_info "  主题: $subject"
    print_info "  颁发者: $issuer"
    print_info "  过期时间: $expiry_date"
    print_info "  剩余天数: $days_left"

    log "INFO" "证书状态检查 - 主题: $subject, 过期时间: $expiry_date, 剩余天数: $days_left"

    # 判断是否需要续签
    if [ $days_left -le $FORCE_RENEW_DAYS ]; then
        print_warn "证书即将在 $days_left 天后过期，开始自动续签"
        log "WARN" "证书即将过期，剩余 $days_left 天，开始自动续签"
        renew_certificate
        return 2
    elif [ $days_left -le $RENEW_REMIND_DAYS ]; then
        print_warn "证书将在 $days_left 天后过期，请注意续签"
        log "WARN" "证书即将过期，剩余 $days_left 天，需要续签"
        return 1
    fi

    print_info "证书状态良好"
    return 0
}

# 显示证书信息
show_certificate_info() {
    local domain="$1"
    local cert_file="$CERT_PATH/live/$domain/cert.pem"

    if [ ! -f "$cert_file" ]; then
        print_error "证书文件不存在: $cert_file"
        return 1
    fi

    print_info "证书详细信息:"

    # 证书主题
    local subject=$(openssl x509 -in "$cert_file" -noout -subject | cut -d'=' -f6)
    print_info "  主题: $subject"

    # SAN (Subject Alternative Names)
    local sans=$(openssl x509 -in "$cert_file" -noout -text | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/DNS://g' | tr ',' '\n' | sed 's/^ *//' | grep -v '^$' | tr '\n' ' ')
    if [ -n "$sans" ]; then
        print_info "  域名列表: $sans"
    fi

    # 有效期
    local start_date=$(openssl x509 -in "$cert_file" -noout -startdate | cut -d= -f2)
    local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
    print_info "  生效时间: $start_date"
    print_info "  过期时间: $expiry_date"

    # 颁发者
    local issuer=$(openssl x509 -in "$cert_file" -noout -issuer | cut -d'=' -f6)
    print_info "  颁发者: $issuer"

    # 序列号
    local serial=$(openssl x509 -in "$cert_file" -noout -serial | cut -d= -f2)
    print_info "  序列号: $serial"
}

# 列出所有证书
list_certificates() {
    print_info "列出所有已安装的证书..."

    if [ ! -d "$CERT_PATH/live" ]; then
        print_warn "证书目录不存在"
        return 1
    fi

    local found_cert=false

    for cert_dir in "$CERT_PATH/live"/*; do
        if [ -d "$cert_dir" ]; then
            local domain=$(basename "$cert_dir")
            local cert_file="$cert_dir/cert.pem"

            if [ -f "$cert_file" ]; then
                found_cert=true
                echo ""
                print_info "=== $domain ==="
                show_certificate_info "$domain"
            fi
        fi
    done

    if [ "$found_cert" = false ]; then
        print_warn "未找到任何证书"
    fi
}

# 删除证书
remove_certificate() {
    local domain="$1"

    if [ -z "$domain" ]; then
        print_error "请指定要删除的域名"
        return 1
    fi

    print_info "删除证书: $domain"

    # 构建acme.sh命令
    local acme_cmd
    if command -v acme.sh &> /dev/null; then
        acme_cmd="acme.sh"
    else
        acme_cmd="$HOME/.acme.sh/acme.sh"
    fi

    # 删除证书
    if $acme_cmd --remove -d "$domain"; then
        print_info "证书删除成功"
        log "INFO" "证书删除成功: $domain"

        # 删除本地文件
        rm -rf "$CERT_PATH/live/$domain"
        print_info "本地证书文件已删除"
    else
        print_error "证书删除失败"
        log "ERROR" "证书删除失败: $domain"
        return 1
    fi
}

# 清理日志
clean_logs() {
    print_info "清理日志文件..."

    local keep_days="${1:-30}"

    # 清理超过指定天数的日志
    find "$LOG_PATH" -name "*.log" -type f -mtime +$keep_days -delete

    print_info "已清理 $keep_days 天前的日志文件"
    log "INFO" "日志清理完成，保留 $keep_days 天"
}

# 显示帮助信息
show_help() {
    echo "SSL证书自动管理脚本"
    echo ""
    echo "用法: $0 [命令] [参数]"
    echo ""
    echo "命令:"
    echo "  issue                     申请新证书"
    echo "  renew [domain]            续签指定域名证书 (不指定则续签配置中的域名)"
    echo "  check                     检查证书状态并自动续签"
    echo "  status                    显示证书状态"
    echo "  list                      列出所有证书"
    echo "  info <domain>             显示指定域名证书详细信息"
    echo "  remove <domain>           删除指定域名证书"
    echo "  clean-logs [days]         清理日志文件 (默认保留30天)"
    echo "  test-api                  测试腾讯云DNS API连接"
    echo "  help                      显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 issue                  # 申请配置文件中的域名证书"
    echo "  $0 check                  # 检查证书状态并自动续签"
    echo "  $0 status                 # 查看证书状态"
    echo "  $0 info example.com       # 查看example.com证书详情"
    echo "  $0 remove example.com     # 删除example.com证书"
    echo ""
    echo "配置文件: $PROJECT_DIR/config/dnsapi.conf"
    echo "日志文件: $LOG_PATH/cert-manager.log"
}

# 主函数
main() {
    # 检查基本配置
    if [ ! -f "$PROJECT_DIR/config/dnsapi.conf" ]; then
        print_error "配置文件不存在: $PROJECT_DIR/config/dnsapi.conf"
        print_info "请先运行 ./install.sh 进行安装"
        exit 1
    fi

    # 创建日志目录
    mkdir -p "$LOG_PATH"

    case "${1:-help}" in
        "issue")
            check_dependencies
            check_config
            test_dns_api
            issue_certificate
            ;;
        "renew")
            check_dependencies
            check_config
            if [ -n "$2" ]; then
                # 续签指定域名
                DOMAINS="$2"
            fi
            renew_certificate
            ;;
        "check")
            check_dependencies
            check_config
            check_certificate
            ;;
        "status")
            check_dependencies
            check_config
            check_certificate
            ;;
        "list")
            check_dependencies
            check_config
            list_certificates
            ;;
        "info")
            if [ -z "$2" ]; then
                print_error "请指定域名"
                exit 1
            fi
            check_dependencies
            check_config
            show_certificate_info "$2"
            ;;
        "remove")
            if [ -z "$2" ]; then
                print_error "请指定要删除的域名"
                exit 1
            fi
            check_dependencies
            check_config
            remove_certificate "$2"
            ;;
        "clean-logs")
            check_dependencies
            clean_logs "${2:-30}"
            ;;
        "test-api")
            check_dependencies
            check_config
            test_dns_api
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            print_error "未知命令: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"