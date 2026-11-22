# proton-cachyos-flake

[Proton-CachyOS](https://github.com/CachyOS/proton-cachyos) packaged as a Nix flake, for use as a Steam
compatibility tool on NixOS. A GitHub Action checks for new CachyOS releases every six hours and
updates this repository automatically, so you never have to touch a version or a hash.

This repository contains only the Nix packaging. Nothing from CachyOS is redistributed: the build
downloads the official release tarball straight from
[CachyOS/proton-cachyos](https://github.com/CachyOS/proton-cachyos/releases) and checks it against a
pinned hash.

Every upstream release is available, from 9.0 onwards, in every CPU build CachyOS published for it.

## Packages

The auto-updating packages always follow the newest release:

| Package             | Systems         | Upstream build | Use it on                                                 |
| ------------------- | --------------- | -------------- | --------------------------------------------------------- |
| `proton-cachyos`    | `x86_64-linux`  | `x86_64`       | Any 64-bit x86 PC. This is the default.                   |
| `proton-cachyos`    | `aarch64-linux` | `arm64`        | Any 64-bit ARM machine. This is the default there.        |
| `proton-cachyos-v3` | `x86_64-linux`  | `x86_64_v3`    | CPUs with x86-64-v3 (Intel Haswell / AMD Zen 1 and newer) |

The variants are taken from whatever the newest release ships. CachyOS has published `x86_64_v2` and
`x86_64_v4` builds in the past. If they come back, `proton-cachyos-v2` and `proton-cachyos-v4` appear
automatically. To see what is available right now:

```fish
nix eval github:gravesxe/proton-cachyos-flake#packages.x86_64-linux --apply builtins.attrNames
```

`proton-cachyos` is the generic build for whichever architecture you are on, so the same line works on
both. Not sure whether your CPU qualifies for v3? Use `proton-cachyos`. It runs everywhere, and the v3
build is only a modest optimisation on top.

In Steam these show up under fixed names (`proton-cachyos`, `proton-cachyos-v3`), so games keep using
them across updates, and you can install several side by side.

### A note for ARM users

This flake packages the tool, and the ARM build is the one CachyOS publishes. Getting Steam itself
running on an ARM machine is a separate matter that this flake doesn't address: as far as I know,
nixpkgs' Steam package is x86-only, so ARM setups usually go through an emulation layer. I haven't
tested the ARM build on real hardware, so treat that side as untested. If you register tools by hand
instead of through `programs.steam`, the unpacked tool is available as the package's
`steamcompattool` output.

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
      url = "github:gravesxe/proton-cachyos-flake";
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

The overlay also provides `pkgs.proton-cachyos-versions`, which holds every pinned release for your system,
keyed by version: `pkgs.proton-cachyos-versions."10.0-sunset-slr".proton-cachyos-v3`. See
[Pinning an older release](#pinning-an-older-release).

## Installation on other Linux distributions

On a distribution other than NixOS, you don't need to change your system configuration. Install Nix
(with flakes enabled), build the tool, and link it into Steam's compatibility tools folder.

Enable flakes if you haven't already, by adding this to `~/.config/nix/nix.conf` (or to
`/etc/nix/nix.conf` on a multi-user install, which needs root):

```ini
experimental-features = nix-command flakes
```

Then build the package. `--no-link` avoids creating a `result` symlink, and `--print-out-paths` prints
the path to the tool:

```fish
set tool (nix build --no-link --print-out-paths github:gravesxe/proton-cachyos-flake#proton-cachyos.steamcompattool)
mkdir -p ~/.local/share/Steam/compatibilitytools.d
ln -sfn $tool ~/.local/share/Steam/compatibilitytools.d/proton-cachyos
```

On a CPU with x86-64-v3 support, use `proton-cachyos-v3` instead of `proton-cachyos` in both commands,
for example `#proton-cachyos-v3.steamcompattool` and `.../proton-cachyos-v3`. The v3 build installs as
its own tool, so you can have both side by side.

Steam only reads `compatibilitytools.d` at startup, so fully restart Steam afterwards. `proton-cachyos`
then appears in the compatibility dropdown, as described in [Using it in Steam](#using-it-in-steam).

Things to be aware of:

- **Updating.** The link points at the build you made, so it doesn't change on its own. Run the same
  two commands again to pick up a newer release. Nix fetches the latest version of this flake each time.
- **Steam from Flatpak.** A Flatpak Steam can't see `/nix/store` unless it is given access. Either
  install Steam natively, or override the Flatpak's permissions (for example with
  `flatpak override --user --filesystem=/nix/store com.valvesoftware.Steam`) and link into
  `~/.var/app/com.valvesoftware.Steam/data/Steam/compatibilitytools.d` instead. This is untested here.
- **Steam from Snap.** Snap Steam uses its own home directory and may not see the tool. This is untested
  as well.

## Pinning an older release

Every upstream release stays available under `legacyPackages`, keyed by its version (the release tag
without `cachyos-`):

```nix
programs.steam.extraCompatPackages = [
  inputs.proton-cachyos.packages.${pkgs.stdenv.hostPlatform.system}.proton-cachyos-v3
  inputs.proton-cachyos.legacyPackages.${pkgs.stdenv.hostPlatform.system}.versions."10.0-sunset-slr".proton-cachyos-v3
];
```

A pinned release keeps CachyOS's own versioned name in Steam (for example
`proton-cachyos-10.0-sunset-slr-x86_64_v3`), so it sits next to the auto-updating one rather than
replacing it. Each release only offers the builds CachyOS made for it. Some 10.0 releases have `-v2`
and `-v4`, and releases before 2026 have no ARM build. To list them:

```fish
nix eval github:gravesxe/proton-cachyos-flake#legacyPackages.x86_64-linux.versions --apply builtins.attrNames
nix eval 'github:gravesxe/proton-cachyos-flake#legacyPackages.x86_64-linux.versions."10.0-20260425-slr"' --apply builtins.attrNames
```

## Using it in Steam

For a single game: right-click it, choose **Properties → Compatibility**, tick **Force the use of a
specific Steam Play compatibility tool**, and select `proton-cachyos` (or `proton-cachyos-v3`).

For every game: **Steam → Settings → Compatibility**, enable **Steam Play for all other titles**, and
choose the tool there.

Occasionally a major Proton bump needs a fresh prefix. If a game misbehaves after an update, delete its
`steamapps/compatdata/<appid>` folder and launch it again.

## Getting updates

Updates arrive as ordinary commits to this repository, so they reach you like any other flake input:

```fish
nix flake update proton-cachyos     # just this input
nix flake update                    # everything
```

With `nh`, `nh os switch --update` already does the latter. To freeze the whole flake, pin the input to
a commit: `url = "github:gravesxe/proton-cachyos-flake/<commit-sha>";`.

## How the auto-update works

`.github/workflows/update.yml` runs every six hours (and on demand):

1. `scripts/update.sh` reads the full release list from the GitHub API and rebuilds `sources.json`.
   That file lists every release, every build and its hash. It downloads no tarballs. Hashes come from
   the sha256 digest GitHub records for each asset. Older assets have no digest, so for those the
   script uses the `.sha512sum` file CachyOS uploads next to each tarball. Nix verifies the real
   download against that hash whenever anyone builds it.
2. The newest release is the one with the **highest version**, not the most recently published one.
   This matters because CachyOS sometimes publishes an update to an older line, such as
   `10.0-sunset-slr`, after 11.0 releases have started. The auto-updating packages never jump
   backwards.
3. If nothing changed, the run ends there. Otherwise the workflow builds every package of the newest
   release natively: the x86_64 ones on a standard runner and the aarch64 one on a GitHub ARM runner.
   A release that doesn't build is never committed.
4. Only after every build succeeds does it commit the new `sources.json` and push.

`.github/workflows/ci.yml` evaluates every package, including all pinned releases on both systems, on
each push and pull request.

If a run fails, the repository stays on the last good version and GitHub emails you about the failed
workflow.

## Setting up your own copy (maintainers)

1. Create the repository on GitHub and push this code to it.
2. Go to **Settings → Actions → General → Workflow permissions** and select **Read and write
   permissions**, so the workflow can push its commits.
3. If you protect `main`, allow GitHub Actions to bypass the protection, or the push will be rejected.
4. Open the **Actions** tab, choose **update**, and press **Run workflow** once. On a fresh copy it
   should finish with "Up to date".
5. Pin the third-party action in the workflows to a commit SHA rather than `@main`, and consider
   enabling Dependabot for `github-actions`.

The aarch64 build runs on the `ubuntu-24.04-arm` runner. GitHub provides that runner for public
repositories; for a private repository it may not be available on your plan. If you don't want ARM
builds checked, delete the `ubuntu-24.04-arm` entry from the matrix in `update.yml`.

GitHub may disable scheduled workflows on public repositories after about 60 days without activity. If
updates stop arriving, check the Actions tab and re-enable the workflow.

### Updating by hand

```fish
nix develop                                  # curl, jq and shellcheck
GH_TOKEN=(gh auth token) ./scripts/update.sh # GH_TOKEN is optional, it avoids API rate limits
nix build .#proton-cachyos                   # the generic build for your machine's architecture
nix build .#proton-cachyos-v3                # x86_64 only
```

### Checking changes

```fish
nix flake check --no-build --all-systems
nix build .#proton-cachyos-v3 --print-out-paths
cat result/compatibilitytool.vdf   # tool names should read "proton-cachyos-v3"
```

## Troubleshooting

- **The tool doesn't appear in Steam.** Restart Steam completely, and check that you rebuilt after
  adding it to `extraCompatPackages`.
- **`hash mismatch` during a build.** `sources.json` and the upstream file disagree, usually because
  CachyOS re-uploaded an asset. Run `./scripts/update.sh`, or open an issue if you're on the latest
  commit.
- **`release '…' has no '…' build`.** That release doesn't include that CPU build. The error lists
  the builds it does have.
- **The game runs worse than with another Proton.** Try `proton-cachyos` instead of the v3 build, or
  compare against `proton-ge-bin` for that game.
- **Steam can't find the tool after switching variants.** Each variant has its own name, so reselect
  the tool in the game's properties.

## Licence

The packaging code is MIT-licensed (see `LICENSE`). Proton-CachyOS is a separate project with its own
licences; see [its repository](https://github.com/CachyOS/proton-cachyos).
