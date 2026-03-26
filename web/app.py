import os, json, subprocess, threading, secrets, string
from functools import wraps
from flask import Flask, render_template, request, redirect, url_for, session
from flask_socketio import SocketIO, emit

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INV_FILE = os.path.join(BASE_DIR, "inventory.txt")
USER_FILE = os.path.join(BASE_DIR, "users.txt")
CONFIG_FILE = os.path.join(BASE_DIR, "config", "web_config.json")

app = Flask(__name__)
app.secret_key = os.urandom(32)
socketio = SocketIO(app, async_mode="eventlet")

# ---------------------------
# 工具函数
# ---------------------------

def gen_random_string(length=12):
    chars = string.ascii_letters + string.digits
    return ''.join(secrets.choice(chars) for _ in range(length))

def load_config():
    if not os.path.exists(CONFIG_FILE):
        return {}
    with open(CONFIG_FILE) as f:
        return json.load(f)

def save_config(cfg):
    os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
    with open(CONFIG_FILE, "w") as f:
        json.dump(cfg, f, indent=2)

def read_inventory():
    nodes = []
    if not os.path.exists(INV_FILE):
        return nodes
    with open(INV_FILE) as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            name, ip, ssh_port, ss_port = line.split()
            nodes.append({"name": name, "ip": ip, "ssh_port": ssh_port, "ss_port": ss_port})
    return nodes

def read_users():
    users = []
    if not os.path.exists(USER_FILE):
        return users
    with open(USER_FILE) as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            name, password = line.split()
            users.append({"name": name, "password": password})
    return users

# ---------------------------
# 登录保护
# ---------------------------

def is_logged_in():
    return session.get("logged_in") is True

def login_required(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        cfg = load_config()

        # 未初始化 → 跳 setup
        if "ADMIN_USER" not in cfg or "ADMIN_PASSWORD" not in cfg:
            return redirect(url_for("setup"))

        # 未登录 → 跳 login
        if not is_logged_in():
            return redirect(url_for("login"))

        return f(*args, **kwargs)
    return wrapper

# ---------------------------
# 首次初始化（自动生成账号密码）
# ---------------------------

@app.route("/setup")
def setup():
    cfg = load_config()

    # 已初始化 → 跳登录
    if "ADMIN_USER" in cfg and "ADMIN_PASSWORD" in cfg:
        return redirect(url_for("login"))

    # 自动生成账号密码
    admin_user = gen_random_string(8)
    admin_pass = gen_random_string(16)

    cfg["ADMIN_USER"] = admin_user
    cfg["ADMIN_PASSWORD"] = admin_pass
    save_config(cfg)

    # 显示一次性账号密码
    return render_template("setup_show_credentials.html",
                           user=admin_user,
                           password=admin_pass)

# ---------------------------
# 登录 / 登出
# ---------------------------

@app.route("/login", methods=["GET", "POST"])
def login():
    cfg = load_config()

    if "ADMIN_USER" not in cfg or "ADMIN_PASSWORD" not in cfg:
        return redirect(url_for("setup"))

    if request.method == "POST":
        user = request.form["username"]
        pwd = request.form["password"]

        if user == cfg["ADMIN_USER"] and pwd == cfg["ADMIN_PASSWORD"]:
            session["logged_in"] = True
            return redirect(url_for("index"))

        return "账号或密码错误"

    return render_template("login.html")

@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))

# ---------------------------
# 页面路由
# ---------------------------

@app.route("/")
@login_required
def index():
    return render_template("index.html")

@app.route("/nodes")
@login_required
def nodes():
    return render_template("nodes.html", nodes=read_inventory())

@app.route("/users")
@login_required
def users():
    return render_template("users.html", users=read_users())

@app.route("/edit-users", methods=["GET", "POST"])
@login_required
def edit_users():
    if request.method == "POST":
        content = request.form["content"]
        with open(USER_FILE, "w") as f:
            f.write(content)
        subprocess.call([os.path.join(BASE_DIR, "panel.sh"), "sync-users"])
        return redirect(url_for("users"))

    content = ""
    if os.path.exists(USER_FILE):
        with open(USER_FILE) as f:
            content = f.read()

    return render_template("edit_users.html", content=content)

@app.route("/deploy/<node>")
@login_required
def deploy(node):
    subprocess.call([os.path.join(BASE_DIR, "panel.sh"), "deploy", node])
    return redirect(url_for("nodes"))

@app.route("/restart/<node>")
@login_required
def restart(node):
    subprocess.call([os.path.join(BASE_DIR, "panel.sh"), "restart", node])
    return redirect(url_for("nodes"))

@app.route("/sync-users")
@login_required
def sync_users():
    subprocess.call([os.path.join(BASE_DIR, "panel.sh"), "sync-users"])
    return redirect(url_for("users"))

@app.route("/links/<user>")
@login_required
def links(user):
    out = subprocess.check_output([os.path.join(BASE_DIR, "panel.sh"), "user-links", user]).decode()
    return f"<pre>{out}</pre>"

# ---------------------------
# WebSocket 实时日志
# ---------------------------

@app.route("/realtime-monitor")
@login_required
def realtime_monitor():
    return render_template("realtime_monitor.html")

def run_monitor_and_stream():
    proc = subprocess.Popen([os.path.join(BASE_DIR, "monitor.sh")],
                            stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT,
                            text=True)
    for line in proc.stdout:
        socketio.emit("log", {"line": line.rstrip()})

@socketio.on("start_monitor")
def handle_start_monitor():
    threading.Thread(target=run_monitor_and_stream, daemon=True).start()

# ---------------------------
# 启动
# ---------------------------

if __name__ == "__main__":
    socketio.run(app, host="0.0.0.0", port=8080)
