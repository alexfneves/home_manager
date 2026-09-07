{
  description = "Home Manager configuration — unified across machines";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixgl.url = "github:guibou/nixGL";
    unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Latest RELEASE of ollama, so we can build the git variant straight from
    # GitHub instead of waiting for nixpkgs-unstable to catch up.
    # Pinned to a release tag — main has no real version string (it reports
    # "0.0.0"), which the ollama registry rejects when pulling models. Bump to
    # a newer tag with: nix flake lock --update-input ollama-git
    ollama-git = {
      url = "github:ollama/ollama/v0.32.14";
      flake = false;
    };
    # llama.cpp fork with ROCm FPX support (has its own flake.nix exposing
    # packages.x86_64-linux.{default,vulkan,rocm,...}). Bump with:
    #   nix flake lock --update-input llama-fpx
    llama-fpx.url = "github:charlie12345/ROCmFPX";
    # Mainline llama.cpp — alternative git source for test builds (its flake
    # exposes packages.x86_64-linux.{default,vulkan,rocm,...}). Bump with:
    #   nix flake lock --update-input llama-ggml
    llama-ggml.url = "github:ggml-org/llama.cpp";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      # inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, unstable, home-manager, nixgl, llama-fpx, llama-ggml, self, ... } @ inputs:
    let
      system = "x86_64-linux";

      pkgs = (import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          allowUnfreePredicate = _: true;
        };
      }).extend nixgl.overlay;

      unstablePkgs = import unstable {
        inherit system;
        config = {
          allowUnfree = true;
          allowUnfreePredicate = _: true;
        };
      };

      # ---- ollama built from the latest ollama GitHub release ----
      # The whole derivation lives in ./ollama/ollama-git.nix so flake.nix stays
      # clean; the `ollama-git` input above is the source it builds from.
      # `backend` picks the base nixpkgs build to override ("rocm" or "vulkan").
      #
      # ccache workaround: llama.cpp's cmake auto-enables ccache for vulkan
      # builds, but inside the nix sandbox $HOME is /homeless-shelter (unwritable),
      # so ccache dies with "Permission denied" before compiling anything. Point
      # its cache at the per-build temp dir. nixpkgs doesn't set this for
      # ollama-vulkan, so it applies to both the nixpkgs and git sources.
      fixCcache = pkg: pkg.overrideAttrs (o: {
        preConfigure = (o.preConfigure or "") + ''
          export CCACHE_DIR="$TMPDIR/ccache"
        '';
      });

      ollamaVulkan = fixCcache unstablePkgs.ollama-vulkan;

      ollamaGit = backend:
        fixCcache (
          import ./ollama/ollama-git.nix {
            inherit pkgs unstablePkgs backend;
            lib = pkgs.lib;
            ollamaGit = inputs.ollama-git;
          }
        );

      # ---- llama.cpp variants ----
      # Two independent knobs per host, mirroring the ollama options:
      #   llamaBackend -> "vulkan" or "rocm"
      #   llamaSource  -> "nixpkgs"  (nixpkgs-unstable build, stable)
      #                   "rocmfpx"  (ROCmFPX fork github:charlie12345/ROCmFPX)
      #                   "ggml-org" (mainline github:ggml-org/llama.cpp)
      # All six combinations are valid: nixpkgs-unstable, the fork and
      # mainline all expose a vulkan and a rocm build of llama.cpp.
      llamaCpp = { backend, source }:
        let
          # The ROCmFPX fork's cmake tries to download WebUI assets from
          # Hugging Face during the build, which fails inside the nix sandbox.
          # Build it without the bundled web UI instead. Also:
          #  - target only gfx1151 (Strix Halo) instead of every AMD arch
          #  - GGML_HIP_FORCE_MMQ=ON as recommended by the fork's own
          #    Strix Halo build script
          #  - drop the head-size-256 fattn-vec FP4 template instances:
          #    they blow past the 64 KiB LDS limit on RDNA and none of our
          #    models use head_dim 256 (both are 128)
          fpx = pkg: pkg.overrideAttrs (o: {
            cmakeFlags = (o.cmakeFlags or []) ++ [
              "-DLLAMA_BUILD_WEBUI=OFF"
              "-DGGML_HIP_FORCE_MMQ=ON"
              "-DCMAKE_HIP_ARCHITECTURES=gfx1151"
            ];
            postPatch = (o.postPatch or "") + ''
              for f in ggml/src/ggml-cuda/template-instances/fattn-vec-instance-*rocmfp*.cu; do
                [ -e "$f" ] && sed -i '/DECL_FATTN_VEC_CASE(256,/d' "$f"
              done
              # fattn.cu dispatches head-size 256 for the ROCMFP types too;
              # route them through a 64/128-only macro so no D=256 symbol is
              # referenced (the instances above no longer provide it).
              sed -i '/^#define FATTN_VEC_CASES_TURBO/i \
#define FATTN_VEC_CASES_NO256(type_K, type_V) \\\n    FATTN_VEC_CASE( 64, type_K, type_V)       \\\n    FATTN_VEC_CASE(128, type_K, type_V)       \\\n' ggml/src/ggml-cuda/fattn.cu
              sed -i 's/\(FATTN_VEC_CASES_\)ALL_D(\(GGML_TYPE_Q[0-9]_0_ROCMFP[A-Z0-9_]*\), *\(GGML_TYPE_Q[0-9]_0_ROCMFP[A-Z0-9_]*\))/\1NO256(\2, \3)/' ggml/src/ggml-cuda/fattn.cu
            '';
          });
          # Mainline llama.cpp (github:ggml-org/llama.cpp) builds its webui
          # offline from source, so it only needs the Strix Halo ROCm tweaks:
          # target only gfx1151 and force MMQ kernels (as recommended for UMA
          # APUs); no postPatch / fattn surgery needed.
          ggml = pkg: pkg.overrideAttrs (o: {
            cmakeFlags = (o.cmakeFlags or []) ++ [
              "-DGGML_HIP_FORCE_MMQ=ON"
              "-DCMAKE_HIP_ARCHITECTURES=gfx1151"
            ];
          });
        in
        if source == "rocmfpx"
        then fpx llama-fpx.packages.${system}.${backend}
        else if source == "ggml-org"
        then ggml llama-ggml.packages.${system}.${backend}
        else if backend == "rocm"
        then unstablePkgs.llama-cpp-rocm
        else unstablePkgs.llama-cpp-vulkan;

    # Build a home-manager configuration for a single machine.
      #
      # hostConfig (passed to home.nix) carries everything that differs
      # between machines:
      #   username / email        -> user identity
      #   isNixOS                 -> genericLinux target (Ubuntu etc.)
      #   useNixGL                -> wrap GUI binaries through nixGL (old GPUs/Ubuntu)
      #   enableLlm               -> ROCm stack: ollama, llama-cpp, open-webui
      #   enableNodejs            -> nodejs + npm global setup
      #   ollamaSource            -> which ollama to use: "nixpkgs" (default) or "git"
      #   ollamaBackend           -> "rocm" or "vulkan"
      #   llamaBackend            -> which llama.cpp GPU backend: "vulkan" (default) or "rocm"
      #   llamaSource             -> where llama.cpp comes from: "nixpkgs" (default),
      #                              "rocmfpx" (ROCmFPX fork) or "ggml-org" (mainline)
      #   extraPackages           -> extra plain nixpkgs packages for this host
      #   extraUnstablePkgs       -> extra unstable-channel packages for this host
      mkHome = { username, hostname, email, isNixOS, useNixGL, enableLlm, enableNodejs ? false
               , ollamaSource ? "nixpkgs"
               , ollamaBackend ? "rocm"
               , llamaSource ? "nixpkgs"
               , llamaBackend ? "vulkan"
               , extraPackages ? [], extraUnstablePkgs ? []
               , enableCleanNixEnv ? false }:
        let
          # map host option names to llamaCpp's argument names
          llamaPackage = llamaCpp { backend = llamaBackend; source = llamaSource; };
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          modules = [
            ./home.nix
            {
              home.username = username;
              home.homeDirectory = "/home/${username}";
            }
          ];
          extraSpecialArgs = {
            inherit inputs unstablePkgs ollamaGit ollamaVulkan llamaPackage;
            hostConfig = {
              inherit username hostname email isNixOS useNixGL enableLlm enableNodejs ollamaSource ollamaBackend llamaSource llamaBackend
                       extraPackages extraUnstablePkgs enableCleanNixEnv;
            };
          };
        };
    in let
      hosts = {
        gmktec = import ./hosts/gmktec.nix { inherit pkgs; };
        work-notebook = import ./hosts/work-notebook.nix { inherit pkgs; };
      };
    in {
      # Directly buildable/testable: `nix build .#ollama-git-rocm`
      packages.${system} = {
        ollama-rocm = unstablePkgs.ollama-rocm;
        ollama-vulkan = ollamaVulkan;
        ollama-git-rocm = ollamaGit "rocm";
        ollama-git-vulkan = ollamaGit "vulkan";
        llama-nixpkgs-vulkan = llamaCpp { backend = "vulkan"; source = "nixpkgs"; };
        llama-nixpkgs-rocm   = llamaCpp { backend = "rocm";   source = "nixpkgs"; };
        llama-rocmfpx-vulkan = llamaCpp { backend = "vulkan"; source = "rocmfpx"; };
        llama-rocmfpx-rocm   = llamaCpp { backend = "rocm";   source = "rocmfpx"; };
        llama-ggml-vulkan    = llamaCpp { backend = "vulkan"; source = "ggml-org"; };
        llama-ggml-rocm      = llamaCpp { backend = "rocm";   source = "ggml-org"; };
      };
      apps.${system} = {
        # `nix run .#update-ollama -- 0.33.0`
        update-ollama = {
          type = "app";
          program = "${./ollama/update_and_switch_ollama.sh}";
        };
      };
      homeConfigurations = {
        "${hosts.gmktec.username}@${hosts.gmktec.hostname}" = mkHome hosts.gmktec;
        "${hosts.work-notebook.username}@${hosts.work-notebook.hostname}" = mkHome hosts.work-notebook;
      };
    };
}
