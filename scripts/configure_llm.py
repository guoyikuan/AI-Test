#!/usr/bin/env python3
"""
LLM配置助手
交互式配置AI服务提供商
"""
import os
import sys
from pathlib import Path

# 添加项目根目录到路径
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

try:
    from config.llm_config import LLMConfig
except ImportError:
    print("⚠️  无法导入LLMConfig，使用简化配置")
    LLMConfig = None

def main():
    print("╔══════════════════════════════════════════════════════════════╗")
    print("║         AI服务配置助手                                        ║")
    print("╚══════════════════════════════════════════════════════════════╝")
    print()
    
    # 支持的提供商
    providers = {
        "openai": {
            "name": "OpenAI (GPT系列)",
            "api_key_env": "OPENAI_API_KEY",
            "base_url_env": "OPENAI_BASE_URL",
            "default_model": "gpt-4-turbo-preview"
        },
        "anthropic": {
            "name": "Anthropic (Claude系列)",
            "api_key_env": "ANTHROPIC_API_KEY",
            "default_model": "claude-3-opus-20240229"
        },
        "tongyi": {
            "name": "通义千问 (Tongyi/Qwen)",
            "api_key_env": "TONGYI_API_KEY",
            "base_url_env": "TONGYI_BASE_URL",
            "default_model": "qwen-turbo"
        },
        "zhipu": {
            "name": "智谱AI (Zhipu/GLM)",
            "api_key_env": "ZHIPU_API_KEY",
            "base_url_env": "ZHIPU_BASE_URL",
            "default_model": "glm-4"
        },
        "custom": {
            "name": "自定义服务 (OpenAI兼容接口)",
            "api_key_env": "CUSTOM_LLM_API_KEY",
            "base_url_env": "LLM_BASE_URL",
            "default_model": "gpt-3.5-turbo"
        }
    }
    
    # 显示当前配置
    env_file = project_root / ".env"
    current_provider = "openai"
    if env_file.exists():
        content = env_file.read_text(encoding="utf-8")
        for line in content.split("\n"):
            if line.startswith("LLM_PROVIDER="):
                current_provider = line.split("=", 1)[1].strip()
                break
    
    print(f"当前配置的AI服务: {current_provider}")
    print()
    
    # 显示支持的提供商
    print("支持的AI服务提供商：")
    for key, info in providers.items():
        marker = "👉" if key == current_provider else "  "
        print(f"{marker} {key}: {info['name']}")
    print()
    
    # 选择提供商
    print("请选择要使用的AI服务提供商：")
    choice = input("输入提供商代码 (openai/anthropic/tongyi/zhipu/custom，直接回车保持当前): ").strip().lower()
    
    if not choice:
        choice = current_provider
    
    if choice not in providers:
        print(f"❌ 不支持的提供商: {choice}")
        return
    
    # 获取API密钥
    provider_info = providers[choice]
    api_key_env = provider_info["api_key_env"]
    
    print(f"\n请输入 {provider_info['name']} 的API密钥：")
    api_key = input(f"{api_key_env}: ").strip()
    
    if not api_key:
        print("❌ API密钥不能为空")
        return
    
    # 获取模型（可选）
    default_model = provider_info.get("default_model", "gpt-3.5-turbo")
    print(f"\n模型名称 (默认: {default_model}，直接回车使用默认):")
    model = input().strip() or default_model
    
    # 获取base_url（如果需要）
    base_url = None
    if provider_info.get("base_url_env"):
        print(f"\n自定义API地址 (可选，直接回车跳过):")
        base_url = input().strip() or None
    
    # 更新.env文件
    if not env_file.exists():
        print(f"\n⚠️  .env文件不存在，正在创建...")
        env_file.touch()
    
    # 读取现有配置
    env_content = env_file.read_text(encoding="utf-8") if env_file.exists() else ""
    
    # 更新配置
    lines = env_content.split("\n") if env_content else []
    updated_lines = []
    found_provider = False
    found_api_key = False
    found_model = False
    found_base_url = False
    
    for line in lines:
        if line.startswith("LLM_PROVIDER="):
            updated_lines.append(f"LLM_PROVIDER={choice}")
            found_provider = True
        elif line.startswith(f"{api_key_env}="):
            updated_lines.append(f"{api_key_env}={api_key}")
            found_api_key = True
        elif line.startswith("LLM_MODEL="):
            updated_lines.append(f"LLM_MODEL={model}")
            found_model = True
        elif provider_info.get("base_url_env") and line.startswith(f"{provider_info['base_url_env']}="):
            if base_url:
                updated_lines.append(f"{provider_info['base_url_env']}={base_url}")
            else:
                updated_lines.append(line)  # 保留原有值
            found_base_url = True
        else:
            updated_lines.append(line)
    
    # 添加缺失的配置
    if not found_provider:
        updated_lines.append(f"LLM_PROVIDER={choice}")
    if not found_api_key:
        updated_lines.append(f"{api_key_env}={api_key}")
    if not found_model:
        updated_lines.append(f"LLM_MODEL={model}")
    if base_url and provider_info.get("base_url_env") and not found_base_url:
        updated_lines.append(f"{provider_info['base_url_env']}={base_url}")
    
    # 写入文件
    env_file.write_text("\n".join(updated_lines), encoding="utf-8")
    
    print(f"\n✅ 配置已更新到 {env_file}")
    print("\n配置摘要：")
    print(f"  提供商: {choice} ({provider_info['name']})")
    print(f"  API密钥: {api_key[:10]}...{api_key[-4:] if len(api_key) > 14 else ''}")
    print(f"  模型: {model}")
    if base_url:
        print(f"  API地址: {base_url}")
    
    print("\n✅ 配置完成！现在可以使用新的AI服务了。")

if __name__ == "__main__":
    main()

