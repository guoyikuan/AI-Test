"""
页面对象模型基类
提供统一的页面操作基座和智能等待策略
"""
from typing import Optional, List, Dict, Any
from playwright.sync_api import Page, Locator, expect, TimeoutError as PlaywrightTimeoutError
from loguru import logger
import time


class PageBase:
    """页面对象基类，封装通用操作和智能等待策略"""
    
    def __init__(self, page: Page, base_url: str = ""):
        """
        初始化页面对象
        
        Args:
            page: Playwright Page对象
            base_url: 基础URL
        """
        self.page = page
        self.base_url = base_url
        self.timeout = 30000  # 默认超时30秒
        
    def navigate(self, url: str = ""):
        """
        导航到指定URL
        
        Args:
            url: 相对或绝对URL
        """
        full_url = f"{self.base_url}{url}" if url and not url.startswith("http") else url or self.base_url
        logger.info(f"导航到: {full_url}")
        self.page.goto(full_url, wait_until="networkidle")
        
    def wait_for_element(
        self,
        selector: str,
        timeout: Optional[int] = None,
        state: str = "visible"
    ) -> Locator:
        """
        智能等待元素出现
        
        Args:
            selector: 元素选择器
            timeout: 超时时间（毫秒）
            state: 等待状态 (visible, hidden, attached, detached)
            
        Returns:
            Locator对象
        """
        timeout = timeout or self.timeout
        locator = self.page.locator(selector)
        
        try:
            if state == "visible":
                locator.wait_for(state="visible", timeout=timeout)
            elif state == "hidden":
                locator.wait_for(state="hidden", timeout=timeout)
            elif state == "attached":
                locator.wait_for(state="attached", timeout=timeout)
            elif state == "detached":
                locator.wait_for(state="detached", timeout=timeout)
                
            logger.debug(f"元素已{state}: {selector}")
            return locator
        except PlaywrightTimeoutError:
            logger.error(f"等待元素超时: {selector}, 状态: {state}")
            raise
            
    def click(self, selector: str, timeout: Optional[int] = None, force: bool = False):
        """
        点击元素（带智能等待）
        
        Args:
            selector: 元素选择器
            timeout: 超时时间
            force: 是否强制点击（即使元素不可见）
        """
        locator = self.wait_for_element(selector, timeout)
        logger.info(f"点击元素: {selector}")
        locator.click(force=force)
        
    def fill(self, selector: str, text: str, timeout: Optional[int] = None):
        """
        填充输入框
        
        Args:
            selector: 元素选择器
            text: 要输入的文本
            timeout: 超时时间
        """
        locator = self.wait_for_element(selector, timeout)
        logger.info(f"填充输入框 {selector}: {text[:20]}...")
        locator.fill(text)
        
    def get_text(self, selector: str, timeout: Optional[int] = None) -> str:
        """
        获取元素文本
        
        Args:
            selector: 元素选择器
            timeout: 超时时间
            
        Returns:
            元素文本内容
        """
        locator = self.wait_for_element(selector, timeout)
        text = locator.text_content()
        logger.debug(f"获取文本 {selector}: {text[:50]}...")
        return text or ""
        
    def is_visible(self, selector: str, timeout: Optional[int] = None) -> bool:
        """
        检查元素是否可见
        
        Args:
            selector: 元素选择器
            timeout: 超时时间
            
        Returns:
            是否可见
        """
        try:
            self.wait_for_element(selector, timeout, state="visible")
            return True
        except PlaywrightTimeoutError:
            return False
            
    def wait_for_network_idle(self, timeout: Optional[int] = None):
        """
        等待网络空闲
        
        Args:
            timeout: 超时时间
        """
        timeout = timeout or self.timeout
        self.page.wait_for_load_state("networkidle", timeout=timeout)
        
    def take_screenshot(self, name: str, full_page: bool = True):
        """
        截图
        
        Args:
            name: 截图文件名
            full_page: 是否截取整页
        """
        screenshot_path = f"screenshots/{name}_{int(time.time())}.png"
        self.page.screenshot(path=screenshot_path, full_page=full_page)
        logger.info(f"截图已保存: {screenshot_path}")
        return screenshot_path
        
    def get_page_snapshot(self) -> Dict[str, Any]:
        """
        获取页面快照（用于LLM分析）
        
        Returns:
            页面快照数据
        """
        return {
            "url": self.page.url,
            "title": self.page.title(),
            "html": self.page.content(),
            "screenshot": self.take_screenshot("snapshot"),
            "viewport": self.page.viewport_size,
        }


class SmartWaitStrategy:
    """智能等待策略"""
    
    @staticmethod
    def wait_for_condition(
        page: Page,
        condition: callable,
        timeout: int = 30000,
        interval: int = 500
    ) -> bool:
        """
        等待条件满足
        
        Args:
            page: Page对象
            condition: 条件函数
            timeout: 超时时间
            interval: 检查间隔
            
        Returns:
            是否满足条件
        """
        start_time = time.time() * 1000
        while (time.time() * 1000 - start_time) < timeout:
            try:
                if condition():
                    return True
            except Exception as e:
                logger.debug(f"等待条件检查异常: {e}")
            time.sleep(interval / 1000)
        return False

