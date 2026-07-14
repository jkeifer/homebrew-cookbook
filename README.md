# homebrew-cookbook

A Nix flake **and** Homebrew tap distributing [jkeifer](https://github.com/jkeifer)'s
CLI tools. Versions are pinned here and decoupled from each tool's source — the tool
never knows its own version; this repo pins which released binary to serve.

Apple Silicon (`aarch64-darwin`) only.

## Tools

| Tool | Source | Description |
|------|--------|-------------|
| `gribe` | [transgribe](https://github.com/jkeifer/transgribe) | Transcribe audio locally on Apple Silicon |

## Install with Homebrew

```bash
brew tap jkeifer/cookbook
brew install gribe
```

## Install / run with Nix

```bash
# Run without installing
nix run github:jkeifer/homebrew-cookbook#gribe -- --help

# Add to a flake
inputs.cookbook.url = "github:jkeifer/homebrew-cookbook";
# then use inputs.cookbook.packages.aarch64-darwin.gribe,
# or inputs.cookbook.overlays.default for pkgs.gribe
```

Shell completions (bash/zsh/fish) are installed automatically by both channels.

### home-manager

The flake exposes `homeManagerModules.default` (alias `homeManagerModules.gribe`),
which installs the package and — because a Claude Code skill can't be activated from a
Nix profile, only from `~/.claude/skills/` — links gribe's embedded skill there:

```nix
# flake.nix inputs: cookbook.url = "github:jkeifer/homebrew-cookbook";
# in your home-manager configuration:
imports = [ inputs.cookbook.homeManagerModules.default ];

programs.gribe.enable = true;
# programs.gribe.installSkill = false;   # opt out of ~/.claude/skills/transgribe/SKILL.md
# programs.gribe.package = ...;          # override the package
```

Without home-manager, the skill still ships inside the binary — run `gribe skill install`
to place it imperatively. The package also exposes it at
`<gribe>/share/transgribe/SKILL.md`.

### Browser downloads

If you download a tool's binary directly from its GitHub releases page (not via Nix
or Homebrew), macOS quarantines it. Clear it with:

```bash
xattr -d com.apple.quarantine ./gribe
```

Nix and Homebrew installs are not quarantined and need no such step.

## How versions are pinned

Each tool has `pkgs/<tool>/source.json` (`repo`, `asset`, `version`, `sha256`) read by
the flake, and a matching `Formula/<tool>.rb` for Homebrew.

Bumps are automated: when a tool publishes a GitHub release, its CI sends a
`repository_dispatch` to this repo, and `.github/workflows/update.yml` recomputes the
hashes, **validates the flake still builds** (`nix build` on an arm64 macOS runner —
so a broken or renamed release binary can't land), and commits the bump straight to
`main`. You can also bump manually from the Actions tab
("Update tool" → Run workflow → tool + tag).

If `main` is protected against direct pushes, the workflow's push will fail — either
allow the `github-actions` bot to push, or switch the final step back to opening a PR.
