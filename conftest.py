"""
Pytest配置和全局fixtures
"""
import pytest
from playwright.sync_api import Page, Browser, BrowserContext
from loguru import logger
import os

from core.llm.llm_client import LLMClient
from llm_services.defect_analysis.defect_analyzer import DefectAnalyzer
from dashboard.power_bi_collector import PowerBICollector


@pytest.fixture(scope="session")
def browser_type_launch_args():
    """浏览器启动参数"""
    return {
        "headless": os.getenv("HEADLESS", "true").lower() == "true",
        "slow_mo": 100 if os.getenv("SLOW_MO") else 0
    }


@pytest.fixture(scope="session")
def browser_name():
    """
    指定使用的浏览器类型
    支持通过环境变量BROWSER_TYPE指定: chromium, firefox, webkit
    默认为chromium（项目兼容需求）
    """
    browser_type = os.getenv("BROWSER_TYPE", "chromium").lower()
    valid_browsers = ["chromium", "firefox", "webkit"]
    if browser_type not in valid_browsers:
        logger.warning(f"不支持的浏览器: {browser_type}，使用默认chromium")
        browser_type = "chromium"
    return browser_type


@pytest.fixture(scope="session")
def browser_context_args():
    """浏览器上下文参数"""
    return {
        "viewport": {"width": 1920, "height": 1080},
        "record_video_dir": "videos/",
        "record_video_size": {"width": 1920, "height": 1080}
    }


@pytest.fixture(scope="function")
def page(browser: Browser, browser_context_args: dict) -> Page:
    """创建新页面"""
    context = browser.new_context(**browser_context_args)
    page = context.new_page()
    yield page
    context.close()


@pytest.fixture(scope="session")
def llm_client() -> LLMClient:
    """LLM客户端fixture"""
    provider = os.getenv("LLM_PROVIDER", "openai")
    model = os.getenv("LLM_MODEL")
    return LLMClient(
        provider=provider,
        model=model
    )


@pytest.fixture(scope="session")
def defect_analyzer(llm_client: LLMClient) -> DefectAnalyzer:
    """缺陷分析器fixture"""
    return DefectAnalyzer(llm_client)


@pytest.fixture(scope="session")
def power_bi_collector() -> PowerBICollector:
    """Power BI收集器fixture"""
    collector = PowerBICollector()
    collector.authenticate()
    return collector


@pytest.hookimpl(tryfirst=True, hookwrapper=True)
def pytest_runtest_makereport(item, call):
    """在测试报告生成时收集数据"""
    outcome = yield
    rep = outcome.get_result()
    
    # 如果测试失败，收集失败信息
    if rep.when == "call" and rep.failed:
        # 这里可以添加失败时的处理逻辑
        logger.error(f"测试失败: {item.name}, {rep.longrepr}")


@pytest.fixture(autouse=True)
def setup_test_environment():
    """每个测试前的环境设置"""
    # 创建必要的目录
    os.makedirs("screenshots", exist_ok=True)
    os.makedirs("reports", exist_ok=True)
    os.makedirs("videos", exist_ok=True)
    os.makedirs("allure-results", exist_ok=True)
    yield
    # 测试后的清理工作可以在这里添加

