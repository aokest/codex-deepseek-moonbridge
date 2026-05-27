#!/usr/bin/env python3
"""
Moon Bridge 多 Provider 配置生成器

交互式问答，根据用户输入的 API Key 自动生成 config.yml。
支持：DeepSeek 自有 Key + 九天（中国移动）+ 小米 MiMo

用法:
  python3 generate_config.py                    # 交互式
  python3 generate_config.py --output /path/    # 指定输出目录
  python3 generate_config.py --dry-run          # 只预览，不写文件
"""

import os
import sys
import argparse
from pathlib import Path

CONFIG_TEMPLATE = '''mode: "Transform"

log:
  level: "info"
  format: "text"

server:
  addr: "127.0.0.1:38440"

persistence:
  active_provider: db_sqlite

extensions:
  deepseek_v4:
    config:
      reinforce_instructions: true
      reinforce_prompt: "[System Reminder]: Please pay close attention to the system instructions, AGENTS.md files, and any other context provided. Follow them carefully and completely in your response.\\n[User]:"
  db_sqlite:
    enabled: true
    config:
      path: ./data/moonbridge.db
      wal: true
      busy_timeout_ms: 5000
      max_open_conns: 1

cache:
  mode: "explicit"
  ttl: "5m"
  prompt_caching: true
  automatic_prompt_cache: false
  explicit_cache_breakpoints: true
  allow_retention_downgrade: false
  max_breakpoints: 4
  min_cache_tokens: 1024
  expected_reuse: 2
  minimum_value_score: 2048
  min_breakpoint_tokens: 1024

defaults:
  model: "{default_model}"
  max_tokens: 65536

# ============================================================
# 模型定义
# ============================================================
# 关键规则：模型的 key 会被 Moon Bridge 直接作为上游 API 的 model 参数发送。
# 所以 model key 必须和上游 API 要求的模型 ID 完全一致！
{models_section}

# ============================================================
# Provider 定义
# ============================================================
{providers_section}

# ============================================================
# 路由定义（Codex 中通过 /model <slug> 切换）
# ============================================================
{routes_section}
'''

DEEPSEEK_MODELS = '''
  deepseek-v4-flash:
    context_window: 1000000
    max_output_tokens: 384000
    display_name: "DeepSeek V4 Flash"
    description: "DeepSeek V4 Flash - 284B/13B active, fast & cheap."
    supports_reasoning_summaries: true
    default_reasoning_summary: "auto"
    extensions:
      deepseek_v4:
        enabled: true

  deepseek-v4-pro:
    context_window: 1000000
    max_output_tokens: 384000
    display_name: "DeepSeek V4 Pro"
    description: "DeepSeek V4 Pro with high/xhigh reasoning effort."
    default_reasoning_level: "high"
    supported_reasoning_levels:
      - effort: "high"
        description: "High reasoning effort"
      - effort: "xhigh"
        description: "Extra high reasoning effort"
    supports_reasoning_summaries: true
    default_reasoning_summary: "auto"
    extensions:
      deepseek_v4:
        enabled: true
'''

