# Claude operating instructions for chukmail

## Workflow rule — MANDATORY

**After every change you make in this repo, you MUST commit and push.**

- Stage only files you intentionally changed (no `git add -A` blanket adds — avoid sweeping in build artifacts or unrelated edits).
- Write a Conventional Commits message: `feat:`, `fix:`, `refactor:`, `chore:`, `docs:`, `build:`, `test:`.
- Subject ≤ 50 characters; body only when the *why* is non-obvious.
- Push to `origin main` after each commit. Do not batch unrelated changes into one commit.
- If a pre-commit hook fails, fix the underlying issue and create a NEW commit. Never bypass with `--no-verify`.

This applies to code changes, doc changes, gradle/manifest tweaks — everything.

## Project context

chukmail is a Flutter Android email client. Goals: Material Design, IMAP/SMTP, FOSS-only (no GMS, no FCM, no Firebase), offline-first via SQLite, voice dictation in compose, multi-account, PGP support, block-remote-content toggle for HTML mail privacy.

## Architecture

- `lib/data/` — SQLite (`db.dart`), Riverpod providers, `AccountStore` (creds in `flutter_secure_storage`)
- `lib/models/` — plain DTOs (`Account`, `StoredMessage`, `FolderRow`)
- `lib/services/` — `ImapService`, `SmtpService`, `SyncService`, `NotificationService`, `PgpService`, `VoiceService`, `SettingsService`
- `lib/features/` — UI: `accounts/`, `mailbox/`, `compose/`, `settings/`
- `lib/background/workmanager_dispatcher.dart` — periodic sync entry point (15 min minimum)
- `lib/main.dart`, `lib/router.dart` — app bootstrap

DB schema lives in `db.dart` (sqflite, no codegen). Bump the `version` and add an `onUpgrade` migration when changing tables.

## Notification channels

Two Android channels, defined in `lib/services/notification_service.dart`:

- `mail_background_connection` — `Importance.min`, ongoing+silent. User can disable in system settings without losing new-mail alerts.
- `new_mail_notifications` — `Importance.high`. Should stay enabled.

When adding new notification kinds, route them to the appropriate channel — never push status/sync noise into the high-priority new-mail channel.

## No Google services

- No `firebase_*`, no `google_sign_in`, no `play-services-*`.
- Background work uses `workmanager` (AlarmManager-backed on Android), not Firebase Cloud Messaging.
- Notifications use `flutter_local_notifications` only.

If you add a dependency that pulls in GMS transitively, replace it.

## Building

```bash
flutter pub get
flutter analyze
flutter build apk --release
```

Min SDK 23 (`flutter_secure_storage` requirement). Core library desugaring is enabled for `flutter_local_notifications`.

## Code style

- Default to no comments. Only add one when *why* is non-obvious.
- Don't add error handling for impossible cases — trust internal calls.
- Prefer editing existing files. Don't create new abstractions for hypothetical needs.
- Follow `analysis_options.yaml` (extends `flutter_lints`).
