#!/usr/bin/env bash
# ===========================================================================
#  install.sh  (macOS / Linux)
#  Install the agents + skills GLOBALLY for EVERY AI tool on this machine.
#  Each tool scans its own home folder, so we install into all of them:
#
#     Claude Code     ~/.claude/skills    ~/.claude/agents
#     VS Code Copilot ~/.copilot/skills   ~/.copilot/agents  (also reads ~/.claude/skills)
#     Copilot CLI     ~/.copilot/skills   ~/.copilot/agents
#
#  Skills use one portable SKILL.md format, so they are copied as-is.
#  Agents are Copilot-format (*.agent.md); for Claude Code they are converted
#  to the subagent schema (kebab name + description, full tools).
#
#  Also downloads the latest "caveman" skills and installs them alongside.
#
#  Usage:
#    ./install.sh                 Install for all tools
#    ./install.sh --no-caveman    Skip the caveman download
# ===========================================================================
set -euo pipefail

WANT_CAVEMAN=1
[ "${1:-}" = "--no-caveman" ] && WANT_CAVEMAN=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_SRC="$SCRIPT_DIR/.github/agents"
SKILLS_SRC="$SCRIPT_DIR/.github/skills"

if [ ! -d "$AGENTS_SRC" ] || [ ! -d "$SKILLS_SRC" ]; then
  echo "[ERROR] Missing .github/agents or .github/skills next to this script." >&2
  echo "        Run install.sh from the ai-agents repository root." >&2
  exit 1
fi

# Skills go to every tool's skills folder; agents to every tool's agents folder.
SKILL_TARGETS=("$HOME/.copilot/skills" "$HOME/.claude/skills")
COPILOT_AGENTS="$HOME/.copilot/agents"   # Copilot-format agents (*.agent.md)
CLAUDE_AGENTS="$HOME/.claude/agents"     # converted to Claude subagent schema

echo
echo "Installing from : $SCRIPT_DIR/.github"
echo "Skills  -> ${SKILL_TARGETS[*]}"
echo "Agents  -> $COPILOT_AGENTS  (Copilot)   +  $CLAUDE_AGENTS  (Claude Code)"
echo

# --- Skills: copy the repo skills into every skills target -----------------
for dst in "${SKILL_TARGETS[@]}"; do
  mkdir -p "$dst"
  cp -R "$SKILLS_SRC/." "$dst/"
done
echo "[OK] Repo skills installed."

# --- Agents: Copilot-format as-is; Claude Code needs a converted copy -------
mkdir -p "$COPILOT_AGENTS" "$CLAUDE_AGENTS"
cp -R "$AGENTS_SRC/." "$COPILOT_AGENTS/"

# Convert *.agent.md -> Claude subagent: keep only "name" (kebab, from the file
# name) + "description", drop Copilot-only fields, and keep the body. Omitting
# "tools" lets the Claude agent inherit all tools.
for f in "$AGENTS_SRC"/*.agent.md; do
  [ -e "$f" ] || continue
  base="$(basename "$f" .agent.md)"
  awk -v slug="$base" '
    /^---[[:space:]]*$/ {
      fm++
      if (fm==1) { print "---"; print "name: " slug; next }
      if (fm==2) { if (desc!="") print desc; print "---"; body=1; next }
    }
    fm==1 && /^description:/ { desc=$0; next }
    fm==1 { next }
    body==1 { print }
  ' "$f" > "$CLAUDE_AGENTS/$base.md"
done
echo "[OK] Agents installed (Copilot + Claude Code)."

# --- Caveman skills: download the latest release and install alongside ------
install_caveman() {
  local api="https://api.github.com/repos/JuliusBrussee/caveman/releases/latest"
  local tmp zip ext root zipurl
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  echo "Fetching latest caveman release..."
  zipurl="$(curl -fsSL -H 'User-Agent: caveman-installer' "$api" \
    | sed -n 's/.*"zipball_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  if [ -z "$zipurl" ]; then echo "[WARN] Could not resolve caveman release URL - skipping."; return 0; fi
  zip="$tmp/caveman.zip"; ext="$tmp/x"; mkdir -p "$ext"
  curl -fsSL -H 'User-Agent: caveman-installer' -o "$zip" "$zipurl" || { echo "[WARN] caveman download failed - skipping."; return 0; }
  unzip -qo "$zip" -d "$ext" || { echo "[WARN] caveman unzip failed - skipping."; return 0; }
  root="$(find "$ext" -maxdepth 1 -mindepth 1 -type d | head -1)"
  if [ -z "$root" ] || [ ! -d "$root/skills" ]; then echo "[WARN] caveman archive has no skills/ - skipping."; return 0; fi
  for dst in "${SKILL_TARGETS[@]}"; do
    mkdir -p "$dst"; cp -R "$root/skills/." "$dst/"
  done
  echo "[OK] caveman skills installed."
}
if [ "$WANT_CAVEMAN" = 1 ]; then
  if command -v curl >/dev/null && command -v unzip >/dev/null; then
    install_caveman || true
  else
    echo "[WARN] curl/unzip not found - skipping caveman."
  fi
fi
echo

# --- VS Code settings.json: register ~/.copilot as a safety net ------------
SKILLS_VALUE="~/.copilot/skills"
AGENTS_VALUE="$COPILOT_AGENTS"
case "$(uname -s)" in
  Darwin) BASE="$HOME/Library/Application Support" ;;
  *)      BASE="${XDG_CONFIG_HOME:-$HOME/.config}" ;;
esac
SETTINGS=""
for app in "Code" "Code - Insiders"; do
  [ -d "$BASE/$app/User" ] && { SETTINGS="$BASE/$app/User/settings.json"; break; }
done

add_location() {
  local key="$1" value="$2" content before after
  [ -f "$SETTINGS" ] || printf '{\n}\n' >"$SETTINGS"
  content="$(cat "$SETTINGS")"
  if printf '%s' "$content" | grep -qF "$key"; then
    printf '%s' "$content" | grep -qF "$value" \
      && echo "[OK] '$key' already includes '$value'." \
      || echo "[WARN] '$key' exists but does not list '$value'. Add manually:  \"$value\": true"
    return
  fi
  before="${content%%\{*}"; after="${content#*\{}"
  printf '%s{\n    "%s": {\n        "%s": true\n    },%s' \
    "$before" "$key" "$value" "$after" >"$SETTINGS"
  echo "[OK] Added '$key' -> $value"
}

if [ -n "$SETTINGS" ]; then
  add_location "chat.agentSkillsLocations" "$SKILLS_VALUE"
  add_location "chat.agentFilesLocations"  "$AGENTS_VALUE"
else
  echo "[INFO] No VS Code user folder detected - skipping settings.json registration."
fi

echo
echo "Done. Next steps:"
echo "  - Claude Code: restart it (or run /agents) - skills & agents load from ~/.claude."
echo "  - VS Code: run 'Developer: Reload Window'."
echo "  - Copilot CLI: picks up ~/.copilot automatically."
