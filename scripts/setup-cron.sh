#!/bin/bash

# 定时任务配置脚本
# 设置自动续签定时任务，支持多种操作系统

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
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检测操作系统
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v systemctl &> /dev/null; then
            echo "systemd"
        elif command -v service &> /dev/null; then
            echo "sysvinit"
        else
            echo "linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

# 创建定时任务脚本
create_cron_script() {
    print_info "创建定时任务执行脚本..."

    cat > "$PROJECT_DIR/scripts/cron-renew.sh" << 'CRON_EOF'
#!/bin/bash

# 自动续签定时任务脚本
# 每天凌晨2点自动检查并续签证书

set -e

# 项目路径
PROJECT_DIR="$HOME/腾讯云域名证书"
LOG_FILE="$PROJECT_DIR/logs/cron.log"
LOCK_FILE="/tmp/cert-manager.lock"

# 日志函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# 检查锁文件，防止重复执行
if [ -f "$LOCK_FILE" ]; then
    log "检测到锁文件，可能有其他进程正在执行，跳过本次执行"
    exit 0
fi

# 创建锁文件
touch "$LOCK_FILE"

# 清理函数
cleanup() {
    rm -f "$LOCK_FILE"
    log "清理完成"
}

# 设置清理trap
trap cleanup EXIT

log "=== 开始执行定时续签检查 ==="

# 检查项目目录是否存在
if [ ! -d "$PROJECT_DIR" ]; then
    log "错误: 项目目录不存在 $PROJECT_DIR"
    exit 1
fi

# 检查主脚本是否存在
if [ ! -f "$PROJECT_DIR/scripts/cert-manager.sh" ]; then
    log "错误: 主脚本不存在 $PROJECT_DIR/scripts/cert-manager.sh"
    exit 1
fi

# 执行证书检查和续签
cd "$PROJECT_DIR"
bash "$PROJECT_DIR/scripts/cert-manager.sh" check >> "$LOG_FILE" 2>&1
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    log "证书检查完成，状态正常"
elif [ $EXIT_CODE -eq 1 ]; then
    log "证书检查完成，需要关注"
elif [ $EXIT_CODE -eq 2 ]; then
    log "证书检查完成，已自动续签"
else
    log "证书检查失败，退出码: $EXIT_CODE"
fi

log "=== 定时续签检查完成 ==="
CRON_EOF

    chmod +x "$PROJECT_DIR/scripts/cron-renew.sh"
    print_info "定时任务脚本已创建: $PROJECT_DIR/scripts/cron-renew.sh"
}

# 设置crontab定时任务
setup_crontab() {
    print_info "设置crontab定时任务..."

    local cron_entry="0 2 * * * $PROJECT_DIR/scripts/cron-renew.sh"

    # 检查是否已存在相同的定时任务
    if crontab -l 2>/dev/null | grep -F "$PROJECT_DIR/scripts/cron-renew.sh" > /dev/null; then
        print_warn "定时任务已存在，跳过设置"
        return 0
    fi

    # 添加定时任务
    (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -

    print_info "crontab定时任务已设置"
    print_info "执行时间: 每天凌晨2:00"
    print_info "任务日志: $PROJECT_DIR/logs/cron.log"
}

# 移除crontab定时任务
remove_crontab() {
    print_info "移除crontab定时任务..."

    # 创建临时文件
    local temp_cron=$(mktemp)

    # 获取当前crontab并移除相关行
    crontab -l 2>/dev/null | grep -v -F "$PROJECT_DIR/scripts/cron-renew.sh" > "$temp_cron" 2>/dev/null || true

    # 重新设置crontab
    crontab "$temp_cron" 2>/dev/null || {
        # 如果crontab为空，删除crontab
        crontab -r 2>/dev/null || true
    }

    # 删除临时文件
    rm -f "$temp_cron"

    print_info "crontab定时任务已移除"
}

# 创建systemd定时器
setup_systemd_timer() {
    print_info "创建systemd定时器..."

    local service_name="cert-manager"
    local timer_name="cert-manager"

    # 创建service文件
    cat > "/tmp/$service_name.service" << EOF
[Unit]
Description=SSL Certificate Auto Renewal Service
After=network.target

[Service]
Type=oneshot
User=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/scripts/cron-renew.sh
StandardOutput=append:$PROJECT_DIR/logs/systemd.log
StandardError=append:$PROJECT_DIR/logs/systemd.log

[Install]
WantedBy=multi-user.target
EOF

    # 创建timer文件
    cat > "/tmp/$timer_name.timer" << EOF
[Unit]
Description=SSL Certificate Auto Renewal Timer
Requires=$service_name.service

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    print_info "systemd服务文件已创建，请手动安装："
    print_info "sudo cp /tmp/$service_name.service /etc/systemd/system/"
    print_info "sudo cp /tmp/$timer_name.timer /etc/systemd/system/"
    print_info "sudo systemctl daemon-reload"
    print_info "sudo systemctl enable $timer_name.timer"
    print_info "sudo systemctl start $timer_name.timer"
}

# 创建macOS launchd任务
setup_launchd() {
    print_info "创建macOS launchd定时任务..."

    local plist_name="com.certmanager.renew"
    local plist_file="$HOME/Library/LaunchAgents/$plist_name.plist"

    cat > "$plist_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$plist_name</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PROJECT_DIR/scripts/cron-renew.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>2</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$PROJECT_DIR/logs/launchd.log</string>
    <key>StandardErrorPath</key>
    <string>$PROJECT_DIR/logs/launchd.log</string>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
EOF

    # 加载任务
    launchctl load "$plist_file"

    print_info "macOS launchd任务已创建并加载"
    print_info "任务文件: $plist_file"
    print_info "日志文件: $PROJECT_DIR/logs/launchd.log"
}

# 移除macOS launchd任务
remove_launchd() {
    print_info "移除macOS launchd定时任务..."

    local plist_name="com.certmanager.renew"
    local plist_file="$HOME/Library/LaunchAgents/$plist_name.plist"

    if [ -f "$plist_file" ]; then
        launchctl unload "$plist_file" 2>/dev/null || true
        rm -f "$plist_file"
        print_info "macOS launchd任务已移除"
    else
        print_warn "未找到launchd任务文件"
    fi
}

# 设置定时任务
setup_cron() {
    print_info "设置自动续签定时任务..."

    # 创建定时任务脚本
    create_cron_script

    # 检测操作系统并设置相应的定时任务
    local os_type=$(detect_os)

    case "$os_type" in
        "systemd")
            print_warn "检测到systemd系统"
            print_info "优先使用crontab，如需systemd timer请手动配置"
            setup_crontab
            ;;
        "sysvinit")
            print_info "检测到SysV init系统，使用crontab"
            setup_crontab
            ;;
        "macos")
            print_info "检测到macOS系统，使用launchd"
            setup_launchd
            ;;
        "linux")
            print_info "检测到Linux系统，使用crontab"
            setup_crontab
            ;;
        *)
            print_warn "未知操作系统，尝试使用crontab"
            setup_crontab
            ;;
    esac

    print_info "定时任务设置完成！"
    print_info ""
    print_info "定时执行时间: 每天凌晨2:00"
    print_info "日志位置: $PROJECT_DIR/logs/cron.log"
    print_info ""
    print_info "可以使用以下命令查看日志:"
    print_info "  tail -f $PROJECT_DIR/logs/cron.log"
}

