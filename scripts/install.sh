#!/usr/bin/env bash
# omarchy:summary=Install the toptop notch bar and make it the active bar
# omarchy:group=plugin
# omarchy:args=[source] [--force]
# omarchy:examples=./scripts/install.sh
# omarchy:examples=./scripts/install.sh https://github.com/nagualcode/toptop.git

# Installs nagualcode.toptop and switches the shell over to it.
#
# Re-running is safe. An already-installed plugin is left in place, and only the
# configuration step is repeated, so this doubles as "repair my install".
#
# Only shell.json is touched, and only to record which bar was in use so
# uninstall can put it back.

set -euo pipefail

# Sourced from a checkout next to this script. When the script is piped in
# (`curl … | bash`) there is no such directory, so fetch the repository first and
# use that checkout for the rest of the run — which is where the plugin is
# installed from anyway.
script_dir="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"
if [[ -f "$script_dir/common.sh" ]]; then
  source "$script_dir/common.sh"
elif [[ -f "$script_dir/../scripts/common.sh" ]]; then
  source "$script_dir/../scripts/common.sh"
else
  # Duplicated from common.sh on purpose: that file is what we are about to
  # source, so the URL has to be known before it exists.
  bootstrap_url="https://github.com/nagualcode/toptop.git"
  command -v git >/dev/null 2>&1 || {
    echo "install.sh needs git, or a toptop checkout to run from" >&2
    exit 1
  }
  bootstrap_dir="$(mktemp -d)"
  trap 'rm -rf "$bootstrap_dir"' EXIT
  echo "Fetching toptop into a temporary checkout"
  git clone --depth 1 --quiet "$bootstrap_url" "$bootstrap_dir" \
    || { echo "could not clone $bootstrap_url" >&2; exit 1; }
  source "$bootstrap_dir/scripts/common.sh"
fi

SOURCE="$TOPTOP_REPO"
SOURCE_SET=0
FORCE=0
ASSUME_SHELL=1

usage() {
  cat <<USAGE
Usage: install.sh [source] [--force]

  source   a git URL, or a path to a toptop checkout to install from
           (defaults to $TOPTOP_REPO)

  --force  overwrite an installed toptop when installing from a local path

The bar layout in shell.json is left exactly as it is: toptop shows the same
left, centre and right sections you already have.
USAGE
}

while (( $# > 0 )); do
  case "$1" in
  --force | -f) FORCE=1; shift ;;
  -h | --help) usage; exit 0 ;;
  -*) fail "unknown option: $1" ;;
  *)
    (( ! SOURCE_SET )) || fail "unexpected argument: $1"
    SOURCE_SET=1
    SOURCE="$1"
    shift
    ;;
  esac
done

need jq "install.sh needs jq"

if ! shell_is_running; then
  ASSUME_SHELL=0
  echo "note: omarchy-shell is not responding; installing files only."
  echo "      Start the shell, then run: omarchy-shell shell enablePlugin $TOPTOP_ID '{}'"
fi

# --- 1. put the plugin on disk ---------------------------------------------

if [[ -d "$SOURCE" ]]; then
  LOCAL_SOURCE="$(readlink -f "$SOURCE")"
  if [[ "$LOCAL_SOURCE" == "$(readlink -f "$PLUGIN_DIR" 2>/dev/null || true)" ]]; then
    echo "Already installed from $LOCAL_SOURCE"
  elif [[ -e "$PLUGIN_DIR" || -L "$PLUGIN_DIR" ]]; then
    if (( FORCE )); then
      need rsync "install.sh needs rsync to overwrite an installed copy"
      echo "Updating $PLUGIN_DIR from $LOCAL_SOURCE"
      copy_plugin_tree "$LOCAL_SOURCE" "$PLUGIN_DIR"
      omarchy-plugin-validate "$PLUGIN_DIR" || fail "the copy at $PLUGIN_DIR does not validate"
    else
      # Not an error: re-running install is how you repair a broken install, and
      # the switch below is the part worth repeating.
      echo "$TOPTOP_ID is already installed at $PLUGIN_DIR; leaving it alone (--force to overwrite)"
    fi
  else
    need rsync "install.sh needs rsync to install from a local path"
    echo "Installing from $LOCAL_SOURCE"
    copy_plugin_tree "$LOCAL_SOURCE" "$PLUGIN_DIR"
    omarchy-plugin-validate "$PLUGIN_DIR" || fail "the copy at $PLUGIN_DIR does not validate"
  fi
else
  if [[ -e "$PLUGIN_DIR" || -L "$PLUGIN_DIR" ]]; then
    echo "Already installed at $PLUGIN_DIR (leaving it alone)"
  else
    need git "install.sh needs git to clone $SOURCE"
    echo "Installing from $SOURCE"
    omarchy plugin add "$SOURCE" --yes
  fi
fi

if (( ! ASSUME_SHELL )); then
  echo
  echo "Installed the files. Nothing else was changed."
  exit 0
fi

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
if ! wait_for_plugin_discovery "$TOPTOP_ID"; then
  fail "the shell has not picked up $TOPTOP_ID yet; run: omarchy-shell shell rescanPlugins"
fi

# --- 2. remember which bar we are replacing ---------------------------------

# Before anything writes, while the config is still the user's own arrangement.
backup_shell_config_once

PREVIOUS_BAR_ID="$(jq -r '.bar.id // empty' "$SHELL_CONFIG")"

# Only write the undo record when there is not a good one already. A second
# install runs with `bar.id` already set to toptop, so writing again would record
# toptop as the previous bar — quietly destroying the only thing that knows what
# to put back.
if [[ -f "$INSTALL_STATE" ]] && jq -e '.version == 1' "$INSTALL_STATE" >/dev/null 2>&1; then
  echo "Keeping the existing undo record at $INSTALL_STATE"
else
  write_json_file "$INSTALL_STATE" "$(jq -cn \
    --arg previousBarId "$PREVIOUS_BAR_ID" \
    '{ version: 1, previousBarId: $previousBarId }')"
fi

# --- 3. switch the bar over -------------------------------------------------
#
# Through the shell rather than by hand, so the shell owns the final write of
# its own config and the bar swaps in one step with the layout already loaded.
#
# The layout is not rewritten. toptop reads the same `bar.layout` the stock bar
# did, and it centres the three sections itself, so there is nothing to move.

if ! enable_plugin "$TOPTOP_ID"; then
  fail "the shell would not switch bars; run: omarchy-shell shell enablePlugin $TOPTOP_ID '{}'"
fi

cat <<DONE

TopTop is now the bar.

  Hover the notch      unfold it to show every icon
  Leave it             fold back to the centre section
  Left-drag an icon    move it; icons in the centre are the ones that stay
                       visible when the notch is folded
  Double-click the notch   toggle transparency

The notch reserves no screen space, so windows use the full height of the screen
and the notch is drawn over them. Nothing is pinned implicitly: the folded notch
shows the centre section and nothing else. Its options live in shell.json:

  "bar": {
    "toptop": {
      "pinned": ["io.github.example.battery"],
      "radius": 12,
      "padding": 8,
      "revealDuration": 180,
      "revealDelay": 120
    }
  }

Undo with: scripts/uninstall.sh
DONE