# Agency Agents 269 角色统一治理设计

## 目标

为当前 269 个 Agency Agents 角色统一增加企业治理提示词，同时保持每个角色原有专业人设和业务能力。治理配置同步进入 GitHub 源码、本机 OpenClaw，以及 Codex、Claude、Copilot、Gemini、Qwen、Cursor 等全部已安装适配器。

本阶段只改变角色治理契约和生成机制，不授权任何角色执行真实业务动作、生产写入、权限变更或电话操作。

## 核心原则

- 使用一份中文 `BASE_PROMPT` 作为唯一治理模板。
- 未进入白名单的动作默认 `BLOCK`。
- 每个角色必须获得完整、已解析的变量配置，不在运行时保留 `{ROLE}` 等占位符。
- 原角色提示词位于治理提示词之后，不能覆盖治理边界。
- 每次响应始终输出完整固定 JSON，并在其中包含 `learning_report`。
- 学习结果只能形成提议，不能自动扩大权限、系统范围或生命周期状态。
- 凭据、Token、Cookie、私钥和敏感正文不得进入源码、生成物、日志或交接文件。

## 方案结构

### 1. 统一治理模板

计划新增：

- `agency-agents/governance/base-prompt.zh-CN.md`
- `agency-agents/governance/schemas/role-governance-profile.schema.json`
- `agency-agents/governance/schemas/governed-response.schema.json`

模板包含任务解析、白名单判定、风险分级、最多五步计划、执行校验、回滚和学习报告要求。

### 2. 部门策略模板

按现有部门建立标准策略，统一定义：

- `allowed_read_actions`
- `allowed_write_actions`
- `forbidden_actions`
- `risk_rules`
- `approval_matrix`
- `allowed_systems`

普通内容、分析和设计角色允许在授权数据域内读取、草拟和生成本地交付物。安全、法务、财务、生产运维、权限管理、发布和外部通信角色默认只读；真实写入和外部副作用必须人工审批。

### 3. 269 个角色配置

计划生成一份机器可读角色清单：

- `agency-agents/governance/role-governance-profiles.json`

每个角色至少包含：

- 稳定角色 ID 和显示名称
- 所属部门与风险等级
- 读取和写入白名单
- 禁止动作
- 授权系统
- 审批矩阵
- 日志和回滚要求
- 原始角色文件 SHA-256
- 所应用部门模板和例外规则

高风险角色使用显式覆盖，不能依赖模糊关键词在运行时临时判定。

### 4. 确定性生成器

生成器读取治理模板、部门策略、角色配置和原角色 Markdown，输出完整治理后提示词。相同输入必须产生字节一致结果，并输出来源哈希和生成清单。

生成器拒绝：

- 未知角色或重复角色 ID
- 未解析变量
- 缺少白名单、禁止动作、授权系统或审批矩阵
- 高风险角色存在默认写权限
- 原角色提示词试图覆盖治理规则
- 输出路径逃逸、符号链接或凭据模式命中

### 5. 平台同步

以治理后的角色提示词重新生成并安装全部现有适配器。平台适配器只负责格式转换，不拥有独立治理逻辑。

同步目标包括：

- OpenClaw
- Codex
- Claude
- GitHub Copilot 与 Copilot
- Gemini CLI
- Qwen
- Cursor
- Antigravity、OpenCode、ZCode、Osaurus、Vibe
- Hermes、Aider、Windsurf

OpenClaw 保留默认 `main` Agent；269 个 Agency Agents 必须全部更新。平台自身加载数量限制需要单独记录，不能伪称全部运行时可见。

## 决策与输出契约

每次角色响应使用以下顶层字段：

- `decision`: `ALLOW | NEED_APPROVAL | BLOCK`
- `role`
- `risk_level`: `low | medium | high`
- `plan`: 最多五步
- `evidence`
- `learning_report`
- `human_actions_needed`

`learning_report` 必须包含成功、失败、人工干预、最多三条可复用模式、一条改进提议和 0-100 置信度。没有实际执行时，不得伪造成功证据。

## 风险分类

- `low`：授权域内只读检索、分析、草拟、格式转换。
- `medium`：本地可回滚写入、非敏感配置草稿、受限生成物更新。
- `high`：生产发布、批量修改、权限变更、外部发送、真实电话、敏感数据写入、财务或法律承诺。

高风险动作必须返回 `NEED_APPROVAL`，并给出精确审批条件。越权、未知系统、凭据暴露或无法验证审批时返回 `BLOCK`。

## 日志与证据

每个动作记录：

- `request_id`
- 执行人
- UTC 时间
- 脱敏输入摘要和输入哈希
- 动作结果
- 失败原因
- 回滚点

日志不得保存完整提示正文、认证材料、客户数据或完整敏感标识。

## 验收标准

1. 源角色数量为 269，治理配置覆盖 269，零遗漏、零重复。
2. 所有角色必填变量均已解析，零 `{ROLE}` 等残留占位符。
3. 角色配置和固定输出均通过 JSON Schema 校验。
4. 高风险角色无未审批写权限。
5. 全部平台生成清单与源角色集合一致。
6. 本机 OpenClaw 官方 CLI 报告 269 个 Agency Agents 零缺失。
7. Codex、Claude、Copilot、Gemini、Qwen、Cursor 等安装目录与生成清单一致。
8. 凭据和高置信度密钥扫描为零。
9. 生成器重复运行不产生差异。
10. 完成声明必须获得 Evidence Assurance Supervisor `ALLOW`。

## 回滚

- 每次覆盖本机适配器前创建时间戳备份和 SHA-256 清单。
- Git 回滚以治理实施前提交为基准。
- 本机回滚只恢复适配器和 OpenClaw 角色提示，不修改现有凭据。
- 任一平台失败时保持其旧版本，不能部分覆盖后宣称全量成功。

## 实施顺序

1. 建立治理模板、Schema 和部门策略。
2. 生成并审计 269 个角色配置。
3. 生成治理后角色和全部平台适配器。
4. 在隔离目录验证数量、Schema、哈希、变量和安全扫描。
5. 经动作授权后备份并同步本机运行时，最终提交、推送并执行 Supervisor 验收。

## 与 SIP 自动接听 Agent 的关系

269 角色治理完成后，再继续实施 `AICC SIP Auto-Answer Contact Agent`。该 Agent 继承同一治理模板，但真实接听、并发测试和挂断均属于高风险外部动作，需要独立授权，不能由本次治理批准自动解锁。
