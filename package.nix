{
  lib,
  stdenvNoCC,
  fetchurl,
  variant ? "x86_64",
}:

let
  sources = builtins.fromJSON (builtins.readFile ./sources.json);

  # Steam identifies a compatibility tool by this name, so it is kept stable
  # across updates. It differs per variant so both can be installed together.
  toolName = if variant == "x86_64_v3" then "proton-cachyos-v3" else "proton-cachyos";
in

assert lib.assertMsg (
  sources.hashes ? ${variant}
) "proton-cachyos: no hash for variant '${variant}' in sources.json";

stdenvNoCC.mkDerivation {
  pname = toolName;
  inherit (sources) version;

  src = fetchurl {
    url = "https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-${sources.version}/proton-cachyos-${sources.version}-${variant}.tar.xz";
    hash = sources.hashes.${variant};
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

    # Replace the versioned internal and display names with a stable one
    sed -i -r 's|"proton-cachyos[^"]*"|"${toolName}"|' "$vdf"
    grep -q '"${toolName}"' "$vdf" || { echo "failed to rename the tool in $vdf" >&2; exit 1; }

    ln -s $steamcompattool $out

    runHook postInstall
  '';

  meta = {
    description = "CachyOS's optimised Proton build, for Steam's compatibility tools";
    homepage = "https://github.com/CachyOS/proton-cachyos";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
