#!/bin/bash

# SSL证书安装脚本
# 自动安装证书到xray并重启服务，支持多种配置方式

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

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 日志函数
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_PATH/install-cert.log"
}

# 检测xray安装路径
detect_xray_paths() {
    local xray_paths=(
        "/usr/local/bin/xray"
        "/usr/bin/xray"
        "/usr/local/etc/xray"
        "/etc/xray"
        "/opt/xray"
        "$HOME/xray"
        "$HOME/.local/bin/xray"
    )

    local found_paths=()

    for path in "${xray_paths[@]}"; do
        if [ -d "$path" ] || [ -f "$path" ]; then
            found_paths+=("$path")
        fi
    done

    if [ ${#found_paths[@]} -eq 0 ]; then
        print_warn "未检测到xray安装路径"
        return 1
    fi

    print_info "检测到可能的xray路径:"
    for path in "${found_paths[@]}"; do
        print_info "  $path"
    done

    return 0
}

# 检测系统服务管理器
detect_service_manager() {
    if command -v systemctl &> /dev/null; then
        echo "systemd"
    elif command -v service &> /dev/null; then
        echo "sysvinit"
    elif command -v rc-service &> /dev/null; then
        echo "openrc"
    else
        echo "unknown"
    fi
}

# 备份证书文件
backup_certificates() {
    local domain="$1"
    local backup_dir="$CERT_PATH/archive/$domain/$(date +%Y%m%d_%H%M%S)"

    print_info "备份现有证书到: $backup_dir"
    mkdir -p "$backup_dir"

    # 备份系统证书
    if [ -f "/etc/xray/cert.pem" ]; then
        cp "/etc/xray/cert.pem" "$backup_dir/system_cert.pem"
        log "INFO" "备份系统证书: /etc/xray/cert.pem"
    fi

    if [ -f "/etc/xray/key.pem" ]; then
        cp "/etc/xray/key.pem" "$backup_dir/system_key.pem"
        log "INFO" "备份系统私钥: /etc/xray/key.pem"
    fi

    # 备份xray配置文件
    if [ -f "$XRAY_CONFIG_PATH" ]; then
        cp "$XRAY_CONFIG_PATH" "$backup_dir/xray_config.json"
        log "INFO" "备份xray配置: $XRAY_CONFIG_PATH"
    fi

    print_info "证书备份完成"
}

# 安装证书到系统目录
install_to_system() {
    local domain="$1"
    local cert_file="$CERT_PATH/live/$domain/cert.pem"
    local key_file="$CERT_PATH/live/$domain/key.pem"
    local fullchain_file="$CERT_PATH/live/$domain/fullchain.pem"

    if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
        print_error "证书文件不存在"
        log "ERROR" "证书文件不存在: $cert_file 或 $key_file"
        return 1
    fi

    print_info "安装证书到系统目录..."

    # 创建证书目录
    local cert_dirs=(
        "/etc/xray"
        "/usr/local/etc/xray"
        "/etc/ssl/certs"
        "/etc/ssl/private"
    )

    for dir in "${cert_dirs[@]}"; do
        if [ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null; then
            print_debug "证书目录可用: $dir"
        fi
    done

    # 优先安装到xray目录
    local target_cert_dir="/etc/xray"
    if [ ! -d "$target_cert_dir" ]; then
        target_cert_dir="/usr/local/etc/xray"
    fi

    if [ ! -d "$target_cert_dir" ]; then
        print_error "无法找到合适的证书安装目录"
        return 1
    fi

    # 复制证书文件
    print_info "复制证书到: $target_cert_dir"
    cp "$fullchain_file" "$target_cert_dir/cert.pem"
    cp "$key_file" "$target_cert_dir/key.pem"

    # 设置权限
    chmod 644 "$target_cert_dir/cert.pem"
    chmod 600 "$target_cert_dir/key.pem"

    # 创建符号链接到其他位置（如果需要）
    if [ -d "/etc/ssl/certs" ]; then
        ln -sf "$target_cert_dir/cert.pem" "/etc/ssl/certs/xray-cert.pem" 2>/dev/null || true
    fi

    if [ -d "/etc/ssl/private" ]; then
        ln -sf "$target_cert_dir/key.pem" "/etc/ssl/private/xray-key.pem" 2>/dev/null || true
    fi

    print_info "证书安装完成"
    log "INFO" "证书已安装到: $target_cert_dir"
}

# 更新xray配置文件
update_xray_config() {
    local domain="$1"

    if [ ! -f "$XRAY_CONFIG_PATH" ]; then
        print_warn "xray配置文件不存在: $XRAY_CONFIG_PATH"
        print_info "跳过配置文件更新"
        return 0
    fi

    print_info "更新xray配置文件..."

    # 备份原配置
    local backup_config="$XRAY_CONFIG_PATH.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$XRAY_CONFIG_PATH" "$backup_config"
    log "INFO" "备份xray配置到: $backup_config"

    # 检查配置文件格式
    if ! python3 -c "import json; json.load(open('$XRAY_CONFIG_PATH'))" 2>/dev/null; then
        print_error "xray配置文件格式无效"
        return 1
    fi

    # 使用jq更新配置（如果可用）
    if command -v jq &> /dev/null; then
        update_config_with_jq "$domain"
    else
        update_config_with_sed "$domain"
    fi

    print_info "xray配置文件更新完成"
    log "INFO" "xray配置文件已更新"
}

# 使用jq更新配置
update_config_with_jq() {
    local domain="$1"

    # 更新inbounds配置中的TLS证书路径
    jq --arg cert "/etc/xray/cert.pem" --arg key "/etc/xray/key.pem" '
        (.inbounds[]? | select(.streamSettings?.tls?.settings?.certificates) | .streamSettings.tls.settings.certificates[0]) |=
        {
            certificateFile: $cert,
            keyFile: $key
        }
    ' "$XRAY_CONFIG_PATH" > "$XRAY_CONFIG_PATH.tmp" && mv "$XRAY_CONFIG_PATH.tmp" "$XRAY_CONFIG_PATH"

    # 更新outbounds配置中的TLS证书路径
    jq --arg cert "/etc/xray/cert.pem" --arg key "/etc/xray/key.pem" '
        (.outbounds[]? | select(.streamSettings?.tls?.settings?.certificates) | .streamSettings.tls.settings.certificates[0]) |=
        {
            certificateFile: $cert,
            keyFile: $key
        }
    ' "$XRAY_CONFIG_PATH" > "$XRAY_CONFIG_PATH.tmp" && mv "$XRAY_CONFIG_PATH.tmp" "$XRAY_CONFIG_PATH"
}

# 使用sed更新配置（备用方案）
update_config_with_sed() {
    local domain="$1"

    # 更新证书路径
    sed -i 's|"certificateFile": *"[^"]*"|"certificateFile": "/etc/xray/cert.pem"|g' "$XRAY_CONFIG_PATH"
    sed -i 's|"keyFile": *"[^"]*"|"keyFile": "/etc/xray/key.pem"|g' "$XRAY_CONFIG_PATH"

    print_warn "使用sed更新配置，请检查配置文件格式"
}

# 重启xray服务
restart_xray_service() {
    if [ "$AUTO_RESTART_XRAY" != "yes" ]; then
        print_info "自动重启已禁用，请手动重启xray服务"
        return 0
    fi

    print_info "重启xray服务..."

    local service_manager=$(detect_service_manager)
    local service_names=("xray" "xray.service")

    local restarted=false

    for service_name in "${service_names[@]}"; do
        case "$service_manager" in
            "systemd")
                if systemctl list-unit-files | grep -q "^$service_name"; then
                    if systemctl is-active --quiet "$service_name"; then
                        print_info "重启systemd服务: $service_name"
                        systemctl restart "$service_name" && {
                            print_info "xray服务重启成功"
                            log "INFO" "xray服务重启成功: $service_name"
                            restarted=true
                            break
                        } || {
                            print_error "xray服务重启失败: $service_name"
                            log "ERROR" "xray服务重启失败: $service_name"
                        }
                    else
                        print_info "启动systemd服务: $service_name"
                        systemctl start "$service_name" && {
                            print_info "xray服务启动成功"
                            log "INFO" "xray服务启动成功: $service_name"
                            restarted=true
                            break
                        } || {
                            print_error "xray服务启动失败: $service_name"
                            log "ERROR" "xray服务启动失败: $service_name"
                        }
                    fi
                fi
                ;;
            "sysvinit")
                if service "$service_name" status &>/dev/null; then
                    print_info "重启SysV服务: $service_name"
                    service "$service_name" restart && {
                        print_info "xray服务重启成功"
                        log "INFO" "xray服务重启成功: $service_name"
                        restarted=true
                        break
                    } || {
                        print_error "xray服务重启失败: $service_name"
                        log "ERROR" "xray服务重启失败: $service_name"
                    }
                fi
                ;;
            "openrc")
                if rc-service "$service_name" status &>/dev/null; then
                    print_info "重启OpenRC服务: $service_name"
                    rc-service "$service_name" restart && {
                        print_info "xray服务重启成功"
                        log "INFO" "xray服务重启成功: $service_name"
                        restarted=true
                        break
                    } || {
                        print_error "xray服务重启失败: $service_name"
                        log "ERROR" "xray服务重启失败: $service_name"
                    }
                fi
                ;;
        esac
    done

    if [ "$restarted" = false ]; then
        print_warn "未找到xray服务或重启失败"
        print_info "请手动重启xray服务"

        # 尝试直接执行xray二进制文件
        restart_xray_binary
    fi
}

