# chukmail

Material Design IMAP email client for Android. FOSS, no Google Play Services, no Firebase.

## Features

- Multiple IMAP/SMTP accounts with autodiscover
- Offline mailbox stored in local SQLite (sqflite)
- Background sync every 15 min via WorkManager (uses AlarmManager — no GMS)
- Local notifications for new mail (no FCM)
  - Two notification channels: `new_mail_notifications` (high) and `mail_background_connection` (min, user-disablable)
- Material 3 UI with light/dark theme
- Compose with voice dictation (`speech_to_text`)
- HTML mail rendering with **block-remote-content** toggle (default on, per-account override)
- Attachments: pick, send, view, open
- PGP: keypair generation, import, encrypt, decrypt, sign (`openpgp`)
- Credentials in `flutter_secure_storage` (encrypted shared prefs)
- Per-account signature

## Stack

- Flutter 3.41 / Dart 3.11
- `enough_mail` for IMAP/SMTP
- `flutter_riverpod`, `go_router`
- `sqflite`, `flutter_secure_storage`
- `workmanager`, `flutter_local_notifications`
- `flutter_widget_from_html_core`
- `openpgp`, `speech_to_text`, `permission_handler`
- `file_picker`, `open_filex`, `share_plus`

## Build

```bash
flutter pub get
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Min SDK 23, target latest. Signed with debug key — replace `signingConfig` in `android/app/build.gradle.kts` for production releases.

## Permissions

`INTERNET`, `ACCESS_NETWORK_STATE`, `WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED`, `POST_NOTIFICATIONS`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `RECORD_AUDIO`, storage (legacy + media).

## License

MIT
