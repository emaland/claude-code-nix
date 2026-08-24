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
  version = "2.1.241";

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
    "darwin-arm64" = "03c2cig7kw8wbjzc4aw0ijis88ld95nqplqwbwglbd6k89yfp58l";
    "darwin-x64" = "03f12q9qzsw0590zhgcclfa13xlsysb4vwbnnksmwj36rv5bh0fg";
    "linux-x64" = "1f1pf2yb7k0xr3w49wbqa223c6lyabv9j17wh5jvg0pzdj3bsw87";
    "linux-arm64" = "1zm2jklav8xz9bkdm4v2b2i1z066bfj6sra6xs5fzn5y7s4wpc1d";
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
