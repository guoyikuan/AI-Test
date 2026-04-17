"""
提示词微调和反馈闭环
基于测试结果和LLM表现，持续优化提示词
"""
import json
from typing import Dict, Any, List, Optional
from pathlib import Path
from datetime import datetime
from loguru import logger
import pandas as pd

from dashboard.power_bi_collector import PowerBICollector


class PromptTuner:
    """提示词调优器"""
    
    def __init__(self, prompt_storage_path: str = "config/prompts"):
        """
        初始化提示词调优器
        
        Args:
            prompt_storage_path: 提示词存储路径
        """
        self.prompt_storage = Path(prompt_storage_path)
        self.prompt_storage.mkdir(parents=True, exist_ok=True)
        self.power_bi = PowerBICollector()
        self.version_history: List[Dict[str, Any]] = []
        
    def load_prompt(self, prompt_type: str, version: Optional[str] = None) -> Dict[str, str]:
        """
        加载提示词
        
        Args:
            prompt_type: 提示词类型 (test_generation, defect_analysis, locator_recommendation)
            version: 版本号，如果为None则加载最新版本
            
        Returns:
            提示词配置
        """
        if version:
            prompt_file = self.prompt_storage / f"{prompt_type}_v{version}.json"
        else:
            # 加载最新版本
            prompt_files = sorted(
                self.prompt_storage.glob(f"{prompt_type}_v*.json"),
                key=lambda x: x.stem
            )
            if prompt_files:
                prompt_file = prompt_files[-1]
            else:
                # 返回默认提示词
                return self._get_default_prompt(prompt_type)
                
        if prompt_file.exists():
            with open(prompt_file, "r", encoding="utf-8") as f:
                return json.load(f)
        else:
            return self._get_default_prompt(prompt_type)
            
    def save_prompt(
        self,
        prompt_type: str,
        system_prompt: str,
        user_prompt_template: str,
        metadata: Optional[Dict[str, Any]] = None
    ) -> str:
        """
        保存新版本的提示词
        
        Args:
            prompt_type: 提示词类型
            system_prompt: 系统提示词
            user_prompt_template: 用户提示词模板
            metadata: 元数据
            
        Returns:
            版本号
        """
        # 生成版本号
        existing_versions = [
            f.stem.split("_v")[-1]
            for f in self.prompt_storage.glob(f"{prompt_type}_v*.json")
        ]
        version = self._generate_version(existing_versions)
        
        prompt_data = {
            "version": version,
            "type": prompt_type,
            "system_prompt": system_prompt,
            "user_prompt_template": user_prompt_template,
            "created_at": datetime.now().isoformat(),
            "metadata": metadata or {}
        }
        
        prompt_file = self.prompt_storage / f"{prompt_type}_v{version}.json"
        with open(prompt_file, "w", encoding="utf-8") as f:
            json.dump(prompt_data, f, indent=2, ensure_ascii=False)
            
        # 记录版本历史
        self.version_history.append({
            "type": prompt_type,
            "version": version,
            "created_at": prompt_data["created_at"]
        })
        
        logger.info(f"提示词已保存: {prompt_type}_v{version}")
        return version
        
    def analyze_performance(
        self,
        prompt_type: str,
        days: int = 7
    ) -> Dict[str, Any]:
        """
        分析提示词性能
        
        Args:
            prompt_type: 提示词类型
            days: 分析天数
            
        Returns:
            性能分析结果
        """
        # 这里应该从Power BI或数据库获取数据
        # 目前返回模拟数据
        analysis = {
            "prompt_type": prompt_type,
            "period_days": days,
            "total_requests": 0,
            "success_rate": 0.0,
            "avg_response_time": 0.0,
            "avg_confidence": 0.0,
            "user_satisfaction": 0.0,
            "recommendations": []
        }
        
        # TODO: 从Power BI获取实际数据
        # data = self.power_bi.get_metrics(prompt_type, days)
        
        return analysis
        
    def optimize_prompt(
        self,
        prompt_type: str,
        feedback: Dict[str, Any]
    ) -> Dict[str, str]:
        """
        基于反馈优化提示词
        
        Args:
            prompt_type: 提示词类型
            feedback: 反馈数据
            
        Returns:
            优化后的提示词
        """
        current_prompt = self.load_prompt(prompt_type)
        
        # 分析反馈
        issues = feedback.get("issues", [])
        suggestions = feedback.get("suggestions", [])
        
        # 优化系统提示词
        optimized_system = self._optimize_system_prompt(
            current_prompt.get("system_prompt", ""),
            issues,
            suggestions
        )
        
        # 优化用户提示词模板
        optimized_user = self._optimize_user_prompt(
            current_prompt.get("user_prompt_template", ""),
            issues,
            suggestions
        )
        
        # 保存优化后的提示词
        version = self.save_prompt(
            prompt_type,
            optimized_system,
            optimized_user,
            metadata={
                "optimized_from": current_prompt.get("version", "default"),
                "feedback": feedback
            }
        )
        
        # 收集调优数据
        self.power_bi.collect_prompt_tuning_data(
            prompt_version=version,
            success_rate=feedback.get("success_rate", 0.0),
            avg_response_time=feedback.get("avg_response_time", 0.0),
            user_feedback=json.dumps(feedback)
        )
        
        return {
            "version": version,
            "system_prompt": optimized_system,
            "user_prompt_template": optimized_user
        }
        
    def _optimize_system_prompt(
        self,
        current: str,
        issues: List[str],
        suggestions: List[str]
    ) -> str:
        """优化系统提示词"""
        # 简单的优化逻辑（可以改进为使用LLM优化）
        optimized = current
        
        # 如果反馈提到输出格式问题，添加格式要求
        if any("格式" in issue or "format" in issue.lower() for issue in issues):
            if "输出格式" not in optimized:
                optimized += "\n\n请确保输出格式清晰、结构化。"
                
        # 如果反馈提到准确性问题，强调准确性
        if any("准确" in issue or "accuracy" in issue.lower() for issue in issues):
            if "准确" not in optimized:
                optimized = "请确保分析结果准确、可靠。\n\n" + optimized
                
        return optimized
        
    def _optimize_user_prompt(
        self,
        current: str,
        issues: List[str],
        suggestions: List[str]
    ) -> str:
        """优化用户提示词模板"""
        # 简单的优化逻辑
        optimized = current
        
        # 添加建议的改进
        if suggestions:
            optimized += "\n\n注意：" + "; ".join(suggestions)
            
        return optimized
        
    def _generate_version(self, existing_versions: List[str]) -> str:
        """生成版本号"""
        if not existing_versions:
            return "1.0.0"
            
        # 解析现有版本号
        versions = []
        for v in existing_versions:
            try:
                parts = v.split(".")
                if len(parts) == 3:
                    versions.append(tuple(map(int, parts)))
            except:
                continue
                
        if versions:
            latest = max(versions)
            # 增加补丁版本
            new_version = (latest[0], latest[1], latest[2] + 1)
            return ".".join(map(str, new_version))
        else:
            return "1.0.0"
            
    def _get_default_prompt(self, prompt_type: str) -> Dict[str, str]:
        """获取默认提示词"""
        defaults = {
            "test_generation": {
                "system_prompt": """你是一个测试用例生成专家，能够根据需求文档生成完整的测试用例。
生成的用例应该包括：
1. 前置条件
2. 测试步骤
3. 预期结果
4. 断言
5. 清理步骤

使用Pytest格式。""",
                "user_prompt_template": """测试用例生成请求：

需求描述：
{requirement}

功能点：
{features}

请生成完整的测试用例。"""
            },
            "defect_analysis": {
                "system_prompt": """你是一个专业的测试工程师，擅长分析测试失败的根本原因。
请分析提供的测试失败信息，包括：
1. 错误堆栈
2. 页面截图
3. 网络请求
4. 测试步骤

输出格式：
- 可能原因（按概率排序）
- 建议验证步骤
- 修复建议""",
                "user_prompt_template": """测试失败分析请求：

错误信息：
{error}

测试步骤：
{steps}

页面URL：
{url}

请分析失败的根本原因。"""
            },
            "locator_recommendation": {
                "system_prompt": """你是一个自动化测试专家，擅长推荐稳定的元素定位策略。
根据DOM结构和失败信息，推荐最稳定的定位方式（如role、testid、data-testid等）。""",
                "user_prompt_template": """元素定位推荐请求：

失败的定位器：
{failed_locator}

DOM结构：
{dom_snippet}

请推荐更稳定的定位策略。"""
            }
        }
        
        return defaults.get(prompt_type, {
            "system_prompt": "",
            "user_prompt_template": ""
        })


