#!/bin/bash
# Install the Glorious Mouse bar widget on Omarchy.
#   ./install.sh              add the plugin, put it on the bar, install the theme hooks
#   ./install.sh --no-hooks   skip the theme-set / post-boot hooks (lighting won't follow theme changes)
#   ./install.sh --uninstall  remove the plugin and its hooks
# Also works piped: curl -fsSL https://raw.githubusercontent.com/mattvv/omarchy-glorious-mouse/main/install.sh | bash
set -euo pipefail

REPO="https://github.com/mattvv/omarchy-glorious-mouse.git"
ID="io.github.mattvv.glorious-mouse"
HOOK_NAME="glorious-mouse"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$ID"
HOOKS=1

for arg in "$@"; do
  case "$arg" in
  --no-hooks) HOOKS=0 ;;
  --uninstall)
    rm -f "$HOME/.config/omarchy/hooks/theme-set.d/$HOOK_NAME" "$HOME/.config/omarchy/hooks/post-boot.d/$HOOK_NAME"
    omarchy plugin remove "$ID" --yes
    echo "Removed. Your lighting preference is left in ~/.local/state/glorious-mouse/."
    exit 0 ;;
  -h | --help) sed -n 2,6p "$0"; exit 0 ;;
  *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

command -v omarchy >/dev/null || { echo "This is an Omarchy plugin: 'omarchy' isn't on PATH." >&2; exit 1; }

# 1. glorious-linux does the talking to the mouse.
if ! command -v glorious >/dev/null && [[ ! -x $HOME/.local/bin/glorious ]]; then
  echo "glorious-linux isn't installed. Install it first (it asks once for sudo, for its udev rule):"
  echo "  curl -fsSL https://raw.githubusercontent.com/Virel0/glorious-linux/main/install.sh | bash"
  exit 1
fi
if ! ls /etc/udev/rules.d/*glorious* /usr/lib/udev/rules.d/*glorious* >/dev/null 2>&1; then
  echo "warning: no glorious udev rule found - the widget will get 'permission denied'." >&2
  echo "         Re-run the glorious-linux installer and let it install the rule." >&2
elif ! grep -qs 'a312' /etc/udev/rules.d/*glorious* /usr/lib/udev/rules.d/*glorious*; then
  echo "note: your glorious udev rule predates O3 cable support (3794:a312); wireless works," >&2
  echo "      the cable may not until glorious-linux is updated." >&2
fi

# 2. The plugin itself (from this checkout if run from one, otherwise from GitHub).
if [[ -e $PLUGIN_DIR ]]; then
  echo "Already installed; updating."
  omarchy plugin update "$ID" --yes || true
else
  src="$REPO"
  here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
  [[ -n $here && -f $here/manifest.json && -d $here/.git ]] && src="$here"
  omarchy plugin add "$src" --enable --yes
  git -C "$PLUGIN_DIR" remote set-url origin "$REPO"   # updates come from GitHub even if added from a clone
fi
chmod +x "$PLUGIN_DIR/glorious-mouse-lighting"

# 3. Hooks: re-apply lighting on theme change and at login.
if (( HOOKS )); then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  cp "$PLUGIN_DIR/hooks/glorious-mouse" "$tmp/$HOOK_NAME"
  omarchy hook install theme-set "$tmp/$HOOK_NAME"
  omarchy hook install post-boot "$tmp/$HOOK_NAME"
fi

"$PLUGIN_DIR/glorious-mouse-lighting" apply || echo "(mouse asleep? move it - the theme hook will catch up)"
echo
echo "Done. Click the 󰍽 widget on the bar for battery, dock and lighting."
