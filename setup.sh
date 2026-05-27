#!/bin/bash
# Moon Bridge + Codex 一键安装配置脚本
# 功能：自动安装 Go、克隆 Moon Bridge、生成配置、启动服务、配置 Codex、测试连通性
# 每一步失败都会给出详细的手动操作指引

set -euo pipefail

# ============================================================
# 颜色和输出
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

STEP=0
step() {
    STEP=$((STEP + 1))
    echo ""
    echo -e "${BOLD}${CYAN}═══ 第 ${STEP} 步：$1 ═══${NC}"
    echo ""
}

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() {
    echo -e "  ${RED}✗${NC} $1"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  自动安装失败，请手动完成此步骤。${NC}"
    echo -e "${YELLOW}  详细教程：SETUP.md${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if [[ -n "${2:-}" ]]; then
        echo ""
        echo -e "${BOLD}手动操作：${NC}"
        echo "$2"
    fi
    echo ""
    read -rp "是否继续下一步？(y/n) " cont
    [[ "$cont" != "y" ]] && exit 1
    return 0
}

# ============================================================
# 环境检测
# ============================================================
ARCH=$(uname -m)
OS=$(uname -s)

if [[ "$OS" != "Darwin" ]]; then
    echo "此脚本目前仅支持 macOS。Linux/Windows 用户请参考 SETUP.md 手动配置。"
    exit 1
fi

if [[ "$ARCH" == "arm64" ]]; then
    GO_ARCH="darwin-arm64"
elif [[ "$ARCH" == "x86_64" ]]; then
    GO_ARCH="darwin-amd64"
else
    echo "不支持的架构: $ARCH"
    exit 1
fi

GO_VERSION="1.25.10"
GO_TAR="go${GO_VERSION}.${GO_ARCH}.tar.gz"
GO_URL="https://go.dev/dl/${GO_TAR}"
GO_INSTALL_DIR="$HOME/go-sdk"
MOON_BRIDGE_DIR="$HOME/moon-bridge"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║  Moon Bridge + Codex 一键安装脚本       ║${NC}"
echo -e "${BOLD}${CYAN}║  支持 DeepSeek / 九天 / 小米 MiMo       ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "系统: ${OS} / ${ARCH}"
echo -e "Go 版本: ${GO_VERSION}"
echo -e "安装路径: ${MOON_BRIDGE_DIR}"
echo ""
echo -e "${YELLOW}脚本会自动完成以下操作：${NC}"
echo "  1. 安装 Go ${GO_VERSION} 到 ~/go-sdk/"
echo "  2. 克隆 Moon Bridge 到 ~/moon-bridge/"
echo "  3. 交互式生成配置文件"
echo "  4. 编译 Moon Bridge"
echo "  5. 配置 Codex"
echo "  6. 可选：配置开机自启"
echo "  7. 测试连通性"
echo ""
echo -e "${YELLOW}任何步骤失败都会给出详细的手动操作指引。${NC}"
echo ""
read -rp "按 Enter 开始，或 Ctrl+C 退出..."

# ============================================================
# 第 1 步：安装 Go
# ============================================================
step "安装 Go ${GO_VERSION}"

if [[ -x "${GO_INSTALL_DIR}/go/bin/go" ]]; then
    INSTALLED_VER=$("${GO_INSTALL_DIR}/go/bin/go" version 2>/dev/null | grep -o 'go[0-9.]*' || echo "unknown")
    if [[ "$INSTALLED_VER" == "go${GO_VERSION}" ]]; then
        ok "Go ${GO_VERSION} 已安装"
    else
        warn "已安装 ${INSTALLED_VER}，需要 ${GO_VERSION}"
        read -rp "重新安装？(y/n) " reinstall
        if [[ "$reinstall" == "y" ]]; then
            rm -rf "$GO_INSTALL_DIR"
        fi
    fi
fi

if [[ ! -x "${GO_INSTALL_DIR}/go/bin/go" ]]; then
    echo "  下载 ${GO_URL} ..."
    mkdir -p "$GO_INSTALL_DIR"
    if curl -fsSL --progress-bar "$GO_URL" -o "/tmp/${GO_TAR}"; then
        ok "下载完成"
    else
        fail "下载失败" "
