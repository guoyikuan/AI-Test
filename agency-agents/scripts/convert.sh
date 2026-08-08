#!/usr/bin/env bash
#
# convert.sh — Convert agency agent .md files into tool-specific formats.
#
# Reads all agent files from the standard category directories and outputs
# converted files to integrations/<tool>/. Run this to regenerate all
# integration files after adding or modifying agents.
#
# Usage:
#   ./scripts/convert.sh [--tool <name>] [--out <dir>] [--parallel] [--jobs N] [--help]
#
# Tools:
#   antigravity  — Antigravity skill files (~/.gemini/config/skills/)
#   gemini-cli   — Gemini CLI subagent files (~/.gemini/agents/*.md)
#   opencode     — OpenCode agent files (.opencode/agents/*.md)
#   cursor       — Cursor rule files (.cursor/rules/*.mdc)
#   aider        — Single CONVENTIONS.md for Aider
#   windsurf     — Single .windsurfrules for Windsurf
#   openclaw     — OpenClaw workspaces (integrations/openclaw/<agent>/SOUL.md)
#   qwen         — Qwen Code SubAgent files (~/.qwen/agents/*.md)
#   zcode        — ZCode agent files (.zcode/agents/*.md · ~/.config/zcode/agents/*.md)
#   kimi         — Kimi Code CLI agent files (~/.config/kimi/agents/)
#   codex        — Codex custom agent TOML files (~/.codex/agents/*.toml)
#   osaurus      — Osaurus skill files (~/.osaurus/skills/<name>/SKILL.md)
#   hermes       — Hermes lazy-router plugin (one plugin + on-disk agent index)
#   vibe         — Mistral Vibe agent TOML + prompt files (~/.vibe/agents/*.toml + ~/.vibe/prompts/*.md)
#   claude-code  — Claude Code identity agents (agents/<slug>.md)
#   copilot      — Copilot identity agents (agents/<slug>.md)
#   all          — All tools (default)
#
# Output is written to integrations/<tool>/ relative to the repo root.
# This script never touches user config dirs — see install.sh for that.
#
#   --parallel       When tool is 'all', run independent tools in parallel (output order may vary).
#   --jobs N         Max parallel jobs when using --parallel (default: nproc or 4).

set -euo pipefail

