#!/bin/bash

INV_FILE="inventory.txt"
USER_FILE="users.txt"
TPL_FILE="templates/ss2022-multiuser.json.tpl"
REMOTE_CONF="/etc/sing-box/config.json"
REMOTE_BIN="/usr/local/bin/sing-box"
SERVICE_NAME="sing-box"
GIT_DIR="repo"

usage() {
  echo "用法:"
  echo "  $0 list"
  echo "  $0 deploy-all"
  echo "  $0 deploy <node>"
  echo "  $0 restart <node|all>"
  echo "  $0 status <node|all>"
  echo "  $0 link <node>"
  echo "  $0 user-links <user>"
  echo "  $0 sync-users"
  echo "  $0 menu"
  exit 1
}

list_nodes() {
  awk '!/^#/ && NF {printf "%-15s %-15s ssh:%-5s ss:%-5s\n",$1,$2,$3,$4}' "$INV_FILE"
}

gen_user_block() {
  awk '!/^#/ && NF {printf "        {\"name\":\"%s\",\"password\":\"%s\"},\n",$1,$2}' "$USER_FILE" |
  sed '$ s/,$//'
}

gen_config() {
  local port="$1"
  local user_block
  user_block=$(gen_user_block)
  sed "s/__SS_PORT__/$port/g; s#__USER_BLOCK__#$user_block#g" "$TPL_FILE"
}

deploy_node() {
  local name="$1" ip="$2" ssh_port="$3" ss_port="$4"
  echo ">>> [$name] 部署 SS2022 ($ip:$ss_port)"
  ssh -p "$ssh_port" root@"$ip" "command -v sing-box >/dev/null 2>&1 || (curl -fsSL https://sing-box.app/install.sh | bash)"
  gen_config "$ss_port" | ssh -p "$ssh_port" root@"$ip" "mkdir -p /etc/sing-box && cat > $REMOTE_CONF"
  ssh -p "$ssh_port" root@"$ip" "cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=sing-box service
After=network.target

[Service]
ExecStart=$REMOTE_BIN run -c $REMOTE_CONF
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}
systemctl restart ${SERVICE_NAME}
"
  echo ">>> [$name] 部署完成"
  save_git_version "$name"
}

deploy_all() {
  awk '!/^#/ && NF {print $1,$2,$3,$4}' "$INV_FILE" | while read -r name ip ssh_port ss_port; do
    deploy_node "$name" "$ip" "$ssh_port" "$ss_port"
  done
}

restart_node() {
  local name="$1" ip="$2" ssh_port="$3"
  echo ">>> [$name] 重启服务"
  ssh -p "$ssh_port" root@"$ip" "systemctl restart ${SERVICE_NAME}"
}

status_node() {
  local name="$1" ip="$2" ssh_port="$3"
  echo ">>> [$name] 状态："
  ssh -p "$ssh_port" root@"$ip" "systemctl is-active ${SERVICE_NAME} || echo 'not running'"
}

save_git_version() {
  local name="$1"
  mkdir -p "$GIT_DIR/$name"
  gen_config "60001" > "$GIT_DIR/$name/config.json"
  if [ -d "$GIT_DIR/.git" ]; then
    cd "$GIT_DIR"
    git add .
    git commit -m "Update config for $name" >/dev/null 2>&1 || true
    git push >/dev/null 2>&1 || true
    cd ..
  fi
}

find_node() {
  awk -v target="$1" '!/^#/ && $1==target {print $1,$2,$3,$4}' "$INV_FILE"
}

gen_links_for_node() {
  local name="$1" ip="$2" ssh_port="$3" ss_port="$4"
  echo ">>> [$name] 客户端链接："
  awk '!/^#/ && NF {print $1,$2}' "$USER_FILE" | while read -r user pass; do
    local plain="2022-blake3-aes-256-gcm:${pass}@${ip}:${ss_port}"
    local b64
    b64=$(printf '%s' "$plain" | base64 -w0 2>/dev/null || printf '%s' "$plain" | base64)
    echo "${user}: ss://${b64}#${name}-${user}"
  done
}

gen_links_for_user() {
  local target_user="$1"
  local password
  password=$(awk -v u="$target_user" '$1==u {print $2}' "$USER_FILE")
  [ -z "$password" ] && echo "用户不存在：$target_user" && return
  echo ">>> 用户 $target_user 的所有节点链接："
  awk '!/^#/ && NF {print $1,$2,$3,$4}' "$INV_FILE" | while read -r name ip ssh_port ss_port; do
    local plain="2022-blake3-aes-256-gcm:${password}@${ip}:${ss_port}"
    local b64
    b64=$(printf '%s' "$plain" | base64 -w0 2>/dev/null || printf '%s' "$plain" | base64)
    echo "$name: ss://${b64}#$target_user-$name"
  done
}

