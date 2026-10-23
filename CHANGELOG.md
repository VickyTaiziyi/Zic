# Changelog

## 1.0.18+19 — 2026-10-23

- Sending a message shows that message on the open conversation. The reply
  shows there too, without leaving the task and opening it again.

## 1.0.17+18 — 2026-10-23

- A reply stays on the open task. Sending a message no longer marks the
  link down or reconnects when the desktop refuses another folder.
- Documents written on the desktop open from the chat.
- The update dialog lists what changed in the release.

## 1.0.16+17 — 2026-10-22

- The task home loads every ZCode project, not only the open workspace.
  Names match the desktop sidebar. A project added on the desktop shows
  up on the phone.
- Indexed tasks stay visible while the live session index is still
  loading. Opening a task whose folder differs from the card opens that
  folder.

## 1.0.15+16 — 2026-10-22

- Update checks are pinned to `VickyTaiziyi/Zic`. A newer release prompts
  on startup; Later remembers that version. The browser opens only an
  allowlisted GitHub URL. The app still does not install APKs.
- About opens the GitHub profile, the repository, https://vicyi.com/, and
  in-app privacy, rights, and acknowledgements pages.
- The developer reserves all rights in the Zic name, mark, and this
  distribution. The MIT license and the ZLinker port stay in force.
- Acknowledgements match the real licenses. `flutter_secure_storage` is
  not listed.
- Usage stats explain the empty list. Counts stay on the phone.
- Minimum Android version is 8.0 (API 26). Cleartext traffic is off.
  The release APK is arm64-v8a only.

## 1.0.14+15 — 2026-10-22

- Local storage no longer depends on the SharedPreferences plugin. Devices
  and the ZCode login are written to an app-private JSON file, so swiping
  the app away no longer drops back to temporary mode.
- The header mark's "c" is an open ring. The previous stroke closed the
  mouth, so the letter read as a circle.

## 1.0.0+1 — 2026-10-20

Initial release.

- Zic brand: "Ink & Signal" design system (warm stone neutrals, ink
  primary, signal-orange accent), cut-stroke Z + "ic" mark, branded
  adaptive launcher icon and splash.
- v4 relay auth: official-page login captures the session cookies
  (keystore-encrypted, host-scoped, TLS-only) and attaches them to the
  native WebSocket handshake; `auth-required` failures map to a re-login
  flow. v3 proof links keep working.
- Full protocol surface ported from ZLinker (MIT): devices, task list,
  Conversation V4 chat, workflows, automations, off-peak, usage,
  model providers, desktop settings, notifications, home widget,
  deep links (`zic://device/<id>`).
- Supply-chain hardening: update checks disabled until a release
  namespace is compiled in; the app never downloads APKs.
- 308 unit/widget tests; secret-free repository (CI-enforced).
