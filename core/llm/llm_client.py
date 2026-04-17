"""
LLM客户端封装
支持多种AI服务提供商：OpenAI、Anthropic、通义千问、智谱AI等
"""
import os
from typing import List, Dict, Any, Optional
try:
    from langchain_openai import ChatOpenAI
except ImportError:
    ChatOpenAI = None

try:
    from langchain_anthropic import ChatAnthropic
except ImportError:
    ChatAnthropic = None

try:
    from langchain_community.chat_models import ChatTongyi, ChatZhipuAI
except Exception:
    ChatTongyi = None
    ChatZhipuAI = None

try:
    from langchain.prompts import ChatPromptTemplate, SystemMessagePromptTemplate, HumanMessagePromptTemplate
    from langchain.schema import HumanMessage, SystemMessage
except Exception:
    ChatPromptTemplate = None
    SystemMessagePromptTemplate = None
    HumanMessagePromptTemplate = None
    HumanMessage = None
    SystemMessage = None
from loguru import logger
from dotenv import load_dotenv

load_dotenv()

# 尝试导入国内AI服务（如果可用）
try:
    from langchain_community.chat_models import ChatTongyi, ChatZhipuAI
    HAS_COMMUNITY_MODELS = True
except Exception:
    HAS_COMMUNITY_MODELS = False
    logger.warning("langchain-community未安装或不兼容，部分AI服务可能不可用")


