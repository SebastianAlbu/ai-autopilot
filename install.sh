#!/usr/bin/env bash
# ===========================================================================
#  install.sh  (macOS / Linux)
#  Install the agents + skills GLOBALLY for EVERY AI tool on this machine,
#  in ONE physical place, so nothing ever shows up twice.
#
#  Layout:
#     ~/.claude/skills          <- THE skills store (one physical copy)
#     ~/.copilot/skills         -> symlink to ~/.claude/skills   (Copilot CLI)
#     ~/.claude/agents          <- agents, Claude subagent schema (*.md)
#     ~/.copilot/agents         <- agents, Copilot schema (*.agent.md)
#
#  Why skills are NOT copied twice: VS Code Copilot reads ~/.claude/skills
#  natively AND any folder listed in chat.agentSkillsLocations. Installing into
#  both ~/.claude/skills and ~/.copilot/skills (and registering the latter) is
#  what makes every skill appear twice in the picker. So we keep one real
#  folder, link the other, and remove the duplicate registration.
#
#  Agents genuinely need two folders because the two tools use different
#  front-matter schemas and different file extensions - they never collide.
#
#  Every run PRUNES what previous versions installed (tracked in the manifest
#  at ~/.ai-autopilot-manifest.json) from every known location first, so old
#  copies from earlier layouts cannot linger.
#
#  Before installing, the Anthropic-authored skills vendored in .github/skills
#  (docx, pdf, pptx, xlsx, skill-creator, frontend-design, ...) are refreshed from
#  anthropics/skills so you never install a stale copy. Offline is fine - it warns
#  and installs what is vendored.
#
#  Usage:
#    ./install.sh                 Install for all tools
#    ./install.sh --no-caveman    Skip the caveman download
#    ./install.sh --no-anthropic  Skip the upstream Anthropic-skills refresh
#    ./install.sh --prune-only    Remove everything this installer owns, then stop
#    ./install.sh --no-link       Copy into ~/.copilot/skills instead of linking
#    ./install.sh --dry-run       Show what would be added/removed, change nothing
# ===========================================================================
set -euo pipefail

WANT_CAVEMAN=1; PRUNE_ONLY=0; USE_LINK=1; DRY_RUN=0; WANT_ANTHROPIC=1
for arg in "$@"; do
  case "$arg" in
    --no-caveman)   WANT_CAVEMAN=0 ;;
    --no-anthropic) WANT_ANTHROPIC=0 ;;
    --prune-only)   PRUNE_ONLY=1 ;;
    --no-link)      USE_LINK=0 ;;
    --dry-run)      DRY_RUN=1 ;;
    -h|--help)      sed -n '2,35p' "$0"; exit 0 ;;
    *) echo "[ERROR] Unknown option: $arg" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_SRC="$SCRIPT_DIR/.github/agents"
SKILLS_SRC="$SCRIPT_DIR/.github/skills"
MANIFEST="$HOME/.ai-autopilot-manifest.json"

if [ "$PRUNE_ONLY" = 0 ] && { [ ! -d "$AGENTS_SRC" ] || [ ! -d "$SKILLS_SRC" ]; }; then
  echo "[ERROR] Missing .github/agents or .github/skills next to this script." >&2
  echo "        Run install.sh from the ai-autopilot repository root." >&2
  exit 1
fi

SKILLS_STORE="$HOME/.claude/skills"      # the one real skills folder
COPILOT_SKILLS="$HOME/.copilot/skills"   # symlink to the store
CLAUDE_AGENTS="$HOME/.claude/agents"     # Claude subagent schema
COPILOT_AGENTS="$HOME/.copilot/agents"   # Copilot *.agent.md schema

