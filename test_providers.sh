#!/bin/bash
# Moon Bridge Provider 测试脚本
# 用法:
#   ./test_providers.sh                    # 测试所有 provider
#   ./test_providers.sh deepseek           # 只测试指定 provider
#   ./test_providers.sh jiutian xiaomi     # 测试多个 provider
#   ./test_providers.sh --quick            # 快速模式（每个 provider 只测一个模型）
#   ./test_providers.sh --model xm-v2.5-pro # 测试特定模型

set -euo pipefail

MOON_BRIDGE_URL="${MOON_BRIDGE_URL:-http://127.0.0.1:38440}"
QUICK_MODE=false
SPECIFIC_MODEL=""
SELECTED_PROVIDERS=()

# 颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 模型分类（provider => 测试模型列表，第一个为 quick 模式使用）
declare -A PROVIDER_MODELS
PROVIDER_MODELS[deepseek]="moonbridge-flash moonbridge"
PROVIDER_MODELS[jiutian]="jt-ds-v3 jt-ds-v4-flash jt-qwen3.5-27b jt-glm-5.1"
PROVIDER_MODELS[xiaomi]="xm-v2.5-pro xm-v2.5 xm-v2-pro xm-omni"

usage() {
    cat << 'EOF'
Moon Bridge Provider 测试工具

用法:
  ./test_providers.sh [选项] [provider...]

选项:
  --quick        快速模式：每个 provider 只测一个模型
  --model NAME   只测试指定模型（route slug）
  --help         显示帮助

Provider 可选值:
  deepseek   - DeepSeek 自有 Key
  jiutian    - 九天（中国移动）
  xiaomi     - 小米 MiMo

示例:
  ./test_providers.sh                         # 测试所有
  ./test_providers.sh deepseek                # 只测 DeepSeek
  ./test_providers.sh jiutian xiaomi          # 测九天 + 小米
  ./test_providers.sh --quick                 # 快速测试全部
  ./test_providers.sh --model xm-v2.5-pro     # 测特定模型

环境变量:
  MOON_BRIDGE_URL     Moon Bridge 地址（默认 http://127.0.0.1:38440）
EOF
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --quick)    QUICK_MODE=true; shift ;;
        --model)    SPECIFIC_MODEL="$2"; shift 2 ;;
        --help)     usage; exit 0 ;;
        deepseek|jiutian|xiaomi) SELECTED_PROVIDERS+=("$1"); shift ;;
        *) echo "未知参数: $1"; usage; exit 1 ;;
    esac
done