class FeedbackCollector:
    """反馈收集器"""
    
    def __init__(self):
        """初始化反馈收集器"""
        self.feedback_storage = Path("data/feedback")
        self.feedback_storage.mkdir(parents=True, exist_ok=True)
        
    def collect_feedback(
        self,
        prompt_type: str,
        prompt_version: str,
        llm_response: str,
        actual_result: str,
        user_rating: Optional[int] = None,
        user_comment: Optional[str] = None
    ):
        """
        收集反馈
        
        Args:
            prompt_type: 提示词类型
            prompt_version: 提示词版本
            llm_response: LLM响应
            actual_result: 实际结果
            user_rating: 用户评分（1-5）
            user_comment: 用户评论
        """
        feedback = {
            "timestamp": datetime.now().isoformat(),
            "prompt_type": prompt_type,
            "prompt_version": prompt_version,
            "llm_response": llm_response,
            "actual_result": actual_result,
            "user_rating": user_rating,
            "user_comment": user_comment,
            "match_score": self._calculate_match_score(llm_response, actual_result)
        }
        
        # 保存反馈
        feedback_file = self.feedback_storage / f"feedback_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(feedback_file, "w", encoding="utf-8") as f:
            json.dump(feedback, f, indent=2, ensure_ascii=False)
            
        logger.info(f"反馈已收集: {prompt_type} v{prompt_version}")
        return feedback
        
    def _calculate_match_score(self, response: str, actual: str) -> float:
        """计算匹配分数（简单实现）"""
        # 简单的文本相似度计算
        response_lower = response.lower()
        actual_lower = actual.lower()
        
        # 计算共同词汇比例
        response_words = set(response_lower.split())
        actual_words = set(actual_lower.split())
        
        if not actual_words:
            return 0.0
            
        common_words = response_words & actual_words
        score = len(common_words) / len(actual_words)
        
        return min(score, 1.0)

