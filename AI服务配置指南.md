# AI服务配置指南

## 🎯 支持的AI服务提供商

框架支持以下AI服务：

1. **OpenAI** (GPT系列)
   - 模型：gpt-4-turbo-preview, gpt-3.5-turbo等
   - 支持自定义base_url（用于国内代理）

2. **Anthropic** (Claude系列)
   - 模型：claude-3-opus-20240229等

3. **通义千问** (Tongyi/Qwen)
   - 模型：qwen-turbo, qwen-plus等
   - 支持DashScope API

4. **智谱AI** (Zhipu/GLM)
   - 模型：glm-4, glm-3-turbo等

5. **自定义服务**
   - 支持任何OpenAI兼容接口的AI服务

## ⚙️ 配置方法

### 方法一：使用配置助手（推荐）

```bash
# 激活虚拟环境
source venv/bin/activate

# 运行配置助手
python scripts/configure_llm.py
```

配置助手会引导您：
1. 选择AI服务提供商
2. 输入API密钥
3. 选择模型
4. 配置自定义API地址（如需要）

### 方法二：手动编辑.env文件

```bash
# 编辑.env文件
nano .env
```

#### OpenAI配置示例

```env
LLM_PROVIDER=openai
OPENAI_API_KEY=sk-your-api-key-here
LLM_MODEL=gpt-4-turbo-preview
# 可选：国内代理地址
OPENAI_BASE_URL=https://api.openai-proxy.com/v1
```

#### 通义千问配置示例

```env
LLM_PROVIDER=tongyi
TONGYI_API_KEY=sk-your-api-key-here
LLM_MODEL=qwen-turbo
TONGYI_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1
```

#### 智谱AI配置示例

```env
LLM_PROVIDER=zhipu
ZHIPU_API_KEY=your-api-key-here
LLM_MODEL=glm-4
ZHIPU_BASE_URL=https://open.bigmodel.cn/api/paas/v4
```

#### 自定义服务配置示例

```env
LLM_PROVIDER=custom
CUSTOM_LLM_API_KEY=your-api-key-here
LLM_MODEL=gpt-3.5-turbo
LLM_BASE_URL=https://your-custom-ai-service.com/v1
```

## 🔍 验证配置

```bash
# 检查配置
python scripts/check_llm_config.py

# 或使用Python代码验证
python3 << EOF
from core.llm.llm_client import LLMClient
try:
    client = LLMClient()
    print("✅ LLM配置有效！")
    print(f"提供商: {client.provider}")
except Exception as e:
    print(f"❌ 配置错误: {e}")
EOF
```

## 📋 环境变量说明

| 变量名 | 说明 | 必需 | 默认值 |
|--------|------|------|--------|
| `LLM_PROVIDER` | AI服务提供商 | 是 | openai |
| `LLM_MODEL` | 模型名称 | 否 | 根据提供商不同 |
| `LLM_TEMPERATURE` | 温度参数 | 否 | 0.7 |
| `OPENAI_API_KEY` | OpenAI API密钥 | OpenAI必需 | - |
| `ANTHROPIC_API_KEY` | Anthropic API密钥 | Anthropic必需 | - |
| `TONGYI_API_KEY` | 通义千问API密钥 | 通义千问必需 | - |
| `ZHIPU_API_KEY` | 智谱AI API密钥 | 智谱AI必需 | - |
| `CUSTOM_LLM_API_KEY` | 自定义服务API密钥 | 自定义服务必需 | - |
| `LLM_BASE_URL` | 自定义API地址 | 可选 | - |

## 🚀 使用示例

### 在代码中使用

```python
from core.llm.llm_client import LLMClient

# 使用默认配置（从.env读取）
client = LLMClient()

# 或指定提供商
client = LLMClient(provider="tongyi")

# 生成文本
result = client.generate("你好，请介绍一下自己")
print(result)
```

### 在测试中使用

```python
from core.llm.llm_client import LLMClient

def test_with_llm(llm_client):
    """使用LLM的测试"""
    result = llm_client.generate("分析这个测试用例")
    assert result is not None
```

## 🔄 切换AI服务

### 快速切换

1. 编辑`.env`文件，修改`LLM_PROVIDER`
2. 配置对应的API密钥
3. 重启应用或重新加载配置

### 示例：从OpenAI切换到通义千问

```bash
# 1. 编辑.env
nano .env

# 2. 修改以下行：
LLM_PROVIDER=tongyi
TONGYI_API_KEY=your-tongyi-key
LLM_MODEL=qwen-turbo

# 3. 验证配置
python scripts/check_llm_config.py
```

## ⚠️ 注意事项

1. **API密钥安全**
   - 不要将`.env`文件提交到版本控制
   - 使用环境变量或密钥管理服务

2. **模型选择**
   - 不同提供商的模型名称不同
   - 确保模型名称正确

3. **网络访问**
   - 某些AI服务可能需要代理
   - 配置`BASE_URL`使用代理地址

4. **成本控制**
   - 不同模型的成本不同
   - 建议在测试环境使用较便宜的模型

## 🐛 故障排查

### 问题：API密钥错误

```
ValueError: OPENAI_API_KEY未设置
```

**解决**：检查`.env`文件中的API密钥是否正确配置

### 问题：模型不存在

```
Error: Model not found
```

**解决**：检查模型名称是否正确，参考各提供商的文档

### 问题：网络连接失败

```
ConnectionError: Failed to connect
```

**解决**：
1. 检查网络连接
2. 配置代理或使用`BASE_URL`
3. 检查防火墙设置

## 📖 更多信息

- [OpenAI API文档](https://platform.openai.com/docs)
- [Anthropic API文档](https://docs.anthropic.com)
- [通义千问文档](https://help.aliyun.com/zh/model-studio)
- [智谱AI文档](https://open.bigmodel.cn/)

---

**最后更新**: 2025-12-24