# Every place any version of this installer has ever written to. Pruned on each
# run - but only for items we own (see managed_names), never blindly.
LEGACY_SKILL_ROOTS=(
  "$HOME/.copilot/skills"
  "$HOME/.claude/skills"
  "$HOME/.config/github-copilot/skills"
  "$HOME/.vscode/skills"
  "$HOME/Library/Application Support/Code/User/skills"
  "$HOME/Library/Application Support/Code - Insiders/User/skills"
)
LEGACY_AGENT_ROOTS=(
  "$HOME/.copilot/agents"
  "$HOME/.claude/agents"
  "$HOME/.config/github-copilot/agents"
  "$HOME/.vscode/agents"
  "$HOME/Library/Application Support/Code/User/agents"
  "$HOME/Library/Application Support/Code - Insiders/User/agents"
)

say()  { echo "$@"; }
run()  { if [ "$DRY_RUN" = 1 ]; then echo "  [dry-run] $*"; else "$@"; fi; }

# --- What do we own? repo contents UNION whatever the last run recorded ------
# The manifest is what lets us clean up items that were renamed or dropped
# between versions; without it a removed skill would be orphaned forever.
# Skills this installer also places but that do not live in the repo (downloaded
# by the caveman step). They are ours, so prune must be allowed to remove them.
CAVEMAN_NAMES=(cavecrew caveman caveman-commit caveman-compress caveman-help caveman-review caveman-stats)

managed_skill_names() {
  { [ -d "$SKILLS_SRC" ] && find "$SKILLS_SRC" -maxdepth 1 -mindepth 1 -type d -exec basename {} \;
    printf '%s\n' "${CAVEMAN_NAMES[@]}"
    manifest_names skills
  } | sort -u
}

