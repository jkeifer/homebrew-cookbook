{
  description = "jkeifer's cookbook: Nix flake + Homebrew tap for personal CLI tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
      gribe = pkgs.callPackage ./pkgs/gribe { };
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
    };
}
