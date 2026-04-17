#!/bin/bash

# AI驱动的自动化测试框架 - 自动安装和配置脚本

set -e  # 遇到错误立即退出

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     AI驱动的自动化测试框架 - 自动安装脚本                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 检查Python版本
echo -e "${YELLOW}📋 检查Python环境...${NC}"
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python3未安装，请先安装Python 3.9+${NC}"
    exit 1
fi

PYTHON_VERSION=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1,2)
echo -e "${GREEN}✅ Python版本: $(python3 --version)${NC}"

# 检查pip
if ! command -v pip3 &> /dev/null; then
    echo -e "${YELLOW}⚠️  pip3未找到，尝试使用python3 -m pip...${NC}"
    PIP_CMD="python3 -m pip"
else
    PIP_CMD="pip3"
fi

# 创建虚拟环境
echo ""
echo -e "${YELLOW}📦 创建虚拟环境...${NC}"
if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo -e "${GREEN}✅ 虚拟环境已创建${NC}"
else
    echo -e "${GREEN}✅ 虚拟环境已存在${NC}"
fi

# 激活虚拟环境
echo -e "${YELLOW}🔄 激活虚拟环境...${NC}"
source venv/bin/activate
echo -e "${GREEN}✅ 虚拟环境已激活${NC}"

# 升级pip
echo ""
echo -e "${YELLOW}⬆️  升级pip...${NC}"
$PIP_CMD install --upgrade pip setuptools wheel
echo -e "${GREEN}✅ pip已升级${NC}"

# 安装Python依赖
echo ""
echo -e "${YELLOW}📥 安装Python依赖包...${NC}"
if [ -f "requirements.txt" ]; then
    $PIP_CMD install -r requirements.txt
    echo -e "${GREEN}✅ Python依赖已安装${NC}"
else
    echo -e "${RED}❌ requirements.txt文件不存在${NC}"
    exit 1
fi

# 安装Playwright浏览器
echo ""
echo -e "${YELLOW}🌐 安装Playwright浏览器...${NC}"
if python3 -c "import playwright" 2>/dev/null; then
    python3 -m playwright install chromium
    python3 -m playwright install-deps chromium || true
    echo -e "${GREEN}✅ Playwright浏览器已安装${NC}"
else
    echo -e "${YELLOW}⚠️  Playwright包未安装，跳过浏览器安装${NC}"
    echo -e "${YELLOW}   提示: 依赖已安装，但需要手动运行: python3 -m playwright install${NC}"
fi

# 配置环境变量
echo ""
echo -e "${YELLOW}⚙️  配置环境变量...${NC}"
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        cp .env.example .env
        echo -e "${GREEN}✅ .env文件已从.env.example创建${NC}"
        echo -e "${YELLOW}⚠️  请编辑 .env 文件，填入实际的API密钥和配置${NC}"
    else
        echo -e "${YELLOW}⚠️  .env.example文件不存在，创建基础.env文件${NC}"
        cat > .env << 'ENVEOF'
# LLM配置
OPENAI_API_KEY=your_openai_api_key_here
ANTHROPIC_API_KEY=your_anthropic_api_key_here
LLM_MODEL=gpt-4-turbo-preview
LLM_TEMPERATURE=0.7

# Power BI配置（可选）
POWER_BI_CLIENT_ID=your_power_bi_client_id
POWER_BI_CLIENT_SECRET=your_power_bi_client_secret
POWER_BI_TENANT_ID=your_tenant_id
POWER_BI_WORKSPACE_ID=your_workspace_id
POWER_BI_DATASET_ID=your_dataset_id

# 测试配置
BASE_URL=https://your-test-environment.com
BROWSER=chromium
HEADLESS=true
TIMEOUT=30000
RETRY_COUNT=3

# 报告配置
REPORT_DIR=reports
SCREENSHOT_DIR=screenshots
VIDEO_DIR=videos

# CI/CD配置
CI_MODE=false
PARALLEL_WORKERS=4
ENVEOF
        echo -e "${GREEN}✅ 基础.env文件已创建${NC}"
    fi
else
    echo -e "${GREEN}✅ .env文件已存在${NC}"
fi

# 创建必要的目录
echo ""
echo -e "${YELLOW}📁 创建必要的目录...${NC}"
mkdir -p screenshots reports videos allure-results logs config/prompts data/feedback tests/generated
echo -e "${GREEN}✅ 目录已创建${NC}"

# 验证安装
echo ""
echo -e "${YELLOW}🔍 验证安装...${NC}"

# 检查关键包
echo -n "  - pytest: "
if python3 -c "import pytest" 2>/dev/null; then
    echo -e "${GREEN}✅${NC}"
else
    echo -e "${RED}❌${NC}"
fi

echo -n "  - playwright: "
if python3 -c "import playwright" 2>/dev/null; then
    echo -e "${GREEN}✅${NC}"
else
    echo -e "${RED}❌${NC}"
fi

echo -n "  - langchain: "
if python3 -c "import langchain" 2>/dev/null; then
    echo -e "${GREEN}✅${NC}"
else
    echo -e "${RED}❌${NC}"
fi

echo -n "  - loguru: "
if python3 -c "import loguru" 2>/dev/null; then
    echo -e "${GREEN}✅${NC}"
else
    echo -e "${RED}❌${NC}"
fi

# 检查Playwright浏览器
echo -n "  - Playwright浏览器: "
if python3 -m playwright --version &> /dev/null; then
    echo -e "${GREEN}✅${NC}"
else
    echo -e "${YELLOW}⚠️  未安装${NC}"
fi

# 显示配置信息
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    ✅ 安装完成！                             ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}📝 下一步操作：${NC}"
echo ""
echo -e "1. ${GREEN}配置环境变量${NC}"
echo -e "   编辑 .env 文件，填入以下信息："
echo -e "   - OPENAI_API_KEY 或 ANTHROPIC_API_KEY"
echo -e "   - Power BI认证信息（可选）"
echo -e "   - 测试环境URL"
echo ""
echo -e "2. ${GREEN}运行测试${NC}"
echo -e "   source venv/bin/activate"
echo -e "   pytest tests/ui/ -v"
echo ""
echo -e "3. ${GREEN}生成测试用例${NC}"
echo -e "   python llm_services/test_generation/test_generator.py"
echo ""
echo -e "${BLUE}📖 查看文档：${NC}"
echo -e "   - README.md"
echo -e "   - 项目架构说明.md"
echo -e "   - 快速开始指南.md"
echo ""

