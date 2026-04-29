<div align="center">

# Chuk Mail

**A private, FOSS-only Material Design email client for Android.**

No Google Play Services. No Firebase. No tracking. Just IMAP.

[![Platform](https://img.shields.io/badge/platform-Android-3ddc84?logo=android&logoColor=white)](#)
[![Flutter](https://img.shields.io/badge/Flutter-3.41-02569B?logo=flutter&logoColor=white)](#)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](#license)
[![FOSS](https://img.shields.io/badge/FOSS-only-success)](#-no-google-services)
[![GitHub stars](https://img.shields.io/github/stars/chuk-development/chukmail?style=social)](https://github.com/chuk-development/chukmail)

[Features](#-features) ·
[Build](#-build) ·
[Architecture](#-architecture) ·
[Permissions](#-permissions) ·
[License](#license)

</div>

---

## ✨ Features

| | |
|---|---|
| 📬 **Multi-account IMAP/SMTP** | Add as many accounts as you want — autodiscover figures out the server settings. |
| 📴 **Offline-first** | Full mailbox cached in local SQLite. Read your mail with no signal. |
| 🔄 **Background sync** | Every 15 min via WorkManager — backed by Android's `AlarmManager`, **never** Firebase. |
| 🔔 **Two notification channels** | `new_mail_notifications` (high priority) and `mail_background_connection` (silent, user-disablable). Mute the noise without losing alerts. |
| 🎨 **Material 3** | Light, dark, dynamic theming. Drawer navigation, edge-to-edge. |
| 🎙️ **Voice dictation** | Tap the mic in compose to dictate your message. On-device speech recognition. |
| 🖼️ **HTML mail with privacy guard** | Block-remote-content toggle stops trackers and external images by default. Per-account override. |
| 📎 **Attachments** | Pick, send, download, open. |
| 🔐 **OpenPGP** | Generate, import, encrypt, decrypt, sign — all local. |
| 🔑 **Encrypted credentials** | Stored in `flutter_secure_storage` (Android encrypted shared prefs). |
| ✍️ **Per-account signature** | Auto-appended on send. |

## 🚫 No Google services

Chuk Mail does not include — and refuses to depend on — any of the following:

- ❌ Google Play Services / GMS
- ❌ Firebase / FCM (push notifications work via local IMAP polling)
- ❌ Google Sign-In
- ❌ Crash analytics that phone home

That makes it a clean fit for **F-Droid**, **GrapheneOS**, **CalyxOS**, **/e/OS**, and any de-Googled Android.

## 🛠️ Stack

```
Flutter 3.41 · Dart 3.11 · Material 3
├── enough_mail               IMAP / SMTP
├── flutter_riverpod          state
├── go_router                 navigation
├── sqflite                   offline cache
├── flutter_secure_storage    credentials
├── workmanager               background sync (AlarmManager)
├── flutter_local_notifications  notifications
├── flutter_widget_from_html_core  HTML rendering
├── openpgp                   PGP
├── speech_to_text            voice dictation
├── permission_handler        runtime permissions
├── file_picker / open_filex  attachments
```

## 🏗️ Architecture

```
lib/
├── main.dart                 app entry — init notifications, schedule sync
├── router.dart               go_router routes
├── data/
│   ├── db.dart               SQLite schema (sqflite, no codegen)
│   ├── account_store.dart    accounts table + secure_storage for passwords
│   └── providers.dart        Riverpod providers
├── models/account.dart       DTOs
├── services/
│   ├── imap_service.dart     fetch, sync, flag, move, delete, append-to-Sent
│   ├── smtp_service.dart     authenticated send
│   ├── sync_service.dart     orchestrates per-account sync
│   ├── notification_service.dart   two channels (new mail / background)
│   ├── pgp_service.dart      OpenPGP wrapper
│   ├── voice_service.dart    SpeechToText wrapper
│   └── settings_service.dart key/value settings
├── features/
│   ├── accounts/             add account flow
│   ├── mailbox/              folder list + message view
│   ├── compose/              compose with voice + attachments
│   └── settings/             global + per-account settings
└── background/
    └── workmanager_dispatcher.dart   periodic sync entry point
```

## 🚀 Build

```bash
git clone git@github.com:chuk-development/chukmail.git
cd chukmail
flutter pub get
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

| Setting | Value |
|---|---|
| Min SDK | 23 (Android 6.0) |
| Target SDK | latest |
| Architecture | universal APK |
| Signing | debug key (replace in `android/app/build.gradle.kts` for production) |
| Core library desugaring | enabled |

## 🔐 Permissions

| Permission | Why |
|---|---|
| `INTERNET` | IMAP/SMTP traffic |
| `ACCESS_NETWORK_STATE` | only sync on connectivity |
| `WAKE_LOCK` | hold the radio during sync |
| `RECEIVE_BOOT_COMPLETED` | reschedule sync after reboot |
| `POST_NOTIFICATIONS` | new-mail alerts |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC` | long-running sync |
| `RECORD_AUDIO` | voice dictation in compose (only when you tap the mic) |
| storage / media | save and open attachments |

No location. No contacts. No calendar. No SMS.

## 🗺️ Roadmap

- [ ] Reply / forward shortcuts in message view
- [ ] Outbox queue with retry for offline sends
- [ ] IMAP IDLE foreground service (instant push without polling)
- [ ] PGP toggle in compose UI (engine is wired, button is missing)
- [ ] Search across cached mail
- [ ] Per-folder sync depth

## 🤝 Contributing

PRs welcome. Run `flutter analyze` before submitting. Conventional Commits enforced — see [`CLAUDE.md`](CLAUDE.md) for the full workflow.

## License

MIT — see [LICENSE](LICENSE).
