#!/usr/bin/env bash
# Syncs sources.json with every release of CachyOS/proton-cachyos: adds new releases and
# builds, drops ones that were deleted upstream, and points "latest" at the highest version.
#
# No tarball is downloaded. Hashes come from the sha256 digest GitHub publishes for each
# asset or, for older assets without one, from the .sha512sum file CachyOS uploads next to
# it. Nix checks the real download against that hash at build time.
#
# Needs: bash, curl, jq, nix, coreutils. Set GH_TOKEN to avoid the API's anonymous rate limit.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

repo="CachyOS/proton-cachyos"
nix_flags=(--extra-experimental-features nix-command)

# Report a value to the GitHub Actions workflow (no-op outside Actions)
output() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "$1" >>"$GITHUB_OUTPUT"
  fi
}

to_sri() { # algo hex
  nix "${nix_flags[@]}" hash convert --hash-algo "$1" --to sri "$2"
}

auth=()
if [ -n "${GH_TOKEN:-}" ]; then
  auth=(-H "Authorization: Bearer $GH_TOKEN")
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# All releases, one API page at a time
page=1
echo '[]' >"$tmp/releases.json"
while :; do
  curl -fsSL "${auth[@]}" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$repo/releases?per_page=100&page=$page" >"$tmp/page.json"
  [ "$(jq length "$tmp/page.json")" -gt 0 ] || break
  jq -s 'add' "$tmp/releases.json" "$tmp/page.json" >"$tmp/merged.json"
  mv "$tmp/merged.json" "$tmp/releases.json"
  page=$((page + 1))
done

# One "version variant digest" line per published tarball
# (variant names are validated in the loop below)
jq -r '
  .[]
  | select((.draft | not) and (.prerelease | not) and (.tag_name | startswith("cachyos-")))
  | (.tag_name | ltrimstr("cachyos-")) as $version
  | .assets[]
  | select(.name | startswith("proton-cachyos-" + $version + "-") and endswith(".tar.xz"))
  | "\($version) \(.name | ltrimstr("proton-cachyos-" + $version + "-") | rtrimstr(".tar.xz")) \(.digest // "-")"
' "$tmp/releases.json" >"$tmp/assets.txt"

if [ ! -s "$tmp/assets.txt" ]; then
  echo "No release assets found upstream, refusing to continue" >&2
  exit 1
fi

old='{"latest": null, "releases": {}}'
[ -f sources.json ] && old=$(cat sources.json)
releases='{}'

while read -r version variant digest; do
  if [[ ! "$version" =~ ^[0-9] ]] || [[ ! "$variant" =~ ^(arm64|x86_64(_v[0-9]+)?)$ ]]; then
    echo "Skipping unexpected asset: $version $variant" >&2
    continue
  fi

  if [[ "$digest" == sha256:* ]]; then
    # Always taken from the API, so a re-uploaded asset is picked up
    hash=$(to_sri sha256 "${digest#sha256:}")
  else
    hash=$(jq -r --arg v "$version" --arg a "$variant" '.releases[$v][$a] // empty' <<<"$old")
    if [ -z "$hash" ]; then
      asset="proton-cachyos-$version-$variant"
      echo "Fetching $asset.sha512sum"
      hex=$(curl -fsSL "https://github.com/$repo/releases/download/cachyos-$version/$asset.sha512sum" |
        awk '{print $1; exit}')
      if [[ ! "$hex" =~ ^[0-9a-f]{128}$ ]]; then
        echo "Bad or missing sha512sum for $asset: '$hex'" >&2
        exit 1
      fi
      hash=$(to_sri sha512 "$hex")
    fi
  fi

  releases=$(jq -c --arg v "$version" --arg a "$variant" --arg h "$hash" \
    '.[$v][$a] = $h' <<<"$releases")
done <"$tmp/assets.txt"

latest=$(jq -r 'keys[]' <<<"$releases" | sort -V | tail -n 1)
previous=$(jq -r '.latest // ""' <<<"$old")

jq -S -n --arg latest "$latest" --argjson releases "$releases" \
  '{ latest: $latest, releases: $releases }' >sources.json.tmp

if [ -f sources.json ] && cmp -s sources.json sources.json.tmp; then
  rm sources.json.tmp
  echo "Up to date (latest: $latest)"
  output "updated=false"
  exit 0
fi
mv sources.json.tmp sources.json

added=$(jq -n --argjson o "$old" --argjson n "$releases" \
  '[$n | keys[] as $k | select($o.releases // {} | has($k) | not)] | length')
if [ "$latest" != "$previous" ]; then
  summary="update proton-cachyos to $latest"
else
  summary="sync proton-cachyos releases (latest still $latest)"
fi
if [ "$added" -gt 0 ]; then
  summary="$summary, +$added release(s)"
fi

output "updated=true"
output "version=$latest"
output "summary=$summary"
echo "Done: $summary"
