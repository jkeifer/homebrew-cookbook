{
  description = "jkeifer's cookbook: Nix flake + Homebrew tap for personal CLI tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
      gribe = pkgs.callPackage ./pkgs/gribe { };

      gribeModule = { config, lib, ... }:
        let
          cfg = config.programs.gribe;
          renderValue = v: if lib.isBool v then (if v then "true" else "false") else toString v;
          # git-config style flat "key = value" file, matching gribe's own serializer.
          configText = lib.concatStrings (
            lib.mapAttrsToList (k: v: "${k} = ${renderValue v}\n") cfg.settings
          );
        in
        {
          options.programs.gribe = {
            enable = lib.mkEnableOption "gribe, the local audio transcription CLI";

            package = lib.mkOption {
              type = lib.types.package;
              default = gribe;
              defaultText = lib.literalExpression "gribe (from the cookbook flake)";
              description = "The gribe package to install.";
            };

            installSkill = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                Link the embedded transgribe Claude Code skill into
                ~/.claude/skills/transgribe/SKILL.md.
              '';
            };

            settings = lib.mkOption {
              type = lib.types.attrsOf (lib.types.either lib.types.str lib.types.bool);
              default = { };
              example = lib.literalExpression ''
                {
                  default-model = "parakeet-v3";
                  default-language = "en";
                  default-format = "json";
                  default-include-markup = false;
                }
              '';
              description = ''
                Declarative contents of gribe's config file
                (`$XDG_CONFIG_HOME/transgribe/config`, git-config style
                `key = value`).

                When this is non-empty, home-manager owns the file and it becomes
                a read-only store symlink, so `gribe config set`/`unset` will fail
                — manage configuration here instead. Leave it empty to keep the
                file mutable and use `gribe config` imperatively.

                Values are written verbatim (booleans as `true`/`false`) and are
                NOT validated by Nix; run `gribe config keys` for the valid keys
                and allowed values.
              '';
            };
          };

          config = lib.mkIf cfg.enable {
            home.packages = [ cfg.package ];

            home.file.".claude/skills/transgribe/SKILL.md" = lib.mkIf cfg.installSkill {
              source = "${cfg.package}/share/transgribe/SKILL.md";
            };

            xdg.configFile."transgribe/config" = lib.mkIf (cfg.settings != { }) {
              text = configText;
            };
          };
        };
    in
    {
      packages.${system} = {
        inherit gribe;
        default = gribe;
      };

      apps.${system} = {
        gribe = {
          type = "app";
          program = "${gribe}/bin/gribe";
        };
        default = self.apps.${system}.gribe;
      };

      overlays.default = final: _prev: {
        gribe = final.callPackage ./pkgs/gribe { };
      };

      homeManagerModules.gribe = gribeModule;
      homeManagerModules.default = gribeModule;
    };
}