JIUTIAN_MODELS = '''
  "deepseek/deepseek-v3":
    context_window: 131072
    max_output_tokens: 16384
    display_name: "DeepSeek V3 (九天)"
    description: "DeepSeek V3 via 九天"

  "deepseek/deepseek-v32":
    context_window: 131072
    max_output_tokens: 16384
    display_name: "DeepSeek V3.2 (九天)"
    description: "DeepSeek V3.2 via 九天"

  "deepseek/deepseek-r1":
    context_window: 131072
    max_output_tokens: 32768
    display_name: "DeepSeek R1 (九天)"
    description: "DeepSeek R1 reasoning model via 九天"
    supports_reasoning_summaries: true
    default_reasoning_summary: "auto"

  "deepseek/deepseek-v4-flash":
    context_window: 1000000
    max_output_tokens: 384000
    display_name: "DeepSeek V4 Flash (九天)"
    description: "DeepSeek V4 Flash via 九天"
    supports_reasoning_summaries: true
    default_reasoning_summary: "auto"

  "qwen/qwen3.5-27b":
    context_window: 131072
    max_output_tokens: 16384
    display_name: "Qwen 3.5 27B (九天)"
    description: "Qwen 3.5 27B via 九天"

  "qwen/qwen3.6-35b":
    context_window: 131072
    max_output_tokens: 16384
    display_name: "Qwen 3.6 35B (九天)"
    description: "Qwen 3.6 35B via 九天"

  "qwen/qwen3-235b-a22b-2507":
    context_window: 131072
    max_output_tokens: 16384
    display_name: "Qwen 3 235B A22B (九天)"
    description: "Qwen 3 235B A22B via 九天"

  "qwen/qwen3.5-397b-a17b":
    context_window: 131072
    max_output_tokens: 16384
    display_name: "Qwen 3.5 397B A17B (九天)"
    description: "Qwen 3.5 397B A17B via 九天"

  "qwen/qwen3-next-80b-a3b-instruct":
    context_window: 131072
    max_output_tokens: 16384
    display_name: "Qwen 3 Next 80B (九天)"
    description: "Qwen 3 Next 80B A3B via 九天"

  "moonshotai/kimi-k2.5-thinking":
    context_window: 131072
    max_output_tokens: 32768
    display_name: "Kimi K2.5 Thinking (九天)"
    description: "Kimi K2.5 with thinking via 九天"
    supports_reasoning_summaries: true
    default_reasoning_summary: "auto"

  "moonshotai/kimi-k2.6":
    context_window: 131072
    max_output_tokens: 16384
    display_name: "Kimi K2.6 (九天)"
    description: "Kimi K2.6 via 九天"

  "minimax/minimax-latest":
    context_window: 131072
    max_output_tokens: 16384
    display_name: "MiniMax Latest (九天)"
    description: "MiniMax Latest via 九天"

  "minimax/minimax-m2.5":
    context_window: 131072
    max_output_tokens: 16384
    display_name: "MiniMax M2.5 (九天)"
    description: "MiniMax M2.5 via 九天"

  "minimax/minimax-m2.7":
    context_window: 131072
    max_output_tokens: 16384
    display_name: "MiniMax M2.7 (九天)"
    description: "MiniMax M2.7 via 九天"

  "z.ai/glm-5":
    context_window: 131072
    max_output_tokens: 16384
    display_name: "GLM-5 (九天)"
    description: "Z.AI GLM-5 via 九天"

  "z.ai/glm-5.1":
    context_window: 131072
    max_output_tokens: 16384
    display_name: "GLM-5.1 (九天)"
    description: "Z.AI GLM-5.1 via 九天"

  "nvidia/nemotron-3-super-120b-a12b":
    context_window: 131072
    max_output_tokens: 16384
    display_name: "Nemotron-3 Super (九天)"
    description: "NVIDIA Nemotron-3 Super 120B via 九天"

  "stepfun/step-3.5-flash":
    context_window: 131072
    max_output_tokens: 16384
    display_name: "Step 3.5 Flash (九天)"
    description: "StepFun Step 3.5 Flash via 九天"

  "openai/gpt-oss-120b":
    context_window: 131072
    max_output_tokens: 16384
    display_name: "GPT-OSS 120B (九天)"
    description: "OpenAI GPT-OSS 120B via 九天"

  "jiutian/jiutian-lan-236b":
    context_window: 131072
    max_output_tokens: 16384
    display_name: "九天 LAN 236B"
    description: "九天自研 LAN 236B 模型"
'''

XIAOMI_MODELS = '''
  mimo-v2-omni:
    context_window: 256000
    max_output_tokens: 16384
    display_name: "MiMo V2 Omni (小米)"
    description: "小米 MiMo V2 Omni - 多模态视觉模型，256K 上下文"

  mimo-v2.5-pro:
    context_window: 1000000
    max_output_tokens: 16384
    display_name: "MiMo V2.5 Pro (小米)"
    description: "小米 MiMo V2.5 Pro - 1M 上下文"

  mimo-v2.5:
    context_window: 1000000
    max_output_tokens: 16384
    display_name: "MiMo V2.5 (小米)"
    description: "小米 MiMo V2.5 - 1M 上下文"

  mimo-v2-pro:
    context_window: 1000000
    max_output_tokens: 16384
    display_name: "MiMo V2 Pro (小米)"
    description: "小米 MiMo V2 Pro - 1M 上下文"
'''

DEEPSEEK_PROVIDER = '''
  deepseek:
    base_url: "https://api.deepseek.com/anthropic"
    api_key: "{api_key}"
    version: "2023-06-01"
    user_agent: "moonbridge/1.0"
    offers:
      - model: deepseek-v4-flash
        pricing:
          input_price: 0.14
          output_price: 0.28
          cache_write_price: 0.14
          cache_read_price: 0.0028
      - model: deepseek-v4-pro
        pricing:
          input_price: 2
          output_price: 8
          cache_write_price: 1
          cache_read_price: 0.2
'''

