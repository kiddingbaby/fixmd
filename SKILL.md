---
name: fixmd
description: 脚本优先的 Markdown 质量检查与自动修复。默认先自动修复，再做 markdownlint 复检；缺省配置走临时基线，不污染目标仓。
allowed-tools: Bash(git *), Bash(markdownlint *), Bash(markdownlint-cli2 *), Bash(scripts/fixmd.sh *)
---

# fixmd

只走脚本主路径。先自动修复，再校验；仅在脚本无法完成时才交给 agent 精修。

## Prerequisite check (required)

先确认脚本是否可执行：

```bash
bash scripts/fixmd.sh --help
```

脚本内部工具链策略：

- `markdownlint-cli2/markdownlint` 优先本机
- 本机缺失直接报错并给安装提示
- 不使用 `npx`
- 规则策略：`default: true`（全 MDXXX 规则启用）+ 少量可解释 override（见下）
- repo root 已有 markdownlint 配置时直接复用
- repo 无配置时，运行期使用临时 fallback 基线，不写入目标仓
- 仅 `--install-config` 才会安装 `.markdownlint.jsonc` 到 repo root
- legacy `.markdownlintrc` 仅做 best-effort 兼容，建议迁移到 `.markdownlint.jsonc`
- 退出码：`0=通过/跳过`，`1=检查失败`，`2=参数错误`，`4=工具缺失`

当前识别的 repo root 配置源：

- `.markdownlint.{jsonc,json,yaml,yml,cjs,mjs}`
- `.markdownlint-cli2.{jsonc,yaml,cjs,mjs}`
- `package.json#markdownlint-cli2`
- `.markdownlintrc`（legacy）

## Quick start

```bash
bash scripts/fixmd.sh --target "$(pwd)" --json
```

显式安装基线到仓库：

```bash
bash scripts/fixmd.sh --target "$(pwd)" --install-config
```

## Core workflow

1. 收集仓库 Markdown 文件（git tracked 优先）。
2. 解析 repo root 配置来源：已有配置优先，否则走临时 fallback；仅显式 `--install-config` 时落仓。
3. 按配置兼容关系选择 `markdownlint-cli2` 或 `markdownlint`。
4. 执行 markdownlint 自动修复。
5. 重新执行 markdownlint 校验。
6. 若 markdownlint 失败：直接结束并标记 `needs_agent_refine=true`。
7. 输出简洁报告（JSON/text）。

## Agent handoff rule

仅在以下情况交给 agent：

- `data.fix.needs_agent_refine=true`
- `data.failures[]` 仍有 markdownlint 无法自动修复项

agent 只处理 `failures[]` 涉及文件，修完后必须重跑脚本。
禁止让 agent 大范围改写无关 Markdown 文件。

## Built-in rule policy

规则目标：Agent 理解体验优先，同时保留社区通行风格约束。

全量基线：

- `default: true`（覆盖官方 `Rules.md` 全规则，当前为 53 条 MDXXX）

内置 override（跨仓库可复用）：

- `MD013`: `line_length=160`, `headings/code_blocks/tables=false`
- `MD024`: `siblings_only=true`
- `MD025`: 保留 H1 约束并兼容 frontmatter title
- `MD029`: `style=ordered`
- `MD033`: `false`（允许必要内联 HTML）
- `MD040`: `true`（要求 fenced code 指定语言）
- `MD041`: `false`（frontmatter/平台模板兼容）
- `MD046`: `fenced`
- `MD048`: `backtick`

规则来源：

- 官方全规则索引：`https://github.com/DavidAnson/markdownlint/blob/main/doc/Rules.md`
- 关键参数页：`md013.md` / `md029.md` / `md040.md`

## Output contract (`--json`)

- `schema_version`: `fixmd/v1`
- `tool`: `fixmd`
- `status`: `ok|error`
- `data.config.source`: `existing|temporary|installed`
- `data.config.kind`: `markdownlint|markdownlint-cli2|package-json|legacy-rc|fallback`
- `data.fix.applied|needs_agent_refine`
- `data.checks.markdownlint.status`: `ok|error|skipped`
- `data.checks.markdownlint.toolchain`: `local|missing`
- `data.hints[]`: 下一步动作
- `data.failures[]`: 可定位失败摘要

schema 真源：`contracts/result.schema.json`
