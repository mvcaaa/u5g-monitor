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
- Watchdog `mode=live` since 2026-10-20 21:00 (owner's decision): on each episode diag -> episode tests -> cure, at most one trigger per hour, no daily limit. First real auto-cure: episode 5 (2026-10-21 01:08, recovered ~8 min after onset): docs/episodes/2026-10-21-episode-5.md.
- Episode 1 (2026-10-19) was captured and cured by hand: docs/episodes/2026-10-19-episode-1.md. Root cause on the operator's side is unknown.
- Episodes 2 (night, untreated, ended by itself after ~7.7 h) and 3 (midday, cured by hand; recovery already during the 0D hold): docs/episodes/2026-10-20-episodes-2-3.md.
- The light probe (1 MB/min) is the only detector since 2026-10-20 15:27 (owner's decision; the 5 MB probe.sh stays as diagnostics only; Speedtest Tracker removed): episode = 3 samples in a row >= max(2 x baseline, 0.8 s), clear after 5 fast.
- Episode 4 (evening, cured by hand; first live episode of the light-only detector, detected 4 min after onset): docs/episodes/2026-10-20-episode-4.md.
- Episode tests (`agent/episode-tests.sh`: packet-size pings, MSS-limited downloads, ~21 MB) run on each trigger since 2026-10-20 ~20:40, plus a good-state reference at 04:10/16:10 and a pcap of the downloads since 2026-10-21; in live mode a `diag` is also saved after each cure. Metrics `u5g_eptest_*{kind}`, dashboard row "Episode tests". First run in an episode: episode 5 (smaller MSS does not help; ping loss grows with size towards both destinations).
- 2026-10-21: four episodes, four automatic cures (~8 min each), **onsets every ~6 h 04 min** regardless of cures: docs/episodes/2026-10-21-day.md (prediction for 22.10 hit 4 of 4 within 1 min: docs/episodes/2026-10-22-day.md; next expected 23.10 ~01:33, 07:37, 13:41, 19:45).
- 2026-10-23..26: 14 episodes on the same grid (mean 6 h 03.8 min), one slot skipped (25.10 ~13:12), three ended by themselves within 3-5 min (25.10 19:15, 26.10 01:18, 13:26): docs/episodes/2026-10-23-26-days.md (next expected 26.10 ~19:30; 27.10 ~01:34, 07:37, 13:41, 19:45).
- Since 2026-10-26 15:47 the light probe also records out-of-order packets of its download (`u5g_probe_light_ooo_packets`; since 2026-10-27 19:31 by polling `ss` during the unchanged curl download: the python downloader of 26.10 failed some samples instantly with code 0 and delayed the 26.10 19:29 detection by ~4 min, it was rolled back 27.10 19:28) and the watchdog logs slow samples with reordering as `SHADOW:`; fast rule `LIGHT_OOO` is off. Faster reaction = this rule + `EPTEST=off` (tests ran 22 times): both await the owner.
- Since 2026-10-21 a read-only radio snapshot every 5 min (dispatcher `radio-status`, `agent/radio-status.sh`, metrics `u5g_radio_*`, raw text `radio/<date>.txt`).
- Planned: move the agent scripts off the TrueNAS host into a pinned Docker image (owner, 2026-10-20).
- Open items: watch the first live episodes of the light-only detector (detection delay, false starts/clears; mild ~10 Mbit/s drops are an estimate); test a shorter hold (`band-cycle.sh 20`) and lighter actions (`AT+CGATT`)
  only during an episode and with the owner's go-ahead; evidence package / message for the operator (the owner sends it himself).
