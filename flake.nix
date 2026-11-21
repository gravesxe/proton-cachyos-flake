{
  description = "Proton-CachyOS as a Steam compatibility tool for NixOS (x86_64 and aarch64)";

  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
    };
  };

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      sources = builtins.fromJSON (builtins.readFile ./sources.json);

      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = lib.genAttrs supportedSystems;

      # Attribute name for an upstream build:
      # "x86_64" / "arm64" -> "proton-cachyos", "x86_64_v3" -> "proton-cachyos-v3"
      aliasFor =
        variant:
        let
          level = builtins.match "x86_64_(v[0-9]+)" variant;
        in
        if level == null then "proton-cachyos" else "proton-cachyos-${builtins.head level}";

      systemFor = variant: if variant == "arm64" then "aarch64-linux" else "x86_64-linux";

      # The builds of a release that run on `system`
      variantsFor =
        system: version:
        builtins.filter (variant: systemFor variant == system) (
          builtins.attrNames sources.releases.${version}
        );

      # { proton-cachyos = <drv>; proton-cachyos-v3 = <drv>; ... } for one release and system
      buildsFor =
        pkgs: system: version: args:
        lib.listToAttrs (
          map (variant: {
            name = aliasFor variant;
            value = pkgs.callPackage ./package.nix ({ inherit version variant; } // args);
          }) (variantsFor system version)
        );

      # Every release, keeping upstream's versioned tool name so it can sit next to the
      # auto-updating package in Steam
      versionsFor =
        pkgs: system:
        lib.filterAttrs (_: builds: builds != { }) (
          lib.mapAttrs (version: _: buildsFor pkgs system version { stableName = false; }) sources.releases
        );
    in
    {
      packages = forAllSystems (
        system:
        let
          latest = buildsFor nixpkgs.legacyPackages.${system} system sources.latest { };
        in
        latest // { default = latest.proton-cachyos; }
      );

      # Pinned releases: legacyPackages.<system>.versions."<version>".proton-cachyos[-vN]
      legacyPackages = forAllSystems (system: {
        versions = versionsFor nixpkgs.legacyPackages.${system} system;
      });

      overlays = {
        # Attribute names come from sources.json only, never from `final`, so the overlay
        # doesn't recurse into the package set it is helping to build
        default =
          final: _prev:
          let
            latestVariants = builtins.attrNames sources.releases.${sources.latest};
            # x86_64_vN builds; the generic one is handled below
            optimised = lib.filter (variant: aliasFor variant != "proton-cachyos") latestVariants;
          in
          lib.listToAttrs (
            map (variant: {
              name = aliasFor variant;
              value = final.callPackage ./package.nix { inherit variant; };
            }) optimised
          )
          // {
            # x86_64 or arm64, whichever matches the target platform
            proton-cachyos = final.callPackage ./package.nix { };
            proton-cachyos-versions = versionsFor final final.stdenv.hostPlatform.system;
          };
      };

      devShells = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.mkShell {
          packages = with nixpkgs.legacyPackages.${system}; [
            curl
            jq
            shellcheck
          ];
        };
      });
    };
}
