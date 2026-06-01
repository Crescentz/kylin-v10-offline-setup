#!/bin/bash
# ============================================================
# 麒麟 V10 一键离线安装脚本 v2.0
# 环境: CUDA 12.4 + NVIDIA驱动 550.54.14 + Docker GPU
# ============================================================

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="/tmp/kylin_install_$(date +%Y%m%d_%H%M%S).log"

echo "=========================================="
echo "  麒麟 V10 一键离线安装脚本 v2.0"
echo "  日志文件: $LOG_FILE"
echo "=========================================="

# ========== 检查 root ==========
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 请使用 root 用户运行: sudo bash $0"
    exit 1
fi

# ========== 1. 安装开发工具 ==========
echo ""
echo "======= [1/4] 安装开发工具 (gcc/g++/make/vim/curl) ======="
RPM_DIR="$BASE_DIR/03-开发工具"
if [ -d "$RPM_DIR" ] && ls "$RPM_DIR"/*.rpm &>/dev/null; then
    cd "$RPM_DIR"
    rpm -ivh *.rpm --force --nodeps --nogpgcheck 2>&1 | tee -a "$LOG_FILE"
    echo "✅ 开发工具安装完成"
fi

echo ">> 验证:"
for cmd in gcc g++ make vim curl; do
    if command -v "$cmd" &>/dev/null; then
        echo "   $($cmd --version 2>&1 | head -1)"
    else
        echo "   ⚠️  $cmd 未安装"
    fi
done

# ========== 2. 安装 Docker ==========
echo ""
echo "======= [2/4] 安装 Docker + GPU支持 ======="
DOCKER_DIR="$BASE_DIR/02-Docker"
DOCKER_TGZ="$DOCKER_DIR/docker-29.5.2.tgz"
DOCKER_COMPOSE="$DOCKER_DIR/docker-compose-linux-x86_64"

if [ -f "$DOCKER_TGZ" ]; then
    tar -xzf "$DOCKER_TGZ" -C "$DOCKER_DIR"
    /bin/cp -f "$DOCKER_DIR/docker/"* /usr/bin/

    # 创建 systemd 服务
    cat > /etc/systemd/system/docker.service << 'SERVICEFILE'
[Unit]
Description=Docker Application Container Engine
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/dockerd
ExecReload=/bin/kill -s HUP $MAINPID
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TimeoutStartSec=0
Delegate=yes
KillMode=process
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s

[Install]
WantedBy=multi-user.target
SERVICEFILE
    
    systemctl daemon-reload
    systemctl start docker 2>/dev/null || echo "   ⚠️ Docker启动失败"
    systemctl enable docker 2>/dev/null || true
    echo "✅ Docker 安装完成"
fi

# Docker Compose
if [ -f "$DOCKER_COMPOSE" ]; then
    /bin/cp -f "$DOCKER_COMPOSE" /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo "✅ Docker Compose 安装完成"
fi

# ========== 3. 安装 nvidia-container-toolkit (Docker GPU) ==========
echo ""
echo "======= [3/4] 安装 nvidia-container-toolkit (Docker GPU) ======="
GPU_DIR="$BASE_DIR/06-Docker-GPU"
if [ -d "$GPU_DIR" ] && ls "$GPU_DIR"/*.rpm &>/dev/null; then
    cd "$GPU_DIR"
    rpm -ivh *.rpm --force --nodeps --nogpgcheck 2>&1 | tee -a "$LOG_FILE"
    echo "✅ nvidia-container-toolkit 安装完成"
    
    # 配置 Docker 使用 NVIDIA runtime
    nvidia-ctk runtime configure --runtime=docker 2>/dev/null || true
    systemctl restart docker 2>/dev/null || true
    echo "✅ Docker GPU runtime 已配置"
else
    echo "⚠️  未找到 nvidia-container-toolkit RPM包"
    echo "   请从以下地址下载后放入 06-Docker-GPU/ 目录:"
    echo "   https://nvidia.github.io/libnvidia-container/stable/rpm/el8/x86_64/"
fi

# ========== 4. CUDA 12.4 + NVIDIA 驱动 ==========
echo ""
echo "======= [4/4] 安装 CUDA 12.4 + NVIDIA 驱动 550.54.14 ======="
CUDA_RUN="$BASE_DIR/01-CUDA/cuda_12.4.0_550.54.14_linux.run"
NV_DRIVER="$BASE_DIR/01-CUDA/NVIDIA-Linux-x86_64-550.54.14.run"

echo "╔══════════════════════════════════════════════════╗"
echo "║  安装 CUDA 12.4 + NVIDIA 驱动                    ║"
echo "║                                                  ║"
echo "║  【方案A】用 CUDA runfile 安装（含驱动550.54.14）  ║"
echo "║    sh cuda_12.4.0_550.54.14_linux.run --silent   ║"
echo "║                                                  ║"
echo "║  【方案B】分别安装:                               ║"
echo "║    ① 先装驱动: sh NVIDIA-Linux-550.54.14.run     ║"
echo "║    ② 再装CUDA: sh cuda_12.4.0_linux.run --silent ║"
echo "║                    --toolkit --no-opengl-files    ║"
echo "╚══════════════════════════════════════════════════╝"

if [ -f "$CUDA_RUN" ]; then
    echo ""
    echo "  检测到 CUDA 安装文件 ($(ls -lh "$CUDA_RUN" | awk '{print $5}'))"
    echo "  是否安装？[y/s/t/n]"
    echo "    y = 交互安装  s = 静默全部  t = 静默仅CUDA  n = 跳过"
    read -r choice
    chmod +x "$CUDA_RUN"
    case "${choice:-y}" in
        s|S) sh "$CUDA_RUN" --silent 2>&1 | tee -a "$LOG_FILE" ;;
        t|T) sh "$CUDA_RUN" --silent --toolkit --no-opengl-files 2>&1 | tee -a "$LOG_FILE" ;;
        y|Y|*) sh "$CUDA_RUN" 2>&1 | tee -a "$LOG_FILE" ;;
    esac
    
    # 环境变量
    cat > /etc/profile.d/cuda.sh << 'EOF'
export PATH=/usr/local/cuda-12.4/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-12.4/lib64:$LD_LIBRARY_PATH
EOF
    chmod +x /etc/profile.d/cuda.sh
    echo "✅ CUDA 环境变量已配置: source /etc/profile.d/cuda.sh"
fi

if [ -f "$NV_DRIVER" ]; then
    echo ""
    echo "  检测到独立 NVIDIA 驱动: $(ls -lh "$NV_DRIVER" | awk '{print $5}')"
    echo "  是否安装？[y/n]"
    read -r ans2
    if [ "${ans2:-n}" = "y" ] || [ "${ans2:-n}" = "Y" ]; then
        chmod +x "$NV_DRIVER"
        sh "$NV_DRIVER" 2>&1 | tee -a "$LOG_FILE"
    fi
fi

# ========== 验证 ==========
echo ""
echo "=========================================="
echo "  安装完成！运行验证命令："
echo "=========================================="
echo ""
echo "  nvidia-smi          # 查看驱动 + GPU"
echo "  nvcc --version      # 查看 CUDA 版本"
echo "  docker --version    # 查看 Docker 版本"
echo "  docker run --gpus all nvidia/cuda:12.4.0-base nvidia-smi"
echo "                      # 验证 Docker GPU 可用"
echo ""
echo "日志: $LOG_FILE"
