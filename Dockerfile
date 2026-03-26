FROM python:3.11-slim

WORKDIR /app

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    openssh-client \
    jq \
    whiptail \
    && rm -rf /var/lib/apt/lists/*

# 拷贝项目文件
COPY . /app

# 安装 Python 依赖
RUN pip install --no-cache-dir flask flask-socketio eventlet

EXPOSE 8080

CMD ["python", "web/app.py"]
