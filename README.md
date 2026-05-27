# 在 Mac 上用 DeepSeek 跑 Codex：保姆级配置教程

> 通过 [Moon Bridge](https://github.com/ZhiYi-R/moon-bridge) 协议桥，让 OpenAI Codex CLI/App 使用 DeepSeek V4 模型。支持多 Provider（自有 Key + 九天 + 小米 MiMo），最多可接入 20+ 模型。
>
> **不用写一行 YAML，不用记一个命令。跑个脚本，回答问题，搞定。**

## 一键安装（推荐）

```bash
# 克隆项目
git clone https://github.com/aokest/codex-deepseek-moonbridge.git
cd codex-deepseek-moonbridge

# 跑这个脚本，按提示回答问题即可
bash setup.sh
```

脚本会自动完成：
1. 安装 Go 1.25.x（无需 sudo）
2. 克隆 Moon Bridge
3. 交互式生成配置文件（逐一询问各 Provider 的 API Key）
4. 编译 Moon Bridge
5. 后台启动服务
6. 配置 Codex 连接
7. 测试连通性
8. 可选：配置 macOS 开机自启

**任何一步失败都会给出详细的手动操作指引。** 五分钟后 Codex 就能用了。

> **需要先准备好 API Key**：DeepSeek（[获取](https://platform.deepseek.com/api_keys)）、九天（JWT Token）、小米 MiMo（新加坡端）。

## 自动化工具

| 工具 | 用途 | 用法 |
|------|------|------|
| `setup.sh` | **一键安装全部** | `bash setup.sh` |
| `generate_config.py` | 单独生成 config.yml | `python3 generate_config.py -o ~/moon-bridge/` |
| `test_providers.sh` | 测试 Provider 连通性 | `bash test_providers.sh` / `bash test_providers.sh --quick` / `bash test_providers.sh --model xm-v2.5-pro` |

## 手动配置（如果脚本失败）

如果自动化脚本不适用你的环境，按以下步骤手动操作。每步约 2-5 分钟，全程约 20 分钟。

### 1. 安装 Go

```bash
mkdir -p ~/go-sdk
curl -fsSL https://go.dev/dl/go1.25.10.darwin-arm64.tar.gz | tar -C ~/go-sdk -xzf -
```

> **必须 Go 1.25.x**。1.26.x 编译 Moon Bridge 会报 `redeclared` 错误。
> Intel Mac 把 `arm64` 改为 `amd64`。

### 2. 克隆 Moon Bridge

```bash
git clone https://github.com/ZhiYi-R/moon-bridge ~/moon-bridge
mkdir -p ~/moon-bridge/data
```

### 3. 生成配置

**方式 A（推荐）**：用交互式脚本生成
```bash
python3 generate_config.py -o ~/moon-bridge/
```

**方式 B**：手动复制模板后编辑
```bash
cp config.example.yml ~/moon-bridge/config.yml
# 编辑 config.yml，把 "你的" 替换为真实 API Key
```

### 4. 启动 Moon Bridge

```bash
cd ~/moon-bridge
~/go-sdk/go/bin/go build -o moonbridge ./cmd/moonbridge
./moonbridge --config config.yml &
```

### 5. 配置 Codex

```bash
cat >> ~/.codex/config.toml << 'EOF'
[model_providers.moonbridge]
name = "Moon Bridge"
base_url = "http://127.0.0.1:38440/v1"
wire_api = "responses"
EOF
```

### 6. 生成模型元数据

```bash
cd ~/moon-bridge
~/go-sdk/go/bin/go run ./cmd/moonbridge --config config.yml --codex-home ~/.codex --print-codex-config moonbridge
```

### 7. 启动 Codex

```bash
codex
```

> 详细的手动教程（含每步注意事项、截图、排查方法）见 **[SETUP.md](./SETUP.md)**。

## 为什么需要这个？

Codex 使用 OpenAI **Responses API**（私有协议）与模型通信，DeepSeek 只支持 **Chat Completions API**。两者不兼容——直接改 `base_url` 会 404、工具调用失败。

Moon Bridge 在中间做翻译：

```
Codex ──Responses API──▶ Moon Bridge ──Chat Completions──▶ DeepSeek
       ◀──Responses API──◀             ◀──Chat Completions──◀
```

## 多 Provider 支持

在 Codex 中通过 `/model <slug>` 自由切换：

| Provider | 模型数 | 费用 | 说明 |
|----------|--------|------|------|
| DeepSeek 自有 Key | 2 | 付费 | DeepSeek V4 Flash / Pro |
| 九天（中国移动） | 20 | 部分免费 | DeepSeek、Qwen、Kimi、MiniMax、GLM 等系列 |
| 小米 MiMo（新加坡） | 4 | 付费 | MiMo V2 Omni / V2.5 Pro / V2.5 / V2 Pro |

完整模型列表和配置模板见 **[config.example.yml](./config.example.yml)**。

## 文件说明

| 文件 | 内容 |
|------|------|
| `setup.sh` | **一键安装脚本**（自动装 Go、克隆 Moon Bridge、生成配置、编译启动、配置 Codex、测试） |
| `generate_config.py` | 交互式 config.yml 生成器（询问 API Key，自动生成完整配置） |
| `test_providers.sh` | Provider 连通性测试脚本（支持全测/快测/单模型/指定 Provider） |
| `config.example.yml` | 三 Provider 完整配置模板（脱敏，含所有注释） |
| [README.md](./README.md) | 本文件，快速概览 |
| [SETUP.md](./SETUP.md) | 完整 9 步配置教程，含多 Provider 配置、调试方法论、源码 Patch 指南 |

## 关键踩坑经验

1. **Model Key = 上游模型 ID**：`config.yml` 中 `models` 段的 key 会被 Moon Bridge 直接作为上游 API 的 `model` 参数发送。用自定义短名会导致 401。必须与上游 API 的模型 ID 完全一致（如九天要求 `deepseek/deepseek-v3` 格式）。
2. **含 `/` 的 key 必须加引号**：YAML 中 `"deepseek/deepseek-v3"` 要加引号，否则解析失败。
3. **不同 Provider 的 base_url 不同**：DeepSeek 自有 Key 走 `/anthropic`（Anthropic 兼容），九天走 `/v3`（OpenAI 兼容）。
4. **protocol 必须显式声明**：Provider 默认 protocol 是 `"anthropic"`。使用 OpenAI Chat Completions API 的 Provider（如九天、小米）必须加 `protocol: "openai-chat"`，否则 Moon Bridge 会用 Anthropic 格式发请求，导致 401。
5. **api_version 决定了上游 API 路径**：Moon Bridge 构造的 URL 为 `{base_url}/{api_version}/chat/completions`。九天 API 需要 `api_version: "v3"`。旧版 Moon Bridge 硬编码了 `/v1/`，需手动 patch 源码（详见 SETUP.md 第九步）。
6. **Go 版本敏感**：Go 1.26.x 编译 Moon Bridge 会报 `redeclared`，必须用 1.25.x。
7. **需要裸 model ID 路由**：Codex 从 `/v1/models` 拿到 model name 后可能直接传原始 ID，路由表需要同时注册 slug 和原始 ID 两份路由条目。
8. **`codex-auto-review` 路由必须配置**：Codex 的高风险操作自动审核依赖此模型，缺失会导致大量操作被拦截。
9. **小米 MiMo 模型均为推理模型**：所有 MiMo 模型输出包含 `reasoning_content`，`max_tokens` 设为 10-50 会导致空响应，建议至少 200+。
10. **mimo-v2-flash 不支持**：新加坡小米端点不提供此模型，不要配置。
11. **mimo-v2-omni 是唯一的多模态模型**：需要视觉/图片理解时用此模型，256K 上下文。

## 常见问题

| 问题 | 解决 |
|------|------|
| `unable to open database file` | `mkdir -p ~/moon-bridge/data` |
| Go 编译报 `redeclared` | 用 Go 1.25.x，不要用 1.26.x |
| `brew install go` 极慢 | 用本教程的直接下载方式（setup.sh 已内置） |
| Codex 提示登录 OpenAI | `codex logout` |
| `Model metadata not found` | 重新生成 `models_catalog.json` |
| 九天模型 401 | 1) 加 `protocol: "openai-chat"` 2) 加 `api_version: "v3"` 3) base_url 去掉 `/v3` 后缀 |
| 九天模型 404 (unknown model) | 添加裸 model ID 路由，详见 SETUP.md 9.4 |
| 大量"自动审核已拒绝" | 添加 `codex-auto-review` 路由，详见 SETUP.md 9.6 |
| 小米模型返回空内容 | max_tokens 设太低（10-50），reasoning 吃掉了全部 token 预算，建议 200+ |
| 小米模型 404 (Not supported) | mimo-v2-flash 在新加坡端点不可用，去掉此模型 |

更多排查 → **[SETUP.md 第九步：调试方法论与深度排查](./SETUP.md#第九步调试方法论与深度排查)**

## License

MIT
