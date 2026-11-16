#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

repo="CachyOS/proton-cachyos"
variants=(x86_64 x86_64_v3)

# /releases/latest redirects to the newest release's tag page
latest_url=$(curl -fsSIL -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest")
tag="${latest_url##*/}"
version="${tag#cachyos-}"
current=$(jq -r .version sources.json)

if [ "$version" = "$current" ]; then
  echo "Up to date ($current)"
  exit 0
fi

echo "Updating $current -> $version"
hashes='{}'
for variant in "${variants[@]}"; do
  url="https://github.com/$repo/releases/download/$tag/proton-cachyos-$version-$variant.tar.xz"
  hash=$(nix store prefetch-file --json "$url" | jq -r .hash)
  hashes=$(jq -c --arg k "$variant" --arg h "$hash" '. + {($k): $h}' <<<"$hashes")
done

jq -n --arg version "$version" --argjson hashes "$hashes" \
  '{ version: $version, hashes: $hashes }' >sources.json.tmp
mv sources.json.tmp sources.json

echo "version=$version" >>"${GITHUB_OUTPUT:-/dev/null}"