JIUTIAN_PROVIDER = '''
  jiutian:
    base_url: "https://jiutian.10086.cn/largemodel/moma/api"
    api_key: "{api_key}"
    version: "2023-06-01"
    protocol: "openai-chat"
    api_version: "v3"
    user_agent: "moonbridge/1.0"
    offers:
      - model: deepseek/deepseek-v3
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
      - model: deepseek/deepseek-v32
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
      - model: deepseek/deepseek-r1
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
      - model: deepseek/deepseek-v4-flash
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
      - model: qwen/qwen3.5-27b
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
      - model: qwen/qwen3.6-35b
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
      - model: qwen/qwen3-235b-a22b-2507
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
      - model: qwen/qwen3.5-397b-a17b
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
      - model: qwen/qwen3-next-80b-a3b-instruct
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
      - model: moonshotai/kimi-k2.5-thinking
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
      - model: moonshotai/kimi-k2.6
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
      - model: minimax/minimax-latest
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
      - model: minimax/minimax-m2.5
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
      - model: minimax/minimax-m2.7
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
      - model: z.ai/glm-5
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
      - model: z.ai/glm-5.1
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
      - model: nvidia/nemotron-3-super-120b-a12b
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
      - model: stepfun/step-3.5-flash
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
      - model: openai/gpt-oss-120b
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
      - model: jiutian/jiutian-lan-236b
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
'''

XIAOMI_PROVIDER = '''
  xiaomi:
    base_url: "https://token-plan-sgp.xiaomimimo.com"
    api_key: "{api_key}"
    version: "2023-06-01"
    protocol: "openai-chat"
    user_agent: "moonbridge/1.0"
    offers:
      - model: mimo-v2-omni
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
      - model: mimo-v2.5-pro
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
      - model: mimo-v2.5
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
      - model: mimo-v2-pro
        pricing: {{input_price: 0, output_price: 0, cache_write_price: 0, cache_read_price: 0}}
'''

DEEPSEEK_ROUTES = '''
  moonbridge-flash:
    model: deepseek-v4-flash
    provider: deepseek
  moonbridge:
    model: deepseek-v4-pro
    provider: deepseek
'''

JIUTIAN_ROUTES = '''
  jt-ds-v3:
    model: deepseek/deepseek-v3
    provider: jiutian
  jt-ds-v32:
    model: deepseek/deepseek-v32
    provider: jiutian
  jt-ds-r1:
    model: deepseek/deepseek-r1
    provider: jiutian
  jt-ds-v4-flash:
    model: deepseek/deepseek-v4-flash
    provider: jiutian
  jt-qwen3.5-27b:
    model: qwen/qwen3.5-27b
    provider: jiutian
  jt-qwen3.6-35b:
    model: qwen/qwen3.6-35b
    provider: jiutian
  jt-qwen3-235b:
    model: qwen/qwen3-235b-a22b-2507
    provider: jiutian
  jt-qwen3.5-397b:
    model: qwen/qwen3.5-397b-a17b
    provider: jiutian
  jt-qwen3-next-80b:
    model: qwen/qwen3-next-80b-a3b-instruct
    provider: jiutian
  jt-kimi-k2.5:
    model: moonshotai/kimi-k2.5-thinking
    provider: jiutian
  jt-kimi-k2.6:
    model: moonshotai/kimi-k2.6
    provider: jiutian
  jt-minimax-latest:
    model: minimax/minimax-latest
    provider: jiutian
  jt-minimax-m2.5:
    model: minimax/minimax-m2.5
    provider: jiutian
  jt-minimax-m2.7:
    model: minimax/minimax-m2.7
    provider: jiutian
  jt-glm-5:
    model: z.ai/glm-5
    provider: jiutian
  jt-glm-5.1:
    model: z.ai/glm-5.1
    provider: jiutian
  jt-nemotron:
    model: nvidia/nemotron-3-super-120b-a12b
    provider: jiutian
  jt-step-3.5-flash:
    model: stepfun/step-3.5-flash
    provider: jiutian
  jt-gpt-oss-120b:
    model: openai/gpt-oss-120b
    provider: jiutian
  jt-jiutian-lan:
    model: jiutian/jiutian-lan-236b
    provider: jiutian
'''

