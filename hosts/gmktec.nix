{ pkgs }:
{
  hostname = "gmktec";
  username = "alexfneves";
  email = "alexfneves@gmail.com";
  isNixOS = true;
  useNixGL = false;
  enableLlm = true;
  # halogen-flash-server (Qwen3.8-Flash-Next). Off by default; when true it
  # replaces the ollama/open-webui/llama-server stack because it wants the
  # whole 128 GB machine. Flip to false to get the old stack back.
  enableHalogen = true;
  enableNodejs = true;
  enableCleanNixEnv = false;
  # Which ollama backend to use:
  #   "rocm"   -> AMD ROCm acceleration
  #   "vulkan" -> Vulkan acceleration
  ollamaBackend = "vulkan";
  # Which ollama to run:
  #   "nixpkgs" -> nixpkgs-unstable build (stable, tested)
  #   "git"     -> latest from GitHub (bleeding edge, may crash — easy to flip back)
  ollamaSource = "git";
  # Which llama.cpp to run (llama-server + CLI tools). Two independent knobs:
  #   llamaSource -> "nixpkgs"  (nixpkgs-unstable build, stable),
  #                  "rocmfpx"  (ROCmFPX fork from github:charlie12345/ROCmFPX),
  #                  "ggml-org" (mainline from github:ggml-org/llama.cpp),
  #                  "k2horizon"(MBZUAI-IFM model/K2Horizon fork — k2_horizon MoVA GGUFs),
  #                  "dflash2"  (mainline branch xsn/dflash2 — DFlash2 draft-dflash)
  # NOTE: llamaSource is a single per-host value: whichever is set here is what
  # serves ALL presets. Switching to "dflash2" means [k2-horizon-mova-q8_0] will
  # not load until this is flipped back to "k2horizon".
  #   llamaBackend-> "vulkan" or "rocm"
  llamaSource = "dflash2";
  # ROCmFP4 models (ROCmFPX fork) only run on the ROCm build
  llamaBackend = "vulkan";
  extraPackages = with pkgs; [
    steam
    obs-studio
    vlc
    proton-pass
    protonmail-desktop
    proton-vpn
    python3
  ];
}
