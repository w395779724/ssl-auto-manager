# 腾讯云域名SSL证书自动管理系统

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![ACME.sh](https://img.shields.io/badge/ACME-acme.sh-blue.svg)](https://github.com/acmesh-official/acme.sh)

一个基于acme.sh和腾讯云DNS API的SSL证书自动申请、续签和安装系统，专为xray面板设计，支持全自动化的证书管理。

## ✨ 特性亮点

- 🚀 **一键安装** - 支持curl一键安装，无需手动下载
- 🔧 **交互式配置** - 安装过程引导式配置，用户友好
- 🔄 **全自动续签** - 定时检查和自动续签，避免证书过期
- 🌐 **多域名支持** - 支持SAN证书，一个证书包含多个域名
- 🛡️ **智能备份** - 自动备份现有证书和配置文件
- 📊 **详细日志** - 完整的操作日志记录，便于问题排查
- 🎯 **xray集成** - 专为xray设计，自动安装和重启服务
- 🔒 **安全可靠** - 支持ECC证书，API密钥安全存储

## 🚀 功能特性

- **全自动申请**: 通过腾讯云DNS API自动验证域名所有权
- **自动续签**: 支持定时检查和自动续签，避免证书过期
- **自动安装**: 自动安装证书到xray并重启服务
- **多域名支持**: 支持单个证书包含多个域名（SAN）
- **ECC证书**: 可选择使用RSA或ECC证书
- **智能备份**: 自动备份现有证书和配置文件
- **日志记录**: 详细的操作日志，便于问题排查
- **跨平台**: 支持Linux、macOS等操作系统
- **多种服务管理**: 支持systemd、SysV init、OpenRC等服务管理器

## 📋 系统要求

- Linux或macOS操作系统
- Bash shell环境
- 腾讯云账号和DNS管理权限
- xray代理服务（可选）

## 🚀 快速安装

### 方法一：一键安装（推荐）

直接在服务器上运行以下命令：

```bash
curl -fsSL https://raw.githubusercontent.com/w395779724/ssl-auto-manager/main/quick-install.sh | bash
```

### 方法二：手动安装

#### 1. 克隆或下载项目

```bash
git clone https://github.com/w395779724/ssl-auto-manager.git
cd ssl-auto-manager
```

#### 2. 运行交互式安装脚本

```bash
chmod +x install.sh
./install.sh
```

### 交互式安装说明

安装脚本将引导您完成以下配置：
- 🔑 腾讯云API密钥配置（SecretId 和 SecretKey）
- 🌐 域名列表配置（支持多域名）
- 📧 邮箱地址配置
- ⚙️ xray服务配置
- 🔧 高级选项（续签提醒、ECC证书等）

安装脚本会自动：
- 安装必要的依赖（curl、openssl、socat等）
- 安装acme.sh证书管理工具
- 创建项目目录结构
- 生成配置文件模板
- 创建所有必要的脚本

安装脚本会自动：
- 安装必要的依赖（curl、openssl、socat等）
- 安装acme.sh证书管理工具
- 创建项目目录结构
- 生成交互式配置文件
- 创建所有必要的脚本
- 测试配置是否正确

## 📋 安装前准备

**获取腾讯云API密钥**：
1. 访问[腾讯云API密钥控制台](https://console.cloud.tencent.com/cam/capi)
2. 创建新的API密钥或使用现有密钥
3. 确保密钥具有DNS解析权限

**系统要求确认**：
- 域名已托管在腾讯云DNS
- 服务器能访问外网（需要联系Let's Encrypt服务器）
- 具有sudo权限（用于安装依赖和管理服务）

## 📖 使用指南

### 申请新证书

```bash
# 申请配置文件中的所有域名证书
./scripts/cert-manager.sh issue
```

### 检查证书状态

```bash
# 检查证书状态并自动续签
./scripts/cert-manager.sh check

# 查看证书状态
./scripts/cert-manager.sh status
```

### 续签证书

```bash
# 续签配置文件中的域名证书
./scripts/cert-manager.sh renew

# 续签指定域名证书
./scripts/cert-manager.sh renew example.com
```

### 查看证书信息

```bash
# 列出所有证书
./scripts/cert-manager.sh list

# 查看指定域名的证书详情
./scripts/cert-manager.sh info example.com
```

### 删除证书

```bash
# 删除指定域名的证书
./scripts/cert-manager.sh remove example.com
```

### 设置定时任务

```bash
# 设置每天凌晨2点自动检查续签
./scripts/setup-cron.sh setup

# 查看定时任务状态
./scripts/setup-cron.sh status

# 手动执行一次续签检查
./scripts/setup-cron.sh run

# 移除定时任务
./scripts/setup-cron.sh remove
```

## 📁 项目结构

```
腾讯云域名证书/
├── README.md                    # 使用说明文档
├── install.sh                   # 安装脚本
├── config/
│   └── dnsapi.conf              # 配置文件
├── scripts/
│   ├── cert-manager.sh          # 主证书管理脚本
│   ├── install-cert.sh          # 证书安装脚本
│   └── setup-cron.sh            # 定时任务配置脚本
├── certs/
│   ├── live/                    # 当前使用的证书
│   └── archive/                 # 证书历史备份
└── logs/                        # 日志文件
    ├── cert-manager.log         # 证书管理日志
    ├── install-cert.log         # 证书安装日志
    └── cron.log                 # 定时任务日志
```

## ⚙️ 配置选项

完整配置文件 `config/dnsapi.conf` 说明：

```bash
# 腾讯云DNS API配置
DP_Id="your-secret-id-here"           # 腾讯云SecretId
DP_Key="your-secret-key-here"         # 腾讯云SecretKey

# 域名配置
DOMAINS="example.com www.example.com" # 域名列表
EMAIL="your-email@example.com"        # 邮箱地址

# 路径配置
CERT_PATH="$HOME/腾讯云域名证书/certs" # 证书存储路径
LOG_PATH="$HOME/腾讯云域名证书/logs"   # 日志路径
XRAY_CONFIG_PATH="/usr/local/etc/xray/config.json" # xray配置文件路径

# 自动化配置
AUTO_RESTART_XRAY="yes"               # 是否自动重启xray
RENEW_REMIND_DAYS="30"                # 续签提醒天数
FORCE_RENEW_DAYS="15"                 # 强制续签天数

# 高级配置
ACME_SERVER="https://acme-v02.api.letsencrypt.org/directory" # ACME服务器
RSA_KEY_SIZE="2048"                   # RSA密钥长度
USE_ECC="no"                          # 是否使用ECC证书
DNS_TTL="600"                         # DNS解析TTL
API_TIMEOUT="30"                      # API请求超时时间
```

## 🔍 证书管理命令

### cert-manager.sh 命令详解

```bash
# 基本命令
./scripts/cert-manager.sh issue              # 申请新证书
./scripts/cert-manager.sh renew [domain]     # 续签证书
./scripts/cert-manager.sh check              # 检查并自动续签
./scripts/cert-manager.sh status             # 查看证书状态
./scripts/cert-manager.sh list               # 列出所有证书
./scripts/cert-manager.sh info <domain>      # 显示证书详情
./scripts/cert-manager.sh remove <domain>    # 删除证书

# 管理命令
./scripts/cert-manager.sh test-api           # 测试腾讯云API连接
./scripts/cert-manager.sh clean-logs [days]  # 清理日志文件
./scripts/cert-manager.sh help               # 显示帮助信息
```

### setup-cron.sh 命令详解

```bash
./scripts/setup-cron.sh setup      # 设置定时任务
./scripts/setup-cron.sh remove     # 移除定时任务
./scripts/setup-cron.sh status     # 查看定时任务状态
./scripts/setup-cron.sh run        # 手动执行定时任务
```

## 🛠️ 故障排除

### 常见问题

1. **API密钥错误**
   ```bash
   # 测试API连接
   ./scripts/cert-manager.sh test-api
   ```
   - 检查API密钥是否正确
   - 确认密钥具有DNS管理权限
   - 检查网络连接是否正常

2. **DNS解析失败**
   ```bash
   # 检查域名DNS记录
   nslookup your-domain.com
   dig your-domain.com
   ```
   - 确认域名托管在腾讯云
   - 检查域名状态是否正常
   - 确认API密钥权限

3. **证书申请失败**
   ```bash
   # 查看详细日志
   tail -f logs/cert-manager.log
   ```
   - 检查域名配置是否正确
   - 确认腾讯云DNS服务正常
   - 检查网络连接和防火墙设置

4. **xray服务重启失败**
   ```bash
   # 检查xray服务状态
   systemctl status xray
   service xray status
   ```
   - 检查xray配置文件语法
   - 确认证书文件权限正确
   - 查看xray错误日志

### 日志文件

- `logs/cert-manager.log` - 证书申请和管理日志
- `logs/install-cert.log` - 证书安装和xray配置日志
- `logs/cron.log` - 定时任务执行日志

### 重新安装

如果需要重新安装：
```bash
# 清理现有安装
rm -rf ~/.acme.sh
rm -rf certs/ logs/

# 重新运行安装
./install.sh
```

## 🔐 安全建议

1. **API密钥安全**
   - 定期轮换API密钥
   - 使用最小权限原则
   - 不要在代码中硬编码密钥

2. **证书文件安全**
   - 设置适当的文件权限
   - 定期备份证书文件
   - 监控证书使用情况

3. **系统安全**
   - 定期更新系统和依赖
   - 使用防火墙限制不必要的端口
   - 监控系统日志

## 📞 支持与反馈

- 🐛 **问题报告**: [GitHub Issues](https://github.com/w395779724/ssl-auto-manager/issues)
- 💡 **功能建议**: [GitHub Discussions](https://github.com/w395779724/ssl-auto-manager/discussions)
- 📧 **联系我们**: 通过GitHub Issues联系维护者

### 常见问题

查看[故障排除指南](https://github.com/w395779724/ssl-auto-manager/wiki/Troubleshooting)了解更多常见问题解决方案。

## 🤝 贡献指南

欢迎贡献代码！请查看[贡献指南](CONTRIBUTING.md)了解如何参与项目开发。

### 贡献者

感谢所有为本项目做出贡献的开发者！

## 📄 许可证

本项目采用 [MIT 许可证](LICENSE)。

## 🔗 相关链接

- 📖 [项目文档](https://github.com/w395779724/ssl-auto-manager/wiki)
- 🚀 [在线演示](https://demo.w395779724.com)
- 📊 [统计信息](https://github.com/w395779724/ssl-auto-manager/graphs)
- 🏷️ [发布版本](https://github.com/w395779724/ssl-auto-manager/releases)

## 🙏 致谢

- [acme.sh](https://github.com/acmesh-official/acme.sh) - 优秀的ACME客户端
- [Let's Encrypt](https://letsencrypt.org/) - 免费的SSL证书颁发机构
- [腾讯云](https://cloud.tencent.com/) - 提供DNS API服务
- [xray](https://github.com/XTLS/Xray-core) - 高性能代理工具

## ⭐ Star History

如果这个项目对您有帮助，请给我们一个 ⭐️

[![Star History Chart](https://api.star-history.com/svg?repos=w395779724/ssl-auto-manager&type=Date)](https://star-history.com/#w395779724/ssl-auto-manager&Date)

---

**⚠️ 免责声明**: 本工具仅供学习和合法用途使用。请确保您已阅读并理解相关服务的使用条款和隐私政策。使用本工具所产生的任何后果由用户自行承担。