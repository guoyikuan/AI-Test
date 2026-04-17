# Playwright浏览器兼容性指南

## 📋 支持的浏览器

本框架支持三种浏览器引擎：

| 浏览器 | 推荐场景 | macOS本地 | Docker | 优先级 |
|--------|---------|---------|--------|--------|
| **Firefox** | macOS开发、跨平台 | ✅ | ✅ | 🥇 推荐 |
| **Chromium** | CI/CD、Windows、Linux | ⚠️ | ✅ | 🥈 备选 |
| **WebKit** | Safari兼容性测试 | ⚠️ | ✅ | 🥉 测试用 |

## 🚀 使用方法

### 1. 本地运行（macOS推荐使用Firefox）

```bash
# 使用Firefox（默认，推荐）
python3 -m pytest tests/ui/test_pds_from_excel.py

# 或显式指定Firefox
BROWSER_TYPE=firefox python3 -m pytest tests/ui/test_pds_from_excel.py

# 测试页面结构获取
BROWSER_TYPE=firefox python3 get_page_structure.py
```

### 2. Docker运行（支持所有浏览器）

```bash
# 使用Firefox（默认）
docker-compose up ai_test_framework

# 使用Chromium
docker-compose up ai_test_framework_chromium

# 使用WebKit
docker-compose up ai_test_framework_webkit
```

### 3. 环境变量配置

配置文件中支持的环境变量：

- `BROWSER_TYPE`: 浏览器类型
  - `firefox` (默认) - 最佳macOS兼容性
  - `chromium` - 跨平台兼容性好
  - `webkit` - Safari兼容性测试

- `HEADLESS`: 无头模式
  - `true` (默认) - CI/CD环境
  - `false` - 本地调试

- `SLOW_MO`: 减速执行（毫秒）
  - 默认: 0（不减速）
  - 建议: 100（调试时）

## 🔧 macOS Playwright特殊配置说明

### Firefox （✅ 完全支持）
- 在macOS Apple Silicon上完全兼容
- 无需特殊配置，开箱即用
- 推荐用于本地开发和测试

### Chromium （⚠️ 本地有限制）
- macOS本地存在兼容性问题（特别是Apple Silicon）
- **推荐在Docker中运行**
- 在Linux Docker容器中完全支持

### WebKit （⚠️ 本地有限制）
- macOS本地支持受限
- **主要用于Docker中的跨浏览器测试**
- Safari兼容性测试时使用

## 📝 快速命令参考

```bash
# 本地快速测试（Firefox）
python3 -m pytest tests/ui/test_pds_from_excel.py -v -x

# Docker中的所有浏览器依次测试
docker-compose up ai_test_framework_firefox
docker-compose up ai_test_framework_chromium
docker-compose up ai_test_framework_webkit

# 在Docker中后台运行
docker-compose up -d ai_test_framework_chromium

# 查看Docker日志
docker-compose logs -f ai_test_framework_chromium

# 清理Docker资源
docker-compose down
```

## 🐛 故障排除

### 本地Firefox崩溃
```bash
# 1. 重新安装Playwright
pip3 install --upgrade playwright
python3 -m playwright install firefox

# 2. 清理缓存
rm -rf ~/Library/Caches/ms-playwright

# 3. 重新测试
python3 -m pytest tests/ui/test_pds_from_excel.py::test_pds_ui_case_from_excel -v
```

### Chromium在macOS上无法启动
- 这是已知的Playwright macOS兼容性问题
- **解决方案**: 在Docker中运行Chromium
- **本地调试**: 使用Firefox替代

### Docker构建失败
```bash
# 清理旧镜像重新构建
docker-compose build --no-cache

# 使用特定基础镜像
docker-compose up --build
```

## 🎯 最佳实践

### 本地开发
```bash
# 推荐流程
1. 使用Firefox进行开发和调试
BROWSER_TYPE=firefox python3 -m pytest -v -x

# 测试页面结构
BROWSER_TYPE=firebase python3 get_page_structure.py
```

### CI/CD流程
```bash
# Docker中运行所有浏览器进行完整测试
docker-compose up ai_test_framework_firefox
docker-compose up ai_test_framework_chromium
docker-compose up ai_test_framework_webkit
```

### 跨平台测试
```bash
# macOS: Firefox + Docker Chromium
BROWSER_TYPE=firefox python3 -m pytest
docker-compose up ai_test_framework_chromium

# Linux: Chromium + Firefox
BROWSER_TYPE=chromium python3 -m pytest
BROWSER_TYPE=firefox python3 -m pytest
```

## 📊 性能对比

| 指标 | Firefox | Chromium | WebKit |
|------|---------|----------|--------|
| macOS启动时间 | 2-3s | ❌ 崩溃 | 2-3s |
| Docker启动时间 | 3-4s | 3-4s | 3-4s |
| 页面加载速度 | 快 | 快 | 中等 |
| 内存占用 | 低 | 高 | 中等 |

---

**最后更新**: 2026-03-22  
**推荐配置**: Firefox（本地）+ Chromium（Docker CI/CD）