# Entries in a skills root that this installer does not own - the only things
# that must never be deleted or silently shadowed by the symlink switch.
foreign_entries() {
  local root="$1" entry
  [ -d "$root" ] || return 0
  for entry in "$root"/*; do
    [ -e "$entry" ] || continue
    managed_skill_names | grep -qxF "$(basename "$entry")" || basename "$entry"
  done
}
managed_agent_slugs() {
  { [ -d "$AGENTS_SRC" ] && find "$AGENTS_SRC" -maxdepth 1 -name '*.agent.md' -exec basename {} .agent.md \;
    manifest_names agents
  } | sort -u
}
manifest_names() {
  [ -f "$MANIFEST" ] || return 0
  # Deliberately line-based: the manifest is written by this script, one name per line.
  sed -n "/\"$1\"[[:space:]]*:/,/\]/p" "$MANIFEST" | grep -o '"[^"]*"' | sed '1d;s/"//g'
}

# Names the manifest recorded but that this run will NOT reinstall - renamed or
# dropped between versions. These are the only items safe to delete from the
# install targets themselves; everything else there gets overwritten by the copy.
stale_skill_names() {
  [ -f "$MANIFEST" ] || return 0
  # Caveman names stay in the "live" set even with --no-caveman: that flag means "do not
  # re-download", not "delete what is already installed". Listing them here would drop
  # them from the store with nothing to restore them.
  # Note the `|| true`: a bare `cmd && ...` as the last statement of a command
  # substitution returns 1, which under `set -e` aborts this function and silently
  # yields an empty stale list.
  local live
  live="$( { [ -d "$SKILLS_SRC" ] && find "$SKILLS_SRC" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; ; \
             printf '%s\n' "${CAVEMAN_NAMES[@]}"; } | sort -u || true )"
  comm -23 <(manifest_names skills | sort -u) <(printf '%s\n' "$live")
}
stale_agent_slugs() {
  [ -f "$MANIFEST" ] || return 0
  comm -23 <(manifest_names agents | sort -u) \
           <( { [ -d "$AGENTS_SRC" ] && find "$AGENTS_SRC" -maxdepth 1 -name '*.agent.md' -exec basename {} .agent.md \; ; } | sort -u || true )
}

is_install_target() {
  case "$1" in
    "$SKILLS_STORE"|"$CLAUDE_AGENTS"|"$COPILOT_AGENTS") return 0 ;;
    *) return 1 ;;
  esac
}

# Two different jobs, deliberately kept apart:
#   1. Old LOCATIONS  -> remove every managed item (nothing there gets rewritten).
#   2. Install TARGETS -> remove only STALE items; the rest is overwritten by the
#      copy below. Pruning live items here would delete things a --no-caveman run
#      never restores.
prune() {
  local removed=0 name root
  say "Pruning previous installs (manifest-scoped)..."
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    for root in "${LEGACY_SKILL_ROOTS[@]}"; do
      [ -L "$root" ] && continue   # a link is the store itself - never delete through it
      is_install_target "$root" && continue
      if [ -e "$root/$name" ]; then say "  - $root/$name"; run rm -rf "$root/$name"; removed=$((removed+1)); fi
    done
  done < <(managed_skill_names)
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    for root in "${LEGACY_AGENT_ROOTS[@]}"; do
      [ -L "$root" ] && continue
      is_install_target "$root" && continue
      for f in "$root/$name.agent.md" "$root/$name.md"; do
        if [ -e "$f" ]; then say "  - $f"; run rm -f "$f"; removed=$((removed+1)); fi
      done
    done
  done < <(managed_agent_slugs)

  # Stale items, this time inside the install targets too.
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ -e "$SKILLS_STORE/$name" ]; then say "  - (stale) $SKILLS_STORE/$name"; run rm -rf "$SKILLS_STORE/$name"; removed=$((removed+1)); fi
  done < <(stale_skill_names)
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    for f in "$CLAUDE_AGENTS/$name.md" "$COPILOT_AGENTS/$name.agent.md"; do
      if [ -e "$f" ]; then say "  - (stale) $f"; run rm -f "$f"; removed=$((removed+1)); fi
    done
  done < <(stale_agent_slugs)

  say "[OK] Pruned $removed item(s)."
}

# Records what is installed RIGHT NOW, not the historical union. Writing the union
# would keep every long-removed name in the file forever, so it could never stop being
# reported as stale.
installed_skill_names() {
  { [ -d "$SKILLS_SRC" ] && find "$SKILLS_SRC" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; ; \
    printf '%s\n' "${CAVEMAN_NAMES[@]}"; } | sort -u || true
}
installed_agent_slugs() {
  { [ -d "$AGENTS_SRC" ] && find "$AGENTS_SRC" -maxdepth 1 -name '*.agent.md' -exec basename {} .agent.md \; ; } | sort -u || true
}

write_manifest() {
  [ "$DRY_RUN" = 1 ] && return 0
  {
    echo '{'
    echo '  "generatedBy": "ai-autopilot install.sh",'
    echo "  \"skillsStore\": \"$SKILLS_STORE\","
    echo "  \"claudeAgents\": \"$CLAUDE_AGENTS\","
    echo "  \"copilotAgents\": \"$COPILOT_AGENTS\","
    echo '  "skills": ['
    installed_skill_names | sed 's/.*/    "&",/' | sed '$ s/,$//'
    echo '  ],'
    echo '  "agents": ['
    installed_agent_slugs | sed 's/.*/    "&",/' | sed '$ s/,$//'
    echo '  ]'
    echo '}'
  } > "$MANIFEST"
}

# --- Duplicate detector: the check that catches this class of bug -----------
doctor() {
  local dupes=0 name root hits
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    hits=""
    for root in "${LEGACY_SKILL_ROOTS[@]}"; do
      [ -L "$root" ] && continue          # a link is the same physical folder
      [ -e "$root/$name" ] && hits="$hits $root"
    done
    if [ "$(echo $hits | wc -w)" -gt 1 ]; then
      echo "[DUPLICATE] skill '$name' exists in:$hits"; dupes=$((dupes+1))
    fi
  done < <(managed_skill_names)
  if [ "$dupes" -gt 0 ]; then
    echo "[WARN] $dupes duplicated skill(s) - tools scanning both roots will list them twice."
    echo "       Re-run ./install.sh (it prunes), or delete the extra copies listed above."
  else
    echo "[OK] No duplicates: every skill exists in exactly one physical location."
  fi
}

