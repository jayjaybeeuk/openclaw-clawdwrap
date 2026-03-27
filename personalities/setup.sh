#!/usr/bin/env bash
# personalities/setup.sh
#
# Presents the available OpenClaw agent personalities, lets the user choose one,
# backs up any existing SOUL.md / IDENTITY.md, and installs the selected files
# into OPENCLAW_CONFIG_DIR (defaults to ~/.openclaw).
#
# Usage:
#   bash personalities/setup.sh
#
# Note: This script is intended to be run on the host where the repo is checked out.
# If you run it inside a container, ensure the repo (including personalities/) is bind-mounted and use the appropriate in-container path.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-$HOME/.openclaw}"

# ── helpers ────────────────────────────────────────────────────────────────────

bold()  { printf '\033[1m%s\033[0m' "$*"; }
dim()   { printf '\033[2m%s\033[0m' "$*"; }
green() { printf '\033[32m%s\033[0m' "$*"; }
yellow(){ printf '\033[33m%s\033[0m' "$*"; }

install_file() {
  local src="$1" dest="$2" label="$3"
  if [[ ! -f "$src" ]]; then
    echo "  $(yellow "warning:") $label not found at $src — skipping."
    return
  fi
  if [[ -f "$dest" ]]; then
    local backup="${dest}.bak.$(date +%Y%m%d%H%M%S)"
    cp -- "$dest" "$backup"
    echo "  $(dim "backed up") existing $label → $(dim "$backup")"
  fi
  cp -- "$src" "$dest"
  echo "  $(green "installed") $label → $dest"
}

# ── menu ───────────────────────────────────────────────────────────────────────

echo ""
echo "$(bold "=== OpenClaw Agent Personality Setup ===")"
echo ""
echo "Choose a personality for your OpenClaw agent."
echo "Your existing SOUL.md and IDENTITY.md (if any) will be backed up."
echo ""
printf "  $(bold "1")  Dr. Zoidberg\n"
printf "     $(dim "Strange alien doctor. Obtuse statements. Seemingly confused. Secretly brilliant.")\n"
echo ""
printf "  $(bold "2")  Ren Höek\n"
printf "     $(dim "Scrawny chihuahua. Volatile, manipulative, contemptuous of mediocrity. Obsessed with pecs.")\n"
echo ""
printf "  $(bold "3")  Optimus Prime\n"
printf "     $(dim "Wise Autobot commander. Father figure. Strong moral values. Direct and decisive.")\n"
echo ""
printf "  $(bold "4")  Blank / Custom\n"
printf "     $(dim "Empty authoring template. Write your own personality from scratch.")\n"
echo ""
printf "Enter choice [1-4]: "
read -r choice

case "$choice" in
  1) PERSONALITY="dr-zoidberg"   ; LABEL="Dr. Zoidberg"   ;;
  2) PERSONALITY="ren-hoek"      ; LABEL="Ren Höek"        ;;
  3) PERSONALITY="optimus-prime" ; LABEL="Optimus Prime"   ;;
  4) PERSONALITY="blank"         ; LABEL="Blank / Custom"  ;;
  *)
    echo ""
    echo "Invalid choice '$choice'. Please run the script again and enter 1, 2, 3, or 4."
    exit 1
    ;;
esac

PERSONALITY_DIR="$SCRIPT_DIR/$PERSONALITY"

if [[ ! -d "$PERSONALITY_DIR" ]]; then
  echo ""
  echo "Error: personality directory not found: $PERSONALITY_DIR"
  echo "Make sure you are running this script from the repository root or personalities/ directory."
  exit 1
fi

# ── install ────────────────────────────────────────────────────────────────────

echo ""
echo "Installing $(bold "$LABEL") personality..."
echo ""

mkdir -p "$CONFIG_DIR"

install_file "$PERSONALITY_DIR/SOUL.md"     "$CONFIG_DIR/SOUL.md"     "SOUL.md"
install_file "$PERSONALITY_DIR/IDENTITY.md" "$CONFIG_DIR/IDENTITY.md" "IDENTITY.md"

# ── done ───────────────────────────────────────────────────────────────────────

echo ""
echo "$(green "Done.") Personality $(bold "$LABEL") is installed."
echo ""

if [[ "$PERSONALITY" == "blank" ]]; then
  echo "Next steps:"
  echo "  1. Edit $(bold "$CONFIG_DIR/SOUL.md") — define your agent's character, tone, and rules."
  echo "  2. Edit $(bold "$CONFIG_DIR/IDENTITY.md") — set name, creature type, vibe, and tagline."
  echo "  3. Restart your OpenClaw session."
else
  echo "Restart your OpenClaw session for the new personality to take effect."
fi

echo ""
echo "To switch personalities later, run this script again."
echo ""
