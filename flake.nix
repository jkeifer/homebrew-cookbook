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
          };

          config = lib.mkIf cfg.enable {
            home.packages = [ cfg.package ];

            home.file.".claude/skills/transgribe/SKILL.md" = lib.mkIf cfg.installSkill {
              source = "${cfg.package}/share/transgribe/SKILL.md";
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
