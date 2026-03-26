#!/bin/bash

INV_FILE="inventory.txt"
CONFIG_FILE="config/web_config.json"

load_cfg() {
  if [ -f "$CONFIG_FILE" ]; then
    BOT_TOKEN=$(jq -r '.BOT_TOKEN // empty' "$CONFIG_FILE")
    CHAT_ID=$(jq -r '.CHAT_ID // empty' "$CONFIG_FILE")
  fi
}

tg_send() {
  [ -z "$BOT_TOKEN" ] && return
  [ -z "$CHAT_ID" ] && return
  local msg="$1"
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d text="$msg" >/dev/null
}

check_node() {
  local name="$1" ip="$2" ssh_port="$3" ss_port="$4"
  timeout 3 bash -c "cat < /dev/null > /dev/tcp/${ip}/${ssh_port}" 2>/dev/null
  if [ $? -ne 0 ]; then
    echo "[$name] SSH 不可达"
    tg_send "⚠️ 节点离线：$name ($ip) SSH 不可达"
    return
  fi
  timeout 3 bash -c "cat < /dev/null > /dev/tcp/${ip}/${ss_port}" 2>/dev/null
  if [ $? -ne 0 ]; then
    echo "[$name] SS2022 端口关闭"
    tg_send "⚠️ 节点异常：$name ($ip) SS2022 端口关闭"
    return
  fi
  echo "[$name] 正常"
}

load_cfg

awk '!/^#/ && NF {print $1,$2,$3,$4}' "$INV_FILE" | while read -r name ip ssh_port ss_port; do
  check_node "$name" "$ip" "$ssh_port" "$ss_port"
done