echo
echo "Installing from : $SCRIPT_DIR/.github"
echo "Skills store    : $SKILLS_STORE   (single copy)"
echo "Copilot skills  : $COPILOT_SKILLS $( [ "$USE_LINK" = 1 ] && echo '(symlink)' || echo '(copy)' )"
echo "Agents          : $CLAUDE_AGENTS (Claude)  +  $COPILOT_AGENTS (Copilot)"
[ "$DRY_RUN" = 1 ] && echo "MODE            : dry run - nothing will change"
echo

prune

if [ "$PRUNE_ONLY" = 1 ]; then
  # Full removal: the install targets are not being rewritten this time, so the
  # live items there have to go too.
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    [ -e "$SKILLS_STORE/$name" ] && { say "  - $SKILLS_STORE/$name"; run rm -rf "$SKILLS_STORE/$name"; }
  done < <(managed_skill_names)
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    for f in "$CLAUDE_AGENTS/$name.md" "$COPILOT_AGENTS/$name.agent.md"; do
      [ -e "$f" ] && { say "  - $f"; run rm -f "$f"; }
    done
  done < <(managed_agent_slugs)
  [ -L "$COPILOT_SKILLS" ] && run rm -f "$COPILOT_SKILLS"
  [ "$DRY_RUN" = 0 ] && rm -f "$MANIFEST"
  echo
  echo "Prune complete. Nothing was installed (--prune-only)."
  exit 0
fi

# --- Refresh the vendored Anthropic skills before copying anything ----------
# Runs against the repo, not the install targets, so the update is visible in git
# and the same refreshed files land in every store.
if [ "$WANT_ANTHROPIC" = 1 ]; then
  UPDATER="$SCRIPT_DIR/update-anthropic-skills.sh"
  if [ -x "$UPDATER" ]; then
    "$UPDATER" $( [ "$DRY_RUN" = 1 ] && echo --dry-run ) || echo "[WARN] Anthropic skill refresh failed - installing the vendored copies."
  elif [ -f "$UPDATER" ]; then
    bash "$UPDATER" $( [ "$DRY_RUN" = 1 ] && echo --dry-run ) || echo "[WARN] Anthropic skill refresh failed - installing the vendored copies."
  else
    echo "[WARN] update-anthropic-skills.sh not found - installing the vendored copies."
  fi
  echo
fi

# --- Skills: ONE physical copy ---------------------------------------------
run mkdir -p "$SKILLS_STORE"
if [ "$DRY_RUN" = 1 ]; then echo "  [dry-run] cp -R $SKILLS_SRC/. $SKILLS_STORE/"; else cp -R "$SKILLS_SRC/." "$SKILLS_STORE/"; fi
echo "[OK] Skills installed to $SKILLS_STORE."

# --- Copilot CLI: link its folder at the same store -------------------------
if [ "$USE_LINK" = 1 ]; then
  if [ -L "$COPILOT_SKILLS" ]; then
    run rm -f "$COPILOT_SKILLS"
  elif [ -d "$COPILOT_SKILLS" ]; then
    # Real folder left by an older install. Our items were pruned above, so what
    # remains belongs to the user - never delete that blindly.
    FOREIGN="$(foreign_entries "$COPILOT_SKILLS")"
    if [ -z "$FOREIGN" ]; then
      run rm -rf "$COPILOT_SKILLS"
    else
      echo "[WARN] $COPILOT_SKILLS holds skills this installer does not own:"
      echo "$FOREIGN" | sed 's/^/         /'
      echo "       Leaving it as a real folder - those may appear twice."
      echo "       Move them into $SKILLS_STORE and re-run to finish the switch."
      USE_LINK=0
    fi
  fi
fi
if [ "$USE_LINK" = 1 ]; then
  run mkdir -p "$HOME/.copilot"
  run ln -s "$SKILLS_STORE" "$COPILOT_SKILLS"
  echo "[OK] $COPILOT_SKILLS -> $SKILLS_STORE (link, no second copy)."
