#!/bin/bash
# ============================================================
# 麒麟 V10 一键离线安装脚本
# 使用方法：sudo bash install_all.sh
# 说明：自动安装开发工具 + Docker，辅助安装 CUDA
# ============================================================

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="/tmp/kylin_install_$(date +%Y%m%d_%H%M%S).log"

echo "=========================================="
echo "  麒麟 V10 一键离线安装脚本"
echo "  日志文件: $LOG_FILE"
echo "=========================================="

# ========== 第1步：检查 root 权限 ==========
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 请使用 root 用户运行: sudo bash $0"
    exit 1
fi

# ========== 第2步：安装开发工具 ==========
echo ""
echo "======= [1/3] 安装开发工具 (gcc/g++/make/vim/curl) ======="
RPM_DIR="$BASE_DIR/03-开发工具"
if [ -d "$RPM_DIR" ] && ls "$RPM_DIR"/*.rpm &>/dev/null; then
    echo ">> 安装RPM包中..."
    cd "$RPM_DIR"
    rpm -ivh *.rpm --force --nodeps --nogpgcheck 2>&1 | tee -a "$LOG_FILE"
    echo "✅ 开发工具安装完成"
else
    echo "⚠️  未找到RPM包目录，跳过开发工具安装"
fi

# 验证（忽略失败，继续执行）
echo ""
echo ">> 验证开发工具:"
for cmd in gcc g++ make vim curl; do
    if command -v "$cmd" &>/dev/null; then
        echo "   $($cmd --version 2>&1 | head -1)"
    else
        echo "   ⚠️  $cmd 未安装"
    fi
done

# ========== 第3步：安装 Docker ==========
echo ""
echo "======= [2/3] 安装 Docker ======="
DOCKER_DIR="$BASE_DIR/02-Docker"
DOCKER_TGZ="$DOCKER_DIR/docker-29.5.2.tgz"
DOCKER_COMPOSE="$DOCKER_DIR/docker-compose-linux-x86_64"

if [ -f "$DOCKER_TGZ" ]; then
    echo ">> 解压 Docker 二进制包..."
    tar -xzf "$DOCKER_TGZ" -C "$DOCKER_DIR"
    
    echo ">> 复制 Docker 到 /usr/bin/..."
    /bin/cp -f "$DOCKER_DIR/docker/"* /usr/bin/
    
    echo ">> 创建 Docker systemd 服务..."
    cat > /etc/systemd/system/docker.service << 'SERVICEFILE'
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
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
    systemctl start docker 2>/dev/null || echo "   ⚠️ Docker启动失败，可稍后手动排查"
    systemctl enable docker 2>/dev/null || true
    echo "✅ Docker 安装完成"
else
    echo "⚠️  未找到Docker安装包，跳过Docker安装"
fi

# 安装 Docker Compose
if [ -f "$DOCKER_COMPOSE" ]; then
    echo ">> 安装 Docker Compose..."
    /bin/cp -f "$DOCKER_COMPOSE" /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo "✅ Docker Compose 安装完成"
fi

# 验证 Docker
echo ""
echo ">> 验证 Docker:"
if command -v docker &>/dev/null; then
    docker --version 2>&1
else
    echo "   ⚠️ docker 命令未安装"
fi
if command -v docker-compose &>/dev/null; then
    docker-compose --version 2>&1
else
    echo "   ⚠️ docker-compose 未安装"
fi

# ========== 第4步：安装 CUDA 11.8（提示用户手动操作）==========
echo ""
echo "======= [3/3] CUDA 11.8 安装 ======="
CUDA_RUN="$BASE_DIR/01-CUDA/cuda_11.8.0_520.61.05_linux.run"

if [ -f "$CUDA_RUN" ]; then
    CUDA_SIZE=$(ls -lh "$CUDA_RUN" | awk '{print $5}')
    echo ">> 检测到 CUDA 安装文件 ($CUDA_SIZE)"
    echo ""
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│  现在开始安装 CUDA 11.8                                 │"
    echo "│                                                         │"
    echo "│  ⚠️  请在弹出的交互界面中操作：                          │"
    echo "│  1. 阅读协议 → 按 q 跳过 → 输入 accept 回车             │"
    echo "│  2. 组件选择：                                          │"
    echo "│     【方案A】保留 Driver 勾选 → 驱动和CUDA一起装         │"
    echo "│     【方案B】用空格取消 Driver → 只装CUDA                │"
    echo "│  3. 移动到 Install → 回车开始安装                       │"
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""
    echo ">> 是否现在启动 CUDA 安装程序？"
    echo "   [y] 现在安装（推荐）"
    echo "   [s] 静默安装全部（CUDA + 驱动，无需交互）"
    echo "   [t] 静默安装仅CUDA工具包（不装驱动）"
    echo "   [n] 跳过，稍后手动安装"
    echo -n "请输入 (y/s/t/n，默认 y): "
    read -r cuda_choice
    echo ""
    
    case "${cuda_choice:-y}" in
        s|S)
            echo ">> 执行静默安装（CUDA + 驱动）..."
            chmod +x "$CUDA_RUN"
            sh "$CUDA_RUN" --silent 2>&1 | tee -a "$LOG_FILE"
            echo "✅ CUDA 静默安装完成"
            ;;
        t|T)
            echo ">> 执行静默安装（仅 CUDA 工具包）..."
            chmod +x "$CUDA_RUN"
            sh "$CUDA_RUN" --silent --toolkit 2>&1 | tee -a "$LOG_FILE"
            echo "✅ CUDA 工具包安装完成"
            ;;
        y|Y|*)
            echo ">> 启动交互式安装..."
            chmod +x "$CUDA_RUN"
            sh "$CUDA_RUN" 2>&1 | tee -a "$LOG_FILE"
            echo "✅ CUDA 交互安装完成（请确认安装结果）"
            ;;
    esac
    
    # 配置 CUDA 环境变量
    echo ">> 配置 CUDA 环境变量..."
    cat > /etc/profile.d/cuda.sh << 'EOF'
export PATH=/usr/local/cuda-11.8/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-11.8/lib64:$LD_LIBRARY_PATH
EOF
    chmod +x /etc/profile.d/cuda.sh
    echo "✅ CUDA 环境变量文件已创建: /etc/profile.d/cuda.sh"
    echo "   请执行 source /etc/profile.d/cuda.sh 使其立即生效"
    
    # 验证 nvidia-smi
    if command -v nvidia-smi &>/dev/null; then
        echo ""
        echo ">> NVIDIA 驱动状态:"
        nvidia-smi 2>&1 | head -5
    else
        echo ""
        echo ">> nvidia-smi 未找到。"
        echo "   如果安装了驱动，请重启后重试。"
        echo "   如果未安装驱动，用以下命令安装："
        echo "     sudo sh \"$CUDA_RUN\" --silent"
    fi
else
    echo "⚠️  未找到 CUDA 安装文件，跳过 CUDA 安装"
fi

# ========== 检查单独下载的 NVIDIA 驱动 ==========
shopt -s nullglob
for f in "$BASE_DIR"/*/NVIDIA-Linux-x86_64-*.run; do
    echo ""
    echo ">> 检测到新版 NVIDIA 驱动文件: $(basename "$f")"
    echo "   是否安装此驱动？（默认n）[y/n]: "
    read -r answer
    if [ "${answer:-n}" = "y" ] || [ "${answer:-n}" = "Y" ]; then
        chmod +x "$f"
        sh "$f"
    fi
    break
done
shopt -u nullglob

echo ""
echo "=========================================="
echo "  安装流程结束！"
echo "=========================================="
echo ""
echo "📌 后续步骤："
echo "1. 运行 nvidia-smi 检查驱动"
echo "2. 运行 nvcc -V 检查 CUDA"
echo "3. 如果驱动未安装，运行:"
echo "   sudo sh \"$CUDA_RUN\" --silent"
echo ""
echo "日志文件: $LOG_FILE"