# --- Colour helpers ---
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
  GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[0;31m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  GREEN=''; YELLOW=''; RED=''; BOLD=''; RESET=''
fi

info()    { printf "${GREEN}[OK]${RESET}  %s\n" "$*"; }
warn()    { printf "${YELLOW}[!!]${RESET}  %s\n" "$*"; }
error()   { printf "${RED}[ERR]${RESET} %s\n" "$*" >&2; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }

# Progress bar: [=======>    ] 3/8 (tqdm-style)
progress_bar() {
  local current="$1" total="$2" width="${3:-20}" i filled empty
  (( total > 0 )) || return
  filled=$(( width * current / total ))
  empty=$(( width - filled ))
  printf "\r  ["
  for (( i=0; i<filled; i++ )); do printf "="; done
  if (( filled < width )); then printf ">"; (( empty-- )); fi
  for (( i=0; i<empty; i++ )); do printf " "; done
  printf "] %s/%s" "$current" "$total"
  [[ -t 1 ]] || printf "\n"
}

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$REPO_ROOT/integrations"
TODAY="$(date +%Y-%m-%d)"
SOURCE_MANIFEST=""
SOURCE_MANIFEST_OWNED=false

# Shared helpers (get_field, get_body, slugify, ...)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

AGENT_DIRS=(
  academic design engineering finance game-development gis healthcare marketing paid-media product project-management
  sales security spatial-computing specialized support testing
)

# --- Usage ---
usage() {
  sed -n '3,27p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# Default parallel job count (nproc on Linux; sysctl on macOS when nproc missing)
parallel_jobs_default() {
  local n
  n=$(nproc 2>/dev/null) && [[ -n "$n" ]] && echo "$n" && return
  n=$(sysctl -n hw.ncpu 2>/dev/null) && [[ -n "$n" ]] && echo "$n" && return
  echo 4
}

sha256_file() {
  local file="$1"
  local digest
  digest="$(shasum -a 256 -- "$file")" || return $?
  digest="${digest%% *}"
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || {
    error "Invalid SHA-256 result for source: $file"
    return 1
  }
  printf '%s' "$digest"
}

build_source_manifest() {
  local target="$1"
  local candidates sorted dir dirpath file first_line name digest status
  : > "$target" || return $?

  candidates="$(mktemp)" || return $?
  sorted="$(mktemp)" || {
    local status=$?
    rm -f "$candidates"
    return "$status"
  }

  for dir in "${AGENT_DIRS[@]}"; do
    dirpath="$REPO_ROOT/$dir"
    if [[ -L "$dirpath" || ! -d "$dirpath" ]]; then
      error "Invalid source directory: $dirpath"
      rm -f "$candidates" "$sorted"
      return 1
    fi
    find "$dirpath" -name "*.md" -print0 > "$candidates" || {
      status=$?
      error "Failed to enumerate source directory: $dirpath"
      rm -f "$candidates" "$sorted"
      return "$status"
    }
    sort -z "$candidates" > "$sorted" || {
      status=$?
      error "Failed to sort source directory: $dirpath"
      rm -f "$candidates" "$sorted"
      return "$status"
    }

    while IFS= read -r -d '' file; do
      if [[ -L "$file" || ! -f "$file" || ! -r "$file" ]]; then
        error "Invalid source file: $file"
        rm -f "$candidates" "$sorted"
        return 1
      fi
      first_line="$(head -n 1 -- "$file")" || {
        local status=$?
        error "Failed to read source header: $file"
        rm -f "$candidates" "$sorted"
        return "$status"
      }
      [[ "$first_line" == "---" ]] || continue
      name="$(get_field "name" "$file")" || {
        local status=$?
        error "Failed to parse source name: $file"
        rm -f "$candidates" "$sorted"
        return "$status"
      }
      if [[ -z "$name" ]]; then
        error "Missing source name: $file"
        rm -f "$candidates" "$sorted"
        return 1
      fi
      digest="$(sha256_file "$file")" || {
        local status=$?
        rm -f "$candidates" "$sorted"
        return "$status"
      }
      printf '%s\0%s\0' "$file" "$digest" >> "$target" || {
        local status=$?
        rm -f "$candidates" "$sorted"
        return "$status"
      }
    done < "$sorted"
  done

  rm -f "$candidates" "$sorted"
}

verify_source_manifest() {
  local current
  current="$(mktemp)" || return $?
  build_source_manifest "$current" || {
    local status=$?
    rm -f "$current"
    return "$status"
  }
  if ! cmp -s "$SOURCE_MANIFEST" "$current"; then
    error "Source inventory changed after it was frozen"
    rm -f "$current"
    return 1
  fi
  rm -f "$current"
}

prepare_source_manifest() {
  if [[ -n "${AGENCY_CONVERT_SOURCE_MANIFEST:-}" ]]; then
    SOURCE_MANIFEST="$AGENCY_CONVERT_SOURCE_MANIFEST"
    if [[ -L "$SOURCE_MANIFEST" || ! -f "$SOURCE_MANIFEST" || ! -r "$SOURCE_MANIFEST" ]]; then
      error "Invalid frozen source manifest: $SOURCE_MANIFEST"
      return 1
    fi
  else
    SOURCE_MANIFEST="$(mktemp)" || return $?
    SOURCE_MANIFEST_OWNED=true
    build_source_manifest "$SOURCE_MANIFEST" || return $?
  fi
  verify_source_manifest || return $?
  export AGENCY_CONVERT_SOURCE_MANIFEST="$SOURCE_MANIFEST"
}

validate_frozen_source() {
  local file="$1" expected_digest="$2"
  local first_line name actual_digest
  if [[ -L "$file" || ! -f "$file" || ! -r "$file" ]]; then
    error "Frozen source is no longer readable: $file"
    return 1
  fi
  first_line="$(head -n 1 -- "$file")" || {
    local status=$?
    error "Failed to read frozen source header: $file"
    return "$status"
  }
  if [[ "$first_line" != "---" ]]; then
    error "Frozen source frontmatter changed: $file"
    return 1
  fi
  name="$(get_field "name" "$file")" || {
    local status=$?
    error "Failed to parse frozen source: $file"
    return "$status"
  }
  if [[ -z "$name" ]]; then
    error "Frozen source name is missing: $file"
    return 1
  fi
  actual_digest="$(sha256_file "$file")" || return $?
  if [[ "$actual_digest" != "$expected_digest" ]]; then
    error "Frozen source content changed: $file"
    return 1
  fi
}

# --- Frontmatter helpers: get_field / get_body / slugify now live in lib.sh ---

# Escape a value for a TOML basic string, including control characters that
# cannot appear raw in TOML source.
toml_escape_string() {
  printf '%s' "$1" | perl -0pe '
    s/\\/\\\\/g;
    s/"/\\"/g;
    s/\n/\\n/g;
    s/\r/\\r/g;
    s/\t/\\t/g;
    s/\f/\\f/g;
    s/\x08/\\b/g;
    s/([\x00-\x07\x0B\x0E-\x1F\x7F])/sprintf("\\u%04X", ord($1))/ge;
  '
}

# --- Per-tool converters ---

convert_antigravity() {
  local file="$1"
  local name description slug outdir outfile body

  name="$(get_field "name" "$file")" || return $?
  description="$(get_field "description" "$file")" || return $?
  slug="agency-$(slugify "$name")" || return $?
  body="$(get_governed_body "$file")" || return $?

  outdir="$OUT_DIR/antigravity/$slug"
  outfile="$outdir/SKILL.md"
  mkdir -p "$outdir"

  # Antigravity Agent-Skills SKILL.md — name + description frontmatter and the
  # persona as the body, installed into ~/.gemini/config/skills/ (global) or
  # <project>/.agents/skills/ (project). Standard fields only, so it stays a
  # valid Agent-Skills skill for any host (and deterministic — no date stamp).
  cat > "$outfile" <<HEREDOC
---
name: ${slug}
description: ${description}
---
${body}
HEREDOC
}

convert_osaurus() {
  local file="$1"
  local name description slug outdir outfile body

  name="$(get_field "name" "$file")" || return $?
  description="$(get_field "description" "$file")" || return $?
  slug="agency-$(slugify "$name")" || return $?
  body="$(get_governed_body "$file")" || return $?

  # Stage one dir per skill (install.sh copies into ~/.osaurus/skills/<name>/).
  outdir="$OUT_DIR/osaurus/$slug"
  outfile="$outdir/SKILL.md"
  mkdir -p "$outdir"

  # Osaurus skill format: the Anthropic "Agent Skills" SKILL.md — a directory
  # named for the skill containing a SKILL.md with name + description frontmatter
  # and the persona as the instruction body. Installs into ~/.osaurus/skills/.
  # Kept to the standard fields so it stays compatible with any Agent-Skills host.
  cat > "$outfile" <<HEREDOC
---
name: ${slug}
description: ${description}
---
${body}
HEREDOC
}

convert_codex() {
  local file="$1"
  local name description slug outfile body

  name="$(get_field "name" "$file")" || return $?
  description="$(get_field "description" "$file")" || return $?
  slug="$(slugify "$name")" || return $?
  body="$(get_governed_body "$file")" || return $?

  outfile="$OUT_DIR/codex/agents/${slug}.toml"
  mkdir -p "$(dirname "$outfile")"

  # Codex custom agent format: one TOML file per agent with minimal required
  # fields only. Use a TOML basic string so control characters in the source
  # body are encoded safely instead of producing invalid TOML.
  cat > "$outfile" <<HEREDOC
name = "$(toml_escape_string "$name")"
description = "$(toml_escape_string "$description")"
developer_instructions = "$(toml_escape_string "$body")"
HEREDOC
}

convert_gemini_cli() {
  local file="$1"
  local name description slug outdir outfile body

  name="$(get_field "name" "$file")" || return $?
  description="$(get_field "description" "$file")" || return $?
  slug="$(slugify "$name")" || return $?
  body="$(get_governed_body "$file")" || return $?

  # Gemini CLI subagent format: .md file in ~/.gemini/agents/
  outdir="$OUT_DIR/gemini-cli/agents"
  outfile="$outdir/${slug}.md"
  mkdir -p "$outdir"

  cat > "$outfile" <<HEREDOC
---
name: ${slug}
description: ${description}
---
${body}
HEREDOC
}

# Map known color names and normalize to OpenCode-safe #RRGGBB values.
resolve_opencode_color() {
  local c="$1"
  local mapped

  c="$(printf '%s' "$c" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"

  case "$c" in
    cyan)           mapped="#00FFFF" ;;
    blue)           mapped="#3498DB" ;;
    green)          mapped="#2ECC71" ;;
    red)            mapped="#E74C3C" ;;
    purple)         mapped="#9B59B6" ;;
    orange)         mapped="#F39C12" ;;
    teal)           mapped="#008080" ;;
    indigo)         mapped="#6366F1" ;;
    pink)           mapped="#E84393" ;;
    gold)           mapped="#EAB308" ;;
    amber)          mapped="#F59E0B" ;;
    neon-green)     mapped="#10B981" ;;
    neon-cyan)      mapped="#06B6D4" ;;
    metallic-blue)  mapped="#3B82F6" ;;
    yellow)         mapped="#EAB308" ;;
    violet)         mapped="#8B5CF6" ;;
    rose)           mapped="#F43F5E" ;;
    lime)           mapped="#84CC16" ;;
    gray)           mapped="#6B7280" ;;
    fuchsia)        mapped="#D946EF" ;;
    *)              mapped="$c" ;;
  esac

  if [[ "$mapped" =~ ^#[0-9a-fA-F]{6}$ ]]; then
    printf '#%s\n' "$(printf '%s' "${mapped#\#}" | tr '[:lower:]' '[:upper:]')"
    return
  fi

  if [[ "$mapped" =~ ^[0-9a-fA-F]{6}$ ]]; then
    printf '#%s\n' "$(printf '%s' "$mapped" | tr '[:lower:]' '[:upper:]')"
    return
  fi

  printf '#6B7280\n'
}

convert_opencode() {
  local file="$1"
  local name description color slug outfile body

  name="$(get_field "name" "$file")" || return $?
  description="$(get_field "description" "$file")" || return $?
  color="$(get_field "color" "$file")" || return $?
  color="$(resolve_opencode_color "$color")" || return $?
  slug="$(slugify "$name")" || return $?
  body="$(get_governed_body "$file")" || return $?

  outfile="$OUT_DIR/opencode/agents/${slug}.md"
  mkdir -p "$OUT_DIR/opencode/agents"

  # OpenCode agent format: .md with YAML frontmatter in .opencode/agents/.
  # Named colors are resolved to hex via resolve_opencode_color().
  cat > "$outfile" <<HEREDOC
---
name: ${name}
description: ${description}
mode: subagent
color: '${color}'
---
${body}
HEREDOC
}

convert_cursor() {
  local file="$1"
  local name description slug outfile body

  name="$(get_field "name" "$file")" || return $?
  description="$(get_field "description" "$file")" || return $?
  slug="$(slugify "$name")" || return $?
  body="$(get_governed_body "$file")" || return $?

  outfile="$OUT_DIR/cursor/rules/${slug}.mdc"
  mkdir -p "$OUT_DIR/cursor/rules"

  # Cursor .mdc format: description + globs + alwaysApply frontmatter
  cat > "$outfile" <<HEREDOC
---
description: ${description}
globs: ""
alwaysApply: false
---
${body}
HEREDOC
}

convert_openclaw() {
  local file="$1"
  local name description slug outdir body governance

  name="$(get_field "name" "$file")" || return $?
  if [[ -z "$name" ]]; then
    return 1
  fi
  description="$(get_field "description" "$file")" || return $?
  slug="$(slugify "$name")" || return $?
  body="$(get_body "$file")" || return $?
  governance="$(get_governance_prompt "$file")" || return $?

  outdir="$OUT_DIR/openclaw/$slug"
  mkdir -p "$outdir"

  # OpenClaw contract: AGENTS.md is resolved governance prompt only; SOUL.md
  # is the unmodified persona body. IDENTITY.md remains untouched.
  cat > "$outdir/AGENTS.md" <<HEREDOC
${governance}
HEREDOC
  printf '%s' "$body" > "$outdir/SOUL.md"

  # Write IDENTITY.md — emoji + name + vibe from frontmatter, fallback to description
  local emoji vibe
  emoji="$(get_field "emoji" "$file")" || return $?
  vibe="$(get_field "vibe" "$file")" || return $?

  if [[ -n "$emoji" && -n "$vibe" ]]; then
    cat > "$outdir/IDENTITY.md" <<HEREDOC
# ${emoji} ${name}
${vibe}
HEREDOC
  else
    cat > "$outdir/IDENTITY.md" <<HEREDOC
# ${name}
${description}
HEREDOC
  fi
}

convert_qwen() {
  local file="$1"
  local name description tools slug outfile body

  name="$(get_field "name" "$file")" || return $?
  description="$(get_field "description" "$file")" || return $?
  tools="$(get_field "tools" "$file")" || return $?
  slug="$(slugify "$name")" || return $?
  body="$(get_governed_body "$file")" || return $?

  outfile="$OUT_DIR/qwen/agents/${slug}.md"
  mkdir -p "$(dirname "$outfile")"

  # Qwen Code SubAgent format: .md with YAML frontmatter in ~/.qwen/agents/
  # name and description required; tools optional (only if present in source)
  if [[ -n "$tools" ]]; then
    cat > "$outfile" <<HEREDOC
---
name: ${slug}
description: ${description}
tools: ${tools}
---
${body}
HEREDOC
  else
    cat > "$outfile" <<HEREDOC
---
name: ${slug}
description: ${description}
---
${body}
HEREDOC
  fi
}

convert_zcode() {
  local file="$1"
  local name description tools slug outfile body

  name="$(get_field "name" "$file")" || return $?
  description="$(get_field "description" "$file")" || return $?
  tools="$(get_field "tools" "$file")" || return $?
  slug="$(slugify "$name")" || return $?
  body="$(get_governed_body "$file")" || return $?

  outfile="$OUT_DIR/zcode/agents/${slug}.md"
  mkdir -p "$(dirname "$outfile")"

  # ZCode agent format (Z.ai GLM harness): .md with YAML frontmatter in
  # .zcode/agents/ (project) or ~/.config/zcode/agents/ (global). name and
  # description required; tools optional (only if present in source). Byte-
  # identical to the qwen-md shape, which the Agency Agents app renders natively.
  if [[ -n "$tools" ]]; then
    cat > "$outfile" <<HEREDOC
---
name: ${slug}
description: ${description}
tools: ${tools}
---
${body}
HEREDOC
  else
    cat > "$outfile" <<HEREDOC
---
name: ${slug}
description: ${description}
---
${body}
HEREDOC
  fi
}

convert_kimi() {
  local file="$1"
  local name description slug outdir agent_file body

  name="$(get_field "name" "$file")" || return $?
  description="$(get_field "description" "$file")" || return $?
  slug="$(slugify "$name")" || return $?
  body="$(get_governed_body "$file")" || return $?

  outdir="$OUT_DIR/kimi/$slug"
  agent_file="$outdir/agent.yaml"
  mkdir -p "$outdir"

  # Kimi Code CLI agent format: YAML with separate system prompt file
  # Uses extend: default to inherit Kimi's default toolset
  cat > "$agent_file" <<HEREDOC
version: 1
agent:
  name: ${slug}
  extend: default
  system_prompt_path: ./system.md
HEREDOC

  # Write system prompt to separate file
  cat > "$outdir/system.md" <<HEREDOC
# ${name}

${description}

${body}
HEREDOC
}

convert_vibe() {
  local file="$1"
  local name description slug outdir agent_file prompt_file body

  name="$(get_field "name" "$file")" || return $?
  description="$(get_field "description" "$file")" || return $?
  slug="$(slugify "$name")" || return $?
  body="$(get_governed_body "$file")" || return $?

  # Mistral Vibe uses two files per agent:
  # 1. A TOML configuration file in ~/.vibe/agents/<slug>.toml
  # 2. A markdown prompt file in ~/.vibe/prompts/<slug>.md

  outdir="$OUT_DIR/vibe"
  agent_file="$outdir/agents/${slug}.toml"
  prompt_file="$outdir/prompts/${slug}.md"
  mkdir -p "$outdir/agents" "$outdir/prompts"

  # Write the TOML agent configuration
  cat > "$agent_file" <<HEREDOC
agent_type = "agent"
system_prompt_id = "${slug}"
HEREDOC

  # Write the markdown prompt file
  cat > "$prompt_file" <<HEREDOC
# ${name}

${description}

${body}
HEREDOC
}

convert_claude_code() {
  local file="$1"
  local name description slug outfile body

  name="$(get_field "name" "$file")" || return $?
  description="$(get_field "description" "$file")" || return $?
  slug="$(slugify "$name")" || return $?
  body="$(get_governed_body "$file")" || return $?

  outfile="$OUT_DIR/claude-code/agents/${slug}.md"
  mkdir -p "$(dirname "$outfile")"

  cat > "$outfile" <<HEREDOC
---
name: ${name}
description: ${description}
---
${body}
HEREDOC
}

convert_copilot() {
  local file="$1"
  local name description slug outfile body

  name="$(get_field "name" "$file")" || return $?
  description="$(get_field "description" "$file")" || return $?
  slug="$(slugify "$name")" || return $?
  body="$(get_governed_body "$file")" || return $?

  outfile="$OUT_DIR/github-copilot/agents/${slug}.md"
  mkdir -p "$(dirname "$outfile")"

  cat > "$outfile" <<HEREDOC
---
name: ${name}
description: ${description}
---
${body}
HEREDOC
}

# Aider and Windsurf are single-file formats — accumulate into temp files
# then write at the end.
AIDER_TMP="$(mktemp)"
WINDSURF_TMP="$(mktemp)"
cleanup_conversion_temps() {
  rm -f "$AIDER_TMP" "$WINDSURF_TMP"
  if $SOURCE_MANIFEST_OWNED && [[ -n "$SOURCE_MANIFEST" ]]; then
    rm -f "$SOURCE_MANIFEST"
  fi
}
trap cleanup_conversion_temps EXIT

# Write Aider/Windsurf headers once
cat > "$AIDER_TMP" <<'HEREDOC'
# The Agency — AI Agent Conventions
#
# This file provides Aider with the full roster of specialized AI agents from
# The Agency (https://github.com/msitarzewski/agency-agents).
#
# To activate an agent, reference it by name in your Aider session prompt, e.g.:
#   "Use the Frontend Developer agent to review this component."
#
# Generated by scripts/convert.sh — do not edit manually.

HEREDOC

cat > "$WINDSURF_TMP" <<'HEREDOC'
# The Agency — AI Agent Rules for Windsurf
#
# Full roster of specialized AI agents from The Agency.
# To activate an agent, reference it by name in your Windsurf conversation.
#
# Generated by scripts/convert.sh — do not edit manually.

HEREDOC

accumulate_aider() {
  local file="$1"
  local name description body

  name="$(get_field "name" "$file")" || return $?
  description="$(get_field "description" "$file")" || return $?
  body="$(get_governed_body "$file")" || return $?

  cat >> "$AIDER_TMP" <<HEREDOC

---

## ${name}

> ${description}

${body}
HEREDOC
}

accumulate_windsurf() {
  local file="$1"
  local name description body

  name="$(get_field "name" "$file")" || return $?
  description="$(get_field "description" "$file")" || return $?
  body="$(get_governed_body "$file")" || return $?

  cat >> "$WINDSURF_TMP" <<HEREDOC

================================================================================
## ${name}
${description}
================================================================================

${body}

HEREDOC
}

# --- Main loop ---

# Remove a tool's previously-generated output before regenerating, so renamed or
# deleted agents don't leave orphan files behind (convert.sh overwrites in place
# but never pruned stale output). Preserves the committed README.md — the only
# tracked file under integrations/<tool>/ for conversion targets.
clean_tool_output() {
  local dir="$OUT_DIR/$1"
  [[ -d "$dir" ]] || return 0
  find "$dir" -mindepth 1 -maxdepth 1 ! -name 'README.md' -exec rm -rf {} + || return $?
}

run_conversions() {
  local tool="$1"
  local count=0
  local status=0

  if [[ "$tool" == "hermes" ]]; then
    clean_tool_output "$tool"
    python3 "$SCRIPT_DIR/build-hermes-plugin.py" --repo-root "$REPO_ROOT" --out "$OUT_DIR/hermes" || return $?
    verify_source_manifest || return $?
    return 0
  fi

  clean_tool_output "$tool"

  local file expected_digest
  while IFS= read -r -d '' file; do
    if ! IFS= read -r -d '' expected_digest; then
      error "Truncated frozen source manifest"
      return 1
    fi
    validate_frozen_source "$file" "$expected_digest" || return $?

    case "$tool" in
      antigravity) convert_antigravity "$file" ;;
      codex)       convert_codex       "$file" ;;
      gemini-cli)  convert_gemini_cli  "$file" ;;
      opencode)    convert_opencode    "$file" ;;
      cursor)      convert_cursor      "$file" ;;
      openclaw)    convert_openclaw    "$file" ;;
      claude-code) convert_claude_code "$file" ;;
      copilot)     convert_copilot     "$file" ;;
      qwen)        convert_qwen        "$file" ;;
      zcode)       convert_zcode       "$file" ;;
      kimi)        convert_kimi        "$file" ;;
      osaurus)     convert_osaurus     "$file" ;;
      vibe)        convert_vibe        "$file" ;;
      aider)       accumulate_aider    "$file" ;;
      windsurf)    accumulate_windsurf "$file" ;;
      *)           error "Unknown tool '$tool'"; return 1 ;;
    esac
    status=$?
    if (( status != 0 )); then
      return "$status"
    fi
    count=$((count + 1))
  done < "$SOURCE_MANIFEST"

  verify_source_manifest || return $?

  echo "$count"
}

