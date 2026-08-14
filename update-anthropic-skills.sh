#!/usr/bin/env bash
# ===========================================================================
#  update-anthropic-skills.sh  (macOS / Linux)
#
#  Refresh the Anthropic-authored skills vendored in .github/skills from the
#  upstream repo (anthropics/skills) so they never go stale.
#
#  Which skills? Whichever of OUR .github/skills/<name> folders also exist
#  upstream at skills/<name>. That is auto-detected on every run, so a skill
#  added to either side is picked up with no list to maintain here.
#
#  Our own skills (bitbucket-*, review-*, sple-standards, ...) have no upstream
#  counterpart and are never touched.
#
#  The resolved upstream commit is written to
#  .github/skills/.anthropic-skills.lock.json so you can see exactly which
#  version is vendored, and re-runs are a no-op when nothing changed.
#
#  Vendored folders are REPLACED wholesale - do not hand-edit them; upstream
#  wins. Everything is under git, so review the diff before committing.
#
#  Usage:
#    ./update-anthropic-skills.sh                 Update to latest main
#    ./update-anthropic-skills.sh --ref v1.2.3    Pin to a tag/branch/sha
#    ./update-anthropic-skills.sh --dry-run       Show what would change
#    ./update-anthropic-skills.sh --force         Re-copy even if the lock matches
#    ./update-anthropic-skills.sh --list          Show local vs upstream, change nothing
# ===========================================================================
set -euo pipefail

UPSTREAM_REPO="anthropics/skills"
UPSTREAM_PREFIX="skills"          # where the skills live inside that repo
REF="main"; DRY_RUN=0; FORCE=0; LIST_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --ref)      REF="${2:-}"; [ -n "$REF" ] || { echo "[ERROR] --ref needs a value" >&2; exit 2; }; shift 2 ;;
    --dry-run)  DRY_RUN=1; shift ;;
    --force)    FORCE=1; shift ;;
    --list)     LIST_ONLY=1; shift ;;
    -h|--help)  sed -n '2,29p' "$0"; exit 0 ;;
    *) echo "[ERROR] Unknown option: $1" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$SCRIPT_DIR/.github/skills"
LOCK="$SKILLS_DIR/.anthropic-skills.lock.json"
API="https://api.github.com/repos/$UPSTREAM_REPO"

[ -d "$SKILLS_DIR" ] || { echo "[ERROR] No $SKILLS_DIR - run from the repo root." >&2; exit 1; }
for tool in curl tar python3; do
  command -v "$tool" >/dev/null || { echo "[WARN] '$tool' not found - skipping the Anthropic skill update."; exit 0; }
done

# --- Resolve the upstream commit -------------------------------------------
# Fail soft everywhere: being offline must never block an install.
COMMIT="$(curl -fsSL -H 'User-Agent: ai-autopilot' "$API/commits/$REF" 2>/dev/null \
          | python3 -c 'import json,sys; print(json.load(sys.stdin).get("sha",""))' 2>/dev/null || true)"
if [ -z "$COMMIT" ]; then
  echo "[WARN] Could not reach $UPSTREAM_REPO ($REF) - keeping the vendored copies as they are."
  exit 0
fi
SHORT="${COMMIT:0:7}"

LOCKED=""
if [ -f "$LOCK" ]; then
  LOCKED="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("commit",""))' "$LOCK" 2>/dev/null || true)"
fi

if [ "$LOCKED" = "$COMMIT" ] && [ "$FORCE" = 0 ] && [ "$LIST_ONLY" = 0 ]; then
  echo "[OK] Anthropic skills already at $UPSTREAM_REPO@$SHORT - nothing to do."
  exit 0
fi

# --- Which of our skills exist upstream? -----------------------------------
UPSTREAM_NAMES="$(curl -fsSL -H 'User-Agent: ai-autopilot' "$API/contents/$UPSTREAM_PREFIX?ref=$REF" 2>/dev/null \
  | python3 -c 'import json,sys; print("\n".join(d["name"] for d in json.load(sys.stdin) if d["type"]=="dir"))' 2>/dev/null || true)"
if [ -z "$UPSTREAM_NAMES" ]; then
  echo "[WARN] Could not list $UPSTREAM_REPO/$UPSTREAM_PREFIX - keeping the vendored copies as they are."
  exit 0