# 手动下载 Go:
mkdir -p ~/go-sdk
curl -fsSL ${GO_URL} -o /tmp/${GO_TAR}
tar -C ~/go-sdk -xzf /tmp/${GO_TAR}
"
    fi
    echo "  解压到 ${GO_INSTALL_DIR} ..."
    tar -C "$GO_INSTALL_DIR" -xzf "/tmp/${GO_TAR}"
    rm -f "/tmp/${GO_TAR}"
    ok "Go ${GO_VERSION} 安装完成"
fi

export PATH="${GO_INSTALL_DIR}/go/bin:${GO_INSTALL_DIR}/bin:$PATH"
go version

# ============================================================
# 第 2 步：克隆 Moon Bridge
# ============================================================
step "克隆 Moon Bridge"

if [[ -d "$MOON_BRIDGE_DIR" ]]; then
    ok "Moon Bridge 目录已存在: ${MOON_BRIDGE_DIR}"
    read -rp "更新到最新版本？(y/n) " update
    if [[ "$update" == "y" ]]; then
        cd "$MOON_BRIDGE_DIR"
        git pull || warn "git pull 失败，可能有本地修改，跳过更新"
        cd "$PROJECT_DIR"
    fi
else
    echo "  git clone https://github.com/ZhiYi-R/moon-bridge ${MOON_BRIDGE_DIR}"
    if git clone https://github.com/ZhiYi-R/moon-bridge "$MOON_BRIDGE_DIR"; then
        ok "克隆完成"
    else
        fail "克隆失败" "
# 手动克隆:
git clone https://github.com/ZhiYi-R/moon-bridge ~/moon-bridge
"
    fi
fi

# 创建 data 目录
mkdir -p "${MOON_BRIDGE_DIR}/data"
ok "data 目录已就绪"

# ============================================================
# 第 3 步：生成配置文件
# ============================================================
step "生成 Moon Bridge 配置文件"

CONFIG_FILE="${MOON_BRIDGE_DIR}/config.yml"

if [[ -f "$CONFIG_FILE" ]]; then
    warn "config.yml 已存在"
    read -rp "覆盖现有配置？(y/n) " overwrite
    if [[ "$overwrite" != "y" ]]; then
        ok "保留现有配置"
    else
        NEED_CONFIG=true
    fi
else
    NEED_CONFIG=true
fi

if [[ "${NEED_CONFIG:-false}" == true ]]; then
    if [[ -f "${PROJECT_DIR}/generate_config.py" ]]; then
        python3 "${PROJECT_DIR}/generate_config.py" -o "$MOON_BRIDGE_DIR" || {
            fail "配置生成失败" "
# 手动创建配置:
cp ${PROJECT_DIR}/config.example.yml ${CONFIG_FILE}
# 然后编辑 ${CONFIG_FILE}，将 api_key 替换为你的真实 Key
# 详细说明见 SETUP.md 第三步
"
        }
    else
        # 从 config.example.yml 复制并提示用户编辑
        if [[ -f "${PROJECT_DIR}/config.example.yml" ]]; then
            cp "${PROJECT_DIR}/config.example.yml" "$CONFIG_FILE"
            ok "已从模板创建 config.yml"
            echo ""
            echo -e "${YELLOW}⚠ 请编辑配置文件，替换 API Key：${NC}"
            echo -e "  ${BOLD}vim ${CONFIG_FILE}${NC}"
            echo "  搜索 '你的' 替换为真实 Key"
            echo ""
            read -rp "已完成编辑？(y/n) " edited
        else
            fail "找不到 config.example.yml 模板" "
# 从 GitHub 获取模板:
curl -o ${CONFIG_FILE} https://raw.githubusercontent.com/aokest/codex-deepseek-moonbridge/master/config.example.yml
# 然后编辑 ${CONFIG_FILE}，将 api_key 替换为你的真实 Key
"
        fi
    fi
fi

