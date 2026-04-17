#!/usr/bin/env python3
"""
检查LLM配置
"""
import os
import sys
from pathlib import Path

project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

from dotenv import load_dotenv
load_dotenv()

try:
    from config.llm_config import LLMConfig
    config = LLMConfig()
    print(config.get_config_summary())
except ImportError:
    # 简化版本
    provider = os.getenv("LLM_PROVIDER", "openai")
    print(f"当前LLM提供商: {provider}")
    
    if provider == "openai":
        key = os.getenv("OPENAI_API_KEY", "")
        print(f"OPENAI_API_KEY: {'✅ 已配置' if key and not key.startswith('your_') else '❌ 未配置'}")
    elif provider == "anthropic":
        key = os.getenv("ANTHROPIC_API_KEY", "")
        print(f"ANTHROPIC_API_KEY: {'✅ 已配置' if key and not key.startswith('your_') else '❌ 未配置'}")
    elif provider == "tongyi":
        key = os.getenv("TONGYI_API_KEY") or os.getenv("DASHSCOPE_API_KEY", "")
        print(f"TONGYI_API_KEY: {'✅ 已配置' if key and not key.startswith('your_') else '❌ 未配置'}")
    elif provider == "zhipu":
        key = os.getenv("ZHIPU_API_KEY", "")
        print(f"ZHIPU_API_KEY: {'✅ 已配置' if key and not key.startswith('your_') else '❌ 未配置'}")