else
  run mkdir -p "$COPILOT_SKILLS"
  if [ "$DRY_RUN" = 1 ]; then echo "  [dry-run] cp -R $SKILLS_SRC/. $COPILOT_SKILLS/"; else cp -R "$SKILLS_SRC/." "$COPILOT_SKILLS/"; fi
  echo "[OK] Skills copied to $COPILOT_SKILLS (second copy - duplicates are possible)."
fi

# --- Agents: two schemas, two folders, no overlap ---------------------------
run mkdir -p "$COPILOT_AGENTS" "$CLAUDE_AGENTS"
if [ "$DRY_RUN" = 1 ]; then echo "  [dry-run] cp -R $AGENTS_SRC/. $COPILOT_AGENTS/"; else cp -R "$AGENTS_SRC/." "$COPILOT_AGENTS/"; fi

# Convert *.agent.md -> Claude subagent: keep only "name" (kebab, from the file
# name) + "description", drop Copilot-only fields, and keep the body. Omitting
# "tools" lets the Claude agent inherit all tools.
if [ "$DRY_RUN" = 0 ]; then
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
fi
echo "[OK] Agents installed (Copilot + Claude Code)."

# --- Caveman skills: into the single store only -----------------------------
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
  cp -R "$root/skills/." "$SKILLS_STORE/"
  echo "[OK] caveman skills installed into $SKILLS_STORE."
}
if [ "$WANT_CAVEMAN" = 1 ] && [ "$DRY_RUN" = 0 ]; then
  if command -v curl >/dev/null && command -v unzip >/dev/null; then
    install_caveman || true
  else
    echo "[WARN] curl/unzip not found - skipping caveman."
  fi
fi
echo

# --- VS Code settings.json --------------------------------------------------
# agentFilesLocations  -> ~/.copilot/agents  (VS Code needs the *.agent.md schema)
# agentSkillsLocations -> nothing of ours. VS Code already reads ~/.claude/skills
#                         natively; registering a second skills folder is exactly
#                         what produced the duplicates, so we remove it.
case "$(uname -s)" in
  Darwin) BASE="$HOME/Library/Application Support" ;;
  *)      BASE="${XDG_CONFIG_HOME:-$HOME/.config}" ;;
esac
SETTINGS=""
for app in "Code" "Code - Insiders"; do
  [ -d "$BASE/$app/User" ] && { SETTINGS="$BASE/$app/User/settings.json"; break; }
done

remove_skill_location() {
  local value="$1"
  [ -f "$SETTINGS" ] || return 0
  grep -qF "\"$value\"" "$SETTINGS" || return 0
  if [ "$DRY_RUN" = 1 ]; then echo "  [dry-run] remove \"$value\" from chat.agentSkillsLocations"; return 0; fi
  # Line-scoped delete: settings.json is JSONC, so a full re-serialize would
  # destroy the user's comments. One entry per line is how VS Code writes it.
  local tmp; tmp="$(mktemp)"
  grep -vF "\"$value\"" "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "[OK] Removed duplicate skills location '$value' from settings.json."
}

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
  if [ "$DRY_RUN" = 1 ]; then echo "  [dry-run] add $key -> $value"; return; fi
  before="${content%%\{*}"; after="${content#*\{}"
  printf '%s{\n    "%s": {\n        "%s": true\n    },%s' \
    "$before" "$key" "$value" "$after" >"$SETTINGS"
  echo "[OK] Added '$key' -> $value"
}

if [ -n "$SETTINGS" ]; then
  remove_skill_location "~/.copilot/skills"
  remove_skill_location "$COPILOT_SKILLS"
  add_location "chat.agentFilesLocations" "$COPILOT_AGENTS"
else
  echo "[INFO] No VS Code user folder detected - skipping settings.json registration."
fi

write_manifest
echo
doctor

echo
echo "Done. Next steps:"
echo "  - Claude Code: restart it (or run /agents) - skills & agents load from ~/.claude."
echo "  - VS Code: run 'Developer: Reload Window'."
echo "  - Copilot CLI: picks up ~/.copilot automatically."
