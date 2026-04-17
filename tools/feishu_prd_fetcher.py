#!/usr/bin/env python3
"""
飞书文档获取工具
用途：获取飞书Wiki/文档内容，用于生成测试用例
"""

import os
import json
import requests
from typing import Optional, Dict, List
from urllib.parse import urlparse, parse_qs
import time


class FeishuPRDFetcher:
    """飞书文档获取器"""
    
    def __init__(self, app_id: Optional[str] = None, app_secret: Optional[str] = None):
        """
        初始化飞书获取器
        
        Args:
            app_id: 飞书应用ID (可从环境变量FEISHU_APP_ID获取)
            app_secret: 飞书应用Secret (可从环境变量FEISHU_APP_SECRET获取)
        """
        self.app_id = app_id or os.getenv("FEISHU_APP_ID")
        self.app_secret = app_secret or os.getenv("FEISHU_APP_SECRET")
        self.access_token = None
        self.token_expire_time = 0
        self.base_url = "https://open.feishu.cn/open-apis"
        
    def get_access_token(self) -> str:
        """
        获取飞书访问令牌
        
        Returns:
            访问令牌
            
        Raises:
            RuntimeError: 如果没有配置app_id和app_secret
        """
        if not self.app_id or not self.app_secret:
            raise RuntimeError(
                "未配置飞书应用凭证。请设置环境变量:\n"
                "  export FEISHU_APP_ID=your_app_id\n"
                "  export FEISHU_APP_SECRET=your_app_secret\n"
                "\n获取凭证方式:\n"
                "1. 访问: https://open.feishu.cn/app\n"
                "2. 创建或选择应用\n"
                "3. 在应用凭证处获取 App ID 和 App Secret"
            )
        
        # 检查token是否仍有效
        if self.access_token and time.time() < self.token_expire_time:
            return self.access_token
        
        url = f"{self.base_url}/auth/v3/tenant_access_token/internal"
        payload = {
            "app_id": self.app_id,
            "app_secret": self.app_secret
        }
        
        try:
            response = requests.post(url, json=payload, timeout=10)
            response.raise_for_status()
            data = response.json()
            
            if data.get("code") != 0:
                raise RuntimeError(f"获取token失败: {data.get('msg')}")
            
            self.access_token = data.get("tenant_access_token")
            # token有效期约2小时，提前10分钟刷新
            self.token_expire_time = time.time() + int(data.get("expire", 7200)) - 600
            return self.access_token
            
        except requests.exceptions.RequestException as e:
            raise RuntimeError(f"请求飞书API失败: {str(e)}")
    
    def extract_doc_id(self, url: str) -> Optional[str]:
        """
        从飞书URL提取文档ID
        
        Args:
            url: 飞书文档URL
            
        Returns:
            文档ID
        """
        # 支持的URL格式:
        # https://airudder.feishu.cn/wiki/HxVOwkl1HiE0pek69idcqAHyneZ
        # https://airudder.feishu.cn/docs/doccn...
        
        if "feishu.cn" not in url:
            return None
        
        parts = url.rstrip('/').split('/')
        if len(parts) > 0:
            doc_id = parts[-1]
            # 移除查询参数
            if '?' in doc_id:
                doc_id = doc_id.split('?')[0]
            return doc_id
        
        return None
    
    def get_document_raw_content(self, doc_id: str) -> str:
        """
        获取文档原始内容（支持多种格式）
        
        Args:
            doc_id: 文档ID
            
        Returns:
            文档内容
        """
        token = self.get_access_token()
        
        # 尝试作为wiki获取
        url = f"{self.base_url}/wiki/v2/spaces/get_node"
        headers = {"Authorization": f"Bearer {token}"}
        payload = {"token": doc_id}
        
        try:
            response = requests.post(url, json=payload, headers=headers, timeout=10)
            response.raise_for_status()
            data = response.json()
            
            if data.get("code") == 0:
                return json.dumps(data.get("data", {}), ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"获取wiki内容失败: {str(e)}")
        
        # 如果wiki失败，尝试作为doc获取
        url = f"{self.base_url}/docs/v4/documents/{doc_id}/raw_content"
        try:
            response = requests.get(url, headers=headers, timeout=10)
            response.raise_for_status()
            return response.text
        except Exception as e:
            print(f"获取doc内容失败: {str(e)}")
        
        raise RuntimeError(f"无法获取文档内容: {doc_id}")
    
    def fetch_from_url(self, url: str) -> str:
        """
        从飞书URL获取文档内容
        
        Args:
            url: 飞书文档URL
            
        Returns:
            文档内容
        """
        doc_id = self.extract_doc_id(url)
        if not doc_id:
            raise ValueError(f"无法从URL提取文档ID: {url}")
        
        return self.get_document_raw_content(doc_id)


def main():
    """主函数 - 演示用法"""
    import sys
    
    if len(sys.argv) < 2:
        print("用法: python feishu_prd_fetcher.py <飞书文档URL>")
        print("\n示例:")
        print("  python feishu_prd_fetcher.py https://airudder.feishu.cn/wiki/HxVOwkl1HiE0pek69idcqAHyneZ")
        print("\n环境变量配置:")
        print("  export FEISHU_APP_ID=your_app_id")
        print("  export FEISHU_APP_SECRET=your_app_secret")
        sys.exit(1)
    
    url = sys.argv[1]
    
    try:
        fetcher = FeishuPRDFetcher()
        print(f"正在获取文档内容: {url}")
        content = fetcher.fetch_from_url(url)
        print("\n" + "="*80)
        print("文档内容:")
        print("="*80)
        print(content)
        
        # 保存到文件
        timestamp = time.strftime("%Y%m%d_%H%M%S")
        output_file = f"prd_content_{timestamp}.json"
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"\n✓ 内容已保存到: {output_file}")
        
    except RuntimeError as e:
        print(f"❌ 错误: {str(e)}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"❌ 未知错误: {str(e)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
