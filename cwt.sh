# cwt - fuzzy git repo & worktree switcher (bash + zsh)
#
# Source this file from your shell rc:  source /path/to/cwt.sh
# Then: cwt --store [path] | cwt --remove <name> | cwt --list
#       cwt <repo>           -> cd to repo main checkout
#       cwt <repo> <wtterm>  -> cd to a matching worktree
#       cwt                  -> fzf over every repo + worktree
#
# `cwt` must be a sourced function (not a script) so it can cd the parent shell.

# --- storage -----------------------------------------------------------------

_cwt_registry() {
  printf '%s/cwt/repos' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

# Read the registry, dropping records whose path no longer exists (rewriting the
# file when anything was pruned), and emit the live `name<TAB>path` records.
_cwt_load_repos() {
  local reg tmp changed name rdir
  reg="$(_cwt_registry)"
  [ -f "$reg" ] || return 0
  tmp="$(mktemp)"
  changed=0
  # NB: do not name a local "path" — in zsh it is tied to $PATH and assigning it
  # (or read-ing into it) clobbers command lookup inside the function.
  while IFS="$(printf '\t')" read -r name rdir; do
    [ -z "$name" ] && continue
    if [ -d "$rdir" ]; then
      printf '%s\t%s\n' "$name" "$rdir" >> "$tmp"
    else
      changed=1
    fi
  done < "$reg"
  if [ "$changed" -eq 1 ]; then
    mv "$tmp" "$reg"
  else
    rm -f "$tmp"
  fi
  [ -f "$reg" ] && cat "$reg"
}

# --- matching ----------------------------------------------------------------

# Reads `key<TAB>...` lines on stdin; prints matching lines prefixed with a rank
# field, sorted best-first: 0=exact 1=prefix 2=substring 3=subsequence 4=empty term.
_cwt_filter() {
  awk -F'\t' -v term="$1" '
    function subseq(t, k,   i, j) {
      j = 1
      for (i = 1; i <= length(k) && j <= length(t); i++)
        if (substr(k, i, 1) == substr(t, j, 1)) j++
      return j > length(t)
    }
    BEGIN { t = tolower(term) }
    {
      k = tolower($1); rank = -1
      if (t == "")            rank = 4
      else if (k == t)        rank = 0
      else if (index(k, t) == 1) rank = 1
      else if (index(k, t) > 0)  rank = 2
      else if (subseq(t, k))  rank = 3
      if (rank >= 0) print rank "\t" $0
    }
  ' | sort -n -k1,1 -s
}

# Reads candidate `key<TAB>value` lines on stdin, resolves $1 to a single value.
# Unique best-rank match -> that value. Several -> fzf picker (fallback: list+fail).
_cwt_resolve() {
  local term="$1" matched minrank best bestcount sel
  matched="$(_cwt_filter "$term")"
  if [ -z "$matched" ]; then
    echo "cwt: no match for '$term'" >&2
    return 1
  fi
  minrank="$(printf '%s\n' "$matched" | head -1 | cut -f1)"
  best="$(printf '%s\n' "$matched" | awk -F'\t' -v r="$minrank" '$1 == r')"
  bestcount="$(printf '%s\n' "$best" | grep -c '')"
  if [ "$bestcount" -eq 1 ]; then
    printf '%s\n' "$best" | cut -f3-
    return 0
  fi
  if command -v fzf >/dev/null 2>&1; then
    sel="$(printf '%s\n' "$matched" | cut -f2- \
      | fzf --select-1 --query="$term" --delimiter='\t' --with-nth=1)"
    [ -z "$sel" ] && return 1
    printf '%s\n' "$sel" | cut -f2-
  else
    echo "cwt: multiple matches for '$term':" >&2
    printf '%s\n' "$matched" | cut -f2 | sed 's/^/  /' >&2
    return 1
  fi
}

# Non-interactive: best-ranked first match's value (used by completion).
_cwt_resolve_first() {
  local matched
  matched="$(_cwt_filter "$1")"
  [ -z "$matched" ] && return 1
  printf '%s\n' "$matched" | head -1 | cut -f3-
}

# --- worktrees ---------------------------------------------------------------

# Emit `key<TAB>path` for every worktree of the given repo. key = branch name
# (refs/heads/ stripped); detached/anonymous heads fall back to the path leaf.
_cwt_worktrees() {
  git -C "$1" worktree list --porcelain 2>/dev/null | awk '
    function emit() {
      if (wt == "") return
      key = br
      if (key == "" || key == "(detached)") { n = split(wt, a, "/"); key = a[n] }
      print key "\t" wt
      wt = ""; br = ""
    }
    /^worktree /  { emit(); wt = substr($0, 10) }
    /^branch /    { br = substr($0, 8); sub("refs/heads/", "", br) }
    /^detached$/  { br = "(detached)" }
    END           { emit() }
  '
}

_cwt_main_checkout() {
  local main
  main="$(git -C "$1" worktree list --porcelain 2>/dev/null \
    | awk '/^worktree /{ print substr($0, 10); exit }')"
  [ -n "$main" ] && printf '%s\n' "$main" || printf '%s\n' "$1"
}

# --- commands ----------------------------------------------------------------

_cwt_cd() {
  [ -z "$1" ] && return 1
  cd "$1" || return 1
  printf 'cwt: %s\n' "$PWD"
}

_cwt_store() {
  local target abs main name reg tmp
  target="${1:-$PWD}"
  if [ ! -d "$target" ]; then
    echo "cwt: not a directory: $target" >&2
    return 1
  fi
  abs="$(cd "$target" 2>/dev/null && pwd)" || return 1
  if ! git -C "$abs" rev-parse --git-dir >/dev/null 2>&1; then
    echo "cwt: not a git repository: $abs" >&2
    return 1
  fi
  # Register the main checkout even when invoked from inside a worktree.
  main="$(_cwt_main_checkout "$abs")"
  abs="$main"
  name="$(basename "$abs")"
  reg="$(_cwt_registry)"
  mkdir -p "$(dirname "$reg")"
  touch "$reg"
  tmp="$(mktemp)"
  awk -F'\t' -v n="$name" '$1 != n' "$reg" > "$tmp"
  printf '%s\t%s\n' "$name" "$abs" >> "$tmp"
  sort -o "$tmp" "$tmp"
  mv "$tmp" "$reg"
  echo "cwt: stored '$name' -> $abs"
}

_cwt_remove() {
  local name reg tmp
  name="$1"
  if [ -z "$name" ]; then
    echo "cwt: --remove needs a repo name" >&2
    return 1
  fi
  reg="$(_cwt_registry)"
  [ -f "$reg" ] || { echo "cwt: nothing stored" >&2; return 1; }
  if ! awk -F'\t' -v n="$name" '$1 == n { found = 1 } END { exit !found }' "$reg"; then
    echo "cwt: no such repo: $name" >&2
    return 1
  fi
  tmp="$(mktemp)"
  awk -F'\t' -v n="$name" '$1 != n' "$reg" > "$tmp"
  mv "$tmp" "$reg"
  echo "cwt: removed '$name'"
}

_cwt_help() {
  cat >&2 <<'EOF'
cwt - fuzzy git repo & worktree switcher

  cwt <repo>            cd to a stored repo's main checkout (fuzzy)
  cwt <repo> <wt>       cd to a matching worktree of that repo (fuzzy)
  cwt                   fzf over every repo + worktree
  cwt --store [path]    store a repo (defaults to current dir)
  cwt --remove <name>   forget a repo  (also auto-removed if its path is gone)
  cwt --list            list stored repos
  cwt --help            this help

Matching: exact > prefix > substring > subsequence. Ambiguous terms open fzf.
EOF
}

cwt() {
  case "$1" in
    -s|--store)  _cwt_store "$2";  return $? ;;
    --rm|--remove) _cwt_remove "$2"; return $? ;;
    -l|--list)
      _cwt_load_repos | awk -F'\t' '{ printf "  %-28s %s\n", $1, $2 }'
      return 0 ;;
    -h|--help)   _cwt_help; return 0 ;;
  esac

  local repos repopath dest
  repos="$(_cwt_load_repos)"
  if [ -z "$repos" ]; then
    echo "cwt: no repos stored. Use 'cwt --store [path]'." >&2
    return 1
  fi

  # No args: fzf over all repos + worktrees.
  if [ -z "$1" ]; then
    if ! command -v fzf >/dev/null 2>&1; then
      echo "cwt: install fzf, or pass a repo name. Stored repos:" >&2
      printf '%s\n' "$repos" | cut -f1 | sed 's/^/  /' >&2
      return 1
    fi
    local name rdir sel
    sel="$(
      printf '%s\n' "$repos" | while IFS="$(printf '\t')" read -r name rdir; do
        [ -z "$name" ] && continue
        _cwt_worktrees "$rdir" | while IFS="$(printf '\t')" read -r wk wp; do
          printf '%s/%s\t%s\n' "$name" "$wk" "$wp"
        done
      done | fzf --delimiter='\t' --with-nth=1
    )"
    [ -z "$sel" ] && return 1
    _cwt_cd "$(printf '%s\n' "$sel" | cut -f2-)"
    return $?
  fi

  # Resolve repo.
  repopath="$(printf '%s\n' "$repos" | _cwt_resolve "$1")" || return 1

  # No worktree term: go to main checkout.
  if [ -z "$2" ]; then
    _cwt_cd "$(_cwt_main_checkout "$repopath")"
    return $?
  fi

  # Resolve worktree within the repo.
  dest="$(_cwt_worktrees "$repopath" | _cwt_resolve "$2")" || return 1
  _cwt_cd "$dest"
}

