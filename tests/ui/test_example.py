"""
示例UI测试用例
展示如何使用Playwright + POM + LLM + 自愈机制
"""
import os
import pytest
from playwright.sync_api import Page, expect
from core.base.page_base import PageBase
from core.llm.llm_client import LLMClient
from core.self_healing.self_healing import SelfHealingLocator
from llm_services.defect_analysis.defect_analyzer import DefectAnalyzer
from dashboard.power_bi_collector import PowerBICollector
from loguru import logger


class LoginPage(PageBase):
    """登录页面对象"""
    
    def __init__(self, page: Page):
        base_url = os.getenv("BASE_URL", "https://test-aicc.airudder.com")
        super().__init__(page, base_url=base_url)
        self.self_healing = SelfHealingLocator(page, LLMClient())
        
    def login(self, username: str, password: str):
        """登录操作"""
        self.navigate("/login")
        
        # 使用自愈定位器
        username_input = self.self_healing.find_element(
            "input[name='username']",
            "用户名输入框"
        )
        if username_input:
            username_input.fill(username)
        
        password_input = self.self_healing.find_element(
            "input[name='password']",
            "密码输入框"
        )
        if password_input:
            password_input.fill(password)
            
        login_button = self.self_healing.find_element(
            "button[type='submit']",
            "登录按钮"
        )
        if login_button:
            login_button.click()
            
    def is_logged_in(self) -> bool:
        """检查是否已登录"""
        return self.is_visible(".user-menu", timeout=5000)


@pytest.fixture
def login_page(page: Page) -> LoginPage:
    """登录页面fixture"""
    return LoginPage(page)


@pytest.fixture
def defect_analyzer():
    """缺陷分析器fixture"""
    return DefectAnalyzer()


@pytest.fixture
def power_bi_collector():
    """Power BI收集器fixture"""
    return PowerBICollector()


def test_login_success(login_page: LoginPage, power_bi_collector: PowerBICollector):
    """测试登录成功"""
    import time
    start_time = time.time()
    user = os.getenv("TEST_USER", "testsuperadmin")
    password = os.getenv("TEST_PASSWORD", "Passw0rd!1234")

    try:
        # 执行登录
        login_page.login(user, password)
        
        # 验证登录成功
        assert login_page.is_logged_in(), "登录失败"
        
        duration = time.time() - start_time
        power_bi_collector.collect_test_result(
            test_name="test_login_success",
            status="passed",
            duration=duration
        )
        
    except Exception as e:
        duration = time.time() - start_time
        error_msg = str(e)
        
        # 收集失败数据
        power_bi_collector.collect_test_result(
            test_name="test_login_success",
            status="failed",
            duration=duration,
            error_message=error_msg
        )
        
        raise


def test_login_failure_with_analysis(
    login_page: LoginPage,
    defect_analyzer: DefectAnalyzer,
    power_bi_collector: PowerBICollector
):
    """测试登录失败并使用LLM分析"""
    import time
    import traceback
    start_time = time.time()
    
    try:
        # 执行登录（使用错误密码）
        login_page.login("testuser", "wrongpass")
        
        # 验证登录失败
        assert not login_page.is_logged_in(), "登录应该失败"
        
    except Exception as e:
        duration = time.time() - start_time
        error_msg = str(e)
        stack_trace = traceback.format_exc()
        
        # 截图
        screenshot_path = login_page.take_screenshot("login_failure")
        
        # 使用LLM分析失败原因
        analysis = defect_analyzer.analyze_failure(
            test_name="test_login_failure_with_analysis",
            error_message=error_msg,
            stack_trace=stack_trace,
            screenshot_path=screenshot_path,
            test_steps=["导航到登录页", "输入用户名", "输入密码", "点击登录"]
        )
        
        logger.info(f"LLM分析结果: {analysis}")
        
        # 收集数据
        power_bi_collector.collect_test_result(
            test_name="test_login_failure_with_analysis",
            status="failed",
            duration=duration,
            error_message=error_msg,
            llm_analysis=analysis
        )
        
        # 保存分析报告
        defect_analyzer.save_analysis_report(analysis)
        
        raise

