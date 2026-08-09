#!/usr/bin/env bash
# herdr-cycle: open a fresh herdr session, or pick one of the existing
# sessions to attach to or delete. New sessions are named with a timestamp
# (YYYY-MM-DD-HH-MM-SS-mmm).
#
#   - No sessions       -> spin up a fresh session right away
#   - New session       -> attach to a brand-new timestamped session
#   - New session (name)-> type a name; creates "<name>-<timestamp>"
#   - Attach to (N)     -> pick a session, attach
#
# When herdr exits, the session that was just used is stopped and deleted.
# The terminal closes when no sessions are left, otherwise the menu comes back.
#   - Delete (N)        -> pick a session, stop it if running, delete it,
#                          staying in the delete picker until only one session
#                          is left, then close the terminal
#   - ESC / Ctrl+C      -> on the main menu closes the terminal (window),
#                          inside the sub-menus returns to the main menu
#
# Every session except the persistent "default" workspace is listed, whether
# timestamped (created here) or leftover from an older scheme.
# Deps: herdr, fzf, python3, date (all in home.packages / coreutils).
set -euo pipefail

new_session_name() {
    # herdr only allows [A-Za-z0-9._-] in session names (no colons!),
    # hence the all-dash timestamp format.
    while :; do
        n="$(date +%Y-%m-%d-%H-%M-%S-%3N)"
        # Same-millisecond collision (e.g. a previous run died mid-session):
        # the name exists -> regenerate. Otherwise keep this name.
        if session_list | grep -qF -- "$n"; then
            continue
        fi
        break
    done
    printf '%s' "$n"
}

# Stop + delete a session after it was used. Errors are swallowed: the
# session may already be stopped, and a leftover stays visible in the menu.
cleanup_session() {
    herdr session stop "$1" 2>/dev/null || true
    herdr session delete "$1" 2>/dev/null || true
}

# Ask for a session name via a plain read prompt (fzf can't capture free-form
# input: with an empty candidate list there is nothing to accept on Enter).
# Type + Enter confirms, Ctrl-C aborts back to the menu. Validates herdr's
# charset [A-Za-z0-9._-]; invalid input repeats with an error message.
# Echoes the name; returns 0 = ok, 1 = aborted/empty.
ask_session_name() {
    local name invalid=0
    # Blank the screen so only the name prompt remains (output redirected to
    # the tty: this function's stdout is captured by the caller via $()).
    clear >/dev/tty 2>/dev/null || true
    while :; do
        if [ "$invalid" -eq 1 ]; then
            printf '%s\n' 'Invalid name — only letters, numbers, ".", "_", "-" allowed.' >&2
        else
            printf '%s\n' 'Session name — Enter: create · Ctrl-C: back' >&2
        fi
        # Ctrl-C during read aborts the prompt (and clears itself, so the trap
        # never leaks into fzf menus where Ctrl-C means something else).
        trap 'trap - INT; return 1' INT
        if ! read -r -e -p 'session name> ' name; then
            trap - INT
            return 1 # EOF or aborted
        fi
        trap - INT
        name="${name//[[:space:]]/}"
        if [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
            printf '%s' "$name"
            return 0
        fi
        invalid=1
    done
}

# Outputs "name (running|stopped)" lines for disposable sessions.
session_list() {
    herdr session list --json | python3 -c '
import signal, sys, json
signal.signal(signal.SIGPIPE, signal.SIG_DFL)
for s in json.load(sys.stdin).get("sessions", []):
    if s.get("default"):
        continue # the persistent workspace is never part of the cycle
    state = "running" if s["running"] else "stopped"
    print("{} ({})".format(s["name"], state))
'
}

session_count() {
    session_list | awk 'END { print NR }'
}

# fzf with context + key hints: $1 prompt, $2 header (may be multi-line).
# Enter selects, Ctrl-C aborts (closes on the main menu, goes back elsewhere).
pick() {
    fzf --border --header-first --layout=reverse --prompt "$1" --header "$2"
}

# fzf picker over the session list; echoes the chosen "name (state)" line,
# or nothing if the user aborts with ESC/Ctrl+C. $1 = header text.
pick_session() {
    session_list | pick 'herdr session> ' "$1"
}

main() {
    while true; do
        count=$(session_count)

        if [ "$count" -eq 0 ]; then
            # Nothing to attach to: create a session right away; once herdr
            # exits, stop + delete it and close the terminal.
            n="$(new_session_name)"
            herdr session attach "$n"
            cleanup_session "$n"
            exit 0
        fi

        choice=$(printf 'New session\nNew session with name\nAttach to session (%s)\nDelete session (%s)\n' "$count" "$count" \
                  | pick 'herdr> ' $'Pick an action\nEnter: select \u00b7 Ctrl-C: close terminal' || true)

        case "$choice" in
            'New session')
                n="$(new_session_name)"
                herdr session attach "$n"
                # herdr exited: clean up the session that was just used.
                cleanup_session "$n"
                if [ "$(session_count)" -eq 0 ]; then
                    exit 0 # nothing left: closes the terminal
                fi
                # otherwise: loop back to the main menu
                ;;
            'New session with name')
                typed=$(ask_session_name) || continue # aborted: back to menu
                n="$typed-$(date +%Y-%m-%d-%H-%M-%S-%3N)"
                herdr session attach "$n"
                # herdr exited: clean up the session that was just used.
                cleanup_session "$n"
                if [ "$(session_count)" -eq 0 ]; then
                    exit 0 # nothing left: closes the terminal
                fi
                # otherwise: loop back to the main menu
                ;;
            'Attach to session ('*)
                sel=$(pick_session $'Pick a session to attach (state in parentheses)\nEnter: attach \u00b7 Ctrl-C: back' || true)
                [ -n "$sel" ] || continue # back to main menu
                read -r name _ <<< "$sel"
                herdr session attach "$name"
                # herdr exited: that session was a one-off cycle, clean it up.
                cleanup_session "$name"
                if [ "$(session_count)" -eq 0 ]; then
                    exit 0 # nothing left: closes the terminal
                fi
                # otherwise: loop back to the main menu
                ;;
            'Delete session ('*)
                # Stay in the delete picker until only one session is left,
                # then close the terminal. Ctrl+C on any pick aborts back to
                # the main menu (previous deletions are kept).
                aborted=0
                while true; do
                    sel=$(pick_session $'Pick a session to delete (state in parentheses)\nEnter: delete \u00b7 Ctrl-C: back' || true)
                    if [ -z "$sel" ]; then
                        aborted=1
                        break
                    fi
                    read -r name state <<< "$sel"
                    if [ "$state" = "(running)" ]; then
                        herdr session stop "$name"
                    fi
                    herdr session delete "$name"
                    [ "$(session_count)" -gt 1 ] || break
                done
                [ "$aborted" -eq 1 ] && continue
                exit 0 # one session (or none) left: closes the terminal
                ;;
            *)  # ESC / Ctrl+C on the main menu: closes the terminal
                exit 0
                ;;
        esac
    done
}

main "$@"