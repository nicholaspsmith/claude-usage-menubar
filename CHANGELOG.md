# Changelog

Every push to `main` is a release. Before pushing, add a `## [X.Y.Z] - YYYY-MM-DD`
section at the top with `- ` entries (minor for features, patch for fixes); if an
`## [Unreleased]` section is waiting, turn it into that section. GitHub tags it
and publishes the section as the release notes; a push or pull request
without one is refused (`[no release]` in the tip commit is the only exception).
Versions follow [Semantic Versioning](https://semver.org/). The full rule:
[StatusItemKit — Releases](https://github.com/nicholaspsmith/StatusItemKit#releases-every-push-is-one).

## [1.15.0] - 2026-10-20

### Changed

- Icon ▸ and Color ▸ move out of Settings ▸ into the main menu, directly below Settings and above Quit Claude Usage, still side by side. Settings keeps Show Sessions, One Eye per Window, the sign-in rows, Start at Login and the version. Needs StatusItemKit 0.35.0 (`SettingsMenu.addFooter(belowSettings:)`)

## [1.14.1] - 2026-10-20

- `install.sh` now hands the install to parity on a Mac parity syncs, instead of building a second copy of the app that macOS could launch in place of parity's. `PARITY=off ./install.sh` still builds it locally.

## [1.14.0] - 2026-10-20

- Menu bar icons now update more smoothly with significantly reduced CPU usage during animations.

## [1.13.0] - 2026-10-15

- Settings ▸ One Eye per Window: the owl's left eye shows the session window and its right eye the weekly window, each eye's lid and colours following its own percentage. Off by default, which keeps both lids on the session and both eyes' colours on the week
- Colour pairs are back: Settings ▸ Color offers Grape & Mint, Sky & Tangerine, Lime & Fuchsia and Rose & Cobalt alongside the default Usage (Green → Red). A pair gives the session and weekly bars, the plain meters and the owl's pupils a fixed colour per window; the whites still redden with usage
- Needs StatusItemKit 0.33.0

## [1.12.0] - 2026-10-15

- Carol now sleeps in the menu bar, with her eyes closing, body breathing, and Zs floating above her.

## [1.11.0] - 2026-10-15

- Carol's animation in the menu bar is smoother and no longer clips the top of her headband.

## [1.10.0] - 2026-10-15

- The caterpillar icon in the menu bar now supports a walking animation, adding a new visual state to the app's status item.

## [1.9.0] - 2026-10-13

- When the weekly allowance is spent with more than a day left before it resets, Archimedes says "Dude…go outside!" in a speech bubble under his beak, once a minute until you click it; then he shuts his eyes until the week resets

## [1.8.0] - 2026-10-09

- No user-visible changes.

## [1.7.0] - 2026-10-08

- No user-facing changes.

## [1.6.0] - 2026-10-07

- No user-visible changes.

## [1.5.2] - 2026-10-06

- Ticking a checkbox in the menu no longer closes it: Settings ▸ Show Sessions stays open, and the sessions section appears or goes in the menu behind it

## [1.5.1] - 2026-10-05

- New app icon: Archimedes as he looks in the menu bar

## [1.5.0] - 2026-10-05

- The menu ends with the standard Menumon **Settings ▸** submenu and **Quit Claude Usage** (⌘Q): the version moved into Settings, below Show Sessions, sign-in, Icon and Start at Login

## [1.4.0] - 2026-10-02

- feat: the owl takes turns with the other animated Menumon mascots: it blinks on :00, and Menu Pimp, Carol, Caveepyan and Armonitor follow a second apart (only those that are running)

## [1.3.0] - 2026-10-02

- feat: the owl blinks once a minute, on the minute: a slowed version of a real blink, with the lids falling fast, holding shut briefly, and lifting with a long settle (550 ms in all; skipped under Reduce Motion)

## [1.2.1] - 2026-09-28

- `install.sh` now asks whether to turn on Start at Login (skipped when it is already on, or when there is no terminal to ask in), then relaunches the app, quitting any running copy first so the new build takes over

## [1.2.0] - 2026-09-26

- feat: pupils and usage bars run #005401 → #FF5401; veins only in the last quarter

## [1.1.0] - 2026-09-26

- feat: usage bars and owl pupils share the green→yellow→orange→red ramp
- feat: eyelids are the session, eye colour is the week; colour pairs removed
- fix: a failed sign-in says what the server actually answered

## [1.0.0] - 2026-09-23

- feat: the menu shows the version it was built from
- LICENSE: name the copyright holder above the MPL text
- License: Mozilla Public License 2.0
- feat: sign in with Claude from the menu, no terminal needed
- fix: a stale .credentials.json no longer hides the live Keychain login
- docs: document the --login flag
- fix: --login status no longer enables Start at Login
- docs: bloodshot whites described; icon strip regenerated with the deeper pink
- feat: Icon, Show Sessions and Start at Login move under one Settings submenu
- feat: sessions section hidden by default, with a Show Sessions toggle in the menu
- feat: session and weekly get a colour pair — left pupil matches the session bar, right pupil the weekly
- docs: radial owl veins
- docs: tired-owl icon strip
- docs: Curtain is now Barn
- docs: Apollo Monitor described without the vendor name
- art: new mascot and app icon matching the menu-bar face
- docs: the character menu-bar icon, rendered from code, and what its states mean
- feat: owl eyelids droop with session and weekly usage
- feat: darker owl-eye fills
- feat: owl eyes step green, lime, orange, red by quarter
- feat: owl eyes go orange past 50%, red past 75%
- feat: owl eyes fill black, red only past 75%
- feat: owl icon — eyes are the session and weekly meters (Icon ▸ Owl, default)
- feat: app icon from the Menubarn mascot
- docs: mention the Menubarn widget library
- docs: why a standalone app beats a SwiftBar plugin
- docs: add the Menubarn mascot to the README
- Read the credential through /usr/bin/security, and cache it
- Advertise the menu-bar suite, and add a menu screenshot
- Adopt StatusItemKit's shared Icon menu
- Fill the resting state in light purple instead of green
- Lead the README with a screenshot and install steps
- Keep the menu open on refresh, and show how stale the numbers are
- Stretch the title row and bars to the menu width
- Move refresh onto the title row as an icon
- Drop the tokens section
- Read the live login, add re-auth, and log why a poll came up empty
- Draw the chosen meter when there is no data, instead of a dot
- Limit bars, a choosable icon, and fix the Keychain lookup
- Make estimated cost opt-in
- Claude Usage: menu-bar app for plan limits, token spend, and live sessions
