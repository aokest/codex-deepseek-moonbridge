# 在 Mac 上用 DeepSeek 跑 Codex：保姆级配置教程

> 通过 [Moon Bridge](https://github.com/ZhiYi-R/moon-bridge) 协议桥，让 OpenAI Codex CLI/App 使用 DeepSeek V4 模型。支持多 Provider（自有 Key + 九天等第三方 API），最多可接入 20+ 模型。

## 为什么需要这个？

Codex 使用 OpenAI **Responses API**（私有协议）与模型通信，DeepSeek 只支持 **Chat Completions API**。两者不兼容——直接改 `base_url` 会 404、工具调用失败。

Moon Bridge 在中间做翻译：

```
Codex ──Responses API──▶ Moon Bridge ──Chat Completions──▶ DeepSeek
       ◀──Responses API──◀             ◀──Chat Completions──◀
```

## 快速开始

```bash
# 1. 安装 Go
mkdir -p ~/go-sdk && curl -fsSL https://go.dev/dl/go1.25.10.darwin-arm64.tar.gz | tar -C ~/go-sdk -xzf -

# 2. 克隆 Moon Bridge
git clone https://github.com/ZhiYi-R/moon-bridge ~/moon-bridge
mkdir -p ~/moon-bridge/data

# 3. 配置（替换 YOUR_KEY）
# 编辑 ~/moon-bridge/config.yml（见下方完整配置模板）

# 4. 启动
cd ~/moon-bridge && ~/go-sdk/go/bin/go run ./cmd/moonbridge --config config.yml

# 5. 配置 Codex
cat >> ~/.codex/config.toml << 'EOF'
[model_providers.moonbridge]
name = "Moon Bridge"
base_url = "http://127.0.0.1:38440/v1"
wire_api = "responses"
EOF

# 6. 启动 Codex
codex
```

## 多 Provider 支持

本项目支持同时接入多个上游 API Provider，在 Codex 中通过 `/model <slug>` 自由切换：

| Provider | 模型数 | 费用 | 说明 |
|----------|--------|------|------|
| DeepSeek 自有 Key | 2 | 付费 | DeepSeek V4 Flash / Pro |
| 九天（中国移动） | 20 | 部分免费 | DeepSeek、Qwen、Kimi、MiniMax、GLM 等系列 |

完整模型列表和配置示例见 **[config.example.yml](./config.example.yml)**。

## 详细教程

**[完整教程文档](./SETUP.md)**（含每步注意事项、多 Provider 配置详解、常见问题排查、launchd 自启配置）

## 文件说明

| 文件 | 内容 |
|------|------|
| [README.md](./README.md) | 本文件，快速概览 |
| [SETUP.md](./SETUP.md) | 完整 9 步配置教程，含多 Provider 配置、调试方法论、源码 Patch 指南 |
| [config.example.yml](./config.example.yml) | Moon Bridge 双 Provider 完整配置模板（脱敏） |

## 关键踩坑经验

1. **Model Key = 上游模型 ID**：`config.yml` 中 `models` 段的 key 会被 Moon Bridge 直接作为上游 API 的 `model` 参数发送。用自定义短名会导致 401。必须与上游 API 的模型 ID 完全一致（如九天要求 `deepseek/deepseek-v3` 格式）。
2. **含 `/` 的 key 必须加引号**：YAML 中 `"deepseek/deepseek-v3"` 要加引号，否则解析失败。
3. **不同 Provider 的 base_url 不同**：DeepSeek 自有 Key 走 `/anthropic`（Anthropic 兼容），九天走 `/v3`（OpenAI 兼容）。
4. **protocol 必须显式声明**：Provider 默认 protocol 是 `"anthropic"`。使用 OpenAI Chat Completions API 的 Provider（如九天）必须加 `protocol: "openai-chat"`，否则 Moon Bridge 会用 Anthropic 格式发请求，导致 401。
5. **api_version 决定了上游 API 路径**：Moon Bridge 构造的 URL 为 `{base_url}/{api_version}/chat/completions`。九天 API 需要 `api_version: "v3"`。旧版 Moon Bridge 硬编码了 `/v1/`，需手动 patch 源码（详见 SETUP.md 第九步）。
6. **Go 版本敏感**：Go 1.26.x 编译 Moon Bridge 会报 `redeclared`，必须用 1.25.x。
7. **需要裸 model ID 路由**：Codex 从 `/v1/models` 拿到 model name 后可能直接传原始 ID，路由表需要同时注册 slug 和原始 ID 两份路由条目。

## 常见问题

| 问题 | 解决 |
|------|------|
| `unable to open database file` | `mkdir -p ~/moon-bridge/data` |
| Go 编译报 `redeclared` | 用 Go 1.25.x，不要用 1.26.x |
| `brew install go` 极慢 | 用本教程的直接下载方式 |
| Codex 提示登录 OpenAI | `codex logout` |
| `Model metadata not found` | 重新生成 `models_catalog.json` |
| 九天模型 401 | 1) 加 `protocol: "openai-chat"` 2) 加 `api_version: "v3"` 3) base_url 去掉 `/v3` 后缀 4) 如仍有问题，详见 SETUP.md 第九步 |
| 九天模型 404 (unknown model) | 添加裸 model ID 路由，详见 SETUP.md 9.4 |
| 调试方法 | 详见 [SETUP.md 第九步：调试方法论与深度排查](./SETUP.md#第九步调试方法论与深度排查) |

## License

MIT