# 直接重启xray二进制文件
restart_xray_binary() {
    local xray_binary_paths=(
        "/usr/local/bin/xray"
        "/usr/bin/xray"
        "$HOME/xray"
        "$HOME/.local/bin/xray"
    )

    for binary_path in "${xray_binary_paths[@]}"; do
        if [ -f "$binary_path" ]; then
            print_info "尝试直接重启xray二进制文件: $binary_path"

            # 查找xray进程
            local pids=$(pgrep -f "$binary_path" 2>/dev/null || true)

            if [ -n "$pids" ]; then
                print_info "终止现有xray进程: $pids"
                echo "$pids" | xargs kill 2>/dev/null || true
                sleep 2
            fi

            # 启动xray
            if [ -f "$XRAY_CONFIG_PATH" ]; then
                nohup "$binary_path" -c "$XRAY_CONFIG_PATH" > "$LOG_PATH/xray.log" 2>&1 &
                print_info "xray二进制文件已启动"
                log "INFO" "xray二进制文件已启动: $binary_path"
            else
                print_warn "未找到xray配置文件"
            fi
            return 0
        fi
    done

    print_error "未找到xray二进制文件"
    return 1
}

# 验证证书安装
verify_installation() {
    local domain="$1"
    local cert_file="/etc/xray/cert.pem"

    if [ ! -f "$cert_file" ]; then
        print_error "证书文件安装失败: $cert_file"
        return 1
    fi

    # 验证证书
    if openssl x509 -in "$cert_file" -noout -text &>/dev/null; then
        print_info "证书验证成功"

        # 检查证书域名
        local cert_domains=$(openssl x509 -in "$cert_file" -noout -text | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/DNS://g' | tr ',' '\n' | sed 's/^ *//' | grep -v '^$' | tr '\n' ' ')
        print_info "证书域名: $cert_domains"

        log "INFO" "证书验证成功，域名: $cert_domains"
        return 0
    else
        print_error "证书验证失败"
        log "ERROR" "证书验证失败"
        return 1
    fi
}

# 测试xray服务
test_xray_service() {
    print_info "测试xray服务状态..."

    # 检查端口监听
    local common_ports=(443 80 8443)

    for port in "${common_ports[@]}"; do
        if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
            print_info "检测到端口 $port 正在监听"
        fi
    done

    # 检查进程
    if pgrep -f "xray" >/dev/null; then
        print_info "xray进程正在运行"
        log "INFO" "xray进程运行正常"
    else
        print_warn "未检测到xray进程"
        log "WARN" "未检测到xray进程"
    fi
}

# 主安装函数
main() {
    local domain="$1"

    if [ -z "$domain" ]; then
        # 从配置文件获取主域名
        read -ra DOMAIN_ARRAY <<< "$DOMAINS"
        domain="${DOMAIN_ARRAY[0]}"
    fi

    if [ -z "$domain" ]; then
        print_error "未指定域名且配置文件中无域名信息"
        exit 1
    fi

    print_info "开始安装证书: $domain"
    log "INFO" "开始安装证书: $domain"

    # 创建日志目录
    mkdir -p "$LOG_PATH"

    # 检测系统环境
    detect_xray_paths

    # 备份现有证书
    backup_certificates "$domain"

    # 安装证书
    install_to_system "$domain" || {
        print_error "证书安装失败"
        exit 1
    }

    # 更新xray配置
    update_xray_config "$domain" || {
        print_warn "xray配置更新失败，请手动检查"
    }

    # 重启服务
    restart_xray_service

    # 验证安装
    sleep 3
    verify_installation "$domain" || {
        print_error "证书安装验证失败"
        exit 1
    }

    # 测试服务
    test_xray_service

    print_info "证书安装完成！"
    print_info "证书文件: /etc/xray/cert.pem"
    print_info "私钥文件: /etc/xray/key.pem"
    log "INFO" "证书安装完成: $domain"
}

# 显示帮助信息
show_help() {
    echo "SSL证书安装脚本"
    echo ""
    echo "用法: $0 [域名]"
    echo ""
    echo "参数:"
    echo "  域名    要安装证书的域名 (可选，默认使用配置文件中的主域名)"
    echo ""
    echo "示例:"
    echo "  $0                  # 安装配置文件中的主域名证书"
    echo "  $0 example.com      # 安装example.com的证书"
    echo ""
    echo "配置文件: $PROJECT_DIR/config/dnsapi.conf"
    echo "日志文件: $LOG_PATH/install-cert.log"
}

# 处理命令行参数
case "${1:-}" in
    "-h"|"--help"|"help")
        show_help
        exit 0
        ;;
    *)
        main "$1"
        ;;
esac