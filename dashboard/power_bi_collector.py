"""
Power BI数据收集器
收集测试执行结果、LLM建议、性能指标等数据
"""
import os
import json
from typing import Dict, Any, List, Optional
from datetime import datetime
from loguru import logger
import requests
from azure.identity import ClientSecretCredential
from msal import ConfidentialClientApplication

from dotenv import load_dotenv

load_dotenv()


class PowerBICollector:
    """Power BI数据收集器"""
    
    def __init__(self):
        """初始化Power BI收集器"""
        self.client_id = os.getenv("POWER_BI_CLIENT_ID")
        self.client_secret = os.getenv("POWER_BI_CLIENT_SECRET")
        self.tenant_id = os.getenv("POWER_BI_TENANT_ID")
        self.workspace_id = os.getenv("POWER_BI_WORKSPACE_ID")
        self.dataset_id = os.getenv("POWER_BI_DATASET_ID")
        self.access_token = None
        
    def authenticate(self) -> bool:
        """
        认证Power BI
        
        Returns:
            是否认证成功
        """
        try:
            app = ConfidentialClientApplication(
                client_id=self.client_id,
                client_credential=self.client_secret,
                authority=f"https://login.microsoftonline.com/{self.tenant_id}"
            )
            
            result = app.acquire_token_for_client(
                scopes=["https://analysis.windows.net/powerbi/api/.default"]
            )
            
            if "access_token" in result:
                self.access_token = result["access_token"]
                logger.info("Power BI认证成功")
                return True
            else:
                logger.error(f"Power BI认证失败: {result.get('error_description')}")
                return False
                
        except Exception as e:
            logger.error(f"Power BI认证异常: {str(e)}")
            return False
            
    def collect_test_result(
        self,
        test_name: str,
        status: str,
        duration: float,
        error_message: str = "",
        llm_analysis: Optional[Dict] = None,
        self_healing_used: bool = False,
        healing_success: bool = False
    ):
        """
        收集测试结果
        
        Args:
            test_name: 测试名称
            status: 状态 (passed, failed, skipped)
            duration: 执行时长（秒）
            error_message: 错误消息
            llm_analysis: LLM分析结果
            self_healing_used: 是否使用自愈
            healing_success: 自愈是否成功
        """
        data = {
            "timestamp": datetime.now().isoformat(),
            "test_name": test_name,
            "status": status,
            "duration": duration,
            "error_message": error_message,
            "llm_analysis_used": llm_analysis is not None,
            "llm_confidence": llm_analysis.get("confidence", 0) if llm_analysis else 0,
            "self_healing_used": self_healing_used,
            "healing_success": healing_success,
            "environment": os.getenv("ENVIRONMENT", "dev")
        }
        
        self._push_to_power_bi("test_results", [data])
        
    def collect_llm_metrics(
        self,
        operation_type: str,
        success: bool,
        response_time: float,
        tokens_used: int = 0,
        cost: float = 0.0
    ):
        """
        收集LLM指标
        
        Args:
            operation_type: 操作类型 (test_generation, defect_analysis, locator_recommendation)
            success: 是否成功
            response_time: 响应时间（秒）
            tokens_used: 使用的token数
            cost: 成本
        """
        data = {
            "timestamp": datetime.now().isoformat(),
            "operation_type": operation_type,
            "success": success,
            "response_time": response_time,
            "tokens_used": tokens_used,
            "cost": cost
        }
        
        self._push_to_power_bi("llm_metrics", [data])
        
    def collect_self_healing_metrics(
        self,
        original_locator: str,
        new_locator: str,
        success: bool,
        healing_time: float
    ):
        """
        收集自愈指标
        
        Args:
            original_locator: 原始定位器
            new_locator: 新定位器
            success: 是否成功
            healing_time: 自愈耗时（秒）
        """
        data = {
            "timestamp": datetime.now().isoformat(),
            "original_locator": original_locator,
            "new_locator": new_locator,
            "success": success,
            "healing_time": healing_time
        }
        
        self._push_to_power_bi("self_healing_metrics", [data])
        
    def collect_prompt_tuning_data(
        self,
        prompt_version: str,
        success_rate: float,
        avg_response_time: float,
        user_feedback: Optional[str] = None
    ):
        """
        收集提示词调优数据
        
        Args:
            prompt_version: 提示词版本
            success_rate: 成功率
            avg_response_time: 平均响应时间
            user_feedback: 用户反馈
        """
        data = {
            "timestamp": datetime.now().isoformat(),
            "prompt_version": prompt_version,
            "success_rate": success_rate,
            "avg_response_time": avg_response_time,
            "user_feedback": user_feedback
        }
        
        self._push_to_power_bi("prompt_tuning", [data])
        
    def _push_to_power_bi(self, table_name: str, rows: List[Dict[str, Any]]):
        """
        推送数据到Power BI
        
        Args:
            table_name: 表名
            rows: 数据行
        """
        if not self.access_token:
            if not self.authenticate():
                logger.warning("Power BI认证失败，数据未推送")
                return
                
        try:
            url = f"https://api.powerbi.com/v1.0/myorg/groups/{self.workspace_id}/datasets/{self.dataset_id}/tables/{table_name}/rows"
            
            headers = {
                "Authorization": f"Bearer {self.access_token}",
                "Content-Type": "application/json"
            }
            
            payload = {"rows": rows}
            
            response = requests.post(url, headers=headers, json=payload)
            
            if response.status_code == 200:
                logger.debug(f"数据已推送到Power BI: {table_name}, {len(rows)}行")
            else:
                logger.warning(f"Power BI推送失败: {response.status_code}, {response.text}")
                
        except Exception as e:
            logger.error(f"Power BI推送异常: {str(e)}")
            
    def batch_collect(self, data_batch: Dict[str, List[Dict[str, Any]]]):
        """
        批量收集数据
        
        Args:
            data_batch: 数据批次，键为表名，值为数据行列表
        """
        for table_name, rows in data_batch.items():
            self._push_to_power_bi(table_name, rows)

