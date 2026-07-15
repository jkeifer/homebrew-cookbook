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

The flake exposes `homeManagerModules.default` (alias
`homeManagerModules.gribe`), which installs the package. As a Claude Code skill
can't be activated from a Nix profile, only from `~/.claude/skills/`, the flake
also supports linking gribe's embedded skill there. It also allows managing the
gribe config settings.

```nix
# flake.nix inputs: cookbook.url = "github:jkeifer/homebrew-cookbook";
# in your home-manager configuration:
imports = [ inputs.cookbook.homeManagerModules.default ];

programs.gribe.enable = true;
# install ~/.claude/skills/transgribe/SKILL.md for claude code (default false)
# programs.gribe.installSkill = true;
# override the package
# programs.gribe.package = ...;

# Declaratively manage ~/.config/transgribe/config:
programs.gribe.settings = {
  default-model = "parakeet-v3";
  default-language = "en-US";
  default-include-markup = false;
};
```

Setting `settings` makes home-manager own `~/.config/transgribe/config` (a
read-only store symlink), so `gribe config set`/`unset` will fail — manage it
here, or leave `settings` empty to keep using `gribe config` imperatively. See
`gribe config keys` for valid keys/values (Nix does not validate them). Note:
`settings` only takes effect on a gribe release that includes the `config`
command.

Without home-manager, the skill still ships inside the binary — run `gribe
skill install` to place it imperatively. The package also exposes it at
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
