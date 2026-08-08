# Agency Agents 269 本地使用手册

适用版本：

- 仓库基线提交：`8bed97f7df7e31ad56a1a2111be14fb73c56a159`
- 正式同步入口：`agency-agents/local-deployment/sync-all-local.sh`
- 正式同步入口 SHA-256：`f0610cabef0c689ff6c4567dd4c2794893664d8267af682ac4b9c704019e9bbd`
- 正式同步入口行数：`7740`
- 冻结同步清单：`agency-agents/local-deployment/frozen-action-manifest.json`
- 批准平台适配器集合：`aider, antigravity, claude-code, codex, cursor, gemini-cli, github-copilot, hermes, kimi, openclaw, opencode, osaurus, qwen, vibe, windsurf, zcode`

本手册只描述当前仓库中已经落盘并通过验收的最终版本事实。仓库代码层面只保留一个正式完整版本：`agency-agents/local-deployment/sync-all-local.sh`。不得再恢复、复制或依赖 legacy / trunc / temp 版本。

## 1. 目录结构

与本地同步直接相关的目录和文件：

- `agency-agents/local-deployment/sync-all-local.sh`：正式同步入口
- `agency-agents/local-deployment/frozen-action-manifest.json`：冻结的 16 平台部署清单
- `agency-agents/local-deployment/install-all-local.sh`：OpenClaw 本地注册/治理入口
- `agency-agents/local-deployment/register-openclaw-agents.mjs`：OpenClaw 工作区注册与校验
- `agency-agents/local-deployment/installation-manifest.json`：本地安装/运行时清单，含 OpenClaw `269 workspaces + 270 registeredAgents`
- `agency-agents/local-deployment/openclaw.config.example.json`：OpenClaw 脱敏示例配置
- `agency-agents/governance/base-prompt.zh-CN.md`：治理固定 JSON 合同模板
- `agency-agents/scripts/governance.py`：治理渲染与校验逻辑
- `agency-agents/scripts/tests/test_governance.py`：治理固定响应 contract 测试
- `agency-agents/local-deployment/tests/`：同步与安装测试

## 2. 前置条件与安全边界

前置条件：

- 在仓库根目录执行，或显式传入绝对路径参数。
- `sync-all-local.sh` 的 CLI 只接受绝对路径参数：`--entry`、`--source/--source-root`、`--project`、`--home`，可选 `--manifest`、`--json-report`、`--test-mode-root`、`--action-file/--auth-bytes`、`--signature-file/--auth-signature`、`--allowed-signers`、`--ledger`。
- CLI 必须显式选择一个模式：`--dry-run` 或 `--apply`。
- `install-all-local.sh` 的治理入口必须使用 `--apply-governance`；若只做预检，配合 `--dry-run`。
- `register-openclaw-agents.mjs` 的 `--verify-only` 是只读校验模式；默认模式是 apply。

安全边界：

- 默认拒绝未授权动作；治理模板明确要求高风险动作先人工审批。
- 不提交真实 Token、Cookie、密码、私钥、认证头、本机运行时缓存。
- `openclaw.config.example.json` 仅是结构示例，不能替代本机真实配置。
- 本机真实 OpenClaw 配置位于 `~/.openclaw/`，不得复制进仓库。
- `sync-all-local.sh` 帮助输出是单个 JSON 对象，不是人类可读说明页。
- 正式 apply 涉及签名/授权/ledger/allowed signers；缺这些输入时不应尝试真实写入。

## 3. 正式同步入口的准确命令

### 3.1 查看帮助

```bash
bash agency-agents/local-deployment/sync-all-local.sh --help
```

当前仓库事实：

- 返回码：`0`
- `stdout` 是一个 JSON 对象
- `schema`：`agency-agents.local-sync-report/v1`
- `failure.reason`：`help-requested`
- `result.status`：`passed`

### 3.2 dry-run 命令骨架

`sync-all-local.sh` 的参数解析器要求：

- 模式：`--dry-run`
- 必填：`--entry`、`--source`、`--project`、`--home`
- 可选：`--manifest`、`--json-report`、`--test-mode-root`

推荐显式命令骨架：

```bash
bash agency-agents/local-deployment/sync-all-local.sh \
  --dry-run \
  --entry "$(pwd)/agency-agents/local-deployment/sync-all-local.sh" \
  --source "$(pwd)/agency-agents/integrations" \
  --project "$(pwd)" \
  --home "$HOME" \
  --manifest "$(pwd)/agency-agents/local-deployment/frozen-action-manifest.json" \
  --json-report "/ABS/PATH/local-sync-report.json"
```

说明：

