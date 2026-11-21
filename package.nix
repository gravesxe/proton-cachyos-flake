{
  lib,
  stdenvNoCC,
  fetchurl,
  # Which upstream release to fetch. Defaults to the newest one in sources.json.
  version ? null,
  # Which upstream build to fetch: "x86_64", "x86_64_v2", "x86_64_v3", "x86_64_v4" or "arm64"
  # (whichever the release ships). Defaults to the generic build for the target platform.
  variant ? (if stdenvNoCC.hostPlatform.isAarch64 then "arm64" else "x86_64"),
  # true: rename the tool to a fixed name ("proton-cachyos", "proton-cachyos-v3", ...) so Steam
  # keeps using it across updates. false: keep upstream's versioned name, so a pinned release
  # can sit next to the auto-updating one.
  stableName ? true,
}:

let
  sources = builtins.fromJSON (builtins.readFile ./sources.json);
  release = if version == null then sources.latest else version;

  # "x86_64" and "arm64" share the plain name (a machine only ever has one architecture);
  # "x86_64_vN" becomes "proton-cachyos-vN"
  stableToolName =
    let
      level = builtins.match "x86_64_(v[0-9]+)" variant;
    in
    if level == null then "proton-cachyos" else "proton-cachyos-${builtins.head level}";

  platform = if variant == "arm64" then "aarch64-linux" else "x86_64-linux";
in

assert lib.assertMsg (sources.releases ? ${release})
  "proton-cachyos: release '${release}' is not in sources.json";
assert lib.assertMsg (sources.releases.${release} ? ${variant})
  "proton-cachyos: release '${release}' has no '${variant}' build (it has: ${lib.concatStringsSep ", " (builtins.attrNames sources.releases.${release})})";

stdenvNoCC.mkDerivation {
  pname = if stableName then stableToolName else "proton-cachyos-${variant}";
  version = release;

  src = fetchurl {
    url = "https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-${release}/proton-cachyos-${release}-${variant}.tar.xz";
    hash = sources.releases.${release}.${variant};
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  outputs = [
    "out"
    "steamcompattool"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $steamcompattool
    tar -xf $src -C $steamcompattool --strip-components=1

    vdf=$steamcompattool/compatibilitytool.vdf
    test -f "$vdf" || { echo "compatibilitytool.vdf missing from the release" >&2; exit 1; }
  ''
  + lib.optionalString stableName ''
    # Replace the versioned internal and display names with a stable one
    sed -i -r 's|"proton-cachyos[^"]*"|"${stableToolName}"|' "$vdf"
    grep -q '"${stableToolName}"' "$vdf" || { echo "failed to rename the tool in $vdf" >&2; exit 1; }
  ''
  + ''

    ln -s $steamcompattool $out

    runHook postInstall
  '';

  meta = {
    description = "CachyOS's optimised Proton build, for Steam's compatibility tools";
    homepage = "https://github.com/CachyOS/proton-cachyos";
    platforms = [ platform ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
