# Security Policy

Zic is a thin, credential-holding client for the official ZCode remote
relay. Security work follows **shift-left** principles: threat modeling at
design time, tests for every security-relevant behavior, and automated
scans before release (see CI).

## Threat model (short form)

| Asset | Threat | Mitigation |
|---|---|---|
| Pairing links (`sid`/`hash`) | Leak via backups, logs, screenshots | `allowBackup=false`; links stored only in local storage; never logged |
| Login session cookies | Theft, exfiltration | App-private JSON file in the application files directory (same protection tier as the pairing links: app sandbox + `allowBackup=false`, never in cloud backups); attached **only** to the exact captured host, **only** over TLS; never logged; login WebView navigation restricted to official Z.ai hosts (true subdomain check, no suffix spoofing). The SharedPreferences plugin and keystore-backed storage were both tried and removed — on some OEM stacks their channels never answer, which surfaced as temporary mode and a login that vanished when the process was killed. |
| Relay transport | MITM, downgrade | `wss://` only; cookie headers are never attached to plaintext sockets |
| Update path | Supply chain (foreign APK offered as an "update") | The check calls only `https://api.github.com/repos/VickyTaiziyi/Zic/releases/latest`. An asset URL is opened only when it is `https://github.com/VickyTaiziyi/Zic/releases/download/<tag>/<file>.apk`; every other URL falls back to that repository's releases page. The app never downloads or installs APKs. A dart-define pointing at another repository is ignored. |
| Device metadata | Fingerprinting/telemetry | No third-party telemetry and no Zic account. Traffic is the paired ZCode host, the official login hosts, and the pinned GitHub release API |

## Secure-by-design decisions

1. **No secrets in the repo.** CI runs a secret scan on every push; the
   relay credentials live exclusively on the phone.
2. **Credentials are host-scoped.** `SessionAuth.handshakeHeaders` refuses
   to attach cookies to any host other than the one they were captured
   from, and refuses non-TLS targets (unit-tested).
3. **Fast, actionable auth failures.** A v4 challenge without a proof key
   maps to `auth-required` (close code 4001) instead of a silent retry
   loop; the UI offers a re-login.
4. **WebView containment.** The login WebView may only navigate to
   official Z.ai properties; everything else is handed to the external
   browser.
5. **OWASP MASVS alignment** (storage: MST-STORAGE-1/2 — app-private
   file, `allowBackup=false`; network: MST-NETWORK-1/2 — TLS only,
   `usesCleartextTraffic="false"` and a network security config that
   trusts system CAs; platform: MST-PLATFORM-* — exported surface
   minimized: the widget receiver is `exported="false"`).

## Reporting a vulnerability

Please open a private security advisory on this repository
(Security → Report a vulnerability). Do not open public issues for
suspected vulnerabilities. Reports are triaged within 72 hours.
