# 在 Mac 上用 DeepSeek 跑 Codex：保姆级配置教程

> 通过 [Moon Bridge](https://github.com/ZhiYi-R/moon-bridge) 协议桥，让 OpenAI Codex CLI/App 使用 DeepSeek V4 模型。

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
# 编辑 ~/moon-bridge/config.yml（见下方完整配置）

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

## 详细教程

👉 **[完整教程文档](./SETUP.md)**（含每步注意事项、常见问题排查、launchd 自启配置）

## 文件说明

| 文件 | 内容 |
|------|------|
| [README.md](./README.md) | 本文件，快速概览 |
| [SETUP.md](./SETUP.md) | 完整 8 步配置教程 |
| [config.example.yml](./config.example.yml) | Moon Bridge 配置模板 |

## 常见问题

| 问题 | 解决 |
|------|------|
| `unable to open database file` | `mkdir -p ~/moon-bridge/data` |
| Go 编译报 `redeclared` | 用 Go 1.25.x，不要用 1.26.x |
| `brew install go` 极慢 | 用本教程的直接下载方式 |
| Codex 提示登录 OpenAI | `codex logout` |
| `Model metadata not found` | 重新生成 `models_catalog.json` |

## License

MIT
