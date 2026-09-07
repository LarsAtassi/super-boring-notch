# Super Boring Notch

A personal fork of [boring.notch](https://github.com/TheBoredTeam/boring.notch)
— a macOS app that turns the MacBook notch into a media controller, calendar
peek, file shelf, and HUD replacement.

This is a private build for my own machine, not a redistribution. Upstream does
the hard work; this repo adds a few local changes on top.

**Provenance:** this repository starts from a snapshot of
[TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) at
commit `99900bf630a3d3e97fae079df2175993318d51f7` (2026-08-29, v2.7.3). It is
committed as a fresh tree rather than a git fork, so the commit history does not
record that lineage — this note and [LICENSE](LICENSE) do. Copyright in the
original work remains with its authors.

## Differences from upstream

### Features added on top of upstream

- **Resizable open notch.** Settings → Layout has width and height sliders
  (400–1200 × 150–500 pt). Changes apply live, no relaunch.
- **Apple Shortcuts.** Settings → Shortcuts lets you add shortcuts by name with
  an icon and colour; they appear as buttons in the opened notch. Running one
  uses the `shortcuts://` URL scheme, which works from inside the sandbox.
- **Background only.** The app never takes a Dock icon; a menu is installed
  programmatically so Cmd-C/V/A still work in Settings without one. A toggle
  under General restores the Dock icon if you want it.
- **Adaptive shortcut tiles.** Tiles are sized against the real available area
  so the panel fills its space instead of leaving a dead margin, and scroll
  when they genuinely cannot fit.
- **Grid layout.** Settings → Layout sets the column count (2–6) and each
  panel's width in columns (1–4). Panels fill a row in order and wrap onto the
  next, with a live miniature of the arrangement in settings.
- **Customisable panels.** Music, Calendar, Shortcuts and Mirror each have a
  toggle and drag-to-reorder, and sit on optional cards.
- **Renamed** to Super Boring Notch (`SuperBoringNotch.app`).

### Fork changes

| Change | Why |
|---|---|
| Auto-updater disabled (`SUFeedURL` removed, updater never started) | Upstream's Sparkle feed could otherwise replace this build with theirs |
| ATS narrowed to localhost | Upstream set `NSAllowsArbitraryLoads`; only `http://localhost` actually needs it |
| Bundle ID `com.larsatassi.superboringnotch` | Avoids colliding with an installed boring.notch |
| `com.apple.security.cs.disable-library-validation` | Ad-hoc signing requires it; see SECURITY-AUDIT.md |
| Album art waits before falling back to the app icon | Upstream flashed the player's logo on every track skip |
| Upstream CI, release, and community files removed | They reference secrets and an org this fork doesn't have |

See [SECURITY-AUDIT.md](SECURITY-AUDIT.md) for the review of upstream's code
that this fork is based on.

## Requirements

- macOS 14 Sonoma or later
- Xcode 16+ (this machine has Xcode 26.6 at `/Applications/Xcode.app`)

Note: `xcode-select` points at the Command Line Tools on this machine, so every
build command below sets `DEVELOPER_DIR` explicitly. To make it permanent
instead, run `sudo xcode-select -s /Applications/Xcode.app` once.

## Build

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Release -derivedDataPath build build
```

The app lands at `build/Build/Products/Release/SuperBoringNotch.app`. The Xcode
scheme and target are still named `boringNotch`; only the product was renamed.

## Install

```bash
cp -R build/Build/Products/Release/SuperBoringNotch.app /Applications/
```

The build is ad-hoc signed (no Apple Developer account), so Gatekeeper will
object the first time. Clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/SuperBoringNotch.app
```

Since the app is built locally rather than downloaded, it usually carries no
quarantine attribute at all and this step is a no-op.

## Permissions

On first launch macOS will ask for what the features need — Accessibility (HUD
key interception), Calendar (event widget), Camera (mirror widget), and
Automation for Music/Spotify. Granting is per-feature; skip what you don't use.

## Pulling upstream changes

Because this repo has no shared ancestor with upstream, git cannot merge from
it directly. Diff against the audited snapshot and apply what you want by hand:

```bash
git remote add upstream https://github.com/TheBoredTeam/boring.notch.git
git fetch upstream
git diff 99900bf upstream/main -- <path>
```

Review before applying — the audit in `SECURITY-AUDIT.md` covers commit
`99900bf` and nothing after it.

## License

This is a derivative work of boring.notch and is therefore **GPL-3.0**, the
same licence as the original — see [LICENSE](LICENSE). That obligation applies
if the app is ever distributed; it does not restrict private use.

Third-party components are listed in
[THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES). The bundled MediaRemote adapter
is BSD 3-Clause, © Jonas van den Berg
([ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)).

## Verified

Built and launched on this machine: `BUILD SUCCEEDED`, app stays resident, the
MediaRemote perl stream subprocess spawns as expected, idle CPU 0.0–0.4%.

The notch window was measured against the size setting: at 820 × 260 the window
reports 820 × 280 (the extra 20 pt is `shadowPadding`), and at 640 × 190 it
reports 640 × 210. Shortcut names are percent-encoded so `&` and `+` survive the
round trip, and `shortcuts://` resolves to `/System/Applications/Shortcuts.app`.
