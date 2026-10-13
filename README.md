# Class Notes

An Android app that records your university classes on your phone and turns them into study notes with Gemini. Recordings and notes are stored in your own Telegram channel.

## What it does

- **Class routine:** add your subjects and weekly class times. If a class moves, is cancelled, or there is an extra class, change **that one day** without touching the weekly routine.
- **10 PM check:** every night the app lists tomorrow's classes and asks whether any time changed. Tap **No changes** or **Update times**.
- **Class reminders:** a notification when each class starts, with a **Start recording** button.
- **Recording:** records with the phone microphone in the background (screen can be locked) and stops automatically when the class ends (+ a few minutes, configurable). A level meter warns if the mic hears nothing.
- **Telegram storage:** after class the audio, notes (`.md`) and transcript (`.txt`) are posted to your private Telegram channel by your bot. The phone copy of the audio can be deleted automatically.
- **Gemini notes:** transcript (Bangla, English or mixed) plus structured notes: summary, topics with timestamps, definitions, formulas, examples, short questions, MCQs, flashcards, revision checklist, and a "needs checking" list. Notes appear in each subject's **Notes** tab and can be edited.
- **6 PM check:** each day the app checks today's finished classes, creates any notes that are missing, and tells you about classes that were never recorded.
- **Settings:** change the Gemini API key and model, connect Telegram, and adjust the reminder times.

Everything runs on the phone. There is no server.

**👉 New here? Follow the [step-by-step guide](docs/USER_GUIDE.md):** install, Gemini key, Telegram bot and channel, permissions, routine, daily use, and troubleshooting.

## Setup (short version)

Tap-by-tap details: [docs/USER_GUIDE.md](docs/USER_GUIDE.md).


1. **Install** the APK (see *Build*) on an Android 10+ phone.
2. **Gemini:** get an API key at [Google AI Studio](https://aistudio.google.com/) → Settings → Gemini → *Add*. The app checks the key and lists the available models.
3. **Telegram:**
   1. Create a bot with [@BotFather](https://t.me/BotFather) and copy its token → Settings → Telegram → *Bot token*.
   2. Create a **private channel**, add the bot as an **admin** (with permission to post), and post any message in the channel.
   3. Settings → *Storage channel* → *Find channel* → pick your channel. The bot posts a confirmation message.
4. **Permissions:** Settings → *Permissions* → allow notifications, the microphone, and "ignore battery optimization" (so the 6 PM check and reminders run reliably).
5. **Routine:** add subjects in **Subjects**, then class times in **Routine**.

Keys and tokens are stored in Android's encrypted storage on the phone. They are never in this repository.

## Build

Requirements: Flutter 3.41+, Android SDK, JDK 17.

```bash
cd app
flutter pub get
flutter test
flutter build apk --release   # or: flutter run
```

The APK is at `app/build/app/outputs/flutter-apk/`.

`app/android/gradle.properties` points Gradle at `/usr/lib/jvm/java-17-openjdk-amd64` (Gradle 8.14 does not run on Java 25). Change or remove that line if your JDK 17 is elsewhere.

## Limits to know

- **Telegram bots** can upload files up to 50 MB and download up to 20 MB. Recordings use Opus at 24 kbps (~11 MB per hour), so a 90-minute class is about 16 MB.
- **Background work:** Android may delay the 6 PM check by a few minutes, and it waits for an internet connection. Allow "ignore battery optimization" for best results; some phone brands (Xiaomi, Oppo, Vivo, etc.) also need "autostart" enabled.
- **Recording must be started from the app or notification.** Android does not allow apps to switch on the microphone by themselves in the background.
- **AI notes can be wrong.** Check important points against your course material. Unclear audio is marked `[unclear]`, and doubtful points are listed under "Needs checking".
- Get permission before recording a class, and follow your university's rules.

## Project layout

```
app/lib/
  main.dart              startup, tabs, notification routing
  models.dart            subjects, slots, one-day changes, lectures
  schedule.dart          weekly routine + one-day changes -> classes on a date
  db.dart                local SQLite storage
  settings.dart          keys/tokens (secure storage) and preferences
  services/
    recorder.dart        microphone recording, auto-stop
    pipeline.dart        after class: Telegram upload -> transcript -> notes -> Telegram
    gemini.dart          Gemini REST client (Files API, transcription, structured notes)
    telegram.dart        Telegram Bot API client
    notifications.dart   class reminders, 10 PM check
    background.dart      6 PM missing-notes check, retries (WorkManager)
    notes_format.dart    notes JSON -> Markdown
  ui/                    screens
app/test/                unit tests
```
