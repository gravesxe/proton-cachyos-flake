#!/usr/bin/env bash
# Checks CachyOS/proton-cachyos for a newer release and, if there is one,
# rewrites sources.json with the new version and verified hashes.
# Needs: bash, curl, jq, nix, coreutils (sha512sum), awk.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

repo="CachyOS/proton-cachyos"
variants=(x86_64 x86_64_v3)
nix_flags=(--extra-experimental-features "nix-command flakes")

# Report a value to the GitHub Actions workflow (no-op outside Actions)
output() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "$1" >>"$GITHUB_OUTPUT"
  fi
}

# /releases/latest redirects to the newest release's tag page
latest_url=$(curl -fsSIL -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest")
tag="${latest_url##*/}"
if [[ ! "$tag" =~ ^cachyos-[0-9] ]]; then
  echo "Unexpected release tag '$tag' (from $latest_url), refusing to continue" >&2
  exit 1
fi
version="${tag#cachyos-}"
current=$(jq -r .version sources.json)

if [ "$version" = "$current" ]; then
  echo "Up to date ($current)"
  output "updated=false"
  exit 0
fi

echo "Updating $current -> $version"
base="https://github.com/$repo/releases/download/$tag"
hashes='{}'

for variant in "${variants[@]}"; do
  asset="proton-cachyos-$version-$variant.tar.xz"
  echo "Fetching $asset"

  prefetch=$(nix "${nix_flags[@]}" store prefetch-file --json "$base/$asset")
  hash=$(jq -r .hash <<<"$prefetch")
  store_path=$(jq -r .storePath <<<"$prefetch")

  # Cross-check against the checksum CachyOS publishes next to each asset
  expected=$(curl -fsSL "$base/${asset%.tar.xz}.sha512sum" | awk '{print $1}')
  actual=$(sha512sum "$store_path" | awk '{print $1}')
  if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
    echo "sha512 mismatch for $asset (upstream: '$expected', downloaded: '$actual')" >&2
    exit 1
  fi

  hashes=$(jq -c --arg k "$variant" --arg h "$hash" '. + {($k): $h}' <<<"$hashes")
done

# shellcheck disable=SC2016
jq -n --arg version "$version" --argjson hashes "$hashes" \
  '{ version: $version, hashes: $hashes }' >sources.json.tmp
mv sources.json.tmp sources.json

output "updated=true"
output "version=$version"
echo "Done: sources.json is now at $version"