XIAOMI_ROUTES = '''
  xm-omni:
    model: mimo-v2-omni
    provider: xiaomi
  xm-v2.5-pro:
    model: mimo-v2.5-pro
    provider: xiaomi
  xm-v2.5:
    model: mimo-v2.5
    provider: xiaomi
  xm-v2-pro:
    model: mimo-v2-pro
    provider: xiaomi
'''

# Bare model ID routes (Codex may send raw model names)
JIUTIAN_BARE_ROUTES = '''
  "deepseek/deepseek-v3":
    model: deepseek/deepseek-v3
    provider: jiutian
  "deepseek/deepseek-v32":
    model: deepseek/deepseek-v32
    provider: jiutian
  "deepseek/deepseek-r1":
    model: deepseek/deepseek-r1
    provider: jiutian
  "deepseek/deepseek-v4-flash":
    model: deepseek/deepseek-v4-flash
    provider: jiutian
  "qwen/qwen3.5-27b":
    model: qwen/qwen3.5-27b
    provider: jiutian
  "qwen/qwen3.6-35b":
    model: qwen/qwen3.6-35b
    provider: jiutian
  "qwen/qwen3-235b-a22b-2507":
    model: qwen/qwen3-235b-a22b-2507
    provider: jiutian
  "qwen/qwen3.5-397b-a17b":
    model: qwen/qwen3.5-397b-a17b
    provider: jiutian
  "qwen/qwen3-next-80b-a3b-instruct":
    model: qwen/qwen3-next-80b-a3b-instruct
    provider: jiutian
  "moonshotai/kimi-k2.5-thinking":
    model: moonshotai/kimi-k2.5-thinking
    provider: jiutian
  "moonshotai/kimi-k2.6":
    model: moonshotai/kimi-k2.6
    provider: jiutian
  "minimax/minimax-latest":
    model: minimax/minimax-latest
    provider: jiutian
  "minimax/minimax-m2.5":
    model: minimax/minimax-m2.5
    provider: jiutian
  "minimax/minimax-m2.7":
    model: minimax/minimax-m2.7
    provider: jiutian
  "z.ai/glm-5":
    model: z.ai/glm-5
    provider: jiutian
  "z.ai/glm-5.1":
    model: z.ai/glm-5.1
    provider: jiutian
  "nvidia/nemotron-3-super-120b-a12b":
    model: nvidia/nemotron-3-super-120b-a12b
    provider: jiutian
  "stepfun/step-3.5-flash":
    model: stepfun/step-3.5-flash
    provider: jiutian
  "openai/gpt-oss-120b":
    model: openai/gpt-oss-120b
    provider: jiutian
  "jiutian/jiutian-lan-236b":
    model: jiutian/jiutian-lan-236b
    provider: jiutian
'''

XIAOMI_BARE_ROUTES = '''
  mimo-v2-omni:
    model: mimo-v2-omni
    provider: xiaomi
  mimo-v2.5-pro:
    model: mimo-v2.5-pro
    provider: xiaomi
  mimo-v2.5:
    model: mimo-v2.5
    provider: xiaomi
  mimo-v2-pro:
    model: mimo-v2-pro
    provider: xiaomi
'''

AUTO_REVIEW_ROUTE = '''
  codex-auto-review:
    model: deepseek-v4-pro
    provider: deepseek
'''


def ask_yes_no(prompt, default=True):
    default_str = "Y/n" if default else "y/N"
    resp = input(f"{prompt} [{default_str}]: ").strip().lower()
    if not resp:
        return default
    return resp in ("y", "yes")


def ask_key(prompt):
    key = input(f"{prompt}: ").strip()
    if not key:
        print("  -> 跳过（不配置此 Provider）")
        return None
    return key


