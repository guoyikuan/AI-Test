"""
缺陷根因分析器
使用LLM分析测试失败的根本原因
"""
from typing import Dict, Any, List, Optional
from pathlib import Path
from loguru import logger
import json
import base64

from core.llm.llm_client import LLMClient


class DefectAnalyzer:
    """缺陷分析器"""
    
    def __init__(self, llm_client: Optional[LLMClient] = None):
        """
        初始化缺陷分析器
        
        Args:
            llm_client: LLM客户端
        """
        self.llm_client = llm_client or LLMClient()
        self.analysis_history: List[Dict[str, Any]] = []
        
    def analyze_failure(
        self,
        test_name: str,
        error_message: str,
        stack_trace: str = "",
        screenshot_path: str = "",
        network_logs: List[Dict] = None,
        test_steps: List[str] = None
    ) -> Dict[str, Any]:
        """
        分析测试失败
        
        Args:
            test_name: 测试名称
            error_message: 错误消息
            stack_trace: 堆栈跟踪
            screenshot_path: 截图路径
            network_logs: 网络请求日志
            test_steps: 测试步骤
            
        Returns:
            分析结果
        """
        logger.info(f"开始分析测试失败: {test_name}")
        
        # 准备上下文
        context = {
            "test_name": test_name,
            "error": error_message,
            "stack_trace": stack_trace,
            "test_steps": "\n".join(test_steps) if test_steps else "",
            "network_logs": json.dumps(network_logs, indent=2) if network_logs else ""
        }
        
        # 如果有截图，读取并编码
        if screenshot_path and Path(screenshot_path).exists():
            try:
                with open(screenshot_path, "rb") as f:
                    screenshot_data = base64.b64encode(f.read()).decode()
                context["screenshot"] = screenshot_data
            except Exception as e:
                logger.warning(f"读取截图失败: {str(e)}")
        
        # 使用LLM分析
        result = self.llm_client.analyze(context, "defect_analysis")
        
        # 解析分析结果
        analysis = self._parse_analysis(result.get("analysis", ""))
        
        # 保存分析历史
        analysis_record = {
            "test_name": test_name,
            "error": error_message,
            "analysis": analysis,
            "timestamp": str(Path().cwd())
        }
        self.analysis_history.append(analysis_record)
        
        return {
            "test_name": test_name,
            "possible_causes": analysis.get("causes", []),
            "verification_steps": analysis.get("verification", []),
            "fix_suggestions": analysis.get("fixes", []),
            "confidence": analysis.get("confidence", 0.5)
        }
        
    def _parse_analysis(self, analysis_text: str) -> Dict[str, Any]:
        """
        解析LLM分析结果
        
        Args:
            analysis_text: LLM分析文本
            
        Returns:
            结构化的分析结果
        """
        result = {
            "causes": [],
            "verification": [],
            "fixes": [],
            "confidence": 0.5
        }
        
        # 简单的文本解析（可以改进为更智能的解析）
        lines = analysis_text.split("\n")
        current_section = None
        
        for line in lines:
            line = line.strip()
            if not line:
                continue
                
            # 识别章节
            if "原因" in line or "cause" in line.lower():
                current_section = "causes"
            elif "验证" in line or "verification" in line.lower():
                current_section = "verification"
            elif "修复" in line or "fix" in line.lower():
                current_section = "fixes"
            elif "置信度" in line or "confidence" in line.lower():
                # 提取置信度数值
                import re
                confidence_match = re.search(r'(\d+\.?\d*)', line)
                if confidence_match:
                    result["confidence"] = float(confidence_match.group(1))
            elif current_section and line.startswith(("-", "*", "1.", "2.")):
                # 提取列表项
                item = line.lstrip("-*1234567890. ").strip()
                if item:
                    result[current_section].append(item)
                    
        return result
        
    def save_analysis_report(
        self,
        analysis: Dict[str, Any],
        output_path: str = "reports/defect_analysis.json"
    ):
        """
        保存分析报告
        
        Args:
            analysis: 分析结果
            output_path: 输出路径
        """
        output_file = Path(output_path)
        output_file.parent.mkdir(parents=True, exist_ok=True)
        
        with open(output_file, "w", encoding="utf-8") as f:
            json.dump(analysis, f, indent=2, ensure_ascii=False)
            
        logger.info(f"分析报告已保存: {output_file}")


class FailurePatternDetector:
    """失败模式检测器"""
    
    def __init__(self):
        """初始化失败模式检测器"""
        self.patterns = {
            "timeout": ["timeout", "等待超时", "element not found"],
            "network": ["network", "网络", "connection", "连接"],
            "assertion": ["assert", "断言", "expected", "预期"],
            "locator": ["locator", "定位器", "selector", "元素定位"],
            "permission": ["permission", "权限", "access denied", "访问拒绝"]
        }
        
    def detect_pattern(self, error_message: str) -> List[str]:
        """
        检测失败模式
        
        Args:
            error_message: 错误消息
            
        Returns:
            检测到的模式列表
        """
        detected = []
        error_lower = error_message.lower()
        
        for pattern_name, keywords in self.patterns.items():
            if any(keyword in error_lower for keyword in keywords):
                detected.append(pattern_name)
                
        return detected

