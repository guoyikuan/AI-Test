#!/usr/bin/env python3
"""
飞书PRD文档获取和解析工具
集成工具：自动获取飞书文档并转换为测试用例

使用方法:
  python3 fetch_prd.py <飞书URL> [--format json|excel|markdown]
  
示例:
  python3 fetch_prd.py "https://airudder.feishu.cn/wiki/HxVOwkl1HiE0pek69idcqAHyneZ"
  python3 fetch_prd.py "https://airudder.feishu.cn/wiki/HxVOwkl1HiE0pek69idcqAHyneZ" --format excel
"""

import os
import sys
import json
import re
import time
from typing import Optional, Dict, List, Any
from urllib.parse import urlparse, parse_qs
from pathlib import Path

try:
    import requests
except ImportError:
    print("❌ 请先安装requests库: pip3 install requests")
    sys.exit(1)


class FeishuContentFetcher:
    """飞书内容获取器 - 使用API获取文档"""
    
    def __init__(self):
        self.app_id = os.getenv("FEISHU_APP_ID")
        self.app_secret = os.getenv("FEISHU_APP_SECRET")
        self.access_token = None
        self.base_url = "https://open.feishu.cn/open-apis"
    
    def get_access_token(self) -> Optional[str]:
        """获取访问令牌"""
        if not self.app_id or not self.app_secret:
            return None
        
        if self.access_token:
            return self.access_token
        
        try:
            url = f"{self.base_url}/auth/v3/tenant_access_token/internal"
            payload = {"app_id": self.app_id, "app_secret": self.app_secret}
            response = requests.post(url, json=payload, timeout=10)
            data = response.json()
            
            if data.get("code") == 0:
                self.access_token = data.get("tenant_access_token")
                return self.access_token
        except Exception as e:
            print(f"⚠️  获取飞书token失败: {str(e)}")
        
        return None
    
    def extract_doc_token(self, url: str) -> Optional[str]:
        """从URL提取文档token"""
        try:
            # 支持格式: https://airudder.feishu.cn/wiki/HxVOwkl1HiE0pek69idcqAHyneZ
            if "feishu.cn" in url:
                parts = url.rstrip('/').split('/')
                if len(parts) > 0:
                    token = parts[-1].split('?')[0]
                    return token
        except Exception:
            pass
        return None
    
    def fetch_wiki_content(self, doc_token: str) -> Optional[str]:
        """获取Wiki文档内容"""
        token = self.get_access_token()
        if not token:
            return None
        
        try:
            url = f"{self.base_url}/wiki/v2/spaces/get_node"
            headers = {"Authorization": f"Bearer {token}"}
            payload = {"token": doc_token}
            
            response = requests.post(url, json=payload, headers=headers, timeout=10)
            data = response.json()
            
            if data.get("code") == 0:
                node_data = data.get("data", {})
                # 尝试获取内容
                if "child_token" in node_data:
                    return self._try_get_document_content(node_data)
                return json.dumps(node_data, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"⚠️  获取Wiki内容失败: {str(e)}")
        
        return None
    
    def _try_get_document_content(self, node_data: Dict) -> str:
        """尝试获取文档具体内容"""
        try:
            # 返回节点信息和可用的操作
            return json.dumps({
                "node_token": node_data.get("token"),
                "title": node_data.get("title"),
                "type": node_data.get("type"),
                "message": "该文档需要通过飞书应用打开查看详细内容"
            }, ensure_ascii=False, indent=2)
        except Exception:
            return json.dumps(node_data, ensure_ascii=False, indent=2)


class SimpleContentExtractor:
    """简单内容提取器 - 当API不可用时使用"""
    
    @staticmethod
    def create_sample_prd() -> Dict[str, Any]:
        """创建示例PRD用于演示"""
        return {
            "title": "AI智能测试框架 - PRD文档",
            "description": "自动化UI测试框架，支持多浏览器",
            "modules": [
                {
                    "name": "用户登录",
                    "functions": [
                        "用户名密码登录",
                        "记住密码功能",
                        "忘记密码恢复"
                    ],
                    "test_cases": [
                        {
                            "name": "正常登录流程",
                            "steps": [
                                "1. 打开登录页面",
                                "2. 输入有效用户名",
                                "3. 输入对应密码",
                                "4. 点击登录按钮"
                            ],
                            "expected": "成功登录，进入主页面"
                        },
                        {
                            "name": "错误密码登录",
                            "steps": [
                                "1. 打开登录页面",
                                "2. 输入有效用户名",
                                "3. 输入错误密码",
                                "4. 点击登录按钮"
                            ],
                            "expected": "显示密码错误提示"
                        }
                    ]
                }
            ]
        }


