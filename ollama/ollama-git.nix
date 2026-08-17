{
  lib,
  pkgs,
  unstablePkgs,
  # One of "rocm" | "vulkan" — picks which nixpkgs build gets the newer source.
  backend,
  # Latest ollama source as a locked flake input (see `ollama-git` in flake.nix).
  ollamaGit,
}:

# ollama built straight from the latest ollama RELEASE on GitHub.
#
# ollama doesn't ship its own flake, so we do the flake-native equivalent:
# pull the live source into a locked input, then rebuild nixpkgs' ollama build
# against it. That reuses unstable's well-tested packaging (correct GPU
# targets, runtime wrapping, …) and only swaps in the newer source.
#
# The base derivation follows `backend`:
#   "rocm"   -> unstablePkgs.ollama-rocm
#   "vulkan" -> unstablePkgs.ollama-vulkan
#
#   upstream `main` is intentionally NOT used — it carries no real version
#   string (reports "0.0.0"), which the ollama registry rejects with a 412
#   when pulling models. A release tag gives the registry a version it
#   recognises.
#
# Bump to a newer release (change the tag in flake.nix's `ollama-git` input,
# then refresh the lock):
#     nix flake lock --update-input ollama-git
#     nix build .#ollama-git-rocm     # tells you if a hash below changed
#     home-manager switch --flake '.#alexfneves@gmktec'
# The two hashes below only need refreshing when ollama changes go.mod/go.sum
# (vendorHash) or the llama.cpp target it tracks (llamaCppSrc.hash) — often
# they don't move at all.
let
  basePackage =
    if backend == "vulkan" then unstablePkgs.ollama-vulkan
    else unstablePkgs.ollama-rocm;

  # llama.cpp version this ollama tracks (root `LLAMA_CPP_VERSION` file). We
  # pre-stage it so the sandboxed build never needs network.
  llamaCppVersion = lib.trim (builtins.readFile "${ollamaGit}/LLAMA_CPP_VERSION");

  llamaCppSrc = pkgs.fetchFromGitHub {
    owner = "ggml-org";
    repo = "llama.cpp";
    tag = llamaCppVersion;
    hash = "sha256-Sz0kW1q91YzdrKbZUqMbFJ0DLZrzARSGheUrtCKcoQo="; # bump: see comment above
  };
in
basePackage.overrideAttrs (o: {
  pname = "${o.pname}-git";
  version = "0.32.14"; # keep in sync with the ollama-git input tag
  src = ollamaGit;
  vendorHash = "sha256-HMwoaFBMbpoy8f0I+O+i7kIa9BslLu3FcVWeaIOkpvs="; # bump: see comment above
  # Bleeding-edge builds shouldn't be gated on ollama's network-touching
  # tests; the runtime binary is what we care about.
  doCheck = false;
  doInstallCheck = false;
  postPatch = ''
    substituteInPlace version/version.go --replace-fail 0.0.0 '0.32.14'
    # cmd/launch/*_test.go are CLI launcher tests that need npm + network;
    # drop them (mirrors the upstream derivation).
    rm cmd/launch/*_test.go
    # app/ is the Electron UI and needs a node build — strip it.
    rm -r app
    # Pre-stage llama.cpp for the CMake FetchContent step and apply
    # Ollama's compat patch (idempotent, safe to re-run).
    cp -r ${llamaCppSrc} $TMPDIR/llama-cpp-src
    chmod -R +w $TMPDIR/llama-cpp-src
    ( cd $TMPDIR/llama-cpp-src && \
      cmake -DPATCH_DIR=$NIX_BUILD_TOP/source/llama/compat \
        -P $NIX_BUILD_TOP/source/llama/compat/apply-patch.cmake )
  '';
})
