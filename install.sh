#!/bin/bash
# Universal Website Monitor Installer

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
NC='\033[0m'

# 检测root权限
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用sudo运行此脚本${NC}"
    exit 1
fi

# 用户输入配置
read -p "请输入需要监控的完整URL (示例: https://example.com/path): " target_url
while [ -z "$target_url" ]; do
    echo -e "${RED}错误：监控URL不能为空${NC}"
    read -p "请输入需要监控的完整URL (示例: https://example.com/path): " target_url
done

while true; do
    read -p "请输入服务监听端口 (默认: 1234): " monitor_port
    monitor_port=${monitor_port:-1234}
    
    # 验证端口合法性
    if [[ $monitor_port =~ ^[0-9]+$ ]] && [ $monitor_port -ge 1 ] && [ $monitor_port -le 65535 ]; then
        break
    else
        echo -e "${RED}错误：端口必须为1-65535之间的数字${NC}"
    fi
done

# 安装目录配置
INSTALL_DIR="/opt/web-monitor"
SERVICE_FILE="/etc/systemd/system/web-monitor.service"

# 创建安装目录
mkdir -p $INSTALL_DIR || { echo -e "${RED}目录创建失败${NC}"; exit 1; }

# 生成监控脚本
cat > $INSTALL_DIR/website_monitor.py << EOF
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import requests
import threading
import time

current_status = "{Nothing Changed}"
last_hash = None
timer = None

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(current_status.encode())

def revert_status():
    global current_status
    current_status = "{Nothing Changed}"
    print(f"[{time.ctime()}] Status reverted to normal")

def check_update():
    global last_hash, current_status, timer
    
    try:
        response = requests.get(
            '${target_url}',
            headers={'User-Agent': 'Mozilla/5.0'},
            timeout=10
        )
        current_content = response.content
        
        current_hash = hashlib.md5(current_content).hexdigest()
        
        if not last_hash:
            last_hash = current_hash
            print(f"[{time.ctime()}] Initial hash recorded")
            return

        if current_hash != last_hash:
            print(f"[{time.ctime()}] Change detected!")
            current_status = "{Something Changed}"
            
            if timer and timer.is_alive():
                timer.cancel()
            
            timer = threading.Timer(60, revert_status)
            timer.start()
            
            last_hash = current_hash

    except Exception as e:
        print(f"[{time.ctime()}] Error during check: {str(e)}")

def monitoring_loop():
    while True:
        check_update()
        time.sleep(10)

if __name__ == '__main__':
    check_update()
    
    monitor_thread = threading.Thread(target=monitoring_loop)
    monitor_thread.daemon = True
    monitor_thread.start()
    
    server = HTTPServer(('', ${monitor_port}), RequestHandler)
    print(f"[{time.ctime()}] Server started on port ${monitor_port}")
    server.serve_forever()
EOF

# 生成系统服务文件
cat > $SERVICE_FILE << EOF
[Unit]
Description=Website Change Monitor
After=network.target

[Service]
User=root
ExecStart=/usr/bin/python3 $INSTALL_DIR/website_monitor.py
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

# 安装依赖
echo -e "${BLUE}安装系统依赖...${NC}"
apt update -qq && apt install -y python3 python3-pip firewalld
pip3 install requests

# 配置防火墙
echo -e "${BLUE}配置防火墙...${NC}"
if ! command -v ufw &> /dev/null; then
    apt install -y ufw
fi

ufw allow $monitor_port/tcp
ufw --force enable

# 启动服务
echo -e "${BLUE}启动监控服务...${NC}"
systemctl daemon-reload
systemctl enable --now web-monitor

# 验证输出
echo -e "\n${GREEN}安装完成！${NC}"
echo -e "监控目标：${YELLOW}[用户自定义URL]${NC}"
echo -e "监听端口：${YELLOW}${monitor_port}${NC}"
echo -e "\n服务状态检查：${YELLOW}systemctl status web-monitor${NC}"
echo -e "访问测试命令：${YELLOW}curl http://localhost:${monitor_port}${NC}"
echo -e "防火墙状态检查：${YELLOW}ufw status numbered${NC}"