- 上述命令骨架只使用当前源码中已存在的 CLI 选项。
- `--json-report` 路径必须是绝对路径。
- `--source` 对应当前冻结清单中的 `sourceRoot=integrations`。

### 3.3 正式 apply 命令骨架

`sync-all-local.sh` 的参数解析器支持以下 apply 相关参数：

- `--apply`
- `--action-file` / `--auth-bytes`
- `--signature-file` / `--auth-signature`
- `--allowed-signers`
- `--ledger`

准确命令骨架如下：

```bash
bash agency-agents/local-deployment/sync-all-local.sh \
  --apply \
  --entry "$(pwd)/agency-agents/local-deployment/sync-all-local.sh" \
  --source "$(pwd)/agency-agents/integrations" \
  --project "$(pwd)" \
  --home "$HOME" \
  --manifest "$(pwd)/agency-agents/local-deployment/frozen-action-manifest.json" \
  --json-report "/ABS/PATH/local-sync-report.json" \
  --action-file "/ABS/PATH/authorization-bytes.json" \
  --signature-file "/ABS/PATH/authorization.sig" \
  --allowed-signers "/ABS/PATH/allowed_signers" \
  --ledger "/ABS/PATH/replay-ledger.json"
```

注意：

- 这里给的是当前源码可接受的真实参数名和参数位，不代表任何环境都已经具备可执行的授权材料。
- 没有合法授权材料时，不要自行改成 apply。

## 4. OpenClaw 269+main 的使用与检查

当前仓库事实来自 `agency-agents/local-deployment/installation-manifest.json`：

- `runtime.openclaw.workspaces = 269`
- `runtime.openclaw.registeredAgents = 270`
- 这里的 `270 = 269 workspaces + main`

### 4.1 只读检查安装清单

```bash
jq '.runtime.openclaw' agency-agents/local-deployment/installation-manifest.json
```

最小检查：

```bash
jq -r '.runtime.openclaw.workspaces, .runtime.openclaw.registeredAgents' \
  agency-agents/local-deployment/installation-manifest.json
```

预期：

- 第一行：`269`
- 第二行：`270`

### 4.2 OpenClaw 注册校验

`register-openclaw-agents.mjs` 的帮助声明了以下只读校验模式：

```bash
node agency-agents/local-deployment/register-openclaw-agents.mjs \
  --verify-only \
  --manifest "$HOME/.openclaw/agency-agents/installation-manifest.json"
```

当前源码里的完整参数集为：

```bash
node agency-agents/local-deployment/register-openclaw-agents.mjs \
  --verify-only \
  --manifest "/ABS/PATH/installation-manifest.json" \
  --workspace-root "$HOME/.openclaw/agency-agents" \
  --config-path "$HOME/.openclaw/openclaw.json" \
  --agent-root "$HOME/.openclaw/agents" \
  --backup-root "$HOME/.openclaw/backups" \
  --expected-governance-hash "<HASH>"
```

### 4.3 main 检查路径

测试中被显式探测的 OpenClaw owner 路径包括：

- `~/.openclaw/agents/main`
- `~/.openclaw/agents/main/agent/auth-profiles.json`

这说明当前校验口径明确把 `main` 作为 OpenClaw 运行时对象的一部分。

## 5. 批准平台适配器的使用与检查

### 5.1 冻结集合检查

```bash
jq -r '.tools[].name' agency-agents/local-deployment/frozen-action-manifest.json
```

预期顺序与冻结值：

```text
aider
antigravity
claude-code
github-copilot
codex
cursor
gemini-cli
kimi
openclaw
opencode
osaurus
qwen
hermes
vibe
windsurf
zcode
```

### 5.2 关键冻结值检查

```bash
jq -r '.entrySha256, .sourceRoot, .sourceRoleCount, .expectedSections, (.tools | length)' \
  agency-agents/local-deployment/frozen-action-manifest.json
```

预期：

- `f0610cabef0c689ff6c4567dd4c2794893664d8267af682ac4b9c704019e9bbd`
- `integrations`
- `269`
- `269`
- `16`

### 5.3 OpenClaw target 检查

冻结清单中的 OpenClaw target 是：

- `stagePath = ${HOME}/.openclaw/agency-agents`
- `targetPath = ${HOME}/.openclaw/agency-agents`

也就是说，受管 OpenClaw 工作区根是 `~/.openclaw/agency-agents`，不是 `~/.openclaw/agents/main`。

## 6. 治理响应 JSON 与同步报告 JSON

这里有两个不同的 JSON 合同，不要混淆。

### 6.1 治理响应 JSON（来自 governance 模板/测试）

固定字段来自 `agency-agents/scripts/tests/test_governance.py`：