# 快速脱敏检查
if grep -q "sk-你的\|tp-你的\|你的JWT" "$CONFIG_FILE" 2>/dev/null; then
    warn "config.yml 中仍有占位符，请记得替换为真实的 API Key"
fi

ok "配置文件: ${CONFIG_FILE}"

# ============================================================
# 第 4 步：编译 Moon Bridge
# ============================================================
step "编译 Moon Bridge"

cd "$MOON_BRIDGE_DIR"

if go build -o moonbridge ./cmd/moonbridge 2>&1 | tail -5; then
    ok "编译完成: ${MOON_BRIDGE_DIR}/moonbridge"
else
    fail "编译失败（可能是 Go 版本问题）" "
# 常见原因和解决:
# 1. Go 版本过高（1.26.x 会报 redeclared）→ 用 1.25.x
# 2. 网络问题导致依赖下载失败 → 设置 Go 代理:
   export GOPROXY=https://goproxy.io,direct
   go build -o moonbridge ./cmd/moonbridge
# 3. 详见 SETUP.md 第一步
"
fi

# ============================================================
# 第 5 步：停止旧进程，启动 Moon Bridge
# ============================================================
step "启动 Moon Bridge"

# 停止旧进程
pkill -f "moonbridge" 2>/dev/null && warn "已停止旧进程" || true
sleep 1

# 后台启动
nohup ./moonbridge --config config.yml > /tmp/moonbridge.log 2>&1 &
MOON_PID=$!
echo "  PID: ${MOON_PID}"

# 等待启动
echo "  等待 Moon Bridge 启动..."
for i in $(seq 1 15); do
    sleep 1
    if curl -s -o /dev/null "http://127.0.0.1:38440/v1/models" 2>/dev/null; then
        ok "Moon Bridge 启动成功（端口 38440）"
        break
    fi
    if [[ $i -eq 15 ]]; then
        warn "启动超时"
        echo ""
        echo -e "${YELLOW}查看日志排查问题：${NC}"
        echo "  tail -50 /tmp/moonbridge.log"
        echo ""
        read -rp "继续？(y/n) " cont
        [[ "$cont" != "y" ]] && exit 1
    fi
done

# ============================================================
# 第 6 步：配置 Codex
# ============================================================
step "配置 Codex"

mkdir -p "$CODEX_HOME"

# 备份现有配置
if [[ -f "${CODEX_HOME}/config.toml" ]]; then
    if ! grep -q "moonbridge" "${CODEX_HOME}/config.toml" 2>/dev/null; then
        cp "${CODEX_HOME}/config.toml" "${CODEX_HOME}/config.toml.bak.$(date +%Y%m%d%H%M%S)"
        ok "已备份现有 config.toml"
    fi
fi

# 添加 Moon Bridge provider
if ! grep -q "moonbridge" "${CODEX_HOME}/config.toml" 2>/dev/null; then
    cat >> "${CODEX_HOME}/config.toml" << 'CODECONFIG'

[model_providers.moonbridge]
name = "Moon Bridge"
base_url = "http://127.0.0.1:38440/v1"
wire_api = "responses"
CODECONFIG
    ok "已添加 Moon Bridge provider 到 Codex 配置"
else
    ok "Moon Bridge provider 已存在"
fi

# 生成 models_catalog.json
echo "  生成 models_catalog.json ..."
cd "$MOON_BRIDGE_DIR"
go run ./cmd/moonbridge \
    --config config.yml \
    --codex-home "$CODEX_HOME" \
    --print-codex-config moonbridge > /dev/null 2>&1 || {
    warn "models_catalog.json 自动生成失败"
    echo "  尝试手动生成..."
    # 备选：从 /v1/models 获取
    curl -s "http://127.0.0.1:38440/v1/models" | python3 -c "
import json, sys
data = json.load(sys.stdin)
models = data.get('data', [])
catalog = {'models': []}
for m in models:
    name = m.get('id', m.get('name', ''))
    if name:
        catalog['models'].append({
            'id': name,
            'name': name,
            'provider': 'moonbridge',
            'capabilities': {'reasoning': True}
        })
json.dump(catalog, open('${CODEX_HOME}/models_catalog.json', 'w'), indent=2)
print(f'  已生成 {len(catalog[\"models\"])} 个模型条目')
" 2>/dev/null && ok "models_catalog.json 手动生成完成" || warn "models_catalog.json 生成失败，Codex 可能无法识别模型"
}

