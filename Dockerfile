FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-dev \
    curl \
    wget \
    gnupg \
    libc6-dev \
    libnss3 \
    libx11-6 \
    libxkbfile1 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcairo2 \
    libdbus-1-3 \
    libgtk-3-0 \
    libdrm2 \
    libxcomposite1 \
    libxrandr2 \
    libasound2 \
    libpangocairo-1.0-0 \
    libxss1 \
    xvfb \
    fonts-liberation \
    libappindicator3-1 \
    libxkbcommon0 \
    xdg-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt ./
RUN pip3 install --no-cache-dir -r requirements.txt
RUN pip3 install playwright

# 安装所有支持的浏览器引擎
RUN playwright install chromium firefox webkit

# 复制应用代码
COPY . .

# 设置入口点
ENTRYPOINT ["python3", "-m", "pytest"]
CMD ["tests/ui/test_pds_from_excel.py", "--tb=short", "-v"]

COPY . .

ENV BASE_URL=https://test-aicc.airudder.com
ENV TEST_USER=testsuperadmin
ENV TEST_PASSWORD=Passw0rd!1234
ENV LLM_PROVIDER=openai
ENV OPENAI_API_KEY=fakekey123

# 入口用于执行指定的pytest命令
ENTRYPOINT ["pytest"]
CMD ["-q"]
