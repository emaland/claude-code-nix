# Claude Code Package
#
# Installs Claude Code under one of three package names:
# - claude-code      (binary: claude)
# - claude-code-node (binary: claude-node)
# - claude-code-bun  (binary: claude-bun)
#
# As of claude-code 2.x the upstream npm package (@anthropic-ai/claude-code)
# no longer ships a runnable JavaScript entry point (cli.js). It is now a thin
# launcher whose real payload is a prebuilt, self-contained binary delivered
# via platform-specific optional dependencies. Because there is no longer any
# interpretable JS to run under Node.js or Bun, all three variants now wrap the
# same prebuilt native binary. The node/bun variants are retained as drop-in
# aliases so existing `.#claude-code-node` / `.#claude-code-bun` references keep
# working.

{ lib
, stdenv
, fetchurl
, makeBinaryWrapper
, autoPatchelfHook
, procps
, ripgrep
, bubblewrap
, socat
, runtime ? "native"  # "native", "node", or "bun"
, nativeBinName ? "claude"
, nodeBinName ? "claude-node"
, bunBinName ? "claude-bun"
}:

let
  version = "2.1.191";

  # Platform mapping for native binaries (Nix system -> Anthropic platform)
  platformMap = {
    "aarch64-darwin" = "darwin-arm64";
    "x86_64-darwin" = "darwin-x64";
    "x86_64-linux" = "linux-x64";
    "aarch64-linux" = "linux-arm64";
  };

  platform = platformMap.${stdenv.hostPlatform.system} or null;

  # Native binary hashes per platform
  nativeHashes = {
    "darwin-arm64" = "0064cvp1gq2qsmkvzh7yrq4mn454s0jc01nxmr4ycq2j59azpzcr";
    "darwin-x64" = "195j9jbr8r5s5wyn1z5yqbm0b497s83dm72kfkymkm2gzkasm0vf";
    "linux-x64" = "1vjvdmwchq541p2rlclp0jq2b0q87glq7qy33na806yzifldnf0h";
    "linux-arm64" = "16wlv3z3yrnggxnvfw7gc0zfkdizb2hs1j5zfg0gi16prz5sfc8s";
  };

  # Native binary URL
  nativeBinaryUrl = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${version}/${platform}/claude";

  # Fetch the prebuilt native binary. Every runtime variant uses this now, since
  # the npm package no longer ships a runnable JS entry point.
  nativeBinary = if platform != null then
    fetchurl {
      url = nativeBinaryUrl;
      sha256 = nativeHashes.${platform};
    }
  else null;

  # Runtime-specific configuration. Only the package/binary naming and
  # description differ now; all variants install the same prebuilt binary.
  runtimeConfig = {
    native = {
      description = "Claude Code (Native Binary) - AI coding assistant in your terminal";
      binName = nativeBinName;
    };
    node = {
      description = "Claude Code (Node.js alias) - AI coding assistant in your terminal";
      binName = nodeBinName;
    };
    bun = {
      description = "Claude Code (Bun alias) - AI coding assistant in your terminal";
      binName = bunBinName;
    };
  };

  selected = runtimeConfig.${runtime};
in
assert platform != null ||
  throw "claude-code is not supported on ${stdenv.hostPlatform.system}. Supported: aarch64-darwin, x86_64-darwin, x86_64-linux, aarch64-linux";

stdenv.mkDerivation rec {
  pname = if runtime == "native" then "claude-code"
          else if runtime == "node" then "claude-code-node"
          else "claude-code-${runtime}";
  inherit version;

  dontUnpack = true;

  # The native binary is a self-contained Bun single-file executable;
  # stripping corrupts the Bun trailer.
  dontStrip = true;

  nativeBuildInputs = [ makeBinaryWrapper ]
    ++ lib.optionals stdenv.hostPlatform.isElf [ autoPatchelfHook ];

  buildPhase = ''
    runHook preBuild
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin

    install -m755 ${nativeBinary} $out/bin/.claude-unwrapped

    makeBinaryWrapper $out/bin/.claude-unwrapped $out/bin/${selected.binName} \
      --set DISABLE_AUTOUPDATER 1 \
      --set DISABLE_INSTALLATION_CHECKS 1 \
      --set USE_BUILTIN_RIPGREP 0 \
      --prefix PATH : ${
        lib.makeBinPath (
          [
            procps
            ripgrep
          ]
          ++ lib.optionals stdenv.hostPlatform.isLinux [
            bubblewrap
            socat
          ]
        )
      }

    runHook postInstall
  '';

  meta = with lib; {
    description = selected.description;
    homepage = "https://www.anthropic.com/claude-code";
    license = licenses.unfree;
    platforms = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
    mainProgram = selected.binName;
  };
}
