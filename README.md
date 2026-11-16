# proton-cachyos-flake

[Proton-CachyOS](https://github.com/CachyOS/proton-cachyos) packaged as a Nix flake, for use as a Steam
compatibility tool on NixOS. A GitHub Action checks for new CachyOS releases every six hours and
updates this repository automatically, so you never have to touch a version or a hash.

This repository contains only the Nix packaging. Nothing from CachyOS is redistributed: the build
downloads the official release tarball straight from
[CachyOS/proton-cachyos](https://github.com/CachyOS/proton-cachyos/releases) and checks it against a
pinned hash.

## Packages

| Package             | Build         | Use it on                                                 |
| ------------------- | ------------- | --------------------------------------------------------- |
| `proton-cachyos`    | `x86_64`      | Any 64-bit x86 PC. This is the default.                   |
| `proton-cachyos-v3` | `x86_64_v3`   | CPUs with x86-64-v3 (Intel Haswell / AMD Zen 1 and newer) |

Not sure whether your CPU qualifies? Use `proton-cachyos`. It runs everywhere, and the v3 build is
only a modest optimisation on top.

The two builds show up in Steam under different names (`proton-cachyos` and `proton-cachyos-v3`), so
you can install both side by side. Only x86_64 Linux is supported.

## Installation (NixOS with flakes)

Add the flake as an input:

```nix
# flake.nix
{
  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
    };
    proton-cachyos = {
      url = "github:YOURUSER/proton-cachyos-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, ... }@inputs: {
    nixosConfigurations = {
      myhost = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [ ./configuration.nix ];
      };
    };
  };
}
```

Then register it with Steam in your NixOS configuration:

```nix
# configuration.nix
{ pkgs, inputs, ... }:
{
  programs = {
    steam = {
      enable = true;
      extraCompatPackages = [
        inputs.proton-cachyos.packages.${pkgs.stdenv.hostPlatform.system}.proton-cachyos
        # or, on a modern CPU:
        # inputs.proton-cachyos.packages.${pkgs.stdenv.hostPlatform.system}.proton-cachyos-v3
      ];
    };
  };
}
```

Rebuild, **fully restart Steam** (it only looks for compatibility tools at startup), and you're done.

### Using the overlay instead

If you prefer plain package names, apply the overlay and refer to `pkgs.proton-cachyos`:

```nix
nixpkgs.overlays = [ inputs.proton-cachyos.overlays.default ];

programs.steam.extraCompatPackages = [ pkgs.proton-cachyos ];
```

## Using it in Steam

For a single game: right-click it, choose **Properties → Compatibility**, tick **Force the use of a
specific Steam Play compatibility tool**, and select `proton-cachyos` (or `proton-cachyos-v3`).

For every game: **Steam → Settings → Compatibility**, enable **Steam Play for all other titles**, and
choose the tool there.

Because the tool name never contains a version number, games keep using it after updates. Occasionally
a major Proton bump needs a fresh prefix. If a game misbehaves after an update, delete its
`steamapps/compatdata/<appid>` folder and launch it again.

## Getting updates

Updates arrive as ordinary commits to this repository, so they reach you like any other flake input:

```fish
nix flake update proton-cachyos     # just this input
nix flake update                    # everything
```

With `nh`, `nh os switch --update` already does the latter. To stay on a specific version, pin the
input to a commit: `url = "github:YOURUSER/proton-cachyos-flake/<commit-sha>";`.

## How the auto-update works

`.github/workflows/update.yml` runs every six hours (and on demand):

1. `scripts/update.sh` asks GitHub for the latest CachyOS release tag. If it matches the version in
   `sources.json`, the run ends there. It is cheap and downloads nothing.
2. Otherwise it downloads both builds, computes their Nix hashes, and cross-checks each against the
   `.sha512sum` file CachyOS publishes with the release. A mismatch aborts the run.
3. The workflow then builds both packages. A release that doesn't build is never committed.
4. Only after a successful build does it commit the new `sources.json` and push.

If a run fails, the repository stays on the last good version and GitHub emails you about the failed
workflow.

## Setting up your own copy (maintainers)

1. Create the repository on GitHub and push this code to it.
2. Go to **Settings → Actions → General → Workflow permissions** and select **Read and write
   permissions**, so the workflow can push its commits.
3. If you protect `main`, allow GitHub Actions to bypass the protection, or the push will be rejected.
4. Open the **Actions** tab, choose **update**, and press **Run workflow** once. On a fresh copy it
   should finish with "Up to date".
5. Pin the third-party action in the workflow to a commit SHA rather than `@main`, and consider
   enabling Dependabot for `github-actions`.

GitHub may disable scheduled workflows on public repositories after about 60 days without activity. If
updates stop arriving, check the Actions tab and re-enable the workflow.

### Updating by hand

```fish
nix develop                 # curl, jq and shellcheck
./scripts/update.sh         # edits sources.json if there is a newer release
nix build .#proton-cachyos .#proton-cachyos-v3
```

### Checking changes

```fish
nix flake check
nix build .#proton-cachyos-v3 --print-out-paths
cat result/compatibilitytool.vdf   # tool names should read "proton-cachyos-v3"
```

## Troubleshooting

- **The tool doesn't appear in Steam.** Restart Steam completely, and check that you rebuilt after
  adding it to `extraCompatPackages`.
- **`hash mismatch` during a build.** `sources.json` and the upstream file disagree. Run
  `./scripts/update.sh`, or open an issue if you're on the latest commit.
- **The game runs worse than with another Proton.** Try `proton-cachyos` instead of the v3 build, or
  compare against `proton-ge-bin` for that game.
- **Steam can't find the tool after switching variants.** The two variants have different names, so
  reselect the tool in the game's properties.

## Licence

The packaging code is MIT-licensed (see `LICENSE`). Proton-CachyOS is a separate project with its own
licences; see [its repository](https://github.com/CachyOS/proton-cachyos).
