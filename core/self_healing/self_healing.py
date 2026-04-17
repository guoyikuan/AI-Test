"""
智能定位与自愈机制
当元素定位失败时，使用LLM分析并推荐新的定位策略
"""
from typing import Optional, Dict, Any, List
from playwright.sync_api import Page, Locator, TimeoutError as PlaywrightTimeoutError
from loguru import logger
import json
import re

from core.llm.llm_client import LLMClient


class SelfHealingLocator:
    """智能自愈定位器"""
    
    def __init__(self, page: Page, llm_client: LLMClient):
        """
        初始化自愈定位器
        
        Args:
            page: Playwright Page对象
            llm_client: LLM客户端
        """
        self.page = page
        self.llm_client = llm_client
        self.failed_locators: List[Dict[str, Any]] = []
        
    def find_element(
        self,
        original_locator: str,
        description: str = "",
        timeout: int = 5000
    ) -> Optional[Locator]:
        """
        智能查找元素，失败时自动尝试自愈
        
        Args:
            original_locator: 原始定位器
            description: 元素描述
            timeout: 超时时间
            
        Returns:
            Locator对象，失败返回None
        """
        try:
            # 尝试原始定位器
            locator = self.page.locator(original_locator)
            locator.wait_for(state="visible", timeout=timeout)
            logger.info(f"元素定位成功: {original_locator}")
            return locator
        except PlaywrightTimeoutError:
            logger.warning(f"元素定位失败: {original_locator}, 尝试自愈...")
            return self._heal_locator(original_locator, description)
            
    def _heal_locator(
        self,
        failed_locator: str,
        description: str
    ) -> Optional[Locator]:
        """
        自愈定位器：使用LLM分析并推荐新定位策略
        
        Args:
            failed_locator: 失败的定位器
            description: 元素描述
            
        Returns:
            新的Locator对象，失败返回None
        """
        try:
            # 获取页面快照
            page_snapshot = self._get_page_snapshot()
            
            # 使用LLM分析并推荐定位策略
            context = {
                "failed_locator": failed_locator,
                "description": description,
                "dom_snippet": page_snapshot.get("dom_snippet", ""),
                "url": self.page.url
            }
            
            recommendation = self.llm_client.analyze(
                context,
                "locator_recommendation"
            )
            
            # 解析LLM推荐的新定位器
            new_locators = self._parse_locator_recommendation(
                recommendation.get("recommendation", "")
            )
            
            # 尝试新的定位器
            for new_locator in new_locators:
                try:
                    locator = self.page.locator(new_locator)
                    locator.wait_for(state="visible", timeout=3000)
                    logger.success(f"自愈成功！新定位器: {new_locator}")
                    
                    # 记录自愈信息
                    self._record_healing(failed_locator, new_locator, description)
                    return locator
                except PlaywrightTimeoutError:
                    continue
                    
            logger.error("所有自愈尝试均失败")
            return None
            
        except Exception as e:
            logger.error(f"自愈过程出错: {str(e)}")
            return None
            
    def _get_page_snapshot(self) -> Dict[str, Any]:
        """获取页面快照（DOM片段）"""
        try:
            # 获取页面HTML（限制长度）
            html = self.page.content()
            # 只取前5000字符用于分析
            dom_snippet = html[:5000] if len(html) > 5000 else html
            
            return {
                "dom_snippet": dom_snippet,
                "url": self.page.url,
                "title": self.page.title()
            }
        except Exception as e:
            logger.error(f"获取页面快照失败: {str(e)}")
            return {}
            
    def _parse_locator_recommendation(self, recommendation: str) -> List[str]:
        """
        解析LLM推荐的定位器
        
        Args:
            recommendation: LLM推荐文本
            
        Returns:
            定位器列表
        """
        locators = []
        
        # 尝试提取代码块中的定位器
        code_block_pattern = r'```(?:python|javascript)?\s*(.*?)```'
        matches = re.findall(code_block_pattern, recommendation, re.DOTALL)
        for match in matches:
            # 提取字符串字面量
            string_pattern = r'["\']([^"\']+)["\']'
            strings = re.findall(string_pattern, match)
            locators.extend(strings)
            
        # 如果没有代码块，尝试直接提取引号内容
        if not locators:
            string_pattern = r'["\']([^"\']+)["\']'
            locators = re.findall(string_pattern, recommendation)
            
        # 去重并过滤
        locators = list(set([loc for loc in locators if len(loc) > 3]))
        
        logger.debug(f"解析到 {len(locators)} 个推荐定位器")
        return locators
        
    def _record_healing(
        self,
        original_locator: str,
        new_locator: str,
        description: str
    ):
        """记录自愈信息"""
        healing_record = {
            "original_locator": original_locator,
            "new_locator": new_locator,
            "description": description,
            "timestamp": str(self.page.context.browser.timeout if hasattr(self.page.context, 'browser') else None)
        }
        self.failed_locators.append(healing_record)
        logger.info(f"记录自愈: {original_locator} -> {new_locator}")


class LocatorStrategy:
    """定位策略推荐器"""
    
    STRATEGIES = [
        "get_by_role",
        "get_by_test_id",
        "get_by_label",
        "get_by_placeholder",
        "get_by_text",
        "locator"
    ]
    
    @staticmethod
    def recommend_strategy(element_info: Dict[str, Any]) -> str:
        """
        推荐最佳定位策略
        
        Args:
            element_info: 元素信息
            
        Returns:
            推荐的定位策略
        """
        # 优先级：role > testid > label > placeholder > text > css/xpath
        if element_info.get("role"):
            return "get_by_role"
        elif element_info.get("testid") or element_info.get("data-testid"):
            return "get_by_test_id"
        elif element_info.get("label"):
            return "get_by_label"
        elif element_info.get("placeholder"):
            return "get_by_placeholder"
        elif element_info.get("text"):
            return "get_by_text"
        else:
            return "locator"

