#!/usr/bin/env python3
"""
PRD解析工具
用途：将飞书PRD文档解析为结构化测试用例
"""

import json
import re
from typing import List, Dict, Any, Optional
from pathlib import Path
import sys
import os


class PRDParser:
    """PRD文档解析器"""
    
    def __init__(self):
        """初始化解析器"""
        self.test_cases = []
        self.functions = []
    
    def parse_markdown_content(self, content: str) -> Dict[str, Any]:
        """
        解析Markdown格式的PRD内容
        
        Args:
            content: PRD内容（Markdown格式）
            
        Returns:
            解析后的结构化数据
        """
        result = {
            "title": "",
            "functions": [],
            "test_cases": []
        }
        
        lines = content.split('\n')
        current_section = None
        current_content = []
        
        for line in lines:
            # 识别标题
            if line.startswith('# '):
                if current_section and current_content:
                    result = self._process_section(result, current_section, current_content)
                result["title"] = line.replace('# ', '').strip()
                current_section = None
                current_content = []
            
            # 识别二级标题
            elif line.startswith('## '):
                if current_section and current_content:
                    result = self._process_section(result, current_section, current_content)
                current_section = line.replace('## ', '').strip()
                current_content = []
            
            else:
                current_content.append(line)
        
        # 处理最后一个section
        if current_section and current_content:
            result = self._process_section(result, current_section, current_content)
        
        return result
    
    def parse_json_content(self, content: str) -> Dict[str, Any]:
        """
        解析JSON格式的飞书文档内容
        
        Args:
            content: JSON格式的文档内容
            
        Returns:
            解析后的测试用例
        """
        try:
            data = json.loads(content)
            return self._extract_from_json(data)
        except json.JSONDecodeError:
            return {"error": "无法解析JSON内容", "functions": [], "test_cases": []}
    
    def _extract_from_json(self, data: Dict) -> Dict[str, Any]:
        """从JSON数据提取测试用例信息"""
        result = {
            "title": "",
            "functions": [],
            "test_cases": []
        }
        
        # 尝试从不同的字段提取标题和内容
        if isinstance(data, dict):
            # 提取标题
            for title_key in ["title", "name", "doc_title"]:
                if title_key in data:
                    result["title"] = data[title_key]
                    break
            
            # 尝试查找content字段并解析
            for key in ["content", "body", "description", "data"]:
                if key in data and isinstance(data[key], (str, dict)):
                    if isinstance(data[key], str):
                        # 尝试解析为Markdown
                        content = self.parse_markdown_content(data[key])
                        result["functions"].extend(content.get("functions", []))
                        result["test_cases"].extend(content.get("test_cases", []))
                    elif isinstance(data[key], dict):
                        result["functions"].extend(self._extract_functions(data[key]))
                        result["test_cases"].extend(self._extract_test_cases(data[key]))
        
        return result
    
    def _extract_functions(self, data: Dict) -> List[Dict]:
        """从数据中提取功能点"""
        functions = []
        
        for key, value in data.items():
            if key.lower() in ["functions", "features", "requirements", "功能"]:
                if isinstance(value, list):
                    for item in value:
                        if isinstance(item, dict):
                            functions.append(item)
                        elif isinstance(item, str):
                            functions.append({"name": item})
        
        return functions
    
    def _extract_test_cases(self, data: Dict) -> List[Dict]:
        """从数据中提取测试用例"""
        test_cases = []
        
        for key, value in data.items():
            if key.lower() in ["test_cases", "testcases", "cases", "用例", "测试用例"]:
                if isinstance(value, list):
                    test_cases.extend(value)
        
        return test_cases
    
    def _process_section(self, result: Dict, section: str, content: List[str]) -> Dict:
        """处理一个section"""
        content_text = '\n'.join(content).strip()
        
        if not content_text:
            return result
        
        section_lower = section.lower()
        
        # 识别功能点section
        if any(x in section_lower for x in ["功能", "function", "feature", "requirement"]):
            functions = self._parse_function_section(content_text)
            result["functions"].extend(functions)
        
        # 识别测试用例section
        elif any(x in section_lower for x in ["测试用例", "test case", "用例", "case"]):
            test_cases = self._parse_test_case_section(content_text)
            result["test_cases"].extend(test_cases)
        
        return result
    
    def _parse_function_section(self, content: str) -> List[Dict]:
        """解析功能点section"""
        functions = []
        
        # 简单的列表项识别
        lines = content.split('\n')
        for line in lines:
            line = line.strip()
            if line.startswith(('- ', '* ', '+ ')) or re.match(r'^\d+\.\s', line):
                # 移除列表符号
                func_text = re.sub(r'^[\-\*\+\d\.]\s+', '', line).strip()
                if func_text:
                    functions.append({
                        "name": func_text,
                        "type": "UI"
                    })
        
        return functions
    
    def _parse_test_case_section(self, content: str) -> List[Dict]:
        """解析测试用例section"""
        test_cases = []
        
        # 识别表格格式或结构化格式
        # 简化版本：按特定模式识别
        case_pattern = r'(?:用例|case|测试)\s*[：:]\s*(.+?)(?=\n(?:用例|case|测试)|$)'
        matches = re.findall(case_pattern, content, re.MULTILINE | re.IGNORECASE)
        
        for match in matches:
            case_content = match.strip()
            test_case = {
                "name": case_content[:50],  # 前50个字符作为名称
                "steps": [],
                "expected": ""
            }
            
            # 尝试识别步骤和预期结果
            if '步骤' in case_content or 'steps' in case_content.lower():
                parts = re.split(r'(?:步骤|steps|预期|expected)', case_content, flags=re.IGNORECASE)
                if len(parts) > 1:
                    test_case["steps"] = [p.strip() for p in parts[1].split('\n') if p.strip()]
                if len(parts) > 2:
                    test_case["expected"] = parts[2].strip()
            
            test_cases.append(test_case)
        
        return test_cases
    
    def to_excel_format(self, parsed_data: Dict) -> List[Dict]:
        """
        将解析后的数据转换为Excel格式
        
        Returns:
            可直接写入Excel的字典列表
        """
        excel_rows = []
        
        # 功能点转换为UI测试用例
        for func in parsed_data.get("functions", []):
            row = {
                "用例类型": "UI",
                "用例名称": func.get("name", ""),
                "功能模块": parsed_data.get("title", ""),
                "步骤描述": func.get("description", ""),
                "预期结果": func.get("expected", ""),
                "执行人": "",
                "测试状态": "未执行"
            }
            excel_rows.append(row)
        
        # 测试用例直接转换
        for case in parsed_data.get("test_cases", []):
            steps = case.get("steps", [])
            steps_text = "\n".join(steps) if isinstance(steps, list) else str(steps)
            
            row = {
                "用例类型": case.get("type", "UI"),
                "用例名称": case.get("name", ""),
                "功能模块": parsed_data.get("title", ""),
                "步骤描述": steps_text,
                "预期结果": case.get("expected", ""),
                "执行人": "",
                "测试状态": "未执行"
            }
            excel_rows.append(row)
        
        return excel_rows


