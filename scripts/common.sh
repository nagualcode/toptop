#!/usr/bin/env bash
# Shared helpers for the toptop install and uninstall scripts.
#
# Sourced, never executed.

set -euo pipefail

TOPTOP_ID="nagualcode.toptop"
TOPTOP_REPO="https://github.com/nagualcode/toptop.git"

OMARCHY_CONFIG_DIR="$HOME/.config/omarchy"
SHELL_CONFIG="$OMARCHY_CONFIG_DIR/shell.json"
SHELL_CONFIG_BACKUP="$OMARCHY_CONFIG_DIR/toptop-shell.json.bak"
PLUGINS_DIR="$OMARCHY_CONFIG_DIR/plugins"
PLUGIN_DIR="$PLUGINS_DIR/$TOPTOP_ID"
# How to undo the shell.json edit install.sh made.
INSTALL_STATE="$OMARCHY_CONFIG_DIR/toptop-install.json"

fail() {
  echo "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || fail "$2"
}

# Copy a plugin into place without ever exposing a half-written tree.
#
# The running shell watches the plugin directory and reloads a plugin the moment
# something in it changes, parsing whatever it finds at that instant. `rsync`
# straight into the live directory writes files one at a time, so the shell can
# read a truncated QML file and report a syntax error that no longer exists once
# the copy finishes — which is a miserable thing to debug. Staging the tree and
# swapping it in with a rename means the only thing the watcher can see is a
# whole plugin.
#
# The staging and previous trees deliberately sit beside the plugin directory
# rather than inside it. Anything holding a manifest.json in the watched
# directory is a plugin as far as the shell is concerned, so a
# `nagualcode.toptop.staging.1234` sitting next to the real one gets loaded as
# a second, broken plugin and makes the shell reload everything twice. Beside
# is also the same filesystem, which is what keeps the swap a rename.
copy_plugin_tree() {
  local source="$1" target="$2"
  local staging previous

  rm -rf "$target.staging."* "$target.old."* 2>/dev/null || true
  staging="$(dirname "$target")/.$(basename "$target").staging.$$"
  previous="$(dirname "$target")/.$(basename "$target").previous.$$"

  rm -rf "$staging" "$previous"
  mkdir -p "$staging"
  if ! rsync -a --delete --exclude '.git' "$source"/ "$staging"/; then
    rm -rf "$staging"
    return 1
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    if ! mv "$target" "$previous"; then
      rm -rf "$staging"
      return 1
    fi
  fi
  if ! mv "$staging" "$target"; then
    # Put the working copy back rather than leaving no plugin at all.
    [[ -e "$previous" ]] && mv "$previous" "$target"
    rm -rf "$staging"
    return 1
  fi
  rm -rf "$previous"
}

# Keep the first copy of shell.json we ever see, so a bad edit is always
# recoverable. Written before install.sh switches the bar over, which is the
# moment the config stops being the user's own arrangement.
#
# First touch wins and it is never overwritten: the whole point is to capture the
# state from before toptop ran, so a second install must not clobber it with a
# config that already names toptop.
backup_shell_config_once() {
  [[ -f "$SHELL_CONFIG" ]] || return 0
  [[ -f "$SHELL_CONFIG_BACKUP" ]] && return 0
  cp -p "$SHELL_CONFIG" "$SHELL_CONFIG_BACKUP"
}

# Replace a file in one step, so a watcher never reads a half-written config.
# This is the same trick the shell's own FileView uses with atomicWrites.
write_json_file() {
  local target="$1" content="$2" tmp
  tmp="$(mktemp "${target}.XXXXXX")"
  printf '%s\n' "$content" >"$tmp"
  [[ -f "$target" ]] && chmod --reference="$target" "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$target"
}

# Run a jq program over shell.json and replace the file with the result.
#
# The new content is built and validated in full before anything is moved into
# place, so a jq error leaves the user's shell.json exactly as it was. That
# matters more than it looks: shell.json is the whole shell's configuration, and
# a helper that installs an empty file on failure would take the desktop with
# it. The rename is atomic, so the shell's file watcher never sees a partial
# write either.
rewrite_shell_config() {
  local original rewritten tmp
  [[ -f "$SHELL_CONFIG" ]] || fail "no shell.json at $SHELL_CONFIG"

  original="$(cat "$SHELL_CONFIG")" || fail "could not read $SHELL_CONFIG"
  rewritten="$(jq "$@" <<<"$original")" || fail "jq failed; $SHELL_CONFIG left untouched"
  [[ -n "$rewritten" ]] || fail "jq produced no output; $SHELL_CONFIG left untouched"
  jq -e . >/dev/null <<<"$rewritten" || fail "jq produced invalid JSON; $SHELL_CONFIG left untouched"

  # A first-touch backup, so a bad hand-edit is always recoverable. Never
  # overwritten: the point is to capture the state before toptop ran.
  backup_shell_config_once

  tmp="$(mktemp "${SHELL_CONFIG}.XXXXXX")"
  printf '%s\n' "$rewritten" >"$tmp"
  chmod --reference="$SHELL_CONFIG" "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$SHELL_CONFIG"
}

shell_is_running() {
  omarchy-shell -q shell ping >/dev/null 2>&1
}

# Wait until the shell's plugin registry has actually noticed a plugin.
#
# The registry rescans asynchronously, and a freshly copied plugin folder is not
# in it yet. Enabling before the rescan lands fails with "unknown plugin", and
# nothing retries it — so wait for the plugin to show up rather than guessing.
wait_for_plugin_discovery() {
  local id="$1" attempt
  for attempt in $(seq 1 60); do
    if omarchy-shell shell listPlugins 2>/dev/null \
      | jq -e --arg id "$id" 'any(.[]; .id == $id)' >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

# Switch the shell onto a bar plugin, retrying.
#
# Retried because swapping the bar makes the shell rebuild its window tree, and
# for a moment it answers no IPC at all. A first attempt landing in that window
# fails for a reason that has already resolved itself, so try again before
# treating it as a real refusal.
enable_plugin() {
  local id="$1" attempt
  for attempt in 1 2 3 4 5; do
    if omarchy-shell shell enablePlugin "$id" '{}' >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}