# 设置默认模型
cd "$PROJECT_DIR"

# ============================================================
# 第 7 步：测试连通性
# ============================================================
step "测试连通性"

if [[ -f "${PROJECT_DIR}/test_providers.sh" ]]; then
    bash "${PROJECT_DIR}/test_providers.sh" --quick || {
        warn "部分 Provider 测试未通过"
        echo ""
        echo -e "${YELLOW}排查建议：${NC}"
        echo "  1. 先测试直连上游 API（排除 Key 问题），详见 SETUP.md 9.1"
        echo "  2. 查看 Moon Bridge 日志: tail -50 /tmp/moonbridge.log"
        echo "  3. 检查 config.yml 配置: cat ${CONFIG_FILE}"
        echo "  4. 完整测试: bash ${PROJECT_DIR}/test_providers.sh"
        echo "  5. 详细排查: SETUP.md 第九步"
    }
else
    # 简易测试
    echo "  测试 Moon Bridge ..."
    RESP=$(curl -s "http://127.0.0.1:38440/v1/models" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('data',[])) if 'data' in d else 'ok')" 2>/dev/null || echo "fail")
    if [[ "$RESP" != "fail" ]]; then
        ok "Moon Bridge 响应正常（${RESP} 个模型）"
    else
        fail "Moon Bridge 无响应" "
# 排查:
# 1. 检查进程: ps aux | grep moonbridge
# 2. 查看日志: tail -50 /tmp/moonbridge.log
# 3. 手动启动: cd ~/moon-bridge && go run ./cmd/moonbridge --config config.yml
"
    fi
fi

# ============================================================
# 第 8 步：开机自启（可选）
# ============================================================
step "开机自启（可选）"

read -rp "是否配置 Moon Bridge 开机自启？(y/n) " autostart
if [[ "$autostart" == "y" ]]; then
    USERNAME=$(whoami)
    PLIST_FILE="$HOME/Library/LaunchAgents/com.user.moonbridge.plist"

    cat > "$PLIST_FILE" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.moonbridge</string>
    <key>ProgramArguments</key>
    <array>
        <string>${MOON_BRIDGE_DIR}/moonbridge</string>
        <string>--config</string>
        <string>config.yml</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${MOON_BRIDGE_DIR}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/moonbridge.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/moonbridge.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>${GO_INSTALL_DIR}/go/bin:${GO_INSTALL_DIR}/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
PLIST

    launchctl bootout "gui/$(id -u)" "$PLIST_FILE" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST_FILE"
    ok "开机自启已配置"
    echo "  停止服务: launchctl bootout gui/\$(id -u) ${PLIST_FILE}"
    echo "  查看日志: tail -f /tmp/moonbridge.log"
fi

# ============================================================
# 完成
# ============================================================
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║  安装完成！                             ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}现在可以：${NC}"
echo ""
echo "  启动 Codex:"
echo -e "    ${BOLD}codex${NC}"
echo ""
echo "  在 Codex 中切换模型:"
echo "    /model moonbridge        → DeepSeek V4 Pro"
echo "    /model moonbridge-flash  → DeepSeek V4 Flash"
echo "    /model jt-ds-v3          → DeepSeek V3（九天免费）"
echo "    /model xm-v2.5-pro       → MiMo V2.5 Pro（小米）"
echo ""
echo "  测试连通性:"
echo -e "    ${BOLD}bash ${PROJECT_DIR}/test_providers.sh${NC}"
echo ""
echo "  查看日志:"
echo -e "    ${BOLD}tail -f /tmp/moonbridge.log${NC}"
echo ""
echo -e "${YELLOW}遇到问题？${NC}"
echo "  详细教程: ${PROJECT_DIR}/SETUP.md"
echo "  调试方法: SETUP.md 第九步「调试方法论与深度排查」"
echo ""