def parse_prd_file(file_path: str) -> Dict[str, Any]:
    """
    解析PRD文件
    
    Args:
        file_path: PRD文件路径
        
    Returns:
        解析后的数据
    """
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"文件不存在: {file_path}")
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    parser = PRDParser()
    
    # 检测内容格式
    if content.strip().startswith('{'):
        return parser.parse_json_content(content)
    else:
        return parser.parse_markdown_content(content)


def main():
    """主函数 - 演示用法"""
    if len(sys.argv) < 2:
        print("用法: python prd_parser.py <PRD文件路径> [输出格式]")
        print("\n输出格式:")
        print("  json - JSON格式 (默认)")
        print("  excel - Excel兼容格式")
        sys.exit(1)
    
    file_path = sys.argv[1]
    output_format = sys.argv[2] if len(sys.argv) > 2 else "json"
    
    try:
        print(f"正在解析PRD文件: {file_path}")
        parsed_data = parse_prd_file(file_path)
        
        if output_format == "excel":
            parser = PRDParser()
            excel_data = parser.to_excel_format(parsed_data)
            print("\nExcel格式数据:")
            print(json.dumps(excel_data, ensure_ascii=False, indent=2))
        else:
            print("\n解析结果:")
            print(json.dumps(parsed_data, ensure_ascii=False, indent=2))
        
    except Exception as e:
        print(f"❌ 错误: {str(e)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