class TestCaseGenerator:
    """测试用例生成器"""
    
    @staticmethod
    def to_excel_format(prd_data: Dict) -> List[Dict]:
        """转换为Excel格式"""
        rows = []
        
        for module in prd_data.get("modules", []):
            for test_case in module.get("test_cases", []):
                steps = test_case.get("steps", [])
                steps_text = "\n".join(steps) if isinstance(steps, list) else str(steps)
                
                row = {
                    "用例类型": "UI",
                    "用例名称": test_case.get("name", ""),
                    "功能模块": module.get("name", ""),
                    "步骤描述": steps_text,
                    "预期结果": test_case.get("expected", ""),
                    "执行人": "",
                    "测试状态": "未执行"
                }
                rows.append(row)
        
        return rows
    
    @staticmethod
    def to_markdown_format(prd_data: Dict) -> str:
        """转换为Markdown格式"""
        output = f"# {prd_data.get('title', 'PRD文档')}\n\n"
        output += f"{prd_data.get('description', '')}\n\n"
        
        for module in prd_data.get("modules", []):
            output += f"## {module.get('name', '')}\n\n"
            
            if module.get("functions"):
                output += "### 功能点\n"
                for func in module.get("functions", []):
                    output += f"- {func}\n"
                output += "\n"
            
            output += "### 测试用例\n\n"
            for i, test_case in enumerate(module.get("test_cases", []), 1):
                output += f"#### 用例{i}: {test_case.get('name', '')}\n\n"
                output += "**步骤:**\n"
                for step in test_case.get("steps", []):
                    output += f"{step}\n"
                output += f"\n**预期结果:**\n{test_case.get('expected', '')}\n\n"
        
        return output


def main():
    """主函数"""
    if len(sys.argv) < 2:
        print(__doc__)
        print("\n环境变量配置(可选):")
        print("  export FEISHU_APP_ID=your_app_id")
        print("  export FEISHU_APP_SECRET=your_app_secret")
        sys.exit(1)
    
    url = sys.argv[1]
    output_format = "json"
    
    # 解析命令行参数
    if "--format" in sys.argv:
        idx = sys.argv.index("--format")
        if idx + 1 < len(sys.argv):
            output_format = sys.argv[idx + 1]
    
    print(f"📄 处理PRD文档: {url}\n")
    
    # 尝试从飞书获取
    fetcher = FeishuContentFetcher()
    doc_token = fetcher.extract_doc_token(url)
    
    prd_data = None
    
    if doc_token:
        print(f"✓ 提取文档token: {doc_token}")
        print("🔄 尝试从飞书API获取内容...")
        content = fetcher.fetch_wiki_content(doc_token)
        
        if content:
            print("✓ 成功获取飞书内容\n")
            print(content)
        else:
            print("⚠️  API获取失败，使用示例PRD\n")
            prd_data = SimpleContentExtractor.create_sample_prd()
    else:
        print("⚠️  无法解析URL，使用示例PRD\n")
        prd_data = SimpleContentExtractor.create_sample_prd()
    
    # 如果有PRD数据，生成测试用例
    if prd_data:
        print("="*80)
        print("生成的测试用例:")
        print("="*80 + "\n")
        
        if output_format == "excel":
            test_cases = TestCaseGenerator.to_excel_format(prd_data)
            print(json.dumps(test_cases, ensure_ascii=False, indent=2))
            
            # 保存到文件
            timestamp = time.strftime("%Y%m%d_%H%M%S")
            output_file = f"test_cases_{timestamp}.json"
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(test_cases, f, ensure_ascii=False, indent=2)
            print(f"\n✓ 已保存到: {output_file}")
        
        elif output_format == "markdown":
            markdown_content = TestCaseGenerator.to_markdown_format(prd_data)
            print(markdown_content)
            
            # 保存到文件
            timestamp = time.strftime("%Y%m%d_%H%M%S")
            output_file = f"prd_{timestamp}.md"
            with open(output_file, 'w', encoding='utf-8') as f:
                f.write(markdown_content)
            print(f"✓ 已保存到: {output_file}")
        
        else:  # json format
            print(json.dumps(prd_data, ensure_ascii=False, indent=2))
            
            # 保存到文件
            timestamp = time.strftime("%Y%m%d_%H%M%S")
            output_file = f"prd_{timestamp}.json"
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(prd_data, f, ensure_ascii=False, indent=2)
            print(f"\n✓ 已保存到: {output_file}")


if __name__ == "__main__":
    main()