sync_users() {
  echo ">>> 开始同步 users.txt 到所有节点..."
  awk '!/^#/ && NF {print $1,$2,$3,$4}' "$INV_FILE" | while read -r name ip ssh_port ss_port; do
    echo ">>> [$name] 同步用户配置..."
    gen_config "$ss_port" | ssh -p "$ssh_port" root@"$ip" "cat > $REMOTE_CONF"
    ssh -p "$ssh_port" root@"$ip" "systemctl restart ${SERVICE_NAME}"
    echo ">>> [$name] 完成"
  done
  echo ">>> 所有节点同步完成！"
}

require_whiptail() {
  command -v whiptail >/dev/null 2>&1 || { echo "whiptail 未安装：apt install whiptail -y"; exit 1; }
}

menu_select_node() {
  local nodes=()
  while read -r name ip ssh_port ss_port; do
    [ -z "$name" ] && continue
    nodes+=("$name" "$ip:$ss_port" "OFF")
  done < <(awk '!/^#/ && NF {print $1,$2,$3,$4}' "$INV_FILE")
  whiptail --title "选择节点" --radiolist "请选择一个节点：" 20 70 10 "${nodes[@]}" 3>&1 1>&2 2>&3
}

edit_users() {
  local TMP
  TMP=$(mktemp)
  cp "$USER_FILE" "$TMP"
  if whiptail --title "编辑 users.txt" --textbox "$TMP" --scrolltext --editable 25 70; then
    cp "$TMP" "$USER_FILE"
  else
    nano "$USER_FILE"
  fi
  rm -f "$TMP"
}

run_menu() {
  require_whiptail
  while true; do
    CHOICE=$(whiptail --title "SS2022 面板" --menu "请选择操作：" 20 70 14 \
      "1" "列出所有节点" \
      "2" "部署所有节点" \
      "3" "部署单个节点" \
      "4" "重启单个节点" \
      "5" "查看单个节点状态" \
      "6" "查看单个节点客户端链接" \
      "7" "查看某用户的所有节点链接" \
      "8" "编辑 users.txt" \
      "9" "同步 users.txt 到所有节点" \
      "10" "立即执行节点监控" \
      "0" "退出" \
      3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && break
    case "$CHOICE" in
      1) list_nodes | whiptail --title "节点列表" --textbox /dev/stdin 20 70 ;;
      2) deploy_all | whiptail --title "部署所有节点" --textbox /dev/stdin 20 70 ;;
      3)
        node=$(menu_select_node); [ -z "$node" ] && continue
        info=$(find_node "$node")
        deploy_node $info | whiptail --title "部署节点 $node" --textbox /dev/stdin 20 70
        ;;
      4)
        node=$(menu_select_node); [ -z "$node" ] && continue
        info=$(awk -v target="$node" '!/^#/ && $1==target {print $1,$2,$3}' "$INV_FILE")
        restart_node $info | whiptail --title "重启节点 $node" --textbox /dev/stdin 20 70
        ;;
      5)
        node=$(menu_select_node); [ -z "$node" ] && continue
        info=$(awk -v target="$node" '!/^#/ && $1==target {print $1,$2,$3}' "$INV_FILE")
        status_node $info | whiptail --title "状态：$node" --textbox /dev/stdin 20 70
        ;;
      6)
        node=$(menu_select_node); [ -z "$node" ] && continue
        info=$(find_node "$node")
        gen_links_for_node $info | whiptail --title "客户端链接：$node" --textbox /dev/stdin 20 70
        ;;
      7)
        USER=$(whiptail --inputbox "输入用户名：" 10 60 3>&1 1>&2 2>&3)
        [ -z "$USER" ] && continue
        gen_links_for_user "$USER" | whiptail --title "用户 $USER 的所有节点链接" --textbox /dev/stdin 25 70
        ;;
      8) edit_users ;;
      9) sync_users | whiptail --title "同步用户配置" --textbox /dev/stdin 25 70 ;;
      10) ./monitor.sh | whiptail --title "节点监控结果" --textbox /dev/stdin 25 70 ;;
      0) break ;;
    esac
  done
}

case "$1" in
  list) list_nodes ;;
  deploy-all) deploy_all ;;
  deploy)
    node=$(find_node "$2"); [ -z "$node" ] && echo "节点不存在" && exit 1
    deploy_node $node
    ;;
  restart)
    if [ "$2" = "all" ]; then
      awk '!/^#/ && NF {print $1,$2,$3}' "$INV_FILE" | while read -r name ip ssh_port; do
        restart_node "$name" "$ip" "$ssh_port"
      done
    else
      node=$(find_node "$2"); restart_node $node
    fi
    ;;
  status)
    if [ "$2" = "all" ]; then
      awk '!/^#/ && NF {print $1,$2,$3}' "$INV_FILE" | while read -r name ip ssh_port; do
        status_node "$name" "$ip" "$ssh_port"
      done
    else
      node=$(find_node "$2"); status_node $node
    fi
    ;;
  link)
    node=$(find_node "$2"); [ -z "$node" ] && echo "节点不存在" && exit 1
    gen_links_for_node $node
    ;;
  user-links)
    gen_links_for_user "$2"
    ;;
  sync-users)
    sync_users
    ;;
  menu)
    run_menu
    ;;
  *)
    usage ;;
esac
