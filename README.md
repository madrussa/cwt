# cwt

Fuzzy switcher for local git repos and their worktrees, for **bash** and **zsh**.

Jump to any registered repo or one of its worktrees with short, fuzzy terms — and
tab-complete those terms. It works regardless of how your worktrees are laid out
(`myapp/.worktrees/feature/...`, `webapp/.git-worktrees/<name>`, sibling dirs like
`myapp-hotfix`, etc.) because it enumerates them via `git worktree list`, not
hard-coded paths.

![cwt demo](demo.gif)

```sh
cwt webapp signup-flow   # -> webapp's worktree whose branch matches "signup-flow"
cwt api update-deps      # -> api's matching worktree
cwt webapp               # -> webapp main checkout
cwt web<TAB>             # -> completes "webapp"
```

## Install

```sh
git clone https://github.com/<you>/cwt.git ~/.local/share/cwt
~/.local/share/cwt/install.sh   # adds a source line to ~/.zshrc and ~/.bashrc
source ~/.zshrc                 # or open a new shell
```

The installer is idempotent — re-running it won't duplicate the source line. To wire
it up manually instead, add this to your rc file:

```sh
source "/absolute/path/to/cwt/cwt.sh"
```

## Usage

| Command | Action |
| --- | --- |
| `cwt <repo>` | cd to the repo's main checkout (fuzzy match on name) |
| `cwt <repo> <wt>` | cd to a matching worktree of that repo (fuzzy match on branch) |
| `cwt` | fzf over every stored repo + worktree |
| `cwt --store [path]` | store a repo (defaults to the current directory) |
| `cwt --remove <name>` | forget a repo |
| `cwt --list` | list stored repos |
| `cwt --help` | help |

```sh
cd ~/code/webapp && cwt --store   # registers "webapp"
cd ~/code/api    && cwt --store   # registers "api"
cwt --list
```

`--store` from inside a worktree registers the repo's **main checkout**, so all its
worktrees become reachable. Stored repos whose path no longer exists are pruned
automatically on the next invocation.

## Matching

Terms are ranked **exact > prefix > substring > subsequence**, case-insensitive. A
unique best match jumps straight there; if several candidates tie, an `fzf` picker
opens (pre-seeded with your term). Without `fzf`, the candidates are listed instead.

## Requirements

- `git` (2.5+, for worktrees), `awk`, `sort`, `sed`, `cut` (all standard).
- `fzf` (optional but recommended) for interactive disambiguation and the no-arg menu.

### Installing fzf

```sh
brew install fzf                 # macOS / Linuxbrew
sudo apt install fzf             # Debian / Ubuntu
sudo dnf install fzf             # Fedora
sudo pacman -S fzf               # Arch
```

Or install the latest release straight from the source repo (any OS):

```sh
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf && ~/.fzf/install
```

See the [fzf README](https://github.com/junegunn/fzf#installation) for more options.

## How it works

`cwt` is a **shell function** (it must run in your shell to change its directory).
The registry lives at `${XDG_CONFIG_HOME:-$HOME/.config}/cwt/repos` — one
tab-separated `name<TAB>path` record per line.
