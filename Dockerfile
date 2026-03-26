FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    openssh-client \
    jq \
    whiptail \
    && rm -rf /var/lib/apt/lists/*

COPY . /app

RUN pip install --no-cache-dir flask flask-socketio eventlet

EXPOSE 8080

CMD ["python", "web/app.py"]
