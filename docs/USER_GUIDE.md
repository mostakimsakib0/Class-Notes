# Class Notes: Step-by-Step Guide

This guide takes you from nothing to automatic class notes. Setup takes about 15 minutes, once.

**You need:**
- An Android phone, Android 10 or newer
- A Telegram account
- A Google account (for the Gemini API key)
- Internet on the phone after classes (Wi-Fi or mobile data)

**Contents**
1. [Install the app](#1-install-the-app)
2. [Get a Gemini API key](#2-get-a-gemini-api-key)
3. [Create your Telegram bot](#3-create-your-telegram-bot)
4. [Create your storage channel](#4-create-your-storage-channel)
5. [Connect everything in the app](#5-connect-everything-in-the-app)
6. [Allow permissions (important)](#6-allow-permissions-important)
7. [Add your subjects](#7-add-your-subjects)
8. [Add your weekly routine](#8-add-your-weekly-routine)
9. [Do a 5-minute test](#9-do-a-5-minute-test)
10. [Daily use](#10-daily-use)
11. [When a class time changes](#11-when-a-class-time-changes)
12. [Reading and editing notes](#12-reading-and-editing-notes)
13. [The 6 PM check](#13-the-6-pm-check)
14. [Changing settings](#14-changing-settings)
15. [Troubleshooting](#15-troubleshooting)
16. [FAQ](#16-faq)

---

## 1. Install the app

The app is installed from an APK file. It is not on the Play Store.

1. Download the APK on your phone:
   - Open **https://github.com/mostakimsakib0/Class-Notes/releases/latest**
   - Under **Assets**, tap **`class-notes-v….apk`** to download it.
   - (Or build it yourself: see [Building from source](#building-from-source) at the end.)
2. Open the downloaded file (from the browser's downloads or your Files app).
3. Android asks to **allow installing unknown apps** from that source (Chrome or Files). Tap **Settings** → turn on **Allow from this source** → go back.
4. Tap **Install**.
5. If Play Protect warns "unsafe app", tap **More details → Install anyway**. It warns because the app is not from the Play Store.
6. Open **Class Recorder**.

**Updating:** download the newer APK from the same Releases page and install it over the old one. Your routine and notes are kept.
7. When asked, **allow notifications**.

---

## 2. Get a Gemini API key

Gemini is the AI that writes your notes. The key is free to create; the free tier has daily limits.

1. On any browser, go to **https://aistudio.google.com**.
2. Sign in with your Google account and accept the terms.
3. Click **Get API key** (left menu or top-right).
4. Click **Create API key**. If asked for a project, choose the default or **Create project**.
5. Copy the key. It starts with `AIza…`.
6. Keep it private, like a password. Don't post it in groups or screenshots.

> Tip: send the key to your own Telegram **Saved Messages** so you can paste it on the phone, then delete that message afterwards.

---

## 3. Create your Telegram bot

The bot uploads your recordings and notes to Telegram. It's your own private bot.

1. In Telegram, search for **@BotFather** (the one with the blue verified tick) and open it.
2. Tap **Start**.
3. Send `/newbot`.
4. Send a display name, for example `My Class Notes`.
5. Send a username ending in `bot`, for example `rahim_classnotes_bot`. It must be unique; if it's taken, try another.
6. BotFather replies with a **token** like `7123456789:AAH...xyz`.
7. Copy the token. Keep it private: anyone with it can control your bot.

---

## 4. Create your storage channel

All your recordings and notes are stored here, organized with hashtags like `#CSE101`.

1. In Telegram, tap the **pencil / new message** button → **New Channel**.
2. Name it, for example `Class Notes`, then tap **Next**.
3. Choose **Private Channel**, then tap **Next**. Skip adding members.
4. Open the channel → tap its name at the top → **Administrators** (or **Edit → Administrators**) → **Add Admin**.
5. Search for your bot's username (from step 3) → select it.
6. Make sure **Post Messages** is turned on → tap **Save / Done**.
7. Go back to the channel and **send any message**, for example `hello`. The app uses this message to find the channel.

---

## 5. Connect everything in the app

Open the app → **Settings** tab (bottom right).

### Gemini
1. Under **Gemini (notes)**, next to **API key**, tap **Add**.
2. Paste your key → **Save**.
3. The app checks the key. You should see **"Gemini key saved and working"**.
   - If you see "Gemini API key is invalid", copy the key again and make sure there are no spaces.
4. Optional: next to **Model**, tap **Choose** and pick a model. The default (`gemini-2.5-flash`) is a good balance of speed, quality and free-tier limits.

### Telegram
1. Under **Telegram (storage)**, next to **Bot token**, tap **Add**.
2. Paste the token → **Save**. You should see **"Connected to @yourbot"**.
3. Next to **Storage channel**, tap **Find channel**.
4. Pick your channel from the list.
   - If it says **"No channel found yet"**: check the bot is an admin with **Post Messages** (step 4.6), send another message in the channel, wait 10 seconds, and tap **Find channel** again.
5. The bot posts **"✅ Class Recorder connected…"** in your channel. Setup is done.

The orange **"Set up …"** warning on the **Today** tab disappears once both are connected.

---

## 6. Allow permissions (important)

Without these, reminders can be late and the 6 PM check may not run.

1. **Settings → Permissions → Check.** Allow each prompt:
   - **Notifications:** Allow.
   - **Microphone:** Allow (or "While using the app").
   - **Battery optimization:** Allow, i.e. let the app run in the background.
2. Some phone brands kill background apps aggressively. Also do this on your brand:

| Brand | What to turn on |
|---|---|
| **Xiaomi / Redmi / POCO** | Settings → Apps → Manage apps → Class Recorder → **Autostart: On**, **Battery saver: No restrictions** |
| **Samsung** | Settings → Battery → Background usage limits → make sure Class Recorder is **not** in "Sleeping apps"; App → Battery → **Unrestricted** |
| **Oppo / Realme / OnePlus** | Settings → Apps → Class Recorder → Battery → **Allow background activity**, and **Allow auto launch** |
| **Vivo / iQOO** | Settings → Battery → Background power consumption → Class Recorder → **Allow**; i Manager → App manager → **Autostart: On** |
| **Huawei / Honor** | Settings → Battery → App launch → Class Recorder → **Manage manually**, all three switches on |
| **Pixel / Motorola / Nokia** | Usually fine after step 1 |

More details for your exact model: https://dontkillmyapp.com

---

## 7. Add your subjects

1. Open the **Subjects** tab → tap **+**.
2. Fill in:
   - **Course code:** e.g. `CSE 2101` (shown on notifications and used as the Telegram hashtag)
   - **Name:** e.g. `Data Structures`
   - **Teacher:** optional, helps the AI with context
   - **Color:** tap one
3. Tap **Save**. Repeat for every subject.

---

## 8. Add your weekly routine

1. Open the **Routine** tab → tap **+**.
2. Choose the **Subject** and the **Day**.
3. Tap **Starts …** and pick the start time, then tap **Ends …** and pick the end time.
4. Optional: **Room**.
5. Tap **Save**.
6. Repeat for every class in your week. A subject that meets on 2–3 days needs one entry per day.

If two classes overlap, the app warns you; tap **Save anyway** only if that's really your routine.

To edit or delete a class time, tap it in the **Routine** list.

> The weekly routine is your *normal* week. Don't edit it for one-off changes; see [section 11](#11-when-a-class-time-changes).

---

## 9. Do a 5-minute test

Do this once before relying on the app in a real class.

1. **Today** tab → tap **Record now** → pick any subject.
2. Tap **Start recording** if it hasn't started already.
3. Talk normally for 2–3 minutes (read something aloud). Watch the **Microphone level** bar move.
4. Lock the phone for a minute, unlock it, and check the timer is still running.
5. Tap **Stop & make notes** → **Stop**.
6. Wait 1–3 minutes, then check:
   - A notification **"Notes ready: …"** appears.
   - Your Telegram channel has the **🎙 audio**, **📝 notes .md** and **📄 transcript .txt**.
   - **Subjects → that subject → Notes** shows the test lecture.
7. If it failed, open the lecture → **Status** tab to see the reason, and check [Troubleshooting](#15-troubleshooting).

You can delete the test lecture afterwards: open it → **⋮ → Delete**. This doesn't delete the Telegram copies; delete those in Telegram if you want.

---

## 10. Daily use

A normal day needs only **one tap per class**.

### The night before: 10 PM
You get **"Tomorrow (Sunday): 3 classes"** with the list of classes and the question **"Did any class time change?"**
- Times are the same → tap **No changes**.
- Something changed → tap **Update times** → fix it ([section 11](#11-when-a-class-time-changes)).

### When a class starts
You get **"CSE 2101 is starting"**.
1. Tap **Start recording** on the notification. The app opens and starts recording.
2. Put the phone on the desk with the **microphone facing the lecturer**, not covered, not in a pocket or bag.
3. Lock the phone if you like; recording continues. A notification shows it's recording.

If you miss the notification: open the app → **Today** → tap **Record** on the current class.

### When the class ends
Nothing to do. Recording stops on its own a few minutes after the scheduled end (5 minutes by default).
- Class ending early → open the app and tap **Stop & make notes**.
- Class running late → on the recording screen, tap **Extend 15 min**.

### After class
Automatic: the audio goes to Telegram, Gemini writes the transcript and notes, and those go to Telegram too. You get **"Notes ready: CSE 2101"**. Tap it to read.

### What the Today tab shows

| Label | Meaning |
|---|---|
| Not recorded | No recording yet for this class |
| Recording | Recording now |
| Waiting | Recorded; notes will start soon |
| Saving audio / Transcribing / Writing notes… | In progress |
| Notes ready | Done |
| Failed | Something went wrong; open it for the reason and **Try again** |

---

## 11. When a class time changes

Changes made this way affect **only that date**. Your weekly routine stays the same.

### Change a time
1. Open the day:
   - **Tomorrow:** tap **Update times** on the 10 PM notification, or **Today** tab → **Tomorrow → Change times**.
   - **Today:** **Today** tab → calendar icon (top right).
   - **Any other date:** **Routine** tab → calendar icon (top right) → pick the date.
2. On the class, tap **Change time** → pick the new start → new end → room (optional).
3. The class shows **"Changed"**, and its reminder moves to the new time.

### Cancel a class for one day
Tap **Cancel** on the class. It shows as cancelled, and no reminder is sent.

### Add an extra class
Tap **Add extra class** → subject → start → end.

### Undo a change
Tap **Restore** on the class to bring back its normal time.

When everything is right, tap **Times are correct**.

---

## 12. Reading and editing notes

1. **Subjects** tab → choose a subject → **Notes** tab. Lectures are listed newest first.
2. Tap a lecture. There are three tabs:
   - **Notes:** summary, topics with timestamps, definitions, formulas, examples, questions, MCQs with answers, flashcards, revision checklist, and **Needs checking** (things the AI wasn't sure about).
   - **Transcript:** everything said, with `[hh:mm:ss]` timestamps.
   - **Status:** what's done (audio saved, transcript, notes, saved to Telegram) and any error.
3. **Edit:** tap the ✏️ pencil → change the text (Markdown) → tap ✓ to save.
   - The edit is saved on the phone. To update Telegram too: **⋮ → Send edited notes to Telegram**.
4. **Other actions (⋮ menu):**
   - **Copy notes (Markdown):** paste into Notion, Obsidian, Google Docs, etc.
   - **Regenerate notes:** Gemini writes them again from the transcript. This replaces your edits.
   - **Delete:** removes the lecture from the phone; Telegram copies stay.

> Always check formulas, numbers and anything under **Needs checking** against your slides or textbook. AI notes can be wrong.

**Finding notes in Telegram:** open your channel → search **`#CSE_2101`** (the course code, with spaces and symbols replaced by `_`).

---

## 13. The 6 PM check

Every day around 6 PM, the app checks today's classes that have already ended:
- A recording without notes → it creates the notes now.
- A class with no recording → it tells you.

You get one of these notifications:
- **"All 3 class notes are ready"**: nothing to do.
- **"Some class notes are missing"** with details:
  - **✕ Not recorded: CSE 2101** — that class wasn't recorded. If someone else recorded it, ask them for the audio.
  - **⚠ Notes failed: …** — open the lecture → **Try again**, or check [Troubleshooting](#15-troubleshooting).

Notes:
- It may run a few minutes late, and it waits until the phone has internet.
- Classes that end after 6 PM get notes as soon as recording stops; they're not part of that day's check.
- To run the check right now: **Settings → Process missing notes now**.

---

## 14. Changing settings

All in the **Settings** tab.

| What | Where |
|---|---|
| **Change the Gemini API key** | Gemini → API key → **Change** → paste the new key → **Save** (it's checked before saving) |
| Remove the Gemini key | Gemini → **Remove API key** |
| Change the Gemini model | Gemini → Model → **Choose** → pick from the list |
| Change the bot | Telegram → Bot token → **Change** |
| Change the storage channel | Telegram → Storage channel → **Change** → post a message in the new channel first |
| Time of the "tomorrow" question (default 10:00 PM) | Reminders → **Ask about tomorrow's times at** |
| Time of the daily check (default 6:00 PM) | Reminders → **Check for missing notes at** |
| Extra recording time after class (default 5 min) | Reminders → **Keep recording after class ends** |
| Keep or delete the phone copy of audio | Phone → **Delete recordings from phone after saving to Telegram** |

**When to change the Gemini key:** you hit the free daily limit, the key stopped working, or you want to use a different Google account or a paid key.

---

## 15. Troubleshooting

| Problem | Fix |
|---|---|
| No notification at class time | Check [section 6](#6-allow-permissions-important) (battery and autostart). Make sure the class is in **Routine** for that weekday and not cancelled for the day. Open the app once; it reschedules reminders on every open. |
| No 10 PM question | It only comes when tomorrow has classes. Check battery settings ([section 6](#6-allow-permissions-important)). |
| "Microphone permission is required" | Settings → Permissions → Check, or Android Settings → Apps → Class Recorder → Permissions → Microphone → Allow. |
| Recording stopped by itself early | Your phone killed the app; set battery to **Unrestricted** ([section 6](#6-allow-permissions-important)). The partial recording is kept if usable. |
| "⚠ No sound for 2+ minutes" | The mic is covered or the room is silent. Move the phone and uncover the mic (usually at the bottom edge). |
| "Set up Gemini API key and Telegram storage" | Finish [section 5](#5-connect-everything-in-the-app). |
| "Gemini API key is invalid" | Create a new key ([section 2](#2-get-a-gemini-api-key)) → Settings → API key → **Change**. |
| "Gemini quota/rate limit reached" | The free daily limit was reached. The app retries automatically later, or change to another key or model. |
| "No internet connection" | Notes are created automatically once you're online (a background retry plus the 6 PM check). |
| "Telegram: chat not found" / "not enough rights" | The bot was removed or isn't an admin anymore. Re-add it with **Post Messages**, then Settings → Storage channel → **Change**. |
| "File is larger than 20 MB; bots cannot download it" | Only happens on a retry after the phone copy was deleted, for very long recordings. Turn off **Delete recordings from phone…** so the copy stays until notes are done. |
| "Transcript cut off" in the transcript | The lecture was very long for one Gemini response. Try a different model in Settings, then **Regenerate notes**. |
| Notes look wrong or invented | Check **Needs checking**, compare with the transcript, edit the notes, or try a stronger model and **Regenerate notes**. |
| Failed for any other reason | Open the lecture → **Status** tab to read the error → **Try again**. |

---

## 16. FAQ

**Is my data private?**
Recordings and notes are in *your* private Telegram channel. The audio and transcript are sent to Google's Gemini to make notes; read Google's terms, because the free tier may use data to improve its models. The API key and bot token are stored encrypted on your phone only.

**Do I need to keep the app open?**
No. The reminder, recording (with the screen locked) and processing work in the background. You only tap **Start recording** when the class starts, because Android doesn't let apps turn on the microphone by themselves.

**How much storage and data does it use?**
About **11 MB per hour** of class. A 90-minute class is about 16 MB uploaded to Telegram and about 16 MB to Gemini.

**Which languages work?**
Bangla, English, and mixed. Bangla is written in Bangla script; English terms, code and formulas stay in English. The notes themselves are written in English.

**What if I change phones?**
Your files are safe in Telegram. The routine and notes list on the phone are not transferred yet (backup is planned), so add the routine again on the new phone.

**Can I record a class that isn't in my routine?**
Yes: **Today → Record now** → pick the subject.

**Should I ask before recording?**
Yes. Get permission from your teacher and follow your university's rules.

---

## Building from source

For developers. Requires Flutter 3.41+, the Android SDK and JDK 17.

```bash
git clone https://github.com/mostakimsakib0/Class-Notes.git
cd Class-Notes/app
flutter pub get
flutter test
flutter build apk --release
```

The APK is at `app/build/app/outputs/flutter-apk/app-release.apk`.

To install directly with a USB cable: turn on **Developer options → USB debugging** on the phone, connect it, then run `flutter install`.

If Gradle fails with a Java version error, set the JDK 17 path in `app/android/gradle.properties` (`org.gradle.java.home=...`).