def main():
    parser = argparse.ArgumentParser(description="Moon Bridge 多 Provider 配置生成器")
    parser.add_argument("--output", "-o", default=".",
                        help="输出目录（默认当前目录）")
    parser.add_argument("--dry-run", action="store_true",
                        help="只预览不写文件")
    args = parser.parse_args()

    print("=" * 60)
    print("  Moon Bridge 多 Provider 配置生成器")
    print("=" * 60)
    print()
    print("此工具将引导你配置 Moon Bridge 的多 Provider 支持。")
    print("你可以选择配置一个或多个 Provider。")
    print()
    print("提示：")
    print("  - DeepSeek Key 格式: sk-xxxxxxxxxxxxxxxx")
    print("  - 九天 Key 格式: JWT Token（长字符串）")
    print("  - 小米 Key 格式: tp-xxxxxxxxxxxxxxxx")
    print()

    # 收集配置
    configs = {}

    # Provider A: DeepSeek
    configs["deepseek"] = ask_key("DeepSeek API Key")

    # Provider B: Jiutian
    configs["jiutian"] = ask_key("九天 JWT Key")

    # Provider C: Xiaomi
    configs["xiaomi"] = ask_key("小米 MiMo API Key")

    if not any(configs.values()):
        print("错误：至少需要配置一个 Provider。")
        sys.exit(1)

    # Determine default model
    if configs["deepseek"]:
        default_model = "moonbridge"
    elif configs["xiaomi"]:
        default_model = "xm-v2.5-pro"
    else:
        default_model = "jt-ds-v3"

    print()
    print(f"默认模型设为: {default_model}")
    print()

    # Build sections
    models_parts = []
    providers_parts = []
    routes_parts = []

    if configs["deepseek"]:
        models_parts.append("  # ===== Provider A：自有 DeepSeek Key =====")
        models_parts.append(DEEPSEEK_MODELS.strip())
        providers_parts.append("  # Provider A：DeepSeek 自有 Key")
        providers_parts.append(DEEPSEEK_PROVIDER.format(api_key=configs["deepseek"]).strip())
        routes_parts.append("  # DeepSeek 自有 Key")
        routes_parts.append(DEEPSEEK_ROUTES.strip())

    if configs["jiutian"]:
        models_parts.append("")
        models_parts.append("  # ===== Provider B：九天（OpenAI Chat Completions）=====")
        models_parts.append(JIUTIAN_MODELS.strip())
        providers_parts.append("")
        providers_parts.append("  # Provider B：九天")
        providers_parts.append(JIUTIAN_PROVIDER.format(api_key=configs["jiutian"]).strip())
        routes_parts.append("")
        routes_parts.append("  # 九天")
        routes_parts.append(JIUTIAN_ROUTES.strip())
        routes_parts.append("")
        routes_parts.append("  # 九天 - 裸模型 ID 路由")
        routes_parts.append(JIUTIAN_BARE_ROUTES.strip())

    if configs["xiaomi"]:
        models_parts.append("")
        models_parts.append("  # ===== Provider C：小米 MiMo =====")
        models_parts.append(XIAOMI_MODELS.strip())
        providers_parts.append("")
        providers_parts.append("  # Provider C：小米 MiMo")
        providers_parts.append(XIAOMI_PROVIDER.format(api_key=configs["xiaomi"]).strip())
        routes_parts.append("")
        routes_parts.append("  # 小米 MiMo")
        routes_parts.append(XIAOMI_ROUTES.strip())
        routes_parts.append("")
        routes_parts.append("  # 小米 MiMo - 裸模型 ID 路由")
        routes_parts.append(XIAOMI_BARE_ROUTES.strip())

    # codex-auto-review (always add if deepseek is configured)
    if configs["deepseek"]:
        routes_parts.append("")
        routes_parts.append("  # Codex 内置自动审核模型 — 必须配置！")
        routes_parts.append(AUTO_REVIEW_ROUTE.strip())
    elif configs["xiaomi"]:
        routes_parts.append("")
        routes_parts.append("  # Codex 内置自动审核模型 — 使用小米")
        routes_parts.append("  codex-auto-review:")
        routes_parts.append("    model: mimo-v2.5-pro")
        routes_parts.append("    provider: xiaomi")

    config_content = CONFIG_TEMPLATE.format(
        default_model=default_model,
        models_section="\n".join(models_parts),
        providers_section="\n".join(providers_parts),
        routes_section="\n".join(routes_parts),
    )

    if args.dry_run:
        print("=" * 60)
        print("预览 config.yml：")
        print("=" * 60)
        print(config_content)
    else:
        out_path = Path(args.output) / "config.yml"
        out_path.write_text(config_content)
        print(f"配置已写入: {out_path}")
        print()
        print("下一步：")
        print(f"  1. 检查配置: cat {out_path}")
        print(f"  2. 创建数据目录: mkdir -p ~/moon-bridge/data")
        print(f"  3. 启动 Moon Bridge: cd ~/moon-bridge && go run ./cmd/moonbridge --config {out_path}")
        print(f"  4. 测试连通性: ./test_providers.sh")


if __name__ == "__main__":
    main()
