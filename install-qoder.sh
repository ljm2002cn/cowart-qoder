#!/usr/bin/env bash
# =============================================================================
# Cowart for Qoder — 一键安装脚本
# 安装 Cowart 画布插件（仓库 + 依赖 + MCP server + Skills）
#
# 用法:
#   bash install-qoder.sh
#
# 或一行命令:
#   curl -fsSL https://raw.githubusercontent.com/ljm2002cn/Cowart-for-Qoder/main/install-qoder.sh | bash
#
# 项目地址: https://github.com/ljm2002cn/Cowart-for-Qoder
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[info]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ok]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC}  $*"; }
fail()  { echo -e "${RED}[fail]${NC}  $*"; exit 1; }

COWART_DIR="${COWART_DIR:-$HOME/plugins/cowart}"
QODER_SKILLS_DIR="$HOME/.qoder/skills"
COWART_REPO="https://github.com/zhongerxin/cowart.git"

# ── 检测平台，设置 mcp.json 路径 ──
case "$(uname -s)" in
  Darwin)  QODER_MCP_JSON="$HOME/Library/Application Support/Qoder/SharedClientCache/mcp.json" ;;
  Linux)   QODER_MCP_JSON="${XDG_CONFIG_HOME:-$HOME/.config}/Qoder/SharedClientCache/mcp.json" ;;
  MINGW*|MSYS*|CYGWIN*)
    QODER_MCP_JSON="$APPDATA/Qoder/SharedClientCache/mcp.json" ;;
  *)       QODER_MCP_JSON="$HOME/.config/Qoder/SharedClientCache/mcp.json" ;;