# 如果没有指定 provider，测试全部
if [[ ${#SELECTED_PROVIDERS[@]} -eq 0 ]] && [[ -z "$SPECIFIC_MODEL" ]]; then
    SELECTED_PROVIDERS=(deepseek jiutian xiaomi)
fi

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Moon Bridge Provider 连通性测试${NC}"
echo -e "${CYAN}  ${MOON_BRIDGE_URL}${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# 1. 检查 Moon Bridge 是否在运行
echo -n "检查 Moon Bridge 运行状态... "
if HEALTH=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "${MOON_BRIDGE_URL}/v1/models" 2>/dev/null); then
    if [[ "$HEALTH" == "200" ]]; then
        echo -e "${GREEN}运行中${NC}"
    else
        echo -e "${RED}异常 (HTTP $HEALTH)${NC}"
        exit 1
    fi
else
    echo -e "${RED}无法连接${NC}"
    echo "请确认 Moon Bridge 已启动: cd ~/moon-bridge && go run ./cmd/moonbridge --config config.yml"
    exit 1
fi
echo ""

# 2. 列出可用模型
echo -e "${CYAN}--- 可用模型列表 ---${NC}"
AVAILABLE_MODELS=$(curl -s "${MOON_BRIDGE_URL}/v1/models" | python3 -c "
import json,sys
data = json.load(sys.stdin)
models = data.get('data', data) if isinstance(data, dict) else data
if isinstance(models, list):
    for m in models:
        name = m.get('id', m.get('name', str(m)))
        print(f'  - {name}')
elif isinstance(models, dict):
    for name in models:
        print(f'  - {name}')
" 2>/dev/null || echo "  (无法解析模型列表)")
echo "$AVAILABLE_MODELS"
echo ""

# 3. 测试函数
PASS_COUNT=0
FAIL_COUNT=0
FAILED_MODELS=()

test_model() {
    local model_slug="$1"
    local desc="$2"

    printf "  %-30s " "${model_slug}"
    local start=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo 0)

    local response
    response=$(curl -s --connect-timeout 10 --max-time 30 -X POST "${MOON_BRIDGE_URL}/v1/responses" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"${model_slug}\",
            \"input\": [{\"role\": \"user\", \"content\": \"Reply with just: OK\"}],
            \"max_output_tokens\": 20
        }" 2>&1)

    local end=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo 0)
    local elapsed=$(( (end - start) / 1000 ))

    # 检查是否包含 OK（推理模型可能返回 reasoning + OK）
    local status=$(echo "$response" | python3 -c "
import json,sys
try:
    data = json.load(sys.stdin)
    status = data.get('status', 'unknown')
    if status == 'completed':
        # 尝试获取输出文本
        output = data.get('output', [])
        text = ''
        for item in output:
            if isinstance(item, dict):
                for msg in item.get('content', []):
                    if isinstance(msg, dict) and msg.get('type') == 'output_text':
                        text += msg.get('text', '')
        if text.strip():
            print(f'OK ({text.strip()[:50]}, {elapsed}s)')
        else:
            print(f'OK (empty output, {elapsed}s)')
    else:
        error = data.get('error', data.get('message', str(data)[:200]))
        print(f'FAIL: {error}')
except Exception as e:
    # 尝试提取 HTTP 状态
    import re
    http_match = re.search(r'\"status\":\s*(\d+)', sys.stdin.read())
    sys.stdin.seek(0)
    first_line = sys.stdin.readline().strip()[:200]
    print(f'FAIL: {first_line}'
" 2>/dev/null || echo "FAIL: parse error")

    if [[ "$status" == OK* ]]; then
        echo -e "${GREEN}✓ ${status}${NC}"
        ((PASS_COUNT++)) || true
    else
        echo -e "${RED}✗ ${status}${NC}"
        ((FAIL_COUNT++)) || true
        FAILED_MODELS+=("${model_slug}: ${status}")
    fi
}

# 4. 运行测试
if [[ -n "$SPECIFIC_MODEL" ]]; then
    echo -e "${CYAN}--- 测试模型: ${SPECIFIC_MODEL} ---${NC}"
    test_model "$SPECIFIC_MODEL" ""
else
    for provider in "${SELECTED_PROVIDERS[@]}"; do
        models_str="${PROVIDER_MODELS[$provider]:-}"
        if [[ -z "$models_str" ]]; then
            echo -e "${YELLOW}未知 Provider: $provider${NC}"
            continue
        fi
        read -ra models <<< "$models_str"

        echo -e "${CYAN}--- Provider: ${provider} ($([ "$QUICK_MODE" = true ] && echo "快速模式" || echo "完整测试")) ---${NC}"

        if [[ "$QUICK_MODE" == true ]]; then
            test_model "${models[0]}" "${provider}"
        else
            for m in "${models[@]}"; do
                test_model "$m" "${provider}"
            done
        fi
        echo ""
    done
fi

# 5. 汇总
echo -e "${CYAN}========================================${NC}"
echo -e "  通过: ${GREEN}${PASS_COUNT}${NC}  失败: ${RED}${FAIL_COUNT}${NC}"
echo -e "${CYAN}========================================${NC}"

if [[ ${#FAILED_MODELS[@]} -gt 0 ]]; then
    echo ""
    echo -e "${YELLOW}失败详情:${NC}"
    for f in "${FAILED_MODELS[@]}"; do
        echo "  - $f"
    done
    echo ""
    echo "排查建议:"
    echo "  1. 逐层测试: 先直连上游 API 确认 Key 有效"
    echo "  2. 检查 Moon Bridge 日志: tail -f /tmp/moonbridge.log"
    echo "  3. 确认 config.yml 中 provider 的 protocol/api_version 正确"
    echo "  4. 详见 SETUP.md 第九步「调试方法论与深度排查」"
    exit 1
fi

echo ""
echo -e "${GREEN}所有测试通过 ✓${NC}"