# 移除定时任务
remove_cron() {
    print_info "移除自动续签定时任务..."

    local os_type=$(detect_os)

    case "$os_type" in
        "macos")
            remove_launchd
            ;;
        *)
            remove_crontab
            ;;
    esac

    # 删除定时任务脚本
    rm -f "$PROJECT_DIR/scripts/cron-renew.sh"

    print_info "定时任务已移除"
}

# 检查定时任务状态
check_cron_status() {
    print_info "检查定时任务状态..."

    local os_type=$(detect_os)

    case "$os_type" in
        "macos")
            local plist_name="com.certmanager.renew"
            local plist_file="$HOME/Library/LaunchAgents/$plist_name.plist"

            if [ -f "$plist_file" ]; then
                if launchctl list | grep -q "$plist_name"; then
                    print_info "launchd任务状态: 运行中"
                else
                    print_warn "launchd任务状态: 已停止"
                fi
            else
                print_warn "未找到launchd任务"
            fi
            ;;
        *)
            if crontab -l 2>/dev/null | grep -q -F "$PROJECT_DIR/scripts/cron-renew.sh"; then
                print_info "crontab任务状态: 已设置"
                print_info "任务内容: $(crontab -l 2>/dev/null | grep -F "$PROJECT_DIR/scripts/cron-renew.sh")"
            else
                print_warn "未找到crontab任务"
            fi
            ;;
    esac

    # 检查日志文件
    local log_file="$PROJECT_DIR/logs/cron.log"
    if [ -f "$log_file" ]; then
        print_info "日志文件存在: $log_file"
        print_info "最近5条日志:"
        tail -5 "$log_file" 2>/dev/null | sed 's/^/  /'
    else
        print_warn "日志文件不存在: $log_file"
    fi
}

# 手动执行定时任务
run_cron_now() {
    print_info "手动执行定时任务..."

    if [ ! -f "$PROJECT_DIR/scripts/cron-renew.sh" ]; then
        print_error "定时任务脚本不存在，请先设置定时任务"
        return 1
    fi

    bash "$PROJECT_DIR/scripts/cron-renew.sh"
}

# 显示帮助信息
show_help() {
    echo "定时任务配置脚本"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "命令:"
    echo "  setup     设置定时任务"
    echo "  remove    移除定时任务"
    echo "  status    检查定时任务状态"
    echo "  run       手动执行定时任务"
    echo "  help      显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 setup     # 设置每天凌晨2点自动续签"
    echo "  $0 status    # 查看定时任务状态"
    echo "  $0 run       # 立即执行一次续签检查"
}

# 主函数
main() {
    # 创建日志目录
    mkdir -p "$PROJECT_DIR/logs"

    case "${1:-help}" in
        "setup")
            setup_cron
            ;;
        "remove")
            remove_cron
            ;;
        "status")
            check_cron_status
            ;;
        "run")
            run_cron_now
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

main "$@"