# 🚀 快速开始指南

本指南将帮助您在5分钟内完成SSL证书自动管理系统的配置和使用。

## 📋 前置准备

1. **腾讯云账号** - 需要有域名管理权限
2. **Linux/macOS系统** - 支持Bash环境
3. **xray服务** - 已安装并运行（可选）

## ⚡ 5分钟快速配置

### 步骤 1: 运行安装脚本 (1分钟)

```bash
# 进入项目目录
cd "腾讯云域名证书"

# 运行安装脚本
chmod +x install.sh
./install.sh
```

### 步骤 2: 获取腾讯云API密钥 (2分钟)

1. 访问 [腾讯云API密钥控制台](https://console.cloud.tencent.com/cam/capi)
2. 点击"新建密钥"或使用现有密钥
3. 记录 **SecretId** 和 **SecretKey**

### 步骤 3: 配置系统 (1分钟)

编辑配置文件：
```bash
nano config/dnsapi.conf
```

修改以下配置：
```bash
# 替换为你的API密钥
DP_Id="your-secret-id-here"
DP_Key="your-secret-key-here"

# 替换为你的域名
DOMAINS="your-domain.com www.your-domain.com"

# 替换为你的邮箱
EMAIL="your-email@example.com"
```

### 步骤 4: 申请证书 (1分钟)

```bash
# 申请SSL证书
./scripts/cert-manager.sh issue
```

### 步骤 5: 设置自动续签 (可选，30秒)

```bash
# 设置每天凌晨2点自动检查续签
./scripts/setup-cron.sh setup
```

## ✅ 验证安装

检查证书状态：
```bash
./scripts/cert-manager.sh status
```

如果看到类似输出，说明安装成功：
```
[INFO] 2024-01-01 12:00:00 - 证书将在 89 天后过期
[INFO] 2024-01-01 12:00:00 - 证书状态良好
```

## 🔧 常用命令

```bash
# 查看所有证书
./scripts/cert-manager.sh list

# 查看证书详情
./scripts/cert-manager.sh info your-domain.com

# 手动检查续签
./scripts/cert-manager.sh check

# 查看定时任务状态
./scripts/setup-cron.sh status

# 查看日志
tail -f logs/cert-manager.log
```

## 🆘 遇到问题？

### 常见错误及解决方案

**错误**: "请配置腾讯云API SecretId"
```bash
# 解决: 检查配置文件
nano config/dnsapi.conf
# 确保DP_Id和DP_Key已正确填写
```

**错误**: "证书申请失败"
```bash
# 解决: 测试API连接
./scripts/cert-manager.sh test-api

# 查看详细日志
tail -f logs/cert-manager.log
```

**错误**: "xray服务重启失败"
```bash
# 解决: 检查xray状态
systemctl status xray

# 手动安装证书
./scripts/install-cert.sh
```

## 📞 需要帮助？

1. 查看完整文档: `README.md`
2. 查看故障排除: `README.md#故障排除`
3. 提交Issue: [GitHub Issues](https://github.com/your-repo/ssl-auto-manager/issues)

## 🎉 完成！

恭喜！您已经成功配置了SSL证书自动管理系统。系统将：

- ✅ 自动申请和续签SSL证书
- ✅ 自动安装证书到xray
- ✅ 自动重启xray服务
- ✅ 每天检查证书状态
- ✅ 证书到期前自动续签

现在您可以专注于业务，无需担心证书过期问题！