@AGENTS.md

# CLAUDE.md - Claude Code context for this repository

`AGENTS.md` (imported above) holds the safety rules, repository map and playbooks; follow it first. Reading order of the docs: README.md "Documentation reading order".
**Private, deployment-specific context** (modem address, logins, TrueNAS paths, cron job ids, live Grafana state) is NOT in git: it lives in `CLAUDE.local.md`
next to this file (gitignored). If it is missing, ask the owner for it; never put such details into any committed file, issue or commit message.

## Working style with the owner
- Russian in conversation; code, comments and docs in English.
- One step per message; terminal commands as single short lines (long or multi-line pastes get garbled in his terminal): deliver anything longer as a file.
- Prefers the terminal/CLI over web UIs. Never ask him to paste secrets (tokens, API keys, passwords); scripts must prompt for passwords themselves.
- The owner decides about anything that leaves the machine (git push, e-mails to the operator) and about band changes on the modem: never do those yourself.
- Honest reporting: say what was verified and what is inference; retract wrong statements openly. Do not claim live behaviour you did not observe.
- Everything implemented on the live system must also be in this repo (scripts, dashboards, alerts, docs), with a commit; live-only hacks are not acceptable.

## Where things stand (2026-10-20)
- Stack is deployed on the owner's TrueNAS in "layout B" (hand-built UI apps + cron, see docs/TRUENAS.md); the compose stack in this repo is the portable, tested-by-config-only version.
- Watchdog `mode=dry` (never cures by itself). Auto-cure was never exercised live.
- Episode 1 (2026-10-19) was captured and cured by hand: docs/episodes/2026-10-19-episode-1.md. Root cause on the operator's side is unknown.
- Episodes 2 (night, untreated, ended by itself after ~7.7 h) and 3 (midday, cured by hand; recovery already during the 0D hold): docs/episodes/2026-10-20-episodes-2-3.md.
- The light probe (1 MB/min) is the only detector since 2026-10-20 15:27 (owner's decision; the 5 MB probe.sh stays as diagnostics only; Speedtest Tracker removed): episode = 3 samples in a row >= max(2 x baseline, 0.8 s), clear after 5 fast.
- Open items: watch the first live episodes of the light-only detector (detection delay, false starts/clears; mild ~10 Mbit/s drops are an estimate); test a shorter hold (`band-cycle.sh 20`) and lighter actions (`AT+CGATT`)
  only during an episode and with the owner's go-ahead; evidence package / message for the operator (the owner sends it himself).