fi

LOCAL_NAMES="$(find "$SKILLS_DIR" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort)"
MANAGED="$(comm -12 <(printf '%s\n' "$LOCAL_NAMES") <(printf '%s\n' "$UPSTREAM_NAMES" | sort))"
NEW_UPSTREAM="$(comm -13 <(printf '%s\n' "$LOCAL_NAMES") <(printf '%s\n' "$UPSTREAM_NAMES" | sort))"

if [ "$LIST_ONLY" = 1 ]; then
  echo "Upstream : $UPSTREAM_REPO@$SHORT ($REF)"
  echo "Vendored : $(printf '%s' "$MANAGED" | grep -c . || true) skill(s) tracked from upstream"
  printf '%s\n' "$MANAGED" | sed 's/^/  - /'
  if [ -n "$NEW_UPSTREAM" ]; then
    echo "Available upstream but not vendored here (add the folder to start tracking it):"
    printf '%s\n' "$NEW_UPSTREAM" | sed 's/^/  + /'
  fi
  exit 0
fi

if [ -z "$MANAGED" ]; then
  echo "[INFO] No vendored skills match an upstream skill - nothing to update."
  exit 0
fi

echo "Updating Anthropic skills from $UPSTREAM_REPO@$SHORT ($REF)..."

# --- Download once, copy the folders we track ------------------------------
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
if ! curl -fsSL -H 'User-Agent: ai-autopilot' -o "$TMP/src.tar.gz" "$API/tarball/$COMMIT"; then
  echo "[WARN] Download failed - keeping the vendored copies as they are."; exit 0
fi
mkdir -p "$TMP/x"
tar -xzf "$TMP/src.tar.gz" -C "$TMP/x" || { echo "[WARN] Extract failed - keeping the vendored copies."; exit 0; }
SRC_ROOT="$(find "$TMP/x" -maxdepth 1 -mindepth 1 -type d | head -1)"
[ -n "$SRC_ROOT" ] || { echo "[WARN] Unexpected archive layout - keeping the vendored copies."; exit 0; }

changed=0; skipped=0
while IFS= read -r name; do
  [ -n "$name" ] || continue
  src="$SRC_ROOT/$UPSTREAM_PREFIX/$name"
  dst="$SKILLS_DIR/$name"
  if [ ! -d "$src" ]; then
    echo "  [skip] $name - not in the archive"; skipped=$((skipped+1)); continue
  fi
  if [ -d "$dst" ] && diff -rq "$src" "$dst" >/dev/null 2>&1; then
    continue
  fi
  echo "  [update] $name"
  if [ "$DRY_RUN" = 0 ]; then
    # Replace wholesale so files deleted upstream also disappear here.
    rm -rf "$dst"
    cp -R "$src" "$dst"
  fi
  changed=$((changed+1))
done <<< "$MANAGED"

if [ "$DRY_RUN" = 1 ]; then
  echo "[dry-run] $changed skill(s) would be updated; lock not written."
  exit 0
fi

# --- Lock file --------------------------------------------------------------
{
  echo '{'
  echo "  \"repo\": \"$UPSTREAM_REPO\","
  echo "  \"ref\": \"$REF\","
  echo "  \"commit\": \"$COMMIT\","
  echo '  "skills": ['
  printf '%s\n' "$MANAGED" | sed 's/.*/    "&",/' | sed '$ s/,$//'
  echo '  ]'
  echo '}'
} > "$LOCK"

if [ "$changed" -eq 0 ]; then
  echo "[OK] Anthropic skills already current at $SHORT (lock refreshed)."
else
  echo "[OK] Updated $changed skill(s) to $UPSTREAM_REPO@$SHORT."
  echo "     Review with: git diff -- .github/skills"
fi
[ "$skipped" -gt 0 ] && echo "[WARN] $skipped vendored skill(s) were not in the archive - left untouched."

if [ -n "$NEW_UPSTREAM" ]; then
  echo "[INFO] Upstream also offers: $(printf '%s' "$NEW_UPSTREAM" | tr '\n' ' ')"
  echo "       Create the folder in .github/skills to start tracking one."
fi
exit 0
