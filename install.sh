#!/usr/bin/env bash
# Idempotently wire cwt.sh into ~/.zshrc and ~/.bashrc.
set -euo pipefail

# Absolute path to cwt.sh sitting next to this installer.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
cwt_sh="$script_dir/cwt.sh"

if [ ! -f "$cwt_sh" ]; then
  echo "install: cannot find cwt.sh at $cwt_sh" >&2
  exit 1
fi

source_line="source \"$cwt_sh\""
marker="# cwt - git worktree switcher"

add_to_rc() {
  local rc="$1"
  if [ -f "$rc" ] && grep -Fq "$cwt_sh" "$rc"; then
    echo "install: already wired into $rc"
    return 0
  fi
  {
    printf '\n%s\n%s\n' "$marker" "$source_line"
  } >> "$rc"
  echo "install: added cwt to $rc"
}

add_to_rc "$HOME/.zshrc"
add_to_rc "$HOME/.bashrc"

cat <<EOF

Done. Start a new shell, or reload the current one:
  source ~/.zshrc      # zsh
  source ~/.bashrc     # bash

Quick start:
  cd /path/to/a/repo && cwt --store
  cwt <repo>            # jump to its main checkout
  cwt <repo> <term>     # jump to a matching worktree
EOF
