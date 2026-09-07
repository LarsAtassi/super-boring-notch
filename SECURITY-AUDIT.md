# Security audit — upstream boring.notch

Audit of the upstream source this fork is based on, performed before adopting it.

- **Upstream:** https://github.com/TheBoredTeam/boring.notch
- **Commit audited:** `99900bf630a3d3e97fae079df2175993318d51f7` (2026-08-29)
- **Scope:** 123 Swift files, build config, entitlements, CI, all tracked binaries
- **Verdict:** No malicious code found.

Everything the code does is explained by a feature the app advertises. There is
no telemetry, no analytics SDK, no credential or keychain access, no access to
browser data, SSH keys, Contacts, or Messages, and no obfuscated or encoded
payloads. File writes stay inside the app's own container and temp dirs.

## What was checked

### Prebuilt binary framework (the highest-risk item)

`mediaremote-adapter/MediaRemoteAdapter.framework` is a committed Mach-O
universal binary — opaque source that ships in the repo. It is upstream's copy
of [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
(BSD 3-Clause, `com.vandenbe.MediaRemoteAdapter` v0.1.0), ad-hoc signed.

Static analysis of the arm64 slice:

- **101 imported symbols total.** No `URLSession`, no CFNetwork, no BSD
  sockets, no `dlopen`/`dlsym`, no Security/Keychain, no file I/O beyond
  stdout/stderr. It is not capable of network access or persistence.
- **No embedded URLs, domains, or filesystem paths** in the string table.
- **Exports** are exactly the adapter API — `adapter_get`, `adapter_stream`,
  `adapter_send`, `adapter_seek`, `adapter_shuffle`, `adapter_repeat`,
  `adapter_speed`, `adapter_test` — plus the `MRMediaRemote*` function
  pointers it resolves.
- `CFBundleCreate` + `CFBundleGetFunctionPointerForName` is how it reaches
  MediaRemote's private functions. `NSTask`/`NSPipe`/`kill`/`signal` are its
  helper-process lifecycle. Both are consistent with the documented design.

Recorded hashes (SHA-256), so any future change to these blobs is detectable:

```
91eb19837ca9f2779e476dc8e67d12bc28331dd557c87a19b0e45463c739c2fc  MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter
f177cc4a7d79ea5d70f330eac6266884527039196215738373ea813034285c2a  MediaRemoteAdapterTestClient
9ac5ed4532ad78431a85dd30e353efeca84391c4b84c760de74399c09cc2f2ca  mediaremote-adapter.pl
```

### Network endpoints

Every outbound destination in the codebase:

| Endpoint | Purpose | Data sent |
|---|---|---|
| `lrclib.net/api/search` | Lyrics lookup (no auth) | Track title + artist |
| `localhost:26538` | YouTube Music desktop companion | Local only |
| `assets9.lottiefiles.com/.../lf20_mniampqn.json` | One UI animation, fetched at runtime | Nothing |
| `TheBoredTeam.github.io/.../appcast.xml` | Sparkle update feed | Version check |
| Album art URLs | Artwork, from the media app itself | Nothing |

No unexplained hosts. `ImageService` restricts fetches to http/https and
disables cookies.

### Code execution paths

- `/usr/bin/perl` runs `mediaremote-adapter.pl` — the standard technique for
  reaching MediaRemote (Apple's signed perl carries the entitlement). The
  script is plain text, reviewed in full, and does not eval external input.
- `/usr/bin/zip` compresses shelf files for sharing.
- `dlopen` of SkyLight (window/space management), DisplayServices and
  CoreBrightness (brightness) — private Apple frameworks, expected here.
- AppleScript is only ever hardcoded `tell application "Spotify"/"Music"`
  with numeric interpolation. No user-controlled string reaches a script, so
  there is no injection path.
- **No `Run Script` build phases in the Xcode project** — building the project
  does not execute arbitrary shell.

### XPC helper

`BoringNotchXPCHelper` is unsandboxed (`app-sandbox = false`), which looks
alarming until you read it: 273 lines total, exposing only screen/keyboard
brightness get+set and an accessibility-authorization check. It needs the
sandbox off to reach DisplayServices and IOKit. Its Info.plist declares
`ServiceType = Application`, so macOS scopes it to the containing app rather
than exposing it system-wide. No network, no file writes, no exec.

### Dependencies

All twelve SPM pins are well-known projects — sindresorhus (Defaults,
KeyboardShortcuts, LaunchAtLogin), Airbnb Lottie, Sparkle, Apple
swift-collections, swift-syntax, EmergeTools Pow, siteline swiftui-introspect,
ChimeHQ AsyncXPCConnection, Lakr233 SkyLightWindow, and upstream's own
MacroVisionKit. All pinned to exact revisions in `Package.resolved`.

## Weaknesses found (not malice — fixed in this fork)

1. **Auto-updater pointed at a third party.** `SUFeedURL` targeted
   TheBoredTeam's appcast. Sparkle verifies updates against an embedded EdDSA
   key, so this is not open to hijacking — but it does mean upstream could
   replace this personal build with their own. Removed.
2. **App Transport Security fully disabled.** `NSAllowsArbitraryLoads = true`
   permitted plaintext HTTP to any host, when the only real need is
   `http://localhost`. Narrowed to a localhost-only exception.

## Trade-off accepted in this fork

`com.apple.security.cs.disable-library-validation` was **added** to the app's
entitlements. This is a deliberate loosening, so it is worth stating plainly.

Without an Apple Developer ID this build is ad-hoc signed, and so is the
vendored `MediaRemoteAdapter.framework`. Hardened-runtime library validation
requires a loaded library's Team ID to match the host process; ad-hoc
signatures carry no Team ID, so the check can never pass and the app aborts at
launch with `different Team IDs`. Re-signing the framework does not help — it
was tried first.

The alternative was to turn the hardened runtime off entirely, which is worse:
this entitlement disables only library validation and leaves the remaining
hardened-runtime protections in place. The app sandbox also stays enabled.
The practical exposure is that a process able to write into the app bundle
could get code loaded into it — but anything able to write into
`/Applications` can already replace the whole binary.

## Caveats

This is static analysis of one commit, not a proof of absence. It does not
cover the dependencies' own source, and it does not extend to future upstream
commits — re-check before merging anything from `upstream`.
