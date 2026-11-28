> **Status:** Beta / Personal Project
> **Notice:** Read our [Development Disclaimer & AI Philosophy](./DISCLAIMER.md) before use

# Unsync
### Privacy-first, peer-to-peer encrypted messenger for Android.

No email. No phone numbers. No servers reading your messages. Just two devices talking directly to each other — encrypted end-to-end with the Signal Protocol. Your name is a unique handle you choose.

**Current version: 0.5.0 (build 8).** Published on Google Play as Mercury (`uk.unsync.messenger`); 0.5.0 was sent to Play review on 2026-11-28 (see [the Desktop journal](https://github.com/unsyncsoftware/mercury-desktop/blob/main/BUILD_JOURNAL.md)). 18+ only.

[Releases](https://github.com/unsyncsoftware/mercury-android/releases) · [Report a Bug](https://github.com/unsyncsoftware/mercury-android/issues) · [Privacy policy](https://mercury.unsync.uk/privacy) · [Delete your account](https://mercury.unsync.uk/delete)

---

## Why Unsync?

Most messengers say they're private. Most of them have a server in the middle that *could* read your messages, sell your metadata, or hand it over when asked. Unsync removes that server from the equation entirely. Your device connects directly to your contact's device — no middleman, no logs, no data.

---

## Features

| | |
|---|---|
| 🔐 **Signal Protocol E2EE** | Double Ratchet encryption — same as WhatsApp, but open |
| 📡 **True P2P via WebRTC** | Direct device-to-device — no messages touch a server |
| 📦 **Async store-and-forward** | Messages held encrypted and delivered when recipient is back online |
| 📞 **Encrypted voice calls** | WebRTC audio, fully encrypted |
| 🔔 **FCM wake-up** | Notifications even when the app is killed |
| 👁 **Biometric lock** | Fingerprint / face auth on open |
| 🔗 **On-demand connections** | Connects only when sending, auto-closes after 2 min idle |
| 🕸 **Multi-device mesh** | Each device connects independently — scales to any number of contacts |
| 🗣 **Community forum** | Native forum.site feed, categories, posts, replies, pictures, emoji and public avatars |
| 🆔 **Handle, not an account** | No phone number or email — identity is a cryptographic key pair, and your only name is a unique handle (held 90 days after you leave) |
| 💾 **Encrypted backup** | Passphrase-protected `.mercurybackup` to a folder you choose (Settings → Account backup) |
| 🗑 **Delete account** | Settings → Delete account: remove Mercury from this phone, or delete your account everywhere |

---

## Community forum

The Contacts screen opens the native `forum.site` community feed through Mercury Relay. It supports category filtering, posts, replies, emoji insertion, feature-gated pictures, and public profile avatars. Since 0.5.0 it also has edit/delete of your own posts (when the forum supports it), report, a members list, Community direct messages, and **Block** (this device only). Joining shows the community rules and an 18+ confirmation. The shared Community code is identical to Mercury Desktop's: keep them in step. The forum key is stored in Android secure storage using the same `mercury_forum_key_v1` format as Mercury Desktop; import/export lets one forum identity move between devices.

When the forum advertises Axon handle registration, **Join with Axon handle** opens the Axon browser. Complete its signed registration on `forum.site`, copy the forum key from the forum account, return to Mercury, and choose **Use key from another device**. Axon signs the handle proof; its private key is not transferred to Mercury.


Mercury also sends the chosen Android display name to the private UnSync owner dashboard during signed signaling authentication. This labels the device in the dashboard’s Mercury section; it is separate from both a forum.site account and a public mesh handle. Older app versions do not include the name.

## Architecture

\`\`\`
Device A <──WebRTC P2P──> Device B
    |                          |
Signaling Server (WebSocket)   |
    |                          |
Relay Server (offline fallback)/
\`\`\`

- **Signaling server** — WebSocket server for WebRTC negotiation and peer discovery only. Never sees message content.
- **Relay server** — Stores encrypted blobs for offline delivery. Cannot read content.
- **P2P connection** — Created on demand, auto-closed after 2 min idle.
- **Signal Protocol** — Double Ratchet E2EE, pre-key bundles, persistent sessions.

---

## Getting Started

### Prerequisites
- Flutter 3.x
- Firebase project (for FCM push notifications)
- A running signaling server from the separate [`unsyncsoftware/unsync-network`](https://github.com/unsyncsoftware/unsync-network) repository
- A running relay server — see `/server/relay/`

### Configuration

1. Copy `android/app/google-services.json.example` to `android/app/google-services.json` and fill in your Firebase details.

2. Edit `lib/config.dart`:
\`\`\`dart
class UnsyncConfig {
  static const String signalingUrl = 'wss://signal.unsync.uk';
  static const String relayUrl = 'ws://YOUR_SERVER:5000';
}
\`\`\`

3. Build and run:
\`\`\`bash
flutter pub get
flutter run
\`\`\`

### Server Setup

Mercury is a client-only repository and does not contain the production signaling server. For local signaling development, run the separate `unsync-signaling` checkout independently:
\`\`\`bash
cd C:\dev\unsync-signaling
npm install
node server.js
\`\`\`

Production signaling is maintained in `unsyncsoftware/unsync-network` and deployed at `/root/signaling/server.js` on the VPS. Do not copy `server.js` back into Mercury.

The relay server, if used locally, is still managed separately:
\`\`\`bash
cd server/relay && npm install && pm2 start relay.js --name unsync-relay
\`\`\`

---

## Releasing to Google Play

- Bump `version:` in `pubspec.yaml` (`0.5.0+8`: the number after `+` is the versionCode and must increase).
- Create `android/key.properties` pointing at the upload keystore (`unsync-release.jks`, alias `unsync`). Both it and `*.jks` are git-ignored: never commit them, and move the keystore between PCs by USB only. The upload certificate SHA-1 must match Play Console → Protected with Play → App signing.
- Build with `flutter build appbundle --release`, and upload the `.aab` to a new release in Play Console.

---

## Security Model

- Messages are encrypted on-device before transmission — the signaling server only sees peer IDs and WebRTC metadata
- The relay server stores encrypted blobs only — keys never leave the device
- No central identity store — your identity is a key pair generated locally on first launch
- Open source — audit it yourself

---

## Roadmap

- [ ] Mesh-Mail — decentralized email layer on the P2P backbone
- [ ] Unsync Vault — encrypted file sharing
- [ ] Mirror Station — always-on home relay node (tablet/homelab)
- [x] Play Store public release (0.4.0 live; 0.5.0 in review)

---

## License

GPL v3 — see [LICENSE](LICENSE)

---

## Built by

[Unsync Software](https://unsyncsoftware.com) — solo indie developer, Antipolo, Philippines.
Built with AI. Architected by a human. Tested on real devices.
