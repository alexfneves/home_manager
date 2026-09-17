{ lib, inputs, hostConfig, ... }:

# Home dashboard — a localhost web UI for this machine's CPU / GPU / unified
# memory, and for the status and per-unit resource use of the local LLM user
# units (ollama, llama-server, halogen-flash-server), with start/stop/restart
# buttons.
#
# The package and its home-manager module live in their own flake, pinned as the
# `home-dashboard` input in flake.nix; importing the module is all that is needed
# here. It intentionally only runs where the LLM stack runs (`enableLlm`, i.e.
# gmktec): the three units it watches are the ones modules/llm.nix,
# modules/llama-server.nix and modules/halogen-flash.nix define under the same
# `lib.mkIf llmEnabled` gate. On other hosts the unit set would not exist, so
# the dashboard would just render three `unknown` cards.
#
# Options (see the module's README for the full list):
#   services.home-dashboard.enable       -> whether to run it at all
#   services.home-dashboard.port        -> default 8899
#   services.home-dashboard.bind        -> default 127.0.0.1 (loopback only; the
#                                         server has no TLS and is not meant to
#                                         be exposed)
#   services.home-dashboard.publicHosts -> extra names the Host/Origin guards
#                                         accept; only needed behind a proxy
#
# Why publicHosts is set here: https://home-dashboard.alexfneves.com is served
# by Pangolin (Traefik + the `badger` access-control plugin) running on THIS
# machine, which authenticates the user and then proxies to 127.0.0.1:8899.
# Traefik forwards the public `Host` and the browser's `Origin: https://…`
# unchanged, so without this the dashboard's DNS-rebinding guard answers 403 to
# every proxied request — the page on the Host check, the start/stop POSTs on
# the Origin check. Declaring the name widens the *name* allow-list only: `bind`
# stays loopback, so nothing outside the machine can reach :8899 directly, and
# all authentication stays with Pangolin.
#
# Note: the monitored unit set is compiled into the binary, not configured — see
# the README's "The monitored unit set is compiled in, not configured".
{
  imports = [ inputs.home-dashboard.homeManagerModules.default ];

  services.home-dashboard = {
    enable = hostConfig.enableLlm;
    publicHosts = [ "home-dashboard.alexfneves.com" ];
  };
}
