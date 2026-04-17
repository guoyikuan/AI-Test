import os
import pytest
import pandas as pd
import requests

from tests.ui.test_pds_from_excel import load_pds_api_cases, parse_steps_and_assertions
from core.llm.llm_client import LLMClient


def test_api_case_from_excel(case):
    """基于 Excel API 测试用例动态执行的通用脚本。"""
    case_name = case.get('用例名称', '').strip()
    steps_raw = case.get('步骤描述', '').strip()
    expected = case.get('预期结果', '').strip()

    llm_client = LLMClient()

    assert case_name, '用例名称不可为空'

    # 解析步骤和断言
    actions, assertions = parse_steps_and_assertions(steps_raw, expected, llm_client)

    # 执行API动作
    for action in actions:
        if '发送' in action and '请求' in action:
            # 假设步骤中包含API信息，这里需要解析URL、方法等
            # 这里是简化版，需要根据实际步骤扩展
            response = requests.get('https://api.example.com/test')  # 示例
            assert response.status_code == 200

    # 执行断言
    for assertion in assertions:
        if '状态码' in assertion and '200' in assertion:
            assert response.status_code == 200
        # 添加更多断言...


api_cases = load_pds_api_cases()


@pytest.mark.parametrize('case', api_cases)
def test_pds_api_case_from_excel(case):
    test_api_case_from_excel(case)


if __name__ == '__main__':
    print('PDS API用例数量:', len(api_cases))