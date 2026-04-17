# AI驱动的自动化测试框架

## 🎯 项目概述

基于 Playwright + Pytest + LLM + Robot Framework + LangChain + Power BI Dashboard 的智能自动化测试框架。

## 🏗️ 架构设计

```
ai_test_framework/
├── core/                    # 核心框架
│   ├── base/               # 基础类（POM基座、等待策略）
│   ├── llm/                # LLM集成（LangChain）
│   ├── self_healing/       # 智能定位与自愈
│   └── reporting/          # 报告生成
├── tests/                  # 测试用例
│   ├── ui/                # UI测试（Playwright）
│   ├── api/               # API测试（Pytest）
│   └── robot/             # Robot Framework测试
├── llm_services/           # LLM服务
│   ├── test_generation/   # 用例生成
│   ├── defect_analysis/    # 缺陷分析
│   └── prompt_tuning/     # 提示词微调
├── ci_cd/                  # CI/CD配置
│   └── github_actions/    # GitHub Actions
├── dashboard/              # Power BI数据收集
└── config/                 # 配置文件
```

## 🚀 核心功能

### 1. 统一UI自动化基座
- **Playwright核心**：高性能、跨浏览器支持
- **POM模式**：页面对象模型封装
- **智能等待策略**：自适应元素等待

### 2. LLM驱动能力
- **用例生成**：从需求文档自动生成测试用例
- **智能定位**：分析DOM推荐稳定定位策略
- **缺陷分析**：根因分析和修复建议
- **自愈机制**：自动修复定位失败

### 3. 持续集成
- **GitHub Actions**：提交即触发AI回归
- **并行执行**：多浏览器并行测试
- **智能报告**：可解释的测试报告

### 4. 反馈闭环
- **数据收集**：测试结果、LLM建议、性能指标
- **提示词微调**：基于反馈优化LLM提示
- **质量度量**：Power BI Dashboard可视化

## 📦 技术栈

- **UI自动化**: Playwright
- **测试框架**: Pytest, Robot Framework
- **LLM集成**: LangChain, OpenAI/Claude API
- **CI/CD**: GitHub Actions
- **数据可视化**: Power BI
- **语言**: Python 3.9+

## 🛠️ 快速开始

### 安装依赖

```bash
pip install -r requirements.txt
```

### 配置环境变量

```bash
cp .env.example .env
# 编辑 .env 文件，填入API密钥等配置
```

### 运行测试

```bash
# Playwright测试
pytest tests/ui/

# Robot Framework测试
robot tests/robot/

# 使用LLM生成用例
python llm_services/test_generation/generate_tests.py
```

## 📊 Power BI Dashboard

框架自动收集以下数据：
- 测试执行结果
- LLM生成的用例质量
- 自愈机制成功率
- 缺陷根因分析准确度
- 提示词优化效果

## 🔄 工作流程

1. **需求输入** → LLM生成测试用例
2. **用例执行** → Playwright/Pytest运行
3. **失败分析** → LLM分析根因
4. **自愈修复** → 自动修复定位问题
5. **数据收集** → 发送到Power BI
6. **反馈优化** → 微调提示词

## 📖 文档

- [架构设计文档](docs/architecture.md)
- [LLM集成指南](docs/llm_integration.md)
- [CI/CD配置](docs/ci_cd.md)
- [Power BI Dashboard](docs/dashboard.md)

