# 贡献指南

感谢您对SSL证书自动管理系统的关注！我们欢迎各种形式的贡献。

## 🤝 如何贡献

### 报告问题

- 使用 [GitHub Issues](https://github.com/w395779724/ssl-auto-manager/issues) 报告bug
- 提供详细的问题描述和复现步骤
- 包含系统环境信息（操作系统、shell版本等）
- 附上相关日志文件

### 功能建议

- 在 [GitHub Discussions](https://github.com/w395779724/ssl-auto-manager/discussions) 中讨论新功能
- 提供详细的功能描述和使用场景
- 考虑功能的普适性和维护成本

### 代码贡献

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add some amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 创建 Pull Request

## 📝 代码规范

### Shell脚本规范

- 使用4个空格缩进
- 函数名使用下划线分隔
- 变量名使用大写字母
- 添加适当的注释
- 使用 `set -e` 确保脚本出错时退出

### 提交信息规范

```
<type>(<scope>): <subject>

<body>

<footer>
```

类型：
- `feat`: 新功能
- `fix`: 修复bug
- `docs`: 文档更新
- `style`: 代码格式调整
- `refactor`: 代码重构
- `test`: 测试相关
- `chore`: 构建过程或辅助工具的变动

## 🧪 测试

在提交PR之前，请确保：

1. 在多个操作系统上测试脚本
2. 验证所有功能正常工作
3. 检查错误处理和日志记录
4. 确保向后兼容性

## 📋 检查清单

提交PR前请确认：

- [ ] 代码遵循项目规范
- [ ] 添加了必要的测试
- [ ] 更新了相关文档
- [ ] 通过了所有测试
- [ ] 没有引入新的警告

## 📧 联系方式

如有疑问，请通过以下方式联系：

- GitHub Issues
- GitHub Discussions
- Email: your-email@example.com

感谢您的贡献！🎉