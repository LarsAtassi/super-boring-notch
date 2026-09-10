# Super Boring Notch

A personal fork of [boring.notch](https://github.com/TheBoredTeam/boring.notch)
— a macOS app that turns the MacBook notch into a media controller, calendar
peek, file shelf, and HUD replacement.

This is a personal build, published under the same licence as the original. Mostly vibe coded. Mostly.
Upstream does the hard work; this repo adds a few changes on top. It is not
affiliated with The Boring Team, and it is offered as-is — no support, no
release schedule, and no guarantee it keeps working after a macOS update.

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
| Bundle ID `com.superboringnotch` | Avoids colliding with an installed boring.notch |
| `com.apple.security.cs.disable-library-validation` | Ad-hoc signing requires it; see SECURITY-AUDIT.md |
| Album art waits before falling back to the app icon | Upstream flashed the player's logo on every track skip |
| Upstream CI, release, and community files removed | They reference secrets and an org this fork doesn't have |

See [SECURITY-AUDIT.md](SECURITY-AUDIT.md) for the review of upstream's code
that this fork is based on.

## Requirements

- macOS 14 Sonoma or later
- Designed around the MacBook notch, but it runs on a display without one —
  Settings → Layout sets the height of the closed bar in that case

## Getting started

Two ways in. Downloading a build needs nothing but the Mac you already have;
building it yourself needs Xcode.

### Download a build

Take the latest `SuperBoringNotch.zip` from
[Releases](https://github.com/LarsAtassi/super-boring-notch/releases), unzip it,
and drag `SuperBoringNotch.app` into `/Applications`.

macOS **will** refuse to open it the first time. That is expected and it is not
a sign anything is wrong — see [Running a build you didn't compile
yourself](#running-a-build-you-didnt-compile-yourself) just below for the two
clicks that get past it.

### Build it yourself

Needs **Xcode 16 or later** — the full app from the App Store, around 10GB, not
just the Command Line Tools. The first build also downloads eleven Swift
packages, so it needs a network connection; the versions are pinned in
`Package.resolved`, so everyone builds the same thing.

```bash
git clone https://github.com/LarsAtassi/super-boring-notch.git
cd super-boring-notch
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Release -derivedDataPath build build
cp -R build/Build/Products/Release/SuperBoringNotch.app /Applications/
open /Applications/SuperBoringNotch.app
```

`DEVELOPER_DIR` is set explicitly because `xcodebuild` fails outright if
`xcode-select` points at the Command Line Tools rather than Xcode;
`sudo xcode-select -s /Applications/Xcode.app` fixes that permanently.

The app lands at `build/Build/Products/Release/SuperBoringNotch.app`. The Xcode
scheme and target are still named `boringNotch` — only the product was renamed.
An app you built yourself carries no quarantine flag, so it opens without any
Gatekeeper prompt. If it somehow does object:

```bash
xattr -dr com.apple.quarantine /Applications/SuperBoringNotch.app
```

## Signing

There is no notarisation and no Developer ID. Builds are **ad-hoc signed**,
because signing properly requires a paid Apple Developer account. That is the
only reason macOS complains about a downloaded build, and it applies equally to
a zip from Releases and one sent to you directly.

### Running a build you didn't compile yourself

A `.app` that arrived over the network *is* quarantined, and because the build
is ad-hoc signed rather than notarised, double-clicking it gives you "Apple
could not verify ... free of malware". Either run the `xattr` command above, or
right-click the app → **Open** → **Open** in the dialog, which records a
one-time exception. If macOS shows no Open button at all, use System Settings →
Privacy & Security, where a recently blocked app gets an **Open Anyway** row.

If you are the one handing the app to someone else, compress it with `ditto`
rather than `zip`. The bundle contains symlinks, and `zip` follows them instead
of preserving them, which breaks the code signature on the way out:

```bash
ditto -c -k --keepParent SuperBoringNotch.app SuperBoringNotch.zip
```

## Permissions

macOS asks for each of these the first time the feature that needs it runs.
Granting is per-feature — skip what you don't use, the rest still works.

| Prompt | Needed for |
|---|---|
| Accessibility | Intercepting the volume/brightness keys to draw the HUD |
| Calendar | The calendar panel |
| Camera | The mirror panel |
| Automation (Music / Spotify) | Transport controls for those two apps |
| Audio Recording | The music visualiser |

The Audio Recording prompt is the one that surprises people. The visualiser
reacts to what is actually playing, which needs a Core Audio process tap over
system output, and macOS files that under the same permission as a microphone.
The tap is read in memory to compute an FFT and is never written to disk or
sent anywhere; the code is in
[`SystemAudioMonitor.swift`](boringNotch/managers/SystemAudioMonitor.swift).
Decline it and the visualiser falls back to its canned animation on its own.
That fallback has to be detected rather than reported: macOS still hands the
app a working tap when the grant is missing, it just zeroes every sample, so a
tap that stays silent for four seconds while something is playing is treated
as ungranted.

## Privacy

Out of the box the app makes no network requests. There is no telemetry, no
analytics, and the auto-updater is gone, so nothing phones home. Two features
reach the network only if you use them:

- **Lyrics** (Settings → Media, off by default) sends the current track title
  and artist to [LRCLIB](https://lrclib.net) to look the lyrics up. No account,
  no identifier — but it does tell a third party what you're listening to.
- **Album art** is downloaded when the media source hands over a URL instead of
  embedded artwork. Spotify and Apple Music go through MediaRemote and send the
  image data directly, so nothing is fetched for them.

Settings live in the app's own sandbox container. See
[SECURITY-AUDIT.md](SECURITY-AUDIT.md) for the full review of what the code
touches.

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
