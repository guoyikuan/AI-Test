# 飞书PRD获取工具使用指南

## 概述

`fetch_prd.py` 是一个集成工具，用于从飞书Wiki获取PRD文档内容，并自动转换为测试用例。

## 快速开始

### 基础用法

```bash
# 查看帮助
python3 tools/fetch_prd.py

# 获取PRD并输出为JSON (默认)
python3 tools/fetch_prd.py "https://airudder.feishu.cn/wiki/HxVOwkl1HiE0pek69idcqAHyneZ"

# 输出为Excel格式
python3 tools/fetch_prd.py "https://airudder.feishu.cn/wiki/HxVOwkl1HiE0pek69idcqAHyneZ" --format excel

# 输出为Markdown格式
python3 tools/fetch_prd.py "https://airudder.feishu.cn/wiki/HxVOwkl1HiE0pek69idcqAHyneZ" --format markdown
```

## 功能说明

### 🔧 核心功能

1. **URL解析**
   - 自动从飞书URL提取文档token
   - 支持多种飞书链接格式

2. **内容获取**
   - 使用飞书API获取文档内容（需要配置凭证）
   - 回退方案：使用示例PRD演示功能

3. **格式转换**
   - JSON格式：原始结构化数据
   - Excel格式：可导入测试系统的表格格式
   - Markdown格式：易于阅读的文档格式

4. **自动保存**
   - 自动生成时间戳文件名
   - 保存到当前目录

## 配置飞书API (可选)

要完全使用飞书API获取真实文档，需要配置飞书应用凭证：

### 步骤1: 创建飞书应用

1. 访问 https://open.feishu.cn/app
2. 点击创建新应用
3. 选择自建应用
4. 填写应用信息

### 步骤2: 获取凭证

1. 在应用管理界面找到"凭证与基础信息"
2. 复制 **App ID** 和 **App Secret**

### 步骤3: 配置环境变量

```bash
# 在 ~/.zshrc 或 ~/.bash_profile 中添加
export FEISHU_APP_ID="cli_a94a0b02883b5bc7"
export FEISHU_APP_SECRET="HznfRdEJ77dzcJ4uymvgohSrpBrIQSDP"

# 然后重新加载
source ~/.zshrc
```

## 输出示例

### JSON格式输出

```json
{
  "title": "AI智能测试框架 - PRD文档",
  "description": "自动化UI测试框架，支持多浏览器",
  "modules": [
    {
      "name": "用户登录",
      "functions": ["用户名密码登录", "记住密码功能"],
      "test_cases": [
        {
          "name": "正常登录流程",
          "steps": ["1. 打开登录页面", "2. 输入用户名"],
          "expected": "成功登录"
        }
      ]
    }
  ]
}
```

### Excel格式输出

```json
[
  {
    "用例类型": "UI",
    "用例名称": "正常登录流程",
    "功能模块": "用户登录",
    "步骤描述": "1. 打开登录页面\n2. 输入用户名\n3. 输入密码",
    "预期结果": "成功登录",
    "执行人": "",
    "测试状态": "未执行"
  }
]
```

## 工作流程

```
┌─────────────────────────────────────────┐
│  输入飞书URL                             │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│  URL解析 - 提取文档token                │
└──────────────┬──────────────────────────┘
               │
               ▼
        ┌──────┴──────┐
        │             │
        ▼             ▼
  ┌─────────────┐  ┌────────────────┐
  │ 使用API获取  │  │ 使用示例PRD     │
  │ (需配置凭证) │  │ (演示功能)      │
  └──────┬──────┘  └────────┬───────┘
         │                  │
         └──────────┬───────┘
                    │
                    ▼
        ┌─────────────────────────┐
        │ 解析内容为结构化数据     │
        └──────────┬──────────────┘
                   │
                   ▼
        ┌─────────────────────────┐
        │ 按格式转换输出           │
        └──────────┬──────────────┘
                   │
        ┌──────────┼──────────┐
        ▼          ▼          ▼
      JSON      Excel    Markdown
        │          │          │
        └──────────┼──────────┘
                   │
                   ▼
        ┌─────────────────────────┐
        │ 自动保存到文件           │
        │ (时间戳文件名)          │
        └─────────────────────────┘
```

## 故障排除

### 问题1: 无法连接飞书API

**症状**: 显示 "获取飞书token失败"

**解决方案**:
1. 检查网络连接
2. 确认`FEISHU_APP_ID`和`FEISHU_APP_SECRET`已正确设置
3. 访问 https://open.feishu.cn 验证应用凭证是否有效

### 问题2: URL解析失败

**症状**: "无法解析URL"

**解决方案**:
1. 确保URL格式正确，包含完整的域名和文档token
2. 移除URL末尾的其他参数（如`?login_redirect_times=1`）

示例正确URL:
```
https://airudder.feishu.cn/wiki/HxVOwkl1HiE0pek69idcqAHyneZ
```

### 问题3: 生成的测试用例格式不对

**症状**: 生成的用例字段缺少或顺序不对

**解决方案**:
- 尝试不同的输出格式
- 检查源PRD文档结构是否标准

## 进阶用法

### 集成到CI/CD流程

```bash
#!/bin/bash
# 获取PRD并生成测试用例
python3 tools/fetch_prd.py "https://airudder.feishu.cn/wiki/YOUR_DOC_ID" --format excel > test_cases.json

# 导入到测试系统
pytest --import-test-cases test_cases.json
```

### 处理多个文档

```bash
# 创建脚本处理多个PRD
for url in $(cat prd_urls.txt); do
    python3 tools/fetch_prd.py "$url" --format markdown
done
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `fetch_prd.py` | 主工具脚本 |
| `feishu_prd_fetcher.py` | 飞书API集成（高级功能） |
| `prd_parser.py` | PRD内容解析器（高级功能） |

## 限制和注意

1. **API限制**
   - 飞书API有频率限制，建议不要频繁调用
   - 单次文档大小有限制

2. **内容识别**
   - 当前版本使用示例PRD演示，真实文档需配置API凭证
   - 复杂格式的PRD文档可能识别不完整

3. **隐私和安全**
   - 不要将`FEISHU_APP_SECRET`提交到版本控制
   - 使用环境变量存储敏感信息

## 获取帮助

```bash
# 查看完整帮助
python3 tools/fetch_prd.py --help

# 检查脚本版本信息
head -20 tools/fetch_prd.py
```

---

**最后更新**: 2026-03-23  
**维护者**: AI Test Framework Team
