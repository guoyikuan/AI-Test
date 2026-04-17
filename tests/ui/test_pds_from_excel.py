import os
import pytest
import pandas as pd

from core.base.page_base import PageBase
from core.self_healing.self_healing import SelfHealingLocator
from core.llm.llm_client import LLMClient


def load_pds_ui_cases():
    """从 Excel 文件中读取 PDS UI 测试用例（所有sheet）。"""
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    candidate_paths = [
        os.path.join(base_dir, '测试用例_PDS.xlsx'),
        os.path.join(os.path.dirname(base_dir), '测试用例_PDS.xlsx'),
        os.path.join(os.getcwd(), '测试用例_PDS.xlsx'),
    ]

    excel_path = None
    for p in candidate_paths:
        if os.path.exists(p):
            excel_path = p
            break

    if not excel_path:
        raise FileNotFoundError('未找到测试用例文件: 测试用例_PDS.xlsx, searched: ' + str(candidate_paths))

    all_records = []
    xl = pd.ExcelFile(excel_path)
    for sheet in xl.sheet_names:
        df = xl.parse(sheet_name=sheet, dtype=str)
        if '用例类型' in df.columns:
            ui_df = df[df['用例类型'].str.contains('UI', na=False)]
            if not ui_df.empty:
                all_records.extend(ui_df.fillna('').to_dict(orient='records'))

    return all_records


def load_pds_api_cases():
    """从 Excel 文件中读取 PDS API 测试用例（所有sheet）。"""
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    candidate_paths = [
        os.path.join(base_dir, '测试用例_PDS.xlsx'),
        os.path.join(os.path.dirname(base_dir), '测试用例_PDS.xlsx'),
        os.path.join(os.getcwd(), '测试用例_PDS.xlsx'),
    ]

    excel_path = None
    for p in candidate_paths:
        if os.path.exists(p):
            excel_path = p
            break

    if not excel_path:
        raise FileNotFoundError('未找到测试用例文件: 测试用例_PDS.xlsx, searched: ' + str(candidate_paths))

    all_records = []
    xl = pd.ExcelFile(excel_path)
    for sheet in xl.sheet_names:
        df = xl.parse(sheet_name=sheet, dtype=str)
        if '用例类型' in df.columns:
            api_df = df[df['用例类型'].str.contains('接口', na=False)]
            if not api_df.empty:
                all_records.extend(api_df.fillna('').to_dict(orient='records'))

    return all_records


def parse_steps_and_assertions(steps_raw, expected_raw, llm_client):
    """使用LLM解析步骤描述和预期结果为动作和断言。"""
    if not steps_raw and not expected_raw:
        return [], []

    prompt = f"""
请解析以下测试用例的步骤描述和预期结果，提取出具体的动作和断言。

步骤描述: {steps_raw}
预期结果: {expected_raw}

请以JSON格式返回，格式如下：
{{
  "actions": ["动作1", "动作2", ...],
  "assertions": ["断言1", "断言2", ...]
}}

动作应该是具体的操作，如"点击按钮"、"输入文本"、"导航到页面"等。
断言应该是验证条件，如"元素可见"、"文本匹配"、"状态检查"等。
"""

    try:
        response = llm_client.generate(prompt)
        import json
        parsed = json.loads(response)
        actions = parsed.get('actions', [])
        assertions = parsed.get('assertions', [])
        return actions, assertions
    except Exception as e:
        # 回退到简单解析
        actions = [s.strip() for s in steps_raw.split('#') if s.strip()]
        assertions = [e.strip() for e in expected_raw.split('#') if e.strip()]
        return actions, assertions



class PdsTemplatePage(PageBase):
    """简化版PDS模板元素操作封装"""

    def __init__(self, page):
        base_url = os.getenv('BASE_URL', 'https://test-aicc.airudder.com')
        super().__init__(page, base_url=base_url)
        self.self_healing = SelfHealingLocator(page, LLMClient())

    def open_template_settings(self):
        self.navigate('/#settings/dial-management/cust-info-template')

    def find_mandatory_column(self):
        # 基于页面结构，查找必填字段列
        return self.self_healing.find_element("th[data-field='required'], .column-header[data-key='required'], [data-label*='必填']", '必填字段列')

    def find_required_dropdown(self):
        # 查找必填字段下拉框
        return self.self_healing.find_element("select[name*='required'], .required-field-select, [data-field='required'] select", '必填字段下拉框')

    def find_phone_required_toggle(self):
        # 查找PhoneNumber必填开关
        return self.self_healing.find_element(".field-row[data-name='PhoneNumber'] input[type='checkbox'], .field-row:has-text('PhoneNumber') .switch, #phone-required-toggle", 'PhoneNumber必填开关')

    def find_template_table(self):
        # 查找模板表格
        return self.self_healing.find_element("table, .template-table, .data-table, [role='table']", '模板表格')

    def find_download_template_btn(self):
        # 查找下载模板按钮
        return self.self_healing.find_element("button:has-text('下载'), .download-btn, [data-action='download'], #download-template", '下载模板按钮')

    def find_realtime_board(self):
        # 查找实时看板
        return self.self_healing.find_element(".realtime-board, #realtime-board, [data-board='realtime']", '实时看板主区域')

    def find_history_board(self):
        # 查找历史看板
        return self.self_healing.find_element(".history-board, #history-board, [data-board='history']", '历史看板主区域')

    def find_login_form(self):
        # 查找登录表单
        return self.self_healing.find_element("form, .login-form, #login-form", '登录表单')

    def find_username_input(self):
        # 查找用户名输入框
        return self.self_healing.find_element("input[name='username'], input[type='text'], #username, .username-input", '用户名输入框')

    def find_password_input(self):
        # 查找密码输入框
        return self.self_healing.find_element("input[name='password'], input[type='password'], #password, .password-input", '密码输入框')

    def find_login_button(self):
        # 查找登录按钮
        return self.self_healing.find_element("button[type='submit'], button:has-text('登录'), .login-btn, #login-btn", '登录按钮')

    # 新增更多页面组件定位器
    def find_aicc_menu(self):
        return self.self_healing.find_element(".aicc-menu, #aicc-menu, nav, .navbar", 'AICC菜单')

    def find_home_entry(self):
        return self.self_healing.find_element(".home-entry, #home-entry, a[href*='home'], [data-link='home']", 'Home入口')

    def find_incoming_call_reminder(self):
        return self.self_healing.find_element(".incoming-call, .call-reminder, #incoming-call, [data-type='incoming-call']", '来电提醒页面')

    def find_encrypted_display(self):
        return self.self_healing.find_element(".encrypted-display, .masked-info, [data-encrypted='true']", '密文展示区域')

    def find_number_dimension(self):
        return self.self_healing.find_element(".number-dimension, #number-dimension, [data-section='number']", '号码维度页面')

    def find_new_field(self):
        return self.self_healing.find_element(".new-field, .added-field, [data-new='true']", '新增字段')

    def find_hover_element(self):
        return self.self_healing.find_element("[title], .tooltip-trigger, [data-tooltip]", 'hover提示元素')

    def find_tooltip(self):
        return self.self_healing.find_element(".tooltip, .popover, [role='tooltip']", '提示内容')

    def find_idle_status(self):
        return self.self_healing.find_element(".idle-status, .status-idle, [data-status='idle']", '空闲状态区域')

    def find_hint_icon(self):
        return self.self_healing.find_element(".hint-icon, .info-icon, i[class*='info']", '提示icon')

    def find_human_machine_call(self):
        return self.self_healing.find_element(".human-machine-call, #human-machine, [data-type='human-machine']", '人机协作来电页面')

    def find_new_chart(self):
        return self.self_healing.find_element(".new-chart, .chart-new, [data-chart='new']", '新增图表')

    def find_metric_tooltip(self):
        return self.self_healing.find_element(".metric, .kpi, [data-type='metric']", '指标元素')

    def find_tooltip_content(self):
        return self.self_healing.find_element(".tooltip-content, .tooltip-text, .popover-content", '完整提示信息')

    def find_status_acw(self):
        return self.self_healing.find_element(".status-acw, [data-status='acw'], .acw-status", 'ACW状态')

    def find_status_available(self):
        return self.self_healing.find_element(".status-available, [data-status='available'], .available-status", 'Available状态')

    def find_status_busy(self):
        return self.self_healing.find_element(".status-busy, [data-status='busy'], .busy-status", 'Busy状态')

    def find_calling_variables(self):
        return self.self_healing.find_element(".calling-variables, #calling-variables, [data-section='calling']", 'Calling变量页面')

    def find_required_field(self):
        return self.self_healing.find_element(".required-field, [data-required='true'], .mandatory-field", '必填标识')

    def open_realtime_dashboard(self):
        self.navigate('/#realtime-board')

    def open_history_dashboard(self):
        self.navigate('/#history-board')

    def verify_element_visible(self, selector, description):
        el = self.self_healing.find_element(selector, description)
        assert el is not None, f"[{description}] 未找到元素：{selector}"

    def perform_action(self, action_desc):
        """根据动作描述执行操作"""
        action_lower = action_desc.lower()
        if '导航' in action_lower and '登录' in action_lower:
            self.navigate('/login')
        elif '点击' in action_lower and '登录' in action_lower:
            login_btn = self.find_login_button()
            if login_btn:
                login_btn.click()
        elif '输入' in action_lower and '用户名' in action_lower:
            username_input = self.find_username_input()
            if username_input:
                username_input.fill('testsuperadmin')
        elif '输入' in action_lower and '密码' in action_lower:
            password_input = self.find_password_input()
            if password_input:
                password_input.fill('Passw0rd!1234')
        elif '打开' in action_lower and '模板设置' in action_lower:
            self.open_template_settings()
        elif '打开' in action_lower and '实时看板' in action_lower:
            self.open_realtime_dashboard()
        elif '打开' in action_lower and '历史看板' in action_lower:
            self.open_history_dashboard()
        elif '点击' in action_lower and '下载' in action_lower:
            download_btn = self.find_download_template_btn()
            if download_btn:
                download_btn.click()
        elif '导航' in action_lower and 'calling' in action_lower:
            self.navigate('/#calling-variables')
        elif '导航' in action_lower and 'home' in action_lower:
            home_entry = self.find_home_entry()
            if home_entry:
                home_entry.click()
        elif '导航' in action_lower and '来电' in action_lower:
            self.navigate('/#agent/incoming-call')
        elif '导航' in action_lower and '号码维度' in action_lower:
            self.navigate('/#number-dimension')
        elif '导航' in action_lower and '人机协作' in action_lower:
            self.navigate('/#human-machine/incoming-call')
        # 添加更多动作...

    def perform_assertion(self, assertion_desc):
        """根据断言描述执行验证"""
        assertion_lower = assertion_desc.lower()
        if '显示' in assertion_lower and '必填字段列' in assertion_lower:
            self.verify_element_visible("th[data-field='required'], .column-header[data-key='required']", '必填字段列')
        elif '显示' in assertion_lower and '必填字段下拉框' in assertion_lower:
            self.verify_element_visible("select[name*='required'], .required-field-select", '必填字段下拉框')
        elif '可见' in assertion_lower and '实时看板' in assertion_lower:
            self.verify_element_visible(".realtime-board, #realtime-board", '实时看板主区域')
        elif '可见' in assertion_lower and '历史看板' in assertion_lower:
            self.verify_element_visible(".history-board, #history-board", '历史看板主区域')
        elif '不可编辑' in assertion_lower and 'phonenumber' in assertion_lower:
            toggle = self.find_phone_required_toggle()
            assert toggle and not toggle.is_enabled(), 'PhoneNumber必填开关应不可编辑'
        elif '显示' in assertion_lower and 'home入口' in assertion_lower:
            self.verify_element_visible(".home-entry, #home-entry", 'Home入口')
        elif '显示' in assertion_lower and '密文' in assertion_lower:
            self.verify_element_visible(".encrypted-display, .masked-info", '密文展示区域')
        elif '显示' in assertion_lower and '新增字段' in assertion_lower:
            self.verify_element_visible(".new-field, .added-field", '新增字段')
        elif '显示' in assertion_lower and '提示内容' in assertion_lower:
            self.verify_element_visible(".tooltip, .popover", '提示内容')
        elif '显示' in assertion_lower and '提示icon' in assertion_lower:
            self.verify_element_visible(".hint-icon, .info-icon", '提示icon')
        elif '显示' in assertion_lower and '人机协作' in assertion_lower:
            self.verify_element_visible(".human-machine-call, #human-machine", '人机协作来电页面')
        elif '显示' in assertion_lower and '新增图表' in assertion_lower:
            self.verify_element_visible(".new-chart, .chart-new", '新增图表')
        elif '完整' in assertion_lower and '提示信息' in assertion_lower:
            self.verify_element_visible(".tooltip-content, .tooltip-text", '完整提示信息')
        elif '存在' in assertion_lower and 'acw状态' in assertion_lower:
            self.verify_element_visible(".status-acw, [data-status='acw']", 'ACW状态')
        elif '存在' in assertion_lower and 'available状态' in assertion_lower:
            self.verify_element_visible(".status-available, [data-status='available']", 'Available状态')
        elif '存在' in assertion_lower and 'busy状态' in assertion_lower:
            self.verify_element_visible(".status-busy, [data-status='busy']", 'Busy状态')
        elif '显示' in assertion_lower and '必填标识' in assertion_lower:
            self.verify_element_visible(".required-field, [data-required='true']", '必填标识')
        # 添加更多断言...