# --- completion --------------------------------------------------------------

if [ -n "$ZSH_VERSION" ]; then
  _cwt() {
    emulate -L zsh
    local cur cands
    if (( CURRENT == 2 )); then
      cur="${words[2]}"
      cands="$( { _cwt_load_repos | cut -f1
                  printf '%s\n' --store --remove --list --help; } \
                | _cwt_filter "$cur" | cut -f2 )"
      compadd -- ${(f)cands}
    elif (( CURRENT == 3 )); then
      local repopath
      repopath="$(_cwt_load_repos | _cwt_resolve_first "${words[2]}")"
      [ -z "$repopath" ] && return 0
      cur="${words[3]}"
      cands="$(_cwt_worktrees "$repopath" | cut -f1 | _cwt_filter "$cur" | cut -f2)"
      compadd -- ${(f)cands}
    fi
  }
  if (( $+functions[compdef] )); then
    compdef _cwt cwt
  fi
elif [ -n "$BASH_VERSION" ]; then
  _cwt_bash() {
    local cur cands repopath
    cur="${COMP_WORDS[COMP_CWORD]}"
    if [ "$COMP_CWORD" -eq 1 ]; then
      cands="$( { _cwt_load_repos | cut -f1
                  printf '%s\n' --store --remove --list --help; } \
                | _cwt_filter "$cur" | cut -f2 )"
    elif [ "$COMP_CWORD" -eq 2 ]; then
      repopath="$(_cwt_load_repos | _cwt_resolve_first "${COMP_WORDS[1]}")"
      [ -z "$repopath" ] && return 0
      cands="$(_cwt_worktrees "$repopath" | cut -f1 | _cwt_filter "$cur" | cut -f2)"
    else
      return 0
    fi
    local IFS=$'\n'
    COMPREPLY=( $cands )
  }
  complete -F _cwt_bash cwt
fi
