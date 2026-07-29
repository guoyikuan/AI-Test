# Agency Agents 本地完整部署

本目录用于在 macOS 上完成以下安装：

- 保留 Homebrew 管理的 Agency Agents 桌面应用；
- 使用 Homebrew Node 安装官方 OpenClaw CLI；
- 为 Codex、Claude Code、Copilot、Gemini CLI、Qwen、Cursor 和 OpenClaw 安装 Agent；
- 自动安装上游脚本检测到的其他工具适配器；
- 注册全部 OpenClaw 工作区并重启本地 Gateway；
- 校验 OpenClaw 工作区集合已全部进入运行时注册列表。

执行：

```bash
chmod +x local-deployment/install-all-local.sh
./local-deployment/install-all-local.sh
```

安全边界：

- 仓库只保存脱敏配置模板和安装清单；
- 不提交真实 Token、Cookie、密码、私钥、认证头或本机运行时缓存；
- `openclaw.config.example.json` 仅为结构示例，不能直接替代本机配置；
- 本机真实 OpenClaw 配置默认位于 `~/.openclaw/`，不得复制进仓库。

来源：

- 上游项目：`https://github.com/msitarzewski/agency-agents`
- 导入提交：`8ef49232e02431f7ca4792b487e5a85a7939ff3a`
