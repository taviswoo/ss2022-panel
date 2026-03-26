# SS2022 Panel — Multi‑Node SS2022 Management Platform  
A lightweight, production‑ready, fully script‑driven SS2022 multi‑node management platform with:

- ✔ CLI 面板  
- ✔ TUI 图形菜单  
- ✔ Web Dashboard（登录、配置、操作）  
- ✔ 多节点批量部署  
- ✔ 多用户（单端口多密码）  
- ✔ 自动同步 users.txt  
- ✔ 节点监控 + Telegram Bot 报警  
- ✔ WebSocket 实时日志  
- ✔ Docker 一键部署  

本项目适合需要 **高可控性、自动化、多节点管理、无数据库、无前端框架** 的专业用户。

---

## ✨ 功能特性

### 🖥️ Web Dashboard
- 登录系统（Session + Cookie）
- 首次启动自动要求填写敏感信息（Bot Token、Chat ID、管理密码）
- 节点列表、用户列表、编辑 users.txt
- 一键部署、重启、同步用户
- WebSocket 实时日志（实时查看 monitor 输出）

### 🧰 CLI 面板（panel.sh）
- 一键部署所有节点
- 单节点部署
- 重启、状态检查
- 多用户 SS2022 配置生成
- 自动生成客户端链接（节点/用户）
- 自动同步 users.txt 到所有节点
- Git 配置版本管理（可选）

### 📟 TUI 面板（whiptail）
- 图形化菜单操作
- 编辑 users.txt
- 查看节点状态、链接
- 同步用户
- 调用监控脚本

### 📡 节点监控（monitor.sh）
- SSH 可达性检测
- SS2022 端口检测
- Telegram Bot 自动报警

### 🐳 Docker 一键部署
- 内置 Dockerfile + docker-compose.yml
- 轻量、可移植、可快速部署

---

## 📁 项目结构

