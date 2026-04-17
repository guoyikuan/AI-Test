# 🌐 浏览器配置快速指南

## 概述

本框架已配置支持 **Firefox**、**Chromium** 和 **WebKit** 三种浏览器引擎，解决了 macOS Playwright 兼容性问题。

## ⚡ 快速开始

### 本地运行（推荐Firefox）

```bash
# Firefox（默认，最佳macOS兼容性）
python3 -m pytest tests/ui/test_pds_from_excel.py -v

# 或指定Firefox
BROWSER_TYPE=firefox python3 -m pytest tests/ui/test_pds_from_excel.py -v
```

### Docker运行（支持所有浏览器）

```bash
# Firefox
docker-compose up ai_test_framework

# Chromium
docker-compose up ai_test_framework_chromium

# WebKit
docker-compose up ai_test_framework_webkit
```

## 📊 浏览器支持矩阵

| 环境 | Firefox | Chromium | WebKit |
|------|---------|----------|--------|
| **macOS本地** | ✅ | ❌* | ⚠️ |
| **Docker** | ✅ | ✅ | ✅ |

> *Chromium在macOS本地存在兼容性问题，推荐在Docker中运行

## 🔧 环境变量

```bash
# 指定浏览器
BROWSER_TYPE=firefox           # firefox, chromium, webkit
HEADLESS=true                  # true/false，默认true
SLOW_MO=100                    # 减速（毫秒），调试时使用
```

## 📝 典型用途

| 用途 | 推荐配置 | 命令 |
|------|---------|------|
| 本地开发 | Firefox + headless | `BROWSER_TYPE=firefox pytest` |
| 本地调试 | Firefox + 不headless | `BROWSER_TYPE=firefox HEADLESS=false pytest` |
| CI/CD Firefox | Docker Firefox | `docker-compose up ai_test_framework` |
| CI/CD Chromium | Docker Chromium | `docker-compose up ai_test_framework_chromium` |
| 跨浏览器测试 | 三个Docker服务 | 依次运行三个服务 |

## 🎯 推荐配置

### 本地开发（macOS）
```bash
BROWSER_TYPE=firefox python3 -m pytest tests/ui/test_pds_from_excel.py -v -x
```

### CI/CD流程（Docker）
```bash
# 顺序运行所有浏览器
docker-compose up ai_test_framework_firefox &&
docker-compose up ai_test_framework_chromium &&
docker-compose up ai_test_framework_webkit
```

---

详见 [BROWSER_COMPATIBILITY.md](BROWSER_COMPATIBILITY.md) 了解完整文档和故障排除。
