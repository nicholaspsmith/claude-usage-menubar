# Claude Usage

A macOS menu-bar app for Claude Code usage: how much of your plan you have left,
what you have spent, and which agents are running. Built on
[StatusItemKit](https://github.com/nicholaspsmith/StatusItemKit).

The icon tracks the **5-hour session limit** — the one that actually stops your
work — green below 50%, orange from 50%, red at 80% and up. Pick its shape from
menu ▸ Icon: **Arc**, **Gauge**, **Pie**, or **Wedge**. Every choice shows a
proportion, because that is the icon's whole job; the weekly window is the
slower one and lives in the menu rather than competing for the single glyph.

Both allowances appear in the dropdown as labelled progress bars with their
reset countdowns.

## What the menu shows

| Section | Source |
|---|---|
| Plan (`Max 20x`, `Pro`) and the 5-hour + 7-day allowances, with reset countdowns | Anthropic's OAuth usage endpoint |
| Tokens per day for the last week (estimated cost optional) | `~/.claude/projects/**/*.jsonl` transcripts |
| Today's tokens broken down by model | the same transcripts |
| Running Claude Code sessions and whether each is busy | `~/.claude/sessions/*.json` |

## Install

Needs a sibling checkout of `StatusItemKit`:

```bash
git clone https://github.com/nicholaspsmith/StatusItemKit.git ~/Code/StatusItemKit
git clone https://github.com/nicholaspsmith/claude-usage-menubar.git ~/Code/claude-usage-menubar
cd ~/Code/claude-usage-menubar && ./install.sh
```

`install.sh` builds the bundle, symlinks `~/Applications/Claude Usage.app` to
`build/`, registers Start-at-Login, and launches it.

## The Keychain prompt

On first run macOS asks to read the `Claude Code-credentials` Keychain item.
That item holds the OAuth token, and the token's only destination is the
`Authorization` header of the usage probe — nothing else from the credential
store reaches the UI except the plan name. Choose **Always Allow** to stop the
prompt recurring.

Deny it and the limits section reads "Not signed in"; token counts and session
state keep working, because those come from local files.

If limits read **"Sign-in expired"**, start Claude Code. Only the CLI can mint a
fresh token — this app can only read the one the CLI leaves behind.

## Notes on the numbers

- **Estimated cost is off by default** (menu ▸ Show Estimated Cost). It is the
  API list price — what these tokens *would* have cost on the API. On a
  subscription without overage billing it is money that cannot be charged:
  the tokens are covered by the flat fee, and hitting the limit stops work
  rather than billing for it. Useful as a sense of scale, misleading as a bill.
- Cache traffic is priced separately: reads at 0.1x the base input rate, writes
  at 1.25x (the 5-minute TTL; transcripts don't record which TTL was used).
- A model missing from the rate table is left out of the cost rather than priced
  as something it isn't, and the day's figure gets a `+` to mark it as a floor.
- **The utilization scale is decided per payload.** The endpoint reports
  percentages (`37.0`), but older payloads used fractions (`0.37`). A lone
  `1.0` is genuinely ambiguous, so any value >= 1 marks the whole payload
  percent-scaled and `1.0` reads as 1%.
- Limits are cached and reused for 15s so opening and closing the menu doesn't
  become one request per flick. A failed probe falls back to the last known
  numbers — but only while their window is still open, since a limit past its
  reset describes an allowance that already refilled.

## Development

```bash
swift build
swift test
```

`ClaudeUsageCore` holds the parsing and aggregation and has no AppKit
dependency, so all of it is unit-testable; the app target is the menu and icon.

## License

MIT
