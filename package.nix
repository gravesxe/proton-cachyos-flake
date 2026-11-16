{
  lib,
  stdenvNoCC,
  fetchurl,
  variant ? "x86_64",
}:

let
  sources = builtins.fromJSON (builtins.readFile ./sources.json);
in
stdenvNoCC.mkDerivation {
  pname = "proton-cachyos";
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

    # Keep a stable name in Steam across updates
    sed -i -r 's|"proton-cachyos[^"]*"|"proton-cachyos"|' $steamcompattool/compatibilitytool.vdf

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
