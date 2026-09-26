# Changelog

Every push to `main` is a release. Before pushing, add a `## [X.Y.Z] - YYYY-MM-DD`
section at the top with `- ` entries (minor for features, patch for fixes); if an
`## [Unreleased]` section is waiting, turn it into that section. GitHub tags it
and publishes the section as the release notes; a push without one is refused.
Versions follow [Semantic Versioning](https://semver.org/). The full rule:
[StatusItemKit — Releases](https://github.com/nicholaspsmith/StatusItemKit#releases-every-push-is-one).

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
