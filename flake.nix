{
  description = "Home Manager configuration — unified across machines";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixgl.url = "github:guibou/nixGL";
    # nixGL's own nixpkgs. Its NVIDIA driver wrapper (modules/programs/brave.nix)
    # must build against it: nixos-26.05 dropped the `kernel` argument that nixGL
    # passes to nvidia_x11. Follows nixGL's lock, so it moves with `nixgl`.
    nixgl-nixpkgs.follows = "nixgl/nixpkgs";
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
    # MBZUAI-IFM llama.cpp fork with native k2_horizon (K2-Horizon MoVA)
    # support (model/K2Horizon branch). Same flake interface as mainline, so
    # it plugs into llamaCpp below unchanged. Bump with:
    #   nix flake lock --update-input llama-k2horizon
    llama-k2horizon.url = "github:MBZUAI-IFM/llama.cpp/model/K2Horizon";
    # Mainline llama.cpp branch adding DFlash2 speculative decoding
    # (PR #27342, branch xsn/dflash2). Same flake interface as mainline, so it
    # plugs into llamaCpp below unchanged. Bump with:
    #   nix flake lock --update-input llama-dflash2
    llama-dflash2.url = "github:ggml-org/llama.cpp/xsn/dflash2";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      # inputs.nixpkgs.follows = "nixpkgs";
    };
    # The home dashboard: an Odin backend serving a single-file frontend with
    # CPU/GPU/RAM history plus the status and per-unit resource use of the local
    # LLM user units (ollama, llama-server, halogen-flash-server). Own repo/flake;
    # it exposes `homeManagerModules.default`, imported by modules/dashboard.nix.
    # NOTE: the repo is private, so this must be fetched over SSH (anonymous
    # HTTPS 404s). That means evaluating this config needs a working SSH key for
    # github.com; making the repo public would let it use `github:...` instead.
    # It follows `unstable` so we do not pull a second nixpkgs just for this
    # package. Bump with: nix flake lock --update-input home-dashboard
    home-dashboard = {
      url = "git+ssh://git@github.com/alexfneves/home_dashboard.git";
      inputs.nixpkgs.follows = "unstable";
    };
    # The nws workspace daemon: an Odin CLI plus its NixOS and Home Manager
    # modules (modules/nws.nix). Public repo, so plain github: works without
    # SSH. Follows our nixpkgs so the daemon is built with the same toolchain as
    # the rest of the config. Bump with: nix flake lock --update-input nws
    nws = {
      url = "github:alexfneves/nws";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # herdr-session: the replacement for this repo's herdr-cycle.sh. An Odin TUI
    # that creates / attaches / deletes herdr sessions and hands the terminal
    # over to one (see modules/herdr-session.nix). Public repo, so plain
    # github: works without SSH.
    # It ships NO Home Manager module and NO overlay — only
    # packages.<system>.{default,clayLib,termbox2Lib} — so unlike nws and
    # home-dashboard we consume it as a plain package, not via
    # `imports = [ ... homeManagerModules.default ]`.
    # Follows `unstable`, deliberately NOT `nixpkgs`: the build needs a newer
    # Odin than nixos-26.05 ships. Against nixos-26.05 (odin-dev-2026-05) it
    # fails with `src/app/config.odin(382:15): 'parse_bytes' is not declared by
    # 'json'`; against nixpkgs-unstable (odin-dev-2026-10) it builds clean.
    # Following `unstable` also collapses its own devenv nixpkgs onto ours.
    # Bump with: nix flake lock --update-input herdr-session
    herdr-session = {
      url = "github:alexfneves/herdr_session";
      inputs.nixpkgs.follows = "unstable";
    };
  };

  outputs = { nixpkgs, unstable, home-manager, nixgl, llama-fpx, llama-ggml, llama-k2horizon, llama-dflash2, self, ... } @ inputs:
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

      # Shared `lib` for the nixGL helper below (unfree predicate + getName).
      lib = pkgs.lib;

      # ---- pinned NVIDIA nixGL wrapper (shared) ----
      # Lives in the flake (not in a single module) so every GUI package that
      # needs the pinned NVIDIA driver stack can use it: currently brave
      # (modules/programs/brave.nix) and ghostty
      # (modules/editors/ghostty.nix). Passed to modules through
      # extraSpecialArgs as `nixGLNvidiaWrap` (Chromium-flavoured, what brave
      # uses) and `nixGLNvidiaWrapWith` (same wrapper, explicit flag list).
      # Moved out of brave.nix with its comments intact -- the reasoning below
      # is load-bearing; only the Chromium flags were lifted into a parameter
      # (see nixGLNvidiaWrapWith).
      #
      # The work laptop has an NVIDIA GPU, so nixGL must wrap the NVIDIA driver
      # libraries, and those must match the kernel module the host runs
      # (/proc/driver/nvidia/version). The version is pinned here so evaluation stays
      # pure. The auto-detect `nixGLDefault` read /proc at eval time through
      # `builtins.currentTime`, which needed `--impure`. When Ubuntu upgrades the
      # driver, update nvidiaVersion and nvidiaSha256 (the SHA256 of NVIDIA's
      # NVIDIA-Linux-x86_64-<version>.run; `nix-prefetch-url <url>` prints it).
      nvidiaVersion = "550.163.01";
      nvidiaSha256 = "0blsmdf9fyw8jjm6fq45bdrldvlj7hnziyz98l0ld5a5ngslk0gg";
      # nixGL's nvidia_x11 must be built with nixGL's own nixpkgs (see the
      # nixgl-nixpkgs input above). The NVIDIA driver is unfree, so that
      # instance allows unfree for nvidia packages only.
      nixglPkgs = import inputs.nixgl-nixpkgs {
        inherit system;
        config.allowUnfreePredicate = pkg: lib.hasPrefix "nvidia" (lib.getName pkg);
      };
      nixglLib = import "${inputs.nixgl}/default.nix" {
        pkgs = nixglPkgs;
        enable32bits = true;
        enableIntelX86Extensions = true;
      };
      nixGLBin = nixglLib.nixGLCommon
        (nixglLib.nvidiaPackages { version = nvidiaVersion; sha256 = nvidiaSha256; }).nixGLNvidia;

      # Flags appended to every launch by `nixGLNvidiaWrap`. Chromium-family
      # apps want them: ozone picks the platform itself, VA-API/Vulkan turn on
      # hardware codecs, and the GPU sandbox has to go because it cannot see the
      # driver nixGL injects from outside Nix.
      nixGLChromiumFlags = [
        "--ozone-platform-hint=auto"
        "--enable-features=VaapiVideoDecoder,VaapiVideoEncoder,Vulkan"
        "--disable-gpu-sandbox"
      ];

      # The generic form: wrap every bin/* of `pkg` through the pinned NVIDIA
      # nixGL above, appending `extraArgs` to the command line.
      #
      # The flags are a parameter rather than baked in because appending them
      # unconditionally breaks every non-launch subcommand. ghostty parses its
      # CLI strictly -- `ghostty --ozone-platform-hint=auto +validate-config`
      # exits 1 with no message at all -- and home-manager runs exactly that at
      # activation time (xdg.configFile."ghostty/config".onChange ->
      # `${lib.getExe cfg.package} +validate-config --config-file=...`, with no
      # `|| true`, in a script running under set -e), so a flag-injecting
      # wrapper makes `home-manager switch` on the work host abort. A flagless
      # wrap is fine: `nixGL ghostty +validate-config --config-file=...`
      # exits 0.
      nixGLNvidiaWrapWith = extraArgs: pkg:
        (pkgs.runCommand "${pkg.name}-nixgl-wrapper" { } ''
          mkdir $out
          ln -s ${pkg}/* $out
          rm $out/bin
          mkdir $out/bin
          for bin in ${pkg}/bin/*; do
            wrapped_bin=$out/bin/$(basename $bin)
            cat > $wrapped_bin <<EOS
#!/usr/bin/env bash
# Run through the pinned NVIDIA nixGL wrapper (see nvidiaVersion above)
exec ${nixGLBin}/bin/nixGL $bin ${lib.escapeShellArgs extraArgs} "\$@"
EOS
            chmod +x $wrapped_bin
          done
        '').overrideAttrs (_: {
          # Carry the wrapped package's `meta` through the wrapper. This is not
          # cosmetic: a bare runCommand has no `meta.mainProgram`, and
          # `lib.getExe` throws at EVAL time on such a package. Home-manager's
          # ghostty module runs `${lib.getExe cfg.package} +validate-config`,
          # so a wrapper without meta would break the whole host evaluation.
          # Copying meta over also keeps `meta.mainProgram` ("brave",
          # "ghostty", ...) pointing at the real binary -- which is exactly the
          # one this wrapper re-execs.
          meta = pkg.meta or { };
        });

      # Chromium-flavoured default (brave): pinned nixGL + the Chromium flags.
      nixGLNvidiaWrap = nixGLNvidiaWrapWith nixGLChromiumFlags;

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
      #   llamaSource  -> "nixpkgs"    (nixpkgs-unstable build, stable)
      #                   "rocmfpx"    (ROCmFPX fork github:charlie12345/ROCmFPX)
      #                   "ggml-org"   (mainline github:ggml-org/llama.cpp)
      #                   "k2horizon"  (MBZUAI-IFM fork, model/K2Horizon branch —
      #                                 required for k2_horizon MoVA GGUFs)
      #                   "dflash2"    (mainline branch xsn/dflash2 — required for
      #                                 draft-dflash / Qwen3.8-27B-DFlash2)
      # All combinations are valid: nixpkgs-unstable, the forks and mainline
      # all expose a vulkan and a rocm build of llama.cpp.
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
          # Mainline llama.cpp (github:ggml-org/llama.cpp) and the MBZUAI-IFM
          # k2horizon fork (same flake/package layout) build their webui
          # offline from source, so they only need the Strix Halo ROCm tweaks:
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
        else if source == "k2horizon"
        then ggml llama-k2horizon.packages.${system}.${backend}
        else if source == "dflash2"
        then ggml llama-dflash2.packages.${system}.${backend}
        else if backend == "rocm"
        then unstablePkgs.llama-cpp-rocm
        else unstablePkgs.llama-cpp-vulkan;

      # ---- herdr-session ----
      # `herdr-session` resolves `herdr` — and `ssh`, for its remote hosts —
      # out of the CALLER's PATH at runtime. A window opened from a desktop
      # launcher, where ~/.nix-profile/bin is often not on PATH, therefore
      # reports "herdr not installed here". Prepend both binaries in a wrapper
      # so it works from a launcher as well as from an interactive shell.
      # One binary, spelled out rather than looped over: it is the only thing
      # the package installs, and a quoted heredoc keeps $PATH / $@ literal for
      # the runtime shell instead of baking in this build's values.
      herdrSessionRaw = inputs.herdr-session.packages.${system}.default;
      herdrSessionPackage = pkgs.runCommand "${herdrSessionRaw.name}-path-wrapper" {} ''
        mkdir -p $out/bin
        cat > $out/bin/herdr-session <<'WRAPPER'
        #!/bin/sh
        # Added by this flake: herdr + ssh must be resolvable however we were
        # launched (see herdrSessionPackage in flake.nix).
        export PATH=${unstablePkgs.herdr}/bin:${pkgs.openssh}/bin:$PATH
        exec ${herdrSessionRaw}/bin/herdr-session "$@"
        WRAPPER
        chmod +x $out/bin/herdr-session
      '';

    # Build a home-manager configuration for a single machine.
      #
      # hostConfig (passed to home.nix) carries everything that differs
      # between machines:
      #   username / email        -> user identity
      #   isNixOS                 -> genericLinux target (Ubuntu etc.)
      #   useNixGL                -> wrap GUI binaries through nixGL (old GPUs/Ubuntu)
      #   enableLlm               -> the whole local LLM stack: ollama,
      #                              llama-server, open-webui and the
      #                              halogen-flash-server container. They all
      #                              spawn together; how you divide the box's
      #                              RAM between them is the operator's call.
      #   enableNodejs            -> nodejs + npm global setup
      #   ollamaSource            -> which ollama to use: "nixpkgs" (default) or "git"
      #   ollamaBackend           -> "rocm" or "vulkan"
      #   llamaBackend            -> which llama.cpp GPU backend: "vulkan" (default) or "rocm"
      #   llamaSource             -> where llama.cpp comes from: "nixpkgs" (default),
      #                              "rocmfpx" (ROCmFPX fork), "ggml-org" (mainline),
      #                              "k2horizon" (MBZUAI-IFM model/K2Horizon fork)
      #                              or "dflash2" (mainline branch xsn/dflash2)
      #   enableNws               -> run the nws workspace daemon (modules/nws.nix)
      #   extraPackages           -> extra plain nixpkgs packages for this host
      #   extraUnstablePkgs       -> extra unstable-channel packages for this host
      mkHome = { username, hostname, email, isNixOS, useNixGL, enableLlm, enableNodejs ? false
               , ollamaSource ? "nixpkgs"
               , ollamaBackend ? "rocm"
               , llamaSource ? "nixpkgs"
               , llamaBackend ? "vulkan"
               , extraPackages ? [], extraUnstablePkgs ? []
               , enableCleanNixEnv ? false, enableNws ? false }:
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
            inherit inputs unstablePkgs ollamaGit ollamaVulkan llamaPackage herdrSessionPackage nixGLNvidiaWrap nixGLNvidiaWrapWith;
            hostConfig = {
              inherit username hostname email isNixOS useNixGL enableLlm enableNodejs ollamaSource ollamaBackend llamaSource llamaBackend
                       extraPackages extraUnstablePkgs enableCleanNixEnv enableNws;
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
        llama-k2horizon-vulkan = llamaCpp { backend = "vulkan"; source = "k2horizon"; };
        llama-k2horizon-rocm   = llamaCpp { backend = "rocm";   source = "k2horizon"; };
        llama-dflash2-vulkan = llamaCpp { backend = "vulkan"; source = "dflash2"; };
        llama-dflash2-rocm   = llamaCpp { backend = "rocm";   source = "dflash2"; };
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
