# Class Notes

[![Release](https://img.shields.io/github/v/release/mostakimsakib0/Class-Notes?include_prereleases&label=download)](https://github.com/mostakimsakib0/Class-Notes/releases)
![Android 10+](https://img.shields.io/badge/Android-10%2B-3DDC84?logo=android&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-3.41-02569B?logo=flutter&logoColor=white)

**Record your university classes on your phone and get study notes automatically.**
Gemini writes the transcript and notes, and everything is saved in your own private Telegram channel. No server, no subscription.

<p>
  <a href="https://github.com/mostakimsakib0/Class-Notes/releases"><b>⬇️ Download the APK</b></a> ·
  <a href="docs/USER_GUIDE.md"><b>📖 Step-by-step guide</b></a> ·
  <a href="#troubleshooting"><b>🛠 Troubleshooting</b></a>
</p>

> **Status: v1.0.0 pre-release.** It builds and the unit tests pass, but it hasn't been tested on many phones yet.
> Do the [5-minute test](docs/USER_GUIDE.md#9-do-a-5-minute-test) before relying on it in a real class.

---

## How it works

```
 10 PM          "Tomorrow: 3 classes. Did any time change?"   →  No changes / Update times
 Class starts   "CSE 2101 is starting"                          →  tap Start recording
 During class   records with the screen locked                  →  stops by itself after class
 After class    audio → Telegram → Gemini transcript + notes → Telegram   →  "Notes ready"
 6 PM           checks for missing notes, creates them, flags classes that weren't recorded
```

Your part: **one tap per class**, plus answering the 10 PM question.

## Features

| | |
|---|---|
| 📅 **Routine** | Subjects and weekly class times. Change, cancel or add a class for **one day only**; the weekly routine stays the same. Overlap warnings. |
| 🌙 **10 PM check** | Lists tomorrow's classes and asks whether any time changed. **No changes** or **Update times**, right from the notification. |
| ⏰ **Class reminders** | A notification at the start of each class with a **Start recording** button. |
| 🎙 **Recording** | Phone microphone, keeps going with the screen locked, auto-stops a few minutes after class (adjustable), **Extend 15 min** button, warning if the mic hears nothing. |
| ☁️ **Telegram storage** | Audio (`.ogg`), notes (`.md`) and transcript (`.txt`) posted to your private channel, tagged by subject (e.g. `#CSE_2101`). The phone copy can be deleted automatically. |
| ✨ **Gemini notes** | Bangla, English or mixed lectures. Summary, topics with timestamps, definitions, formulas, examples, short questions, MCQs with answers, flashcards, revision checklist, and a **Needs checking** list. |
| 📚 **Notes per subject** | Each subject has a **Notes** tab. Read, edit, copy as Markdown, regenerate, or re-send to Telegram. |
| ✅ **6 PM check** | Creates notes that are missing and reports classes that weren't recorded. |
| ⚙️ **Settings** | Change the Gemini API key and model, connect Telegram, and set the reminder times. |

## Get started

You need an Android 10+ phone, a Telegram account, and a Google account. Setup takes about 15 minutes, once.

1. **Install:** download `class-notes-v….apk` from [Releases](https://github.com/mostakimsakib0/Class-Notes/releases) and open it on your phone.
2. **Gemini key:** [Google AI Studio](https://aistudio.google.com/) → *Get API key* → *Create API key*. In the app: **Settings → API key → Add**.
3. **Telegram bot:** [@BotFather](https://t.me/BotFather) → `/newbot` → copy the token. In the app: **Settings → Bot token → Add**.
4. **Storage channel:** create a **private channel**, add your bot as an **admin** who can post, and send any message there. In the app: **Settings → Storage channel → Find channel**.
5. **Permissions:** **Settings → Permissions → Check**, and allow everything. On Xiaomi, Oppo, Vivo and similar phones, also turn on *Autostart* ([how to](docs/USER_GUIDE.md#6-allow-permissions-important)).
6. **Routine:** add subjects in **Subjects**, then class times in **Routine**.
7. **Test:** **Today → Record now**, talk for 2 minutes, then stop. Notes should appear within a few minutes.

Every step in detail, tap by tap: **[docs/USER_GUIDE.md](docs/USER_GUIDE.md)**.

## Privacy

- Recordings and notes are stored in **your** private Telegram channel and on your phone. Nothing goes to the developer.
- Audio and transcripts are sent to **Google Gemini** to make the notes. On the free tier, Google may use this data to improve its products; see [Gemini API terms](https://ai.google.dev/gemini-api/terms).
- Your Gemini key and bot token are stored in Android's encrypted storage on the phone. They are never in this repository.
- **Ask permission before recording** a class, and follow your university's rules.

## Limits

- **Starting a recording needs one tap.** Android doesn't allow apps to turn on the microphone by themselves.
- **Telegram bots** upload up to 50 MB and download up to 20 MB. Recordings are about **11 MB per hour**, so a 90-minute class is about 16 MB.
- **Background tasks** can be delayed by a few minutes, and the 6 PM check waits for internet. Battery savers on some brands can stop them unless allowed.
- **AI notes can be wrong.** Unclear audio is marked `[unclear]`, and doubtful points go under **Needs checking**. Verify against your course material.
- The routine and notes list live on the phone. Moving to a new phone means re-adding the routine (Telegram files are kept). Backup is planned.

## Troubleshooting

| Problem | Fix |
|---|---|
| No reminder at class time | Allow battery/autostart ([guide §6](docs/USER_GUIDE.md#6-allow-permissions-important)); open the app once to reschedule reminders. |
| "Set up Gemini API key and Telegram storage" | Finish the steps in **Settings**. |
| "Gemini API key is invalid" / quota reached | **Settings → API key → Change** to a new key, or wait; quota errors retry automatically. |
| "No channel found yet" | Make the bot an admin with **Post Messages**, send a message in the channel, and try again. |
| Recording stopped early | Set the app's battery usage to **Unrestricted**. |
| Notes failed | Open the lecture → **Status** tab for the reason → **Try again**. |

More fixes in the [guide's troubleshooting section](docs/USER_GUIDE.md#15-troubleshooting).

## Roadmap

- [ ] Test on more phones; fix what comes up
- [ ] Split very long lectures for transcription
- [ ] Search across notes and transcripts
- [ ] PDF export (with Bangla support)
- [ ] Back up the routine and notes to Telegram, and restore on a new phone
- [ ] Import the routine from CSV

---

## For developers

**Stack:** Flutter (Dart), SQLite (`sqflite`), `record` (foreground mic service), `flutter_local_notifications`, `workmanager`, `flutter_secure_storage`, Gemini REST API, Telegram Bot API.

### Build

Requirements: Flutter 3.41+, Android SDK, **JDK 17**.

```bash
git clone https://github.com/mostakimsakib0/Class-Notes.git
cd Class-Notes/app
flutter pub get
flutter test
flutter build apk --release   # or: flutter run
```

The APK is written to `app/build/app/outputs/flutter-apk/`.

- **Java:** `app/android/gradle.properties` sets `org.gradle.java.home=/usr/lib/jvm/java-17-openjdk-amd64` because Gradle 8.14 doesn't run on Java 25. Change or remove that line to match your machine.
- **Signing:** release builds use the key in `app/android/key.properties` (gitignored). Without it they fall back to the debug key. Such an APK can't be installed as an update over an official release; uninstall first.

### Project layout

```
app/lib/
  main.dart              startup, tabs, notification routing
  models.dart            subjects, slots, one-day changes, lectures
  schedule.dart          weekly routine + one-day changes → classes on a date
  db.dart                local SQLite storage
  settings.dart          keys/tokens (secure storage) and preferences
  services/
    recorder.dart        microphone recording, auto-stop, crash recovery
    pipeline.dart        after class: Telegram upload → transcript → notes → Telegram
    gemini.dart          Gemini REST client (Files API, transcription, structured notes)
    telegram.dart        Telegram Bot API client
    notifications.dart   class reminders, 10 PM check
    background.dart      6 PM missing-notes check, retries (WorkManager)
    notes_format.dart    notes JSON → Markdown
  ui/                    screens (today, routine, day editor, subjects, lecture, recording, settings)
app/test/                unit tests
docs/USER_GUIDE.md       end-user guide
```

### How processing stays reliable

Each step after class (save audio → transcribe → write notes → save notes) is skipped if it's already done, so a retry continues where it stopped. A lock in the database stops the app and the background check from processing the same lecture at the same time. Quota and network errors schedule a background retry for when the phone is back online.