class LLMClient:
    """LLM客户端，统一封装不同LLM提供商的调用"""
    
    def __init__(
        self,
        provider: Optional[str] = None,
        model: Optional[str] = None,
        temperature: float = 0.7,
        base_url: Optional[str] = None,
        api_key: Optional[str] = None
    ):
        """
        初始化LLM客户端
        
        Args:
            provider: LLM提供商 (openai, anthropic, tongyi, zhipu, custom)
                     如果为None，则从环境变量LLM_PROVIDER读取
            model: 模型名称，如果为None则使用默认模型
            temperature: 温度参数
            base_url: 自定义API基础URL（用于自定义服务）
            api_key: API密钥（如果提供则优先使用，否则从环境变量读取）
        """
        # 从环境变量获取默认配置
        self.provider = provider or os.getenv("LLM_PROVIDER", "openai")
        self.temperature = temperature
        self.base_url = base_url or os.getenv("LLM_BASE_URL")
        
        if self.provider == "openai":
            key = api_key or os.getenv("OPENAI_API_KEY")
            model = model or os.getenv("LLM_MODEL", "gpt-4-turbo-preview")
            openai_base_url = self.base_url or os.getenv("OPENAI_BASE_URL")

            if not key or key.startswith("your_") or key.startswith("your-"):
                logger.warning("OPENAI_API_KEY未设置或为占位符，LLM调用将被禁用")
                self.llm = None
            elif ChatOpenAI is None:
                logger.warning("langchain_openai未安装，LLM调用将被禁用")
                self.llm = None
            else:
                self.llm = ChatOpenAI(
                    model_name=model,
                    temperature=temperature,
                    openai_api_key=key,
                    base_url=openai_base_url if openai_base_url else None
                )
            
        elif self.provider == "anthropic":
            key = api_key or os.getenv("ANTHROPIC_API_KEY")
            model = model or os.getenv("LLM_MODEL", "claude-3-opus-20240229")

            if not key or key.startswith("your_") or key.startswith("your-"):
                logger.warning("ANTHROPIC_API_KEY未设置或为占位符，LLM调用将被禁用")
                self.llm = None
            elif ChatAnthropic is None:
                logger.warning("langchain_anthropic未安装，LLM调用将被禁用")
                self.llm = None
            else:
                self.llm = ChatAnthropic(
                    model=model,
                    temperature=temperature,
                    anthropic_api_key=key
                )
            
        elif self.provider == "tongyi":
            key = api_key or os.getenv("TONGYI_API_KEY") or os.getenv("DASHSCOPE_API_KEY")
            model = model or os.getenv("LLM_MODEL", "qwen-turbo")

            if not key or key.startswith("your_") or key.startswith("your-"):
                logger.warning("TONGYI_API_KEY或DASHSCOPE_API_KEY未设置或为占位符，LLM调用将被禁用")
                self.llm = None
            elif HAS_COMMUNITY_MODELS and ChatTongyi is not None:
                try:
                    self.llm = ChatTongyi(
                        model_name=model,
                        temperature=temperature,
                        dashscope_api_key=key
                    )
                except Exception as e:
                    logger.warning(f"通义千问直接初始化失败，尝试使用OpenAI兼容接口: {e}")
                    self._init_tongyi_via_openai(key, model)
            elif ChatOpenAI is not None:
                self._init_tongyi_via_openai(key, model)
            else:
                logger.warning("无法初始化通义千问（缺少ChatTongyi和ChatOpenAI），LLM调用将被禁用")
                self.llm = None
                
        elif self.provider == "zhipu":
            key = api_key or os.getenv("ZHIPU_API_KEY")
            model = model or os.getenv("LLM_MODEL", "glm-4")

            if not key or key.startswith("your_") or key.startswith("your-"):
                logger.warning("ZHIPU_API_KEY未设置或为占位符，LLM调用将被禁用")
                self.llm = None
            elif HAS_COMMUNITY_MODELS and ChatZhipuAI is not None:
                try:
                    self.llm = ChatZhipuAI(
                        model_name=model,
                        temperature=temperature,
                        zhipuai_api_key=key
                    )
                except Exception as e:
                    logger.warning(f"智谱AI直接初始化失败，尝试使用OpenAI兼容接口: {e}")
                    self._init_zhipu_via_openai(key, model)
            elif ChatOpenAI is not None:
                self._init_zhipu_via_openai(key, model)
            else:
                logger.warning("无法初始化智谱AI（缺少ChatZhipuAI和ChatOpenAI），LLM调用将被禁用")
                self.llm = None
                
        elif self.provider == "custom" or self.base_url:
            key = api_key or os.getenv("CUSTOM_LLM_API_KEY") or os.getenv("OPENAI_API_KEY")
            model = model or os.getenv("LLM_MODEL", "gpt-3.5-turbo")
            llm_base_url = self.base_url or os.getenv("LLM_BASE_URL")

            if not key or key.startswith("your_") or key.startswith("your-"):
                logger.warning("CUSTOM_LLM_API_KEY或OPENAI_API_KEY未设置或为占位符，LLM调用将被禁用")
                self.llm = None
            elif ChatOpenAI is None:
                logger.warning("langchain_openai未安装，LLM调用将被禁用")
                self.llm = None
            else:
                self.llm = ChatOpenAI(
                    model_name=model,
                    temperature=temperature,
                    openai_api_key=key,
                    base_url=llm_base_url
                )
            
        else:
            raise ValueError(
                f"不支持的LLM提供商: {self.provider}\n"
                f"支持的提供商: openai, anthropic, tongyi, zhipu, custom"
            )
            
        logger.info(f"LLM客户端已初始化: {self.provider}, 模型: {model}")
    
    def _init_tongyi_via_openai(self, api_key: str, model: str):
        """通过OpenAI兼容接口初始化通义千问"""
        base_url = os.getenv("TONGYI_BASE_URL", "https://dashscope.aliyuncs.com/compatible-mode/v1")
        self.llm = ChatOpenAI(
            model_name=model,
            temperature=self.temperature,
            openai_api_key=api_key,
            base_url=base_url
        )
    
    def _init_zhipu_via_openai(self, api_key: str, model: str):
        """通过OpenAI兼容接口初始化智谱AI"""
        base_url = os.getenv("ZHIPU_BASE_URL", "https://open.bigmodel.cn/api/paas/v4")
        self.llm = ChatOpenAI(
            model_name=model,
            temperature=self.temperature,
            openai_api_key=api_key,
            base_url=base_url
        )
        
    def generate(
        self,
        prompt: str,
        system_message: Optional[str] = None,
        **kwargs
    ) -> str:
        """
        生成文本
        
        Args:
            prompt: 用户提示
            system_message: 系统消息
            **kwargs: 其他参数
            
        Returns:
            生成的文本
        """
        messages = []
        if system_message:
            messages.append(SystemMessage(content=system_message))
        messages.append(HumanMessage(content=prompt))
        
        if not self.llm:
            logger.warning("当前未配置LLM客户端，generate将返回空字符串")
            return ""

        try:
            response = self.llm.invoke(messages)
            result = response.content if hasattr(response, 'content') else str(response)
            logger.debug(f"LLM生成完成，长度: {len(result)}")
            return result
        except Exception as e:
            logger.error(f"LLM生成失败: {str(e)}")
            raise
            
    def generate_with_template(
        self,
        template: str,
        input_variables: Dict[str, Any],
        system_message: Optional[str] = None
    ) -> str:
        """
        使用模板生成文本
        
        Args:
            template: 提示模板
            input_variables: 模板变量
            system_message: 系统消息
            
        Returns:
            生成的文本
        """
        prompt_template = ChatPromptTemplate.from_template(template)
        prompt = prompt_template.format(**input_variables)
        return self.generate(prompt, system_message)
        
    def analyze(
        self,
        context: Dict[str, Any],
        analysis_type: str,
        **kwargs
    ) -> Dict[str, Any]:
        """
        分析上下文（用于缺陷分析、定位推荐等）
        
        Args:
            context: 上下文数据
            analysis_type: 分析类型
            **kwargs: 其他参数
            
        Returns:
            分析结果
        """
        if analysis_type == "defect_analysis":
            return self._analyze_defect(context, **kwargs)
        elif analysis_type == "locator_recommendation":
            return self._recommend_locator(context, **kwargs)
        elif analysis_type == "test_generation":
            return self._generate_test_case(context, **kwargs)
        else:
            raise ValueError(f"不支持的分析类型: {analysis_type}")
            
    def _analyze_defect(
        self,
        context: Dict[str, Any],
        **kwargs
    ) -> Dict[str, Any]:
        """缺陷根因分析"""
        system_message = """你是一个专业的测试工程师，擅长分析测试失败的根本原因。
请分析提供的测试失败信息，包括：
1. 错误堆栈
2. 页面截图
3. 网络请求
4. 测试步骤

输出格式：
- 可能原因（按概率排序）
- 建议验证步骤
- 修复建议
"""
        
        prompt = f"""
测试失败分析请求：

错误信息：
{context.get('error', 'N/A')}

测试步骤：
{context.get('steps', 'N/A')}

页面URL：
{context.get('url', 'N/A')}

请分析失败的根本原因。
"""
        
        analysis = self.generate(prompt, system_message)
        return {
            "analysis": analysis,
            "type": "defect_analysis",
            "context": context
        }
        
    def _recommend_locator(
        self,
        context: Dict[str, Any],
        **kwargs
    ) -> Dict[str, Any]:
        """推荐定位策略"""
        system_message = """你是一个自动化测试专家，擅长推荐稳定的元素定位策略。
根据DOM结构和失败信息，推荐最稳定的定位方式（如role、testid、data-testid等）。
"""
        
        prompt = f"""
元素定位推荐请求：

失败的定位器：
{context.get('failed_locator', 'N/A')}

DOM结构：
{context.get('dom_snippet', 'N/A')}

请推荐更稳定的定位策略。
"""
        
        recommendation = self.generate(prompt, system_message)
        return {
            "recommendation": recommendation,
            "type": "locator_recommendation",
            "context": context
        }
        
    def _generate_test_case(
        self,
        context: Dict[str, Any],
        **kwargs
    ) -> Dict[str, Any]:
        """生成测试用例"""
        system_message = """你是一个测试用例生成专家，能够根据需求文档生成完整的测试用例。
生成的用例应该包括：
1. 前置条件
2. 测试步骤
3. 预期结果
4. 断言
5. 清理步骤

使用Pytest格式。
"""
        
        prompt = f"""
测试用例生成请求：

需求描述：
{context.get('requirement', 'N/A')}

功能点：
{context.get('features', 'N/A')}

请生成完整的测试用例。
"""
        
        test_case = self.generate(prompt, system_message)
        return {
            "test_case": test_case,
            "type": "test_generation",
            "context": context
        }