esac

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Cowart for Qoder — 一键安装${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""

# ── 0. 前置检查 ──
command -v node >/dev/null 2>&1 || fail "未找到 node，请先安装 Node.js (>= 18)"
command -v npm  >/dev/null 2>&1 || fail "未找到 npm"
command -v git  >/dev/null 2>&1 || fail "未找到 git"
NODE_VER=$(node -v | sed 's/v//' | cut -d. -f1)
[ "$NODE_VER" -ge 18 ] || fail "Node.js 版本过低 (v$NODE_VER)，需要 >= 18"
ok "Node.js $(node -v)"

# ── 1. Clone 仓库 ──
if [ -d "$COWART_DIR/.git" ]; then
  ok "仓库已存在: $COWART_DIR (跳过 clone)"
  info "拉取最新代码..."
  cd "$COWART_DIR" && git pull --quiet 2>/dev/null && ok "已更新" || warn "git pull 失败，使用现有版本"
else
  info "Clone 仓库到 $COWART_DIR ..."
  mkdir -p "$(dirname "$COWART_DIR")"
  git clone --quiet "$COWART_REPO" "$COWART_DIR"
  ok "仓库 clone 完成"
fi

# ── 2. 安装依赖 + 构建 ──
cd "$COWART_DIR"
if [ ! -d node_modules/fractional-indexing ]; then
  info "安装 npm 依赖..."
  npm install --quiet && ok "依赖安装完成"
else
  ok "npm 依赖已存在"
fi
if [ ! -d dist ]; then
  info "构建画布前端..."
  npm run build 2>/dev/null && ok "构建完成"
else
  ok "构建产物已存在"
fi

# ── 3. 配置 MCP server ──
info "配置 Qoder MCP server..."
mkdir -p "$(dirname "$QODER_MCP_JSON")"

node -e "
const fs = require('fs');
const file = process.argv[1];
const cowartDir = process.argv[2];
const cowartServer = { command: 'bash', args: [cowartDir + '/scripts/start-mcp.sh'], cwd: cowartDir };
let config = {};
try { config = JSON.parse(fs.readFileSync(file, 'utf8')); } catch(e) {}
if (!config.mcpServers) config.mcpServers = {};
if (config.mcpServers.cowart) { console.log('  MCP 配置已存在（跳过）'); process.exit(0); }
config.mcpServers.cowart = cowartServer;
fs.writeFileSync(file, JSON.stringify(config, null, 2) + '\n');
console.log('  MCP 配置已写入');
" "$QODER_MCP_JSON" "$COWART_DIR"
ok "MCP server 配置完成"

# ── 4. 安装 Skills ──
info "安装 Qoder Skills..."
mkdir -p "$QODER_SKILLS_DIR"

generate_skill() {
  local name="$1" desc="$2"
  shift 2
  local content="$*"
  mkdir -p "$QODER_SKILLS_DIR/$name"
  cat > "$QODER_SKILLS_DIR/$name/SKILL.md" << EOF
---
name: $name
description: $desc
---

$content
EOF
  ok "  $name"
}

# cowart-open-canvas
generate_skill "cowart-open-canvas" \
  "Open the Cowart local infinite canvas powered by tldraw. Use when the user asks to open, launch, or view the Cowart canvas, or wants a visual whiteboard for their project." \
  "# Cowart Open Canvas

## Workflow

1. Start the Cowart canvas web service (run as background process):

\`\`\`bash
bash $COWART_DIR/scripts/start-canvas.sh /path/to/user/project
\`\`\`

Use the user's current workspace directory. Default URL: \`http://127.0.0.1:43217/\`

2. Open the canvas with RunPreview:

\`\`\`
RunPreview(url=\"http://127.0.0.1:43217\", name=\"Cowart Canvas\")
\`\`\`

3. Tell the user the canvas is ready.

## Canvas Data

\`\`\`
<project>/canvas/pages/<page-id>/cowart-canvas.json
<project>/canvas/pages/<page-id>/assets/
\`\`\`

## Constraints

- Keep the canvas service running in background for other Cowart skills.
- Do not inspect canvas files unless opening fails or user explicitly asks."

# cowart-image-gen
generate_skill "cowart-image-gen" \
  "Generate AI images and insert them into the Cowart canvas. Use when the user asks to create, fill, replace, or place an AI-generated image on the Cowart canvas." \
  "# Cowart Image Gen

## Preconditions

Cowart service should be running at \`http://127.0.0.1:43217\`. If not, use \`cowart-open-canvas\` skill first.

## Workflow

1. Read selection via MCP tool \`get_cowart_selection\` or:
   \`\`\`bash
   curl -s http://127.0.0.1:43217/api/selection
   \`\`\`

2. Check for AI image holder (\`meta.cowartAiImageHolder: true\`).

3. Determine target size from holder \`props.w\`/\`props.h\` or use defaults.

4. Generate image with \`ImageGen\` tool, including target size and aspect ratio in prompt.

5. Copy generated image to \`<project>/canvas/pages/<page-dir>/assets/\` with timestamped filename.

6. Insert via MCP \`insert_cowart_image\` tool:
   \`\`\`json
   { \"imagePath\": \"/path/to/image.png\", \"projectDir\": \"/project\", \"cowartUrl\": \"http://127.0.0.1:43217\", \"anchorShapeId\": \"<holder-id>\", \"placement\": \"right\", \"margin\": 10, \"matchAnchor\": true }
   \`\`\`

7. Confirm shape id, dimensions, and saved path.

## Notes

- Frame holders: insert as child (parentId=holder, x/y/rotation=0).
- Do not delete holder unless asked. Never overwrite existing assets."

# cowart-image-edit
generate_skill "cowart-image-edit" \
  "Generate revised AI images from user-supplied Cowart annotation screenshots. Use when the user provides screenshots showing annotations, arrows, or edit notes and wants revised images." \
  "# Cowart Image Edit

## Preconditions

Cowart service should be running at \`http://127.0.0.1:43217\`. If not, use \`cowart-open-canvas\` skill first.

## Workflow

1. Read user-provided screenshot(s). Each is an independent edit brief.

2. Extract edit requirements: read annotation labels, arrows, notes. Ignore toolbars and UI chrome.

3. Use the clean underlying image as visual base. If screenshot is too low-res, ask user for cleaner source.

4. Generate revised image with \`ImageGen\`:
   - Apply annotations as edit instructions
   - Preserve original composition, aspect ratio, style
   - Remove all annotation artifacts
   - Save as \`annotation-edit-YYYYMMDD-HHMMSS.png\`

5. Insert beside original via MCP \`insert_cowart_image\`:
   \`\`\`json
   { \"imagePath\": \"/path/to/edit.png\", \"projectDir\": \"/project\", \"cowartUrl\": \"http://127.0.0.1:43217\", \"anchorShapeId\": \"<source-id>\", \"placement\": \"right\", \"margin\": 10, \"matchAnchor\": true, \"shapeMeta\": { \"cowartGeneratedFromAnnotationEdit\": true } }
   \`\`\`

6. Place to the right of anchor (~10 units margin). Match anchor size. Do not put inside AI frame.

## Guardrails

- Never replace original unless asked. Never delete annotations.
- Never auto-capture canvas for edit intent — use user screenshots only."

# ── 5. 验证 ──
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  安装验证${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"

ERRORS=0
[ -d "$COWART_DIR/.git" ] && ok "仓库" || { warn "仓库缺失"; ERRORS=$((ERRORS+1)); }
[ -d "$COWART_DIR/node_modules/fractional-indexing" ] && ok "npm 依赖" || { warn "依赖缺失"; ERRORS=$((ERRORS+1)); }
[ -d "$COWART_DIR/dist" ] && ok "前端构建" || { warn "构建缺失"; ERRORS=$((ERRORS+1)); }
[ -f "$QODER_MCP_JSON" ] && grep -q '"cowart"' "$QODER_MCP_JSON" && ok "MCP 配置" || { warn "MCP 配置缺失"; ERRORS=$((ERRORS+1)); }
for skill in cowart-open-canvas cowart-image-gen cowart-image-edit; do
  [ -f "$QODER_SKILLS_DIR/$skill/SKILL.md" ] && ok "Skill: $skill" || { warn "缺失: $skill"; ERRORS=$((ERRORS+1)); }
done

echo ""
if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  ✅ 安装完成！${NC}"
  echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
  echo ""
  echo "  下一步："
  echo "    1. 重启 Qoder（或开启新对话）"
  echo "    2. 说「打开 Cowart 画布」即可使用"
  echo ""
  echo "  已安装："
  echo "    • MCP:   cowart (get_cowart_selection, insert_cowart_image)"
  echo "    • Skill: cowart-open-canvas"
  echo "    • Skill: cowart-image-gen"
  echo "    • Skill: cowart-image-edit"
  echo "    • 仓库:  $COWART_DIR"
  echo ""
else
  echo -e "${YELLOW}  ⚠️  安装完成，但有 $ERRORS 项需检查${NC}"
  echo ""
fi
