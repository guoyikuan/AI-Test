"""
LLM配置管理
支持多种AI服务提供商的配置
"""
import os
from typing import Dict, Any, Optional
from dotenv import load_dotenv
from loguru import logger

load_dotenv()


class LLMConfig:
    """LLM配置管理类"""
    
    # 支持的提供商
    SUPPORTED_PROVIDERS = {
        "openai": {
            "name": "OpenAI",
            "api_key_env": "OPENAI_API_KEY",
            "base_url_env": "OPENAI_BASE_URL",
            "default_model": "gpt-4-turbo-preview"
        },
        "anthropic": {
            "name": "Anthropic Claude",
            "api_key_env": "ANTHROPIC_API_KEY",
            "default_model": "claude-3-opus-20240229"
        },
        "tongyi": {
            "name": "通义千问 (Tongyi/Qwen)",
            "api_key_env": ["TONGYI_API_KEY", "DASHSCOPE_API_KEY"],
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
            "name": "自定义服务",
            "api_key_env": ["CUSTOM_LLM_API_KEY", "OPENAI_API_KEY"],
            "base_url_env": "LLM_BASE_URL",
            "default_model": "gpt-3.5-turbo"
        }
    }
    
    @classmethod
    def get_provider(cls) -> str:
        """获取当前使用的LLM提供商"""
        return os.getenv("LLM_PROVIDER", "openai")
    
    @classmethod
    def get_api_key(cls, provider: Optional[str] = None) -> Optional[str]:
        """获取API密钥"""
        provider = provider or cls.get_provider()
        provider_info = cls.SUPPORTED_PROVIDERS.get(provider)
        
        if not provider_info:
            return None
            
        api_key_env = provider_info.get("api_key_env")
        if isinstance(api_key_env, list):
            # 尝试多个环境变量
            for env_var in api_key_env:
                key = os.getenv(env_var)
                if key:
                    return key
            return None
        else:
            return os.getenv(api_key_env)
    
    @classmethod
    def get_base_url(cls, provider: Optional[str] = None) -> Optional[str]:
        """获取API基础URL"""
        provider = provider or cls.get_provider()
        provider_info = cls.SUPPORTED_PROVIDERS.get(provider)
        
        if not provider_info:
            return None
            
        base_url_env = provider_info.get("base_url_env")
        if base_url_env:
            return os.getenv(base_url_env)
        return None
    
    @classmethod
    def get_model(cls, provider: Optional[str] = None) -> str:
        """获取模型名称"""
        provider = provider or cls.get_provider()
        provider_info = cls.SUPPORTED_PROVIDERS.get(provider)
        
        if not provider_info:
            return os.getenv("LLM_MODEL", "gpt-3.5-turbo")
            
        default_model = provider_info.get("default_model", "gpt-3.5-turbo")
        return os.getenv("LLM_MODEL", default_model)
    
    @classmethod
    def get_temperature(cls) -> float:
        """获取温度参数"""
        return float(os.getenv("LLM_TEMPERATURE", "0.7"))
    
    @classmethod
    def validate_config(cls, provider: Optional[str] = None) -> Dict[str, Any]:
        """
        验证配置是否完整
        
        Returns:
            验证结果字典
        """
        provider = provider or cls.get_provider()
        result = {
            "provider": provider,
            "valid": False,
            "errors": [],
            "warnings": []
        }
        
        provider_info = cls.SUPPORTED_PROVIDERS.get(provider)
        if not provider_info:
            result["errors"].append(f"不支持的提供商: {provider}")
            return result
        
        # 检查API密钥
        api_key = cls.get_api_key(provider)
        if not api_key or api_key.startswith("your_") or api_key.startswith("your-"):
            result["errors"].append(f"{provider_info['name']} API密钥未配置")
        else:
            result["api_key_configured"] = True
        
        # 检查模型
        model = cls.get_model(provider)
        result["model"] = model
        
        # 检查base_url（如果需要）
        base_url = cls.get_base_url(provider)
        if base_url:
            result["base_url"] = base_url
        
        result["valid"] = len(result["errors"]) == 0
        return result
    
    @classmethod
    def list_providers(cls) -> Dict[str, Dict[str, Any]]:
        """列出所有支持的提供商"""
        return cls.SUPPORTED_PROVIDERS
    
    @classmethod
    def get_config_summary(cls) -> str:
        """获取配置摘要"""
        provider = cls.get_provider()
        validation = cls.validate_config(provider)
        
        summary = f"""
当前LLM配置：
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
提供商: {provider} ({cls.SUPPORTED_PROVIDERS.get(provider, {}).get('name', '未知')})
模型: {validation.get('model', 'N/A')}
温度: {cls.get_temperature()}
配置状态: {'✅ 有效' if validation['valid'] else '❌ 无效'}
"""
        
        if validation["errors"]:
            summary += "\n错误:\n"
            for error in validation["errors"]:
                summary += f"  ❌ {error}\n"
        
        if validation.get("base_url"):
            summary += f"\n自定义API地址: {validation['base_url']}\n"
        
        return summary

