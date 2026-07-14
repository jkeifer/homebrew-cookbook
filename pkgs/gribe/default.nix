{ lib, stdenvNoCC, fetchurl, installShellFiles }:

let
  source = lib.importJSON ./source.json;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "gribe";
  version = source.version;

  src = fetchurl {
    url = "https://github.com/${source.repo}/releases/download/v${finalAttrs.version}/${source.asset}";
    hash = source.sha256;
  };

  dontUnpack = true;

  nativeBuildInputs = [ installShellFiles ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/gribe
    installShellCompletion --cmd gribe \
      --bash <($out/bin/gribe --generate-completion-script bash) \
      --zsh  <($out/bin/gribe --generate-completion-script zsh) \
      --fish <($out/bin/gribe --generate-completion-script fish)
    # Emit the embedded Claude Code skill as a stable artifact (no models or
    # network needed — `skill print` just dumps embedded markdown). The
    # home-manager module links this into ~/.claude/skills.
    mkdir -p $out/share/transgribe
    $out/bin/gribe skill print > $out/share/transgribe/SKILL.md
    runHook postInstall
  '';

  meta = {
    description = "Transcribe audio locally on Apple Silicon";
    homepage = "https://github.com/jkeifer/transgribe";
    license = lib.licenses.mit;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "gribe";
  };
})
