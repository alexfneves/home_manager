{ pkgs, lib, hostConfig, ... }:
let
  # halogen-flash-server — a Strix Halo (gfx1151) engine built for exactly one
  # model, Qwen3.8-Flash-Next. Upstream:
  #   https://github.com/peonist-ai/halogen-flash-server
  #
  # Recommended deployment (from the upstream quickstart):
  #   weights repo   : peonist-ai/halogen-qwen3.8-flash-next  (public, ~130 GiB)
  #   weights folder : ~/halogen-models                       (mounted at /models)
  #   image          : see `image` below; upstream ships a :latest tag too, but
  #                    a moving engine under a model that changes its answers is
  #                    not worth it — the tag is pinned here.
  #
  # This server wants most of a 128 GB machine once it is loaded: the weights
  # stay resident and the KV pool is reserved up front.
  #
  # It is gated by `enableLlm` exactly like every other backend, so all of them
  # spawn together. Which ones you actually keep loaded at the same time is your
  # call, not something this config enforces — watch the pinned weights plus
  # whatever ollama and llama-server load alongside it. What this file does do
  # is put halogen first in the boot order and make it wait for memory rather
  # than start into a host that cannot give it the pin; see `Before` and
  # `preflightGate` below.
  llmEnabled = hostConfig.enableLlm;

  weightsRepo = "peonist-ai/halogen-qwen3.8-flash-next";

  # 0.18.9 (was 0.5.8). Two things this bump changes for us, both checked
  # against upstream's docs at the tag before pinning it:
  #
  #   * The KV pool is much cheaper than it was. 0.5.8 charged ~35.0 GiB for
  #     524,288 positions; 0.18.9 charges ~27 GB, so the pool we could not
  #     afford in September now fits inside the same budget. Every pool number
  #     in the pre-0.18 comments in this file was obsolete.
  #   * The default checkpoint is now `qwen38-flash-next-v2.hgn`, not w4b.
  #     Our volume holds w4b only, and the entrypoint falls back to it
  #     (`LEGACY_W4B=1`), so nothing changes on disk. Note the upgrade does
  #     NOT silently switch us to v2 — that takes the file plus an explicit
  #     HALOGEN_CHECKPOINT, and ~110 GiB of download.
  image = "ghcr.io/peonist-ai/halogen-flash-server:0.18.9";

  # ---- Tuning knobs --------------------------------------------------------
  #
  # HOW THESE REACH THE ENGINE. They go into a generated env file that the
  # `podman run` line passes with `--env-file`. They are NOT set via the unit's
  # `Environment=`, because a systemd unit's environment does not propagate
  # into a container — only explicit `--env`/`--env-file` flags do. Everything
  # in this block was dead for a month that way: the box was running pure image
  # defaults while this file described something else. If a knob here ever
  # seems ignored, confirm with:
  #
  #   podman inspect halogen-flash-server --format '{{range .Config.Env}}{{println .}}{{end}}' | grep HALOGEN
  #
  # THE TWO THINGS THAT HAVE TO FIT: the prompt and the reply.
  #
  # HALOGEN_CTX is the context of ONE request — prompt AND generated tokens,
  # together, inside the same window, always. The pool below is a different
  # thing: it decides how many such requests can be resident at once,
  # because each takes `prompt + max_tokens` positions out of it. Conflating
  # them cost a debugging session, so: ctx = how big one request may be,
  # pool = how many requests at once.
  #
  # WHY THE NATIVE 262,144 STOPPED BEING ENOUGH. pi is configured with
  # contextWindow 262144 for this model (~/.pi/agent/models.json) — exactly
  # the native figure — and it sizes both its ordinary requests and its
  # compaction requests against its OWN chars/4 estimate of the prompt, for
  # which the 0.18.9 measured reality on code/tool-heavy content is higher.
  # So pi sends a request the server has no room to answer, and the clamp
  # eats the reply. From the journal on this box:
  #
  #   02:06:28  prompt 257978 | max_tokens clamped 8119 -> 4166
  #
  # 262144 - 257978 = 4166 exactly. That request was pi's turn-prefix
  # compaction summary: its budget is floor(0.5 * compaction.reserveTokens)
  # = 8192, already trimmed by pi to 8119 because its estimate believed the
  # prompt was 254,025 tokens. halogen handed it the 4,166 positions the
  # window had left, HALOGEN_THINKING_ANSWER_ROOM then carved 1,024 of that
  # for the visible answer, and the summary ran out of room mid-sentence —
  # which pi reports as a hard failure, once for auto-compaction and again
  # for overflow recovery:
  #
  #   Auto-compaction failed: Turn prefix summarization failed: generation
  #     hit the token cap and the summary is incomplete
  #
  # A summariser has to read close to the whole window and then WRITE inside
  # that same window. A server whose context equals the client's window has
  # no room for the client's own bookkeeping. Headroom above the client's
  # window is genuinely required; the only question is who pays for it. The
  # server-side version on this model is static YaRN (`ctx 327,680` =
  # 1.25 x native, HALOGEN_ROPE_YARN=1.25), it was tried on 2026-10-25 and
  # it is rolled back below, because on this box that headroom is bought out
  # of the same RAM that carries conversation concurrency and the trade
  # loses. The headroom therefore has to come from the client: `contextWindow
  # ~245760` with `compaction.reserveTokens ~32768` in
  # ~/.pi/agent/settings.json, which asks nothing of the server. Until that
  # is applied, the failure above still happens near the top of the window.
  #
  # THE TRADE THAT UN-DID THIS: headroom and concurrency come out of the
  # SAME 37.5 GiB.
  #
  # This was tried at ctx 327,680 on 2026-10-25 and it stalled the box.
  # The engine's own prints give an exact cost model for this checkpoint:
  #
  #   786,432 positions -> ~34.0 GiB (12.4 of it not-the-pool, max_tok 32768)
  #   983,040 positions -> needs ~37.8 GiB  -> refused, budget is 37.5
  #   491,520 positions -> ~24.3 GiB       -> what the fitter took
  #
  #   need ~= intercept + 28.1 KiB x positions   (intercept 12.4 GiB at
  #   max_tok 32768, 10.8 GiB at 16384 — that part is the prefill arena,
  #   slot state and the vision tower, not the pool)
  #
  # So 983,040 never existed. What ran, both at 17:12 and again at 17:57, was:
  #
  #   kv pool: 983040 positions need ~37.8 GiB (plus 1.5 of margin) and
  #            host RAM cannot spare it. LOWERING THE POOL TO 491520 (~24.3 GiB)
  #
  # Raising ctx to 327,680 at the same time put pool/ctx at 1.5 instead of
  # the 3.0 the box had been running. That is not enough for a main session
  # plus agents, and the failure is a WAIT, not an error — which is why it
  # looked like a hang rather than a broken request:
  #
  #   kv pool: request 34 waits for 258189 positions: the pool holds 387328
  #            of 491520 in 2 busy and 0 held regions; 95488 free, the
  #            largest free gap 95488 (not enough)
  #
  # 15 of those in the first 25 minutes of the 17:57 start, against 2 hard
  # stalls in the 43 hours before the change. Agents block there until one of
  # the two running conversations ends, or until HALOGEN_QUEUE_TIMEOUT (3600s)
  # or the 180s engine watchdog takes the container down — hence "restart it
  # and the agents work again".
  #
  # THE RULE THIS LEAVES BEHIND: on a 123 GiB box in bf16 the pool maxes at
  # ~917,600 positions (36.0 GiB usable after the fitter's 1.5 margin).
  # Divided by ctx, that is the concurrency:
  #
  #   ctx 262,144 -> 3.5 conversations   (pool 851,968)
  #   ctx 327,680 -> 2.8 conversations   (pool 917,504)  <- worse than the 3.0 you had
  #
  # There is no bf16 setting that buys the ctx headroom AND keeps three
  # conversations. Only int8 does — kv8=true drops the slope to ~15.9 KiB per
  # position, so 983,040 costs ~25.3 GiB and 1,310,720 (4 x 327,680) costs
  # ~30.2 GiB. That is the honest upgrade path if the 327k context is ever
  # genuinely wanted: it is paid for in answer-identity, not in RAM.
  #
  # STATUS: reverted to native ctx. The compaction headroom that motivated
  # this now has to come from the client — pi's contextWindow ~245760 with
  # compaction.reserveTokens ~32768 in ~/.pi/agent/settings.json — which is
  # numerics-free, costs a little usable window, and leaves the pool ratio at
  # 3.0 (or 3.5, if the pool is taken to 851,968).
  #
  # Do NOT re-raise contextPositions without reading the block above, and do
  # not let pi's declared window catch up with the server's either way: if pi's
  # model auto-discovery ever reads `context: 327680` off /health, pi will
  # fill 327k and every number here stops being true.
  # Kept an integer so the native comparison below needs no string->int
  # conversion (the `lib` handed to these modules carries no stringToInt).
  contextPositions = 262144;

  # Native for this checkpoint. Anything above it requires YaRN (the
  # entrypoint warns and refuses a big prefill arena) and `pastNative` ties
  # the yarn factor and the arena cut to ctx so the three cannot drift.
  nativeContext = 262144;
  pastNative = contextPositions > nativeContext;
  ropeYarnFactor = "1.25";

  # The prefill arena. Past native the entrypoint forces this to 16384; set
  # it here so the ~9% prefill cost is chosen rather than discovered. At
  # native ctx it stays at 32768, which is also what keeps the 12.4 GiB
  # non-pool intercept in the cost model above honest — the model changes if
  # this changes.
  prefillArenaTokens = if pastNative then "16384" else "32768";

  # THE POOL.
  #
  # The cost model, taken from the engine's own prints on this box rather than
  # derived — and note that an earlier version of this comment got this wrong
  # by shrinking the non-pool term without re-adding it, which is what sent
  # the whole thing to the fitter:
  #
  #   kv pool: host RAM 123 GiB, less 68.0 resident weights and 18.0
  #            reserved for the n-gram page cache and the OS
  #            = 37.5 GiB for the device
  #   kv pool: 786432 positions, ~34.0 GiB (12.4 GiB of it for everything
  #            but the pool, at max_tok 32768)
  #
  #   need ~= intercept + 28.1 KiB x positions
  #   intercept = 12.4 GiB at max_tok 32768, 10.8 GiB at 16384
  #
  # Verified against three separate engine prints:
  #
  #    786,432 @32768 -> 21.6 + 12.4 = 34.0 GiB   (printed 34.0)
  #    983,040 @16384 -> 26.5 + 10.8 = 37.3 GiB   (printed 37.8, refused)
  #    491,520 @16384 -> 13.2 + 10.8 = 24.0 GiB   (printed 24.3, what it fell back to)
  #
  # The fitter's test is `need + 1.5 <= 37.5`, so 36.0 GiB is the ceiling:
  #
  #   bf16 pool ceiling ~= (36.0 - intercept) / 28.1 KiB
  #                   = 917,600 positions at max_tok 16384
  #                   = 851,700 positions at max_tok 32768
  #
  # 786,432 is kept: it is the value that ran here for weeks, 2.0 GiB inside
  # the budget, at 3.0 x ctx — which is the concurrency a main session plus
  # agents needs. 851,968 (3.25 x ctx) also fits but on 0.7 GiB of margin,
  # which one heavier vision charge eats; not worth the thinness when the
  # fitter's fallback is a 1.5x pool and a stalled box.
  #
  # CHECK IT AFTER THE FIRST START; the fitter outvotes the arithmetic above:
  #
  #   journalctl --user -u halogen-flash-server -b \
  #     | grep -E 'kv pool:|KV budget|[Ll]ower'
  #   curl -s localhost:8731/health \
  #     | grep -oE '"(context|slot_ctx|kv_pool_positions|kv_cache|rope_scaling)":[^,]*'
  #
  # Any "LOWERING THE POOL" line means the ask did not fit and concurrency is
  # now worse than this comment claims — read the number it took and go back
  # down here rather than shaving hostReserveGiB. And watch for the queueing
  # signature in the journal; that is what a stall looks like:
  #
  #   grep -c 'kv pool: request .* waits for' <this boot's log>
  #
  # A handful an hour is normal pressure at 3 conversations. More than that,
  # or any "forgetting no held region could make any", is the box saying the
  # pool is too small for what is being asked of it.
  #
  # Throughput at any of these sizes (upstream-measured):
  #   1 stream alone ~41 t/s (speculative) | 4 streams ~76 total, 18.7 each
  #   | 8 streams ~85 total, 10.9 each; past 8 the total stops growing.
  kvPoolPositions = "786432";   # 3.0 x contextPositions

  # Left free on top of the weights when the engine sizes the pool at startup.
  # Too little and the server starts, answers short prompts, then crawls on
  # long ones with the disk busy — that is the n-gram table being starved.
  # 18 is the number the whole 37.5 GiB device budget above is built from, so
  # every pool number in this file is only true at this reserve. If long
  # prompts start crawling, this is the knob to raise — and the pool is the
  # knob to lower with it; they moved together before and they still do.
  hostReserveGiB = "18";

  # Conversations generating at once. Not the memory knob (a slot is ~115 MB);
  # the pool is. Slots beyond what the pool can hold just queue. Kept at 4: it
  # matches the ~3-agent reality here and is where upstream tuned per-stream
  # speed. Raise to 6-8 to admit more clients at once instead of queueing
  # them, accepting ~11 t/s per stream at 8.
  kvSlots = "4";

  # The reply budget, in tokens, covering reasoning AND the answer.
  #
  # READ THIS BEFORE LOWERING THE CAP. The cap does not save memory. A request
  # over the cap is REJECTED, not shrunk — so a cap below what your clients
  # actually send converts working requests into 400s and frees nothing. This
  # is not theoretical: pi is configured with maxTokens 65536 for this model
  # (~/.pi/agent/models.json, providers/halogen/models[0] and
  # providers/pangolin/modelOverrides/halogen-qwen3.8-flash-next), and a cap
  # of 32768 broke a live 157k-token session with:
  #
  #   400: max_tokens 65536 exceeds this server's cap of 32768
  #
  # What DOES bound the reservation is the clamp, which landed in 0.18.4
  # (issue #178): a budget larger than the room the prompt leaves now runs in
  # that room instead of 400-ing, reported as timings.max_tokens_clamped_from
  # / _clamped_to and logged as `max_tokens clamped`. So near the context
  # ceiling a generous client budget is already safe, and the cap adds nothing
  # except the ability to break clients. Keep the cap at or above what clients
  # send. 65536 is upstream's default and matches pi exactly.
  #
  # CAREFUL with "already safe". The clamp protects RAM; it does not protect
  # the reply. A clamped budget the model then fills comes back
  # finish_reason=length, and pi reads that as a failed compaction — "generation
  # hit the token cap and the summary is incomplete" — or as a truncated
  # answer. The clamp makes the request run; it does not make the response
  # complete. That distinction is what the ctx headroom above is for.
  #
  # If you ever genuinely want smaller reservations, change what pi ASKS for
  # (its maxTokens per model), not the server cap. That shrinks the actual
  # reservation; the cap only refuses it.
  #
  # NOT SET ON PURPOSE: HALOGEN_THINKING_ANSWER_ROOM (default
  # max(1024, 15% of max_tokens)). Raising it looks like a cheap fix for the
  # truncated summary and is not one. The room is a FLOOR for the answer, so
  # in a 4,166-token squeeze a fixed 4096 leaves 70 tokens of thinking — and
  # worse, any request that asks for less than the room (pi's 2-token probes,
  # title calls, small budgets) gets its thinking capped at 1 token, for
  # every client, globally. Fix the headroom instead of the carve-out.
  #
  # The default is inert for pi and still worth setting: it only applies to
  # requests that name no budget, and 16384 is upstream's recommendation for
  # an agentic turn. It can never produce an error.
  maxTokensDefault = "16384";
  maxTokensCap = "65536";

  # 8-bit KV cache (0.18.9, opt-in). Keeps the attention cache in 8 bits
  # instead of 16, nearly halving it: a 524,288-position pool goes from
  # ~14.4 GiB of cache to ~8.2, and the whole device figure from ~27 GiB to
  # ~21. Prefill unchanged; decode ~0.2-0.6% slower short, ~1.7-1.9% at 32k.
  #
  # This is the lever that reaches "four full 262k conversations" without
  # cutting anything else. A 1,048,576-position pool is four full-length
  # conversations; at 16-bit it costs 36.9 GiB and additionally needs
  # HALOGEN_MAX_TOK=16384 (~9% off prefill) to fit alongside an 18 GiB
  # reserve. At 8-bit the same pool lands around 29 GiB and fits the 37.5 GiB
  # budget with real room, keeping MAX_TOK at 32768.
  #
  # And if the 327,680 context is ever wanted again, int8 is the only way to
  # afford it without losing concurrency: 983,040 positions at 8-bit is
  # ~14.5 GiB of pool instead of 26.5, so the device figure drops to ~25 GiB
  # and four full-length conversations at 1,310,720 positions come to ~30 GiB
  # — inside the 37.5 GiB budget with room. Still off, because that is a
  # second change to the answers on a box that is not asking for either.
  #
  # LEFT OFF ON PURPOSE, not forgotten. With drafting on it is not
  # byte-identical to the 16-bit cache: perplexity moves -0.3% to +0.5% and
  # a long-context answer can differ. Retrieval of planted facts at 128k and
  # 250k scored the same as 16-bit, which is reassuring for agent work, but
  # it is still a change to what the model says rather than only how fast it
  # says it. Flip this to true if four resident 262k conversations matter
  # more than identical output, and note it cannot be combined with
  # HALOGEN_COMPOSABLE_CONTEXT=1. `/health` reports the format as
  # `kv_cache`: "bf16" or "int8".
  kv8 = false;

  # Keep the weights locked in RAM. The published decode speeds are measured
  # with this ON; `0` hands back a lot of memory and costs several times the
  # decode speed (6 t/s against 37 upstream). Also: it only applies to w4b —
  # v2 refuses 0 at startup. Only reach for it if another huge workload must
  # share this host.
  pinTrunk = "1";

  # Vision. `true` maps to HALOGEN_VISION_TOWER=1, which means "look for the
  # sidecar beside the checkpoint" — we have qwen38-flash-next-vision.hgn
  # there, so the tower loads. `false` makes the image path absent entirely
  # (upstream's default: images are a 400 naming the flag) and gives back the
  # ~2 GiB of tower + scratch, which is ~0.5 GiB more of n-gram page cache
  # at 1080p. Flip to false if nothing here actually sends images.
  visionEnabled = true;

  # The scratch scales with this cap, so it is the cheapest knob to turn if
  # the pool budget gets tight: upstream notes 4K reads no better than 1440p
  # and 1080p is plenty for text.
  visionMaxPixels = "3686400"; # 2560x1440 (upstream default)
  # visionMaxPixels = "2073600"; # 1920x1080 -> frees ~0.5 GiB of vision scratch

  # Best-effort image refresh before each start. A failure is not fatal (leading
  # "-") and the cached image still runs. Set to false to take the network out
  # of the start path entirely — with `halogenDownload = false` below, the
  # container then makes no outbound connections at all.
  pullImage = true;

  # The ~130 GiB weights are already on disk in ~/halogen-models, so the volume
  # goes back read-only and the download env goes away. That is the upstream
  # recommendation once the weights are in place: nothing to clobber, nothing to
  # re-verify, no outbound fetch on start. Flip to true only to re-download.
  halogenDownload = false;

  # ---- The environment the container actually gets -------------------------
  #
  # One list, one file, one `--env-file`. Every knob above reaches the engine
  # through this and through nothing else. If you add a knob, add it here, and
  # confirm it landed with:
  #
  #   podman inspect halogen-flash-server --format '{{range .Config.Env}}{{println .}}{{end}}' | grep HALOGEN
  #
  # HALOGEN_KV_POOL_FIT=1 is deliberate: the engine measures the device budget
  # at startup and lowers the pool rather than failing the start. Asking for
  # more than fits degrades gracefully with the fitter on (that is exactly
  # what happened on 2026-10-25, when 983,040 became 491,520); with the
  # fitter off the same ask risks a hard allocation failure mid-boot. It also
  # means the pool in the running container is NOT necessarily the pool in
  # this file — read it back with the health check below, every time.
  halogenEnv =
    [
      "HALOGEN_API_PORT=8731"
      # One request's window, the prefill arena, and the yarn factor that lets
      # the window go past native. See the headroom note above the knobs.
      "HALOGEN_CTX=${toString contextPositions}"
      "HALOGEN_MAX_TOK=${prefillArenaTokens}"
      "HALOGEN_KV_POOL_POSITIONS=${kvPoolPositions}"
      "HALOGEN_KV_POOL_FIT=1"
      "HALOGEN_HOST_RESERVE_GIB=${hostReserveGiB}"
      "HALOGEN_KV_SLOTS=${kvSlots}"
      "HALOGEN_MAX_TOKENS_DEFAULT=${maxTokensDefault}"
      "HALOGEN_MAX_TOKENS_CAP=${maxTokensCap}"
      "HALOGEN_FLASH_PIN_TRUNK=${pinTrunk}"
    ]
    ++ lib.optionals visionEnabled [
      "HALOGEN_VISION_TOWER=1"
      "HALOGEN_VISION_MAX_PIXELS=${visionMaxPixels}"
    ]
    ++ lib.optionals pastNative [ "HALOGEN_ROPE_YARN=${ropeYarnFactor}" ]
    ++ lib.optionals kv8 [ "HALOGEN_KV8=1" ]
    ++ lib.optionals halogenDownload [ "HALOGEN_DOWNLOAD=${weightsRepo}" ];

  halogenEnvFile = pkgs.writeText "halogen-flash.env" (lib.concatStringsSep "\n" halogenEnv + "\n");

  # ---- Pre-flight: do not start into a host that cannot give us the pin ----
  #
  # WHY THIS EXISTS. The engine refuses to pin when MemAvailable is under
  # `payload + a 16 GiB floor`, because pinned pages cannot be swapped and a
  # task waiting on them cannot be killed, so over-pinning wedges the machine
  # for minutes instead of failing. On Sep 16 that gate closed and the unit,
  # set to restart forever with no rate limit, restarted 1,246 times in ~11
  # hours (~120/hour) while the desktop held the RAM. Each attempt was loud in
  # the journal and invisible in practice.
  #
  # Waiting is the honest behaviour here: memory frees up when the thing
  # holding it exits, and then halogen can start. So poll, say so, and give up
  # with a message that names the number rather than an exit code nobody reads.
  # This is not a crash guard and does not replace thinking about what runs
  # beside halogen — it turns a silent restart loop into a legible wait.
  #
  # The 83600 MiB is w4b-specific: 65.64 GiB of pinnable payload plus the
  # engine's 16.00 GiB floor = 81.64 GiB = 83,600 MiB. v2 needs less; if the
  # volume changes to v2, re-read the "refusing to pin" line for the new
  # payload figure and lower this with it.
  preflightGate = true;
  preflightMinMemMiB = 83600;
  preflightWaitSec = 600;

  preflightScript = pkgs.writeShellScript "halogen-preflight" ''
    need=${toString preflightMinMemMiB}
    deadline=${toString preflightWaitSec}
    step=15
    elapsed=0
    while :; do
      avail_kb=$(${pkgs.gawk}/bin/awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
      avail_mib=$((avail_kb / 1024))
      if [ "$avail_mib" -ge "$need" ]; then
        if [ "$elapsed" -gt 0 ]; then
          echo "preflight: MemAvailable recovered to $avail_mib MiB after ''${elapsed}s, starting"
        else
          echo "preflight: MemAvailable $avail_mib MiB >= $need MiB, starting"
        fi
        exit 0
      fi
      if [ "$elapsed" -ge "$deadline" ]; then
        echo "preflight: NOT starting. MemAvailable is $avail_mib MiB; the weight pin needs $need MiB."
        echo "preflight: the engine will refuse to pin below that (pinned pages cannot be swapped,"
        echo "           and a task waiting on them cannot be killed), and it is right to."
        echo "preflight: free some memory - a browser, a loaded ollama/llama-server model, a"
        echo "           second desktop session - and this unit comes up on its own next retry."
        echo "preflight: as root, 'echo 1 > /proc/sys/vm/compact_memory' helps if the RAM is"
        echo "           free but fragmented rather than used."
        exit 1
      fi
      echo "preflight: MemAvailable $avail_mib MiB < $need MiB, waiting ($elapsed of $deadline s)"
      ${pkgs.coreutils}/bin/sleep $step
      elapsed=$((elapsed + step))
    done
  '';

  # The mount mode follows the download switch. The entrypoint refuses to download into
  # a read-only volume, so enabling halogenDownload while leaving `:ro` would just fail
  # the start; deriving one from the other keeps them from drifting apart.
  modelsMountOpt = if halogenDownload then "" else ":ro";
in
{
  # Run the server. Rootless podman, one container ("all" mode): the engine
  # binds loopback inside the container and the OpenAI-compatible front-end is
  # published on :8731 (loopback-only on the host).
  systemd.user.services.halogen-flash-server = lib.mkIf llmEnabled {
    Unit = {
      Description = "halogen-flash server (Qwen3.8-Flash-Next, OpenAI API :8731)";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];

      # Start before the other LLM backends. All three are enabled on this box
      # by the same `enableLlm` flag and halogen is the one that needs ~66 GiB
      # pinned in large contiguous chunks, so it should win that race rather
      # than arrive after ollama and llama-server have taken pages. Ordering
      # only, no dependency: if they are not enabled this is inert, and if
      # halogen's gate holds, they still start.
      Before = [ "llama-server.service" "ollama.service" ];

      # A crash loop here is not a cheap crash loop: every restart re-pins ~68
      # GiB of weights and re-reads them through the page cache, and a re-pin
      # that fights a fragmented host can burn tens of minutes at 100% of one
      # core. A rate limit is left OFF deliberately (0.17's "let halogen try to
      # recover by himself") so a transient failure self-heals rather than
      # leaving the model down. The pre-flight gate above is what keeps that
      # loop legible now: it waits for memory instead of hammering, so the
      # failure mode is "waiting, N of 600 s" in the journal rather than 1,246
      # anonymous restarts. Re-enable this only if you want halogen to stop
      # trying rather than keep trying.
      # StartLimitIntervalSec = 900;
      # StartLimitBurst = 3;
    };

    Install.WantedBy = [ "default.target" ];
    # WantedBy used to be graphical-session.target, which put this *behind* the
    # desktop in the race for RAM: Plasma, browsers and everything else grab
    # pages and fragment them before the 68 GiB pin starts. With lingering on
    # (users.users.alexfneves.linger = true in /etc/nixos/configuration.nix)
    # default.target starts this at login ahead of the session, so the weights get
    # contiguous memory first. Verified in the startup log by the line
    #   "host memory: N contiguous 2 MiB blocks ... free"
    # — a bigger N means an easier start.

    Service = {
      # systemd gives user units a minimal PATH; the nixpkgs podman needs its
      # helper wrapper (crun/conmon) and the setuid newuidmap/newgidmap helpers
      # in /run/wrappers/bin for rootless operation.
      # HALOGEN's OWN SETTINGS ARE NOT SET HERE — see halogenEnv above. A
      # systemd unit's `Environment=` is not inherited by a container, so every
      # HALOGEN_* variable that used to live here was silently dropped and the
      # server ran pure image defaults for a month. They go in via --env-file.
      Environment = [
        "PATH=${pkgs.podman}/bin:/run/wrappers/bin:/run/current-system/sw/bin:/usr/bin:/bin"
      ];

      # Gate first (cheap, and it is the thing that should stop us), then the
      # best-effort image refresh. The leading "-" on the pull keeps a network
      # failure from taking the start down; the gate is fatal on purpose.
      ExecStartPre =
        lib.optionals preflightGate [ preflightScript ]
        ++ lib.optionals pullImage [ "-${pkgs.podman}/bin/podman pull ${image}" ];

      ExecStart = pkgs.writeShellScript "halogen-flash-server" ''
        exec ${pkgs.podman}/bin/podman run --rm --replace \
          --name halogen-flash-server \
          --env-file ${halogenEnvFile} \
          --publish 127.0.0.1:8731:8731 \
          --device /dev/kfd \
          --device /dev/dri \
          --group-add keep-groups \
          --security-opt seccomp=unconfined \
          --ipc=host \
          --ulimit memlock=-1:-1 \
          --volume "$HOME/halogen-models:/models${modelsMountOpt}" \
          ${image}
      '';

      Restart = "always";
      # 5s was fast enough to march through repeated 68 GiB re-pins. Give the
      # host time to settle (and to get its page cache back) between tries.
      RestartSec = "20";
      TimeoutStopSec = "120";
    };
  };

  # ---- Checking what this actually resolved to -------------------------------
  #
  # The pool we asked for, the pool the engine took, the firmware carve-out and
  # the memory left over are all printed at startup:
  #
  #   journalctl --user -u halogen-flash-server 2>&1 \
  #     | grep -E '^(dmalloc|kv pool:|startup|slots:|checkpoint:)'
  #
  # ...and live, without touching anything:
  #
  #   curl -s localhost:8731/health | grep -o '"kv_pool_positions":[0-9]*'
  #   curl -s localhost:8731/health | grep -o '"context":[0-9]*'
  #   curl -s localhost:8731/health | grep -o '"rope_scaling":[^,]*'   # {"type":"yarn",...} not null
  #   curl -s localhost:8731/health | grep -o '"kv_cache":"[a-z0-9]*"'   # bf16 or int8 (kv8)
  #   curl -s localhost:8731/health | grep -o '"vision":{[^}]*'
  #   curl -s localhost:8731/health | grep -o '"max_tokens_default":[0-9]*'
  #
  # and that the file we generated is what the container was handed:
  #
  #   podman inspect halogen-flash-server --format '{{range .Config.Env}}{{println .}}{{end}}' | grep HALOGEN
  #
  # NOTE ON MEMORY REPORTING: `free`/`MemAvailable` count this server's locked
  # weights as reclaimable page cache, so they overstate what this host has free
  # by roughly 68 GiB, and htop's "used" excludes page cache entirely and
  # therefore understates halogen by roughly the same amount. The two numbers
  # that are honest here are the engine's own
  #   "host memory left for everything else: ... GiB"
  # and the cgroup:
  #   podman stats --no-stream halogen-flash-server
  #
  # BEFORE restarting: close the browser-heavy apps first, and as root
  #   echo 1 > /proc/sys/vm/compact_memory
  # Restarting against a fragmented host is the slow way to boot this thing.
  # The pre-flight gate is checked against MemAvailable, which is the number
  # to watch: at the w4b layout it needs 81.64 GiB and a desktop session that
  # has been up a while usually leaves 78-80, which is why a mid-session
  # restart is the risky one and a cold boot is not.
  #
  # OUTSIDE HOME-MANAGER (needs root). Status against /etc/nixos/configuration.nix,
  # read on 2026-10-18, not carried over from old comments in this file:
  #
  #   ALREADY DONE — do not repeat:
  #     * amd_iommu=off, plus ttm/amdttm pages_limit and page_pool_size at
  #       28,835,840 pages (110 GiB). The old note asking for these was stale;
  #       they are in boot.kernelParams already, and amd_iommu=off is the one
  #       worth a double-digit percentage of prefill.
  #     * linger = true, which is what lets default.target bring this unit up
  #       ahead of the graphical session.
  #
  #   NOT DONE, AND NOT WORTH THE REBUILD:
  #     * vm.swappiness=10 / vm.page-cluster=0. Carried in old comments as if
  #       outstanding. They are not set (60 / 3 today), but swap has been at
  #       0 B used across every check we made, so the reclaim behaviour they
  #       would change is not being exercised. A speculative tuning on a box
  #       that is not swapping. Skip unless swap actually gets used and something
  #       stalls on it.
  #
  #   STILL WORTH IT, AND NOT A NIX CHANGE:
  #     * BIOS: UMA frame buffer / dedicated graphics memory -> Auto (~512 MiB).
  #       ~2.0 GiB is carved out for the iGPU in firmware and invisible to
  #       /proc/meminfo; halogen drives the GPU through GTT and does not use
  #       it. That GiB would go to the n-gram page cache, i.e. prefill speed.
  #       The engine warns about it at startup.
}