# --- Entry point ---

main() {
  local tool="all"
  local use_parallel=false
  local parallel_jobs
  parallel_jobs="$(parallel_jobs_default)"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tool)     tool="${2:?'--tool requires a value'}"; shift 2 ;;
      --out)      OUT_DIR="${2:?'--out requires a value'}"; shift 2 ;;
      --parallel) use_parallel=true; shift ;;
      --jobs)     parallel_jobs="${2:?'--jobs requires a value'}"; shift 2 ;;
      --help|-h)  usage ;;
      *)          error "Unknown option: $1"; usage ;;
    esac
  done

  local valid_tools=("antigravity" "gemini-cli" "opencode" "cursor" "aider" "windsurf" "openclaw" "qwen" "zcode" "kimi" "codex" "osaurus" "hermes" "vibe" "claude-code" "copilot" "all")
  local valid=false
  for t in "${valid_tools[@]}"; do [[ "$t" == "$tool" ]] && valid=true && break; done
  if ! $valid; then
    error "Unknown tool '$tool'. Valid: ${valid_tools[*]}"
    exit 1
  fi

  header "The Agency -- Converting agents to tool-specific formats"
  echo "  Repo:   $REPO_ROOT"
  echo "  Output: $OUT_DIR"
  echo "  Tool:   $tool"
  echo "  Date:   $TODAY"
  if $use_parallel && [[ "$tool" == "all" ]]; then
    info "Parallel mode: output buffered so each tool's output stays together."
  fi

  local tools_to_run=()
  if [[ "$tool" == "all" ]]; then
    tools_to_run=("antigravity" "gemini-cli" "opencode" "cursor" "aider" "windsurf" "openclaw" "qwen" "zcode" "kimi" "codex" "osaurus" "hermes" "vibe" "claude-code" "copilot")
  else
    tools_to_run=("$tool")
  fi

  local total=0

  local n_tools=${#tools_to_run[@]}
  prepare_source_manifest || return $?

  if $use_parallel && [[ "$tool" == "all" ]]; then
    # Tools that write to separate dirs can run in parallel; buffer output so each tool's output stays together
    local parallel_tools=(antigravity gemini-cli opencode cursor openclaw qwen zcode kimi codex osaurus hermes vibe claude-code copilot)
    local parallel_out_dir
    parallel_out_dir="$(mktemp -d)"
    local status=0
    info "Converting: ${#parallel_tools[@]}/${n_tools} tools in parallel (output buffered per tool)..."
    export AGENCY_CONVERT_OUT_DIR="$parallel_out_dir"
    export AGENCY_CONVERT_SCRIPT="$SCRIPT_DIR/convert.sh"
    export AGENCY_CONVERT_OUT="$OUT_DIR"
    printf '%s\n' "${parallel_tools[@]}" | xargs -P "$parallel_jobs" -I {} sh -c '"$AGENCY_CONVERT_SCRIPT" --tool "{}" --out "$AGENCY_CONVERT_OUT" > "$AGENCY_CONVERT_OUT_DIR/{}" 2>&1' || {
      status=$?
      printf '%s\n' "${parallel_tools[@]}" | xargs -P 1 -I {} sh -c 'if [ -f "$AGENCY_CONVERT_OUT_DIR/{}" ]; then cat "$AGENCY_CONVERT_OUT_DIR/{}"; fi' 2>&1
      rm -rf "$parallel_out_dir"
      return "$status"
    }
    for t in "${parallel_tools[@]}"; do
      [[ -f "$parallel_out_dir/$t" ]] && cat "$parallel_out_dir/$t"
    done
    rm -rf "$parallel_out_dir"
    local idx="${#parallel_tools[@]}"
    idx=$((idx + 1))
    for t in aider windsurf; do
      progress_bar "$idx" "$n_tools"
      printf "\n"
      header "Converting: $t ($idx/$n_tools)"
      local count
      count="$(run_conversions "$t")" || return $?
      total=$(( total + count ))
      info "Converted $count agents for $t"
      idx=$(( idx + 1 ))
    done
  else
    local i=0
    for t in "${tools_to_run[@]}"; do
      i=$(( i + 1 ))
      progress_bar "$i" "$n_tools"
      printf "\n"
      header "Converting: $t ($i/$n_tools)"
      local count
      count="$(run_conversions "$t")" || return $?
      total=$(( total + count ))
      info "Converted $count agents for $t"
    done
  fi

  # Write single-file outputs after accumulation
  if [[ "$tool" == "all" || "$tool" == "aider" ]]; then
    mkdir -p "$OUT_DIR/aider"
    cp "$AIDER_TMP" "$OUT_DIR/aider/CONVENTIONS.md"
    info "Wrote integrations/aider/CONVENTIONS.md"
  fi
  if [[ "$tool" == "all" || "$tool" == "windsurf" ]]; then
    mkdir -p "$OUT_DIR/windsurf"
    cp "$WINDSURF_TMP" "$OUT_DIR/windsurf/.windsurfrules"
    info "Wrote integrations/windsurf/.windsurfrules"
  fi

  echo ""
  if $use_parallel && [[ "$tool" == "all" ]]; then
    info "Done. $n_tools tools (parallel; total conversions not aggregated)."
  else
    info "Done. Total conversions: $total"
  fi
}

main "$@"