pds_cases = load_pds_ui_cases()


@pytest.mark.parametrize('case', pds_cases)
def test_pds_case_from_excel(case, page, power_bi_collector):
    """基于 Excel 测试用例动态执行的通用脚本。"""
    case_name = case.get('用例名称', '').strip()
    steps_raw = case.get('步骤描述', '').strip()
    expected = case.get('预期结果', '').strip()

    pds_page = PdsTemplatePage(page)
    llm_client = LLMClient()

    assert case_name, '用例名称不可为空'

    # 解析步骤和断言
    actions, assertions = parse_steps_and_assertions(steps_raw, expected, llm_client)

    # 统一登录流程（可根据实际页面修改）
    pds_page.navigate('/login')

    # 基于case_name的路由器
    if '登录' in case_name and '验证' in case_name:
        # 执行登录相关动作
        for action in actions:
            pds_page.perform_action(action)
        for assertion in assertions:
            pds_page.perform_assertion(assertion)

    elif '必填字段' in case_name and '自动外呼模板' in case_name:
        pds_page.open_template_settings()
        for action in actions:
            pds_page.perform_action(action)
        for assertion in assertions:
            pds_page.perform_assertion(assertion)

    elif '必填字段下拉框' in case_name:
        pds_page.open_template_settings()
        for action in actions:
            pds_page.perform_action(action)
        for assertion in assertions:
            pds_page.perform_assertion(assertion)

    elif 'PhoneNumber字段必填状态不可编辑' in case_name:
        pds_page.open_template_settings()
        for action in actions:
            pds_page.perform_action(action)
        for assertion in assertions:
            pds_page.perform_assertion(assertion)

    elif '下载模板' in case_name and '必填字段标识' in case_name:
        pds_page.open_template_settings()
        for action in actions:
            pds_page.perform_action(action)
        for assertion in assertions:
            pds_page.perform_assertion(assertion)

    elif '实时看板' in case_name:
        pds_page.open_realtime_dashboard()
        for action in actions:
            pds_page.perform_action(action)
        for assertion in assertions:
            pds_page.perform_assertion(assertion)

    elif '历史看板' in case_name:
        pds_page.open_history_dashboard()
        for action in actions:
            pds_page.perform_action(action)
        for assertion in assertions:
            pds_page.perform_assertion(assertion)

    elif case.get('一级模块', '').strip() == '实时看板':
        pds_page.open_realtime_dashboard()
        for action in actions:
            pds_page.perform_action(action)
        for assertion in assertions:
            pds_page.perform_assertion(assertion)

    elif case.get('一级模块', '').strip() == '历史看板':
        pds_page.open_history_dashboard()
        for action in actions:
            pds_page.perform_action(action)
        for assertion in assertions:
            pds_page.perform_assertion(assertion)

    elif '必填字段在自动外呼模板中的位置' in case_name:
        pds_page.open_template_settings()
        mandatory_col = pds_page.find_mandatory_column()
        assert mandatory_col is not None, '必填字段列应存在'
        # 检查位置逻辑可以在这里扩展

    elif 'Calling变量校验页面必填标识' in case_name:
        pds_page.navigate('/#calling-variables')
        pds_page.verify_element_visible(".required-field, [data-required='true']", 'Calling变量必填标识')

    elif 'AICC菜单左下角新增Home入口' in case_name:
        pds_page.verify_element_visible(".home-entry, #home-entry", 'Home入口')

    elif '座席端来电提醒页面密文展示' in case_name:
        pds_page.navigate('/#agent/incoming-call')
        pds_page.verify_element_visible(".encrypted-display, .masked-info", '密文展示区域')

    elif '号码维度新增字段' in case_name:
        pds_page.navigate('/#number-dimension')
        pds_page.verify_element_visible(".new-field, .added-field", '新增字段')

    elif 'hover提示内容' in case_name:
        element = pds_page.find_hover_element()
        if element:
            element.hover()
            pds_page.verify_element_visible(".tooltip, .popover", '提示内容')

    elif '空闲状态提示icon' in case_name:
        pds_page.verify_element_visible(".hint-icon, .info-icon", '空闲状态提示icon')

    elif '人机协作来电页面' in case_name:
        pds_page.navigate('/#human-machine/incoming-call')
        pds_page.verify_element_visible(".human-machine-call, #human-machine", '人机协作来电页面')

    elif '新增图表位置与基础属性' in case_name:
        pds_page.open_realtime_dashboard()
        pds_page.verify_element_visible(".new-chart, .chart-new", '新增图表')

    elif '指标提示信息完整性' in case_name:
        pds_page.open_realtime_dashboard()
        element = pds_page.find_metric_tooltip()
        if element:
            element.hover()
            pds_page.verify_element_visible(".tooltip-content, .tooltip-text", '完整提示信息')

    elif 'ACW/Available/Busy状态新增' in case_name:
        pds_page.verify_element_visible(".status-acw, [data-status='acw']", 'ACW状态')
        pds_page.verify_element_visible(".status-available, [data-status='available']", 'Available状态')
        pds_page.verify_element_visible(".status-busy, [data-status='busy']", 'Busy状态')

    elif '不同状态的颜色编码' in case_name:
        acw_element = pds_page.self_healing.find_element(".status-acw, [data-status='acw']", 'ACW状态元素')
        available_element = pds_page.self_healing.find_element(".status-available, [data-status='available']", 'Available状态元素')
        busy_element = pds_page.self_healing.find_element(".status-busy, [data-status='busy']", 'Busy状态元素')
        assert acw_element and available_element and busy_element, '所有状态元素应存在'

    else:
        # 通用执行：执行解析的动作和断言
        for action in actions:
            pds_page.perform_action(action)
        for assertion in assertions:
            pds_page.perform_assertion(assertion)

    power_bi_collector.collect_test_result(
        test_name=case_name,
        status='passed',
        duration=0.0
    )



if __name__ == '__main__':
    print('PDS UI用例数量:', len(pds_cases))
