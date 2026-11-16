{
  description = "Proton-CachyOS as a Steam compatibility tool for NixOS";

  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
    };
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      build = variant: pkgs.callPackage ./package.nix { inherit variant; };
    in
    {
      packages = {
        ${system} = {
          # Generic x86-64: works on any 64-bit PC
          proton-cachyos = build "x86_64";
          # Optimised for x86-64-v3 CPUs (Intel Haswell / AMD Zen 1 and newer)
          proton-cachyos-v3 = build "x86_64_v3";
          default = self.packages.${system}.proton-cachyos;
        };
      };

      overlays = {
        default = final: _prev: {
          proton-cachyos = final.callPackage ./package.nix { variant = "x86_64"; };
          proton-cachyos-v3 = final.callPackage ./package.nix { variant = "x86_64_v3"; };
        };
      };

      devShells = {
        ${system} = {
          default = pkgs.mkShell {
            packages = with pkgs; [
              curl
              jq
              shellcheck
            ];
          };
        };
      };
    };
}
