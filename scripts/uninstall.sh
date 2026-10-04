#!/usr/bin/env bash
# omarchy:summary=Remove the toptop notch bar and restore the previous bar
# omarchy:group=plugin
# omarchy:args=[--keep-config]
# omarchy:examples=./scripts/uninstall.sh

# Puts the previous bar back and removes nagualcode.toptop.
#
# Only `bar.id` in shell.json is rewritten. The layout, and anything else in the
# config, is left untouched — uninstalling a bar should not cost you the layout
# you built up with it.

set -euo pipefail

script_dir="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"
if [[ -f "$script_dir/common.sh" ]]; then
  source "$script_dir/common.sh"
else
  fail "uninstall.sh needs to run from a toptop checkout (missing $script_dir/common.sh)"
fi

KEEP_CONFIG=0
FALLBACK_BAR_ID="omarchy.bar"

usage() {
  cat <<USAGE
Usage: uninstall.sh [--keep-config]

  --keep-config  leave the "toptop" block in shell.json alone

The block is inert once the plugin is gone, so by default it is left in place:
it holds the pinned-icon list, which is worth keeping if you reinstall.
USAGE
}

while (( $# > 0 )); do
  case "$1" in
  --keep-config) KEEP_CONFIG=1; shift ;;
  -h | --help) usage; exit 0 ;;
  *) fail "unknown option: $1" ;;
  esac
done

need jq "uninstall.sh needs jq"

# --- 1. work out which bar to go back to -------------------------------------
#
# The undo record is what makes this correct on a second uninstall: by then
# `bar.id` already reads nagualcode.toptop, so falling back to it would leave the
# shell pointing at a plugin that is no longer on disk.
PREVIOUS_BAR_ID="$FALLBACK_BAR_ID"
if [[ -f "$INSTALL_STATE" ]]; then
  recorded="$(jq -r '.previousBarId // empty' "$INSTALL_STATE" 2>/dev/null || true)"
  [[ -n "$recorded" ]] && PREVIOUS_BAR_ID="$recorded"
  echo "Recorded previous bar: $PREVIOUS_BAR_ID"
else
  echo "No undo record at $INSTALL_STATE; falling back to $FALLBACK_BAR_ID"
fi

ASSUME_SHELL=1
if ! shell_is_running; then
  ASSUME_SHELL=0
  echo "note: omarchy-shell is not responding; removing files only."
fi

# --- 2. put the shell back on the previous bar ------------------------------

if (( ASSUME_SHELL )); then
  if enable_plugin "$PREVIOUS_BAR_ID"; then
    # enablePlugin persists asynchronously, and a shell that is busy rebuilding
    # its bar can accept the call without writing the config. Deleting the
    # plugin while bar.id still names it would leave the next start with no bar
    # at all, so confirm the switch actually landed.
    for _ in $(seq 1 50); do
      [[ "$(jq -r '.bar.id // empty' "$SHELL_CONFIG")" != "$TOPTOP_ID" ]] && break
      sleep 0.1
    done
    if [[ "$(jq -r '.bar.id // empty' "$SHELL_CONFIG")" == "$TOPTOP_ID" ]]; then
      rewrite_shell_config --arg id "$PREVIOUS_BAR_ID" '.bar.id = $id'
      echo "The shell did not persist the switch; set bar.id directly"
    fi
    echo "Switched back to $PREVIOUS_BAR_ID"
  else
    fail "the shell would not switch back to $PREVIOUS_BAR_ID; run: omarchy-shell shell enablePlugin $PREVIOUS_BAR_ID '{}'"
  fi
else
  # bar.id still names toptop, and the plugin is about to be deleted — so the
  # id has to be rewritten here even with the shell down, or the next start
  # would look for a bar that is no longer installed.
  rewrite_shell_config --arg id "$PREVIOUS_BAR_ID" '.bar.id = $id'
  echo "Set bar.id to $PREVIOUS_BAR_ID"
fi

# `bar.toptop` is dropped too, unless asked to keep it. Only ever removes the
# key: `del` on a missing path is a no-op, so this works on a config toptop never
# configured.
if (( ! KEEP_CONFIG )); then
  rewrite_shell_config '.bar |= (if has("toptop") then del(.toptop) else . end)'
  echo "Removed bar.toptop from shell.json"
else
  echo "Kept bar.toptop in shell.json (inert; unused keys are ignored)"
fi

# --- 3. take the plugin off disk --------------------------------------------
#
# Renamed first, deleted after. Removing the tree file by file would let the
# shell's watcher notice a plugin that has lost half its files and reload it.
if [[ -e "$PLUGIN_DIR" || -L "$PLUGIN_DIR" ]]; then
  doomed="${PLUGIN_DIR}.removed.$$"
  mv "$PLUGIN_DIR" "$doomed" || fail "could not remove $PLUGIN_DIR"
  rm -rf "$doomed"
  echo "Removed $PLUGIN_DIR"
else
  echo "$TOPTOP_ID was not installed at $PLUGIN_DIR"
fi

rm -f "$INSTALL_STATE"

if [[ -f "$SHELL_CONFIG_BACKUP" ]]; then
  echo
  echo "A pre-install copy of shell.json is still at $SHELL_CONFIG_BACKUP"
fi

echo
echo "Done. The bar is back to $PREVIOUS_BAR_ID with your layout untouched."