- `decision`
- `role`
- `risk_level`
- `plan`
- `evidence`
- `learning_report`
- `human_actions_needed`

决策枚举值固定为：

```text
ALLOW | NEED_APPROVAL | BLOCK
```

治理模板中的执行语义：

- `ALLOW`：动作在白名单与授权域内，可以执行。
- `NEED_APPROVAL`：动作需先满足审批条件，再等待人工审批。
- `BLOCK`：动作越界或有风险，直接停止，并给替代动作。

### 6.2 同步报告 JSON（来自 sync-all-local.sh）

`sync-all-local.sh` 的帮助输出和测试都绑定到：

- `schema = agency-agents.local-sync-report/v1`

失败报告最小结构含：

- `failure.id`
- `failure.operation`
- `failure.reason`
- `failure.stage`
- `failure.target`
- `failure.tool`
- `manifest`
- `result`
- `rollback`
- `schema`
- `targets`

`result` 的固定字段集合：

- `backupCount`
- `mode`
- `rc`
- `status`

约束：

- `status` 只能是 `passed` 或 `failed`
- `mode` 只能是 `null`、`dry-run` 或 `apply`

`apply` 失败时还可能出现：

- `securityReasonCode`

源码中已绑定的取值包括：

- `action-replay-detected`
- `isolated-test-security-root-layout-invalid`
- `ledger-write-failed`

### 6.3 rollback 字段

同步报告中的 `rollback` 至少关注：

- `performed`
- `attempted`
- `restored`
- `restoreFailures`
- `entries`

测试明确校验了回滚场景下这些字段的计数和 entries 明细。

## 7. 日志、备份、回滚与凭据禁止事项

禁止事项：

- 不提交 Token、Cookie、私钥、认证头、真实 OpenClaw 配置。
- 不把 `~/.openclaw/` 运行时内容复制回仓库。
- 不把临时报告、缓存、`.superpowers/`、本地调试残留提交到正式源码。
- 不恢复 legacy/trunc/temp 版本的 sync 脚本。

建议做法：

- 给 `--json-report` 使用 repo 外绝对路径。
- 正式 apply 前准备独立备份目录。
- 只把冻结 manifest、正式入口和批准适配器集合作为事实来源。

## 8. 最小验收命令

### 8.1 正式入口帮助输出

```bash
bash agency-agents/local-deployment/sync-all-local.sh --help | jq .
```

预期：

- `schema == "agency-agents.local-sync-report/v1"`
- `result.rc == 0`
- `result.status == "passed"`
- `failure.reason == "help-requested"`

### 8.2 正式入口冻结哈希

```bash
shasum -a 256 agency-agents/local-deployment/sync-all-local.sh
```

预期首列：

```text
f0610cabef0c689ff6c4567dd4c2794893664d8267af682ac4b9c704019e9bbd
```

### 8.3 批准适配器集合

```bash
jq -r '.tools[].name' agency-agents/local-deployment/frozen-action-manifest.json | wc -l
```

预期：

```text
16
```

### 8.4 OpenClaw 269+main

```bash
jq -r '.runtime.openclaw.workspaces, .runtime.openclaw.registeredAgents' \
  agency-agents/local-deployment/installation-manifest.json
```

预期：

```text
269
270
```

## 9. 常见故障

- `entry is required` / `source is required` / `project is required` / `home option is required`
  - 原因：缺少 `sync-all-local.sh` 必填绝对路径参数。
- `Unknown option`
  - 原因：传入了源码未定义的 flag。
- `Missing governance signature`
  - 原因：进入 apply 路径但未提供合法签名文件。
- `source path invalid` / `project path invalid` / `home path invalid`
  - 原因：参数不是绝对路径，或路径格式不满足词法校验。
- `securityReasonCode=action-replay-detected`
  - 原因：授权/ledger 被判定为 replay。
- OpenClaw verify-only 失败
  - 先检查 `installation-manifest.json` 与 `register-openclaw-agents.mjs` 的路径参数是否一致，再检查本机 `~/.openclaw/agency-agents`、`~/.openclaw/openclaw.json`、`~/.openclaw/agents` 是否存在。

## 10. 单版本声明

当前最终仓库只承认以下正式版本事实：

- 正式 sync 入口只有 `agency-agents/local-deployment/sync-all-local.sh`
- 正式入口 SHA-256 固定为 `f0610cabef0c689ff6c4567dd4c2794893664d8267af682ac4b9c704019e9bbd`
- 本地治理部署以 `frozen-action-manifest.json` 的 16 平台集合作为唯一冻结口径
- 不应存在 legacy、trunc、tmp 版 sync 脚本作为可执行替代品
