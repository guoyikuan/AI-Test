"""
LLM驱动的测试用例生成器
从需求文档或用户故事生成Pytest/Robot Framework测试用例
"""
import os
import json
from typing import List, Dict, Any, Optional
from pathlib import Path
from loguru import logger

from core.llm.llm_client import LLMClient


class TestCaseGenerator:
    """测试用例生成器"""
    
    def __init__(self, llm_client: Optional[LLMClient] = None):
        """
        初始化测试用例生成器
        
        Args:
            llm_client: LLM客户端，如果为None则自动创建
        """
        self.llm_client = llm_client or LLMClient()
        self.output_dir = Path("tests/generated")
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
    def generate_from_requirement(
        self,
        requirement: str,
        feature_name: str,
        output_format: str = "pytest"
    ) -> Dict[str, Any]:
        """
        从需求文档生成测试用例
        
        Args:
            requirement: 需求描述
            feature_name: 功能名称
            output_format: 输出格式 (pytest, robot)
            
        Returns:
            生成的测试用例信息
        """
        logger.info(f"开始生成测试用例: {feature_name}")
        
        context = {
            "requirement": requirement,
            "features": feature_name,
            "format": output_format
        }
        
        result = self.llm_client.analyze(context, "test_generation")
        test_case_code = result.get("test_case", "")
        
        # 保存生成的测试用例
        output_file = self._save_test_case(
            test_case_code,
            feature_name,
            output_format
        )
        
        return {
            "feature": feature_name,
            "code": test_case_code,
            "file": str(output_file),
            "format": output_format
        }
        
    def generate_from_user_story(
        self,
        user_story: str,
        output_format: str = "pytest"
    ) -> Dict[str, Any]:
        """
        从用户故事生成测试用例
        
        Args:
            user_story: 用户故事文本
            output_format: 输出格式
            
        Returns:
            生成的测试用例信息
        """
        # 解析用户故事
        story_parts = self._parse_user_story(user_story)
        
        requirement = f"""
作为 {story_parts.get('role', '用户')}
我想要 {story_parts.get('want', '')}
以便 {story_parts.get('benefit', '')}

验收标准：
{story_parts.get('criteria', '')}
"""
        
        feature_name = story_parts.get('feature', 'user_story')
        return self.generate_from_requirement(requirement, feature_name, output_format)
        
    def batch_generate(
        self,
        requirements: List[Dict[str, str]],
        output_format: str = "pytest"
    ) -> List[Dict[str, Any]]:
        """
        批量生成测试用例
        
        Args:
            requirements: 需求列表，每个元素包含 requirement 和 feature_name
            output_format: 输出格式
            
        Returns:
            生成的测试用例列表
        """
        results = []
        for req in requirements:
            try:
                result = self.generate_from_requirement(
                    req.get("requirement", ""),
                    req.get("feature_name", "unknown"),
                    output_format
                )
                results.append(result)
            except Exception as e:
                logger.error(f"生成测试用例失败: {req.get('feature_name')}, 错误: {str(e)}")
                results.append({
                    "feature": req.get("feature_name", "unknown"),
                    "error": str(e)
                })
        return results
        
    def _parse_user_story(self, user_story: str) -> Dict[str, str]:
        """
        解析用户故事
        
        Args:
            user_story: 用户故事文本
            
        Returns:
            解析后的用户故事组件
        """
        # 简单的用户故事解析（可以改进）
        parts = {
            "role": "",
            "want": "",
            "benefit": "",
            "criteria": "",
            "feature": ""
        }
        
        lines = user_story.split("\n")
        for line in lines:
            if "作为" in line or "As a" in line:
                parts["role"] = line.split("作为")[-1].split("As a")[-1].strip()
            elif "我想要" in line or "I want" in line:
                parts["want"] = line.split("我想要")[-1].split("I want")[-1].strip()
            elif "以便" in line or "so that" in line:
                parts["benefit"] = line.split("以便")[-1].split("so that")[-1].strip()
            elif "验收" in line or "criteria" in line.lower():
                parts["criteria"] = line
                
        # 从want中提取功能名称
        if parts["want"]:
            parts["feature"] = parts["want"].split()[0] if parts["want"].split() else "feature"
            
        return parts
        
    def _save_test_case(
        self,
        code: str,
        feature_name: str,
        format: str
    ) -> Path:
        """
        保存生成的测试用例
        
        Args:
            code: 测试用例代码
            feature_name: 功能名称
            format: 格式
            
        Returns:
            保存的文件路径
        """
        # 清理功能名称（用于文件名）
        safe_name = "".join(c for c in feature_name if c.isalnum() or c in (' ', '-', '_')).strip()
        safe_name = safe_name.replace(' ', '_').lower()
        
        if format == "pytest":
            filename = f"test_{safe_name}.py"
        elif format == "robot":
            filename = f"{safe_name}.robot"
        else:
            filename = f"{safe_name}.{format}"
            
        file_path = self.output_dir / filename
        
        # 添加文件头注释
        header = f'''"""
自动生成的测试用例
功能: {feature_name}
生成时间: {os.popen('date').read().strip()}
注意: 请检查并完善生成的测试用例
"""
'''
        
        if format == "pytest":
            full_code = header + code
        else:
            full_code = code
            
        file_path.write_text(full_code, encoding="utf-8")
        logger.info(f"测试用例已保存: {file_path}")
        
        return file_path


class RequirementParser:
    """需求文档解析器"""
    
    @staticmethod
    def parse_markdown(markdown_text: str) -> List[Dict[str, str]]:
        """
        解析Markdown格式的需求文档
        
        Args:
            markdown_text: Markdown文本
            
        Returns:
            需求列表
        """
        requirements = []
        # 简单的Markdown解析（可以改进）
        lines = markdown_text.split("\n")
        current_requirement = {}
        
        for line in lines:
            if line.startswith("#"):
                if current_requirement:
                    requirements.append(current_requirement)
                current_requirement = {
                    "feature_name": line.lstrip("#").strip(),
                    "requirement": ""
                }
            elif current_requirement:
                current_requirement["requirement"] += line + "\n"
                
        if current_requirement:
            requirements.append(current_requirement)
            
        return requirements

