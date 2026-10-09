# <img src="assets/images/logo.png" width="40" height="40" alt="" style="vertical-align: middle;" /> Omnya

A peptide and injection protocol tracker for women, built with Flutter for iOS and Android.

Most trackers only record what went in. Omnya also shows what came out: weight against her cycle, weekly photos side by side, and plain-English notes drawn from her own logs. It is designed to feel like a wellness app, not a lab tool.

## What the app does

- **Today**: the next dose due, logged in one tap with an undo. A daily check-in for energy and appetite, with optional weight (typed or from Apple Health), waist, sleep, pain, side effects, skin notes and period start. One short note drawn from her own data, such as a vial running out or likely water weight before a period.
- **Progress**: her first and latest weekly photos in a before and after slider, the first photo of each month side by side, a "toned, not frail" score from her protein target and weekly strength check-in, a weight chart that shades the week before each logged period, what changed since each compound started (from day 14), a weekly read of her photos measured on the phone, and a weekly report. A 9:16 progress card she can share, with an optional photo that has faces blurred.
- **Stack**: each compound with its dose and unit, route, half-life, dose steps, schedule, a body map of injection sites with how long each has rested, mixed-vial expiry, doses left, runout day and monthly cost. A mixing calculator converts vial strength into syringe units.
- **Circle**: an invite-only group of up to 5 people who see each other's dose consistency and nothing else.
- **Reminders**: local notifications on dose days, before a runout, when a mixed vial expires, a Sunday photo prompt and the weekly report. Nothing goes through a server.
- **Widgets**: next dose, days on protocol and runout on the home and lock screen, plus a Live Activity on shot day.
- **Settings**: Face ID lock, a doctor report PDF of the last 90 days, and import from a Shotsy CSV export.
- **Pro**: RevenueCat subscriptions (monthly, yearly with a trial, lifetime). Free users get up to 2 compounds, the calculator, check-ins, the widget, a watermarked progress card and the weekly report headline. The outcome engine, weekly photo read, cycle-aware insights, full weekly report, doctor PDF, monthly spend and Circles are Pro, shown blurred with a tap to the plans.
- **Milestones**: a full-screen moment on the first dose, day 30 and day 90. Day 30 and day 90 show her own 90-day goal back to her.

She enters every compound, dose and schedule herself. The app never suggests a dose.

## How it is built

- **App**: Flutter 3.44 and Dart 3.12, with Provider for state. The phone is the source of truth: everything works offline and backs up when a connection is available.
- **Backend**: Supabase only. Each install signs in anonymously, and row level security in `supabase/schema.sql` limits every row to its owner. There is no custom server.
- **Photos**: weekly photos are saved in the app's private storage on the phone and are never uploaded. Face measurements and blurring use Apple's Vision framework on the phone.
- **iOS native**: `ios/Runner/AppDelegate.swift` holds the Health, Vision and widget channel. `ios/OmnyaWidget` is the widget and Live Activity extension.

```text
lib/
  core/          theme, shared widgets, copy, compound names
  data/          models, local storage, Supabase client, repository
  domain/        schedule math, insights, mixing calculator
  ui/            screens
tool/            regenerates the tab bar icons from Hugeicons
test/            unit and widget tests
integration_test/
supabase/        database schema and access rules
assets/          fonts (Fraunces, Instrument Sans) and logo
```

## Setup

1. Install Flutter 3.44 or newer, then run `flutter pub get`.
2. In the Supabase dashboard, turn on anonymous sign-ins under Authentication > Sign In / Providers.
3. Run `supabase/schema.sql` once in the SQL editor. It resets the app tables, so run it again only before launch.
4. Run the app with `flutter run`.

The Supabase URL and publishable key are passed as Dart compile-time defines. The publishable key is meant to ship inside apps; access is enforced by the database rules.

## Building for release

- **Android**: add `android/key.properties` with `storeFile`, `storePassword`, `keyAlias` and `keyPassword`, then pass the Supabase values to the release build:

  ```bash
  flutter build apk --release \
    --dart-define=SUPABASE_URL=https://your-project.supabase.co \
    --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_... \
    --dart-define=REVENUECAT_APPLE_API_KEY=appl_...
  ```

  Without `REVENUECAT_APPLE_API_KEY`, purchases are off and the paywall says plans couldn't load.

  Use the same `--dart-define` flags with `flutter build appbundle` for a Play Store bundle. Without `key.properties`, release builds are signed with the debug key, which the Play Store rejects. Builds include arm64 only.
- **iOS**: set your team in Xcode. In the Apple Developer portal, turn on HealthKit and App Groups (`group.com.omnya.omnya`) for `com.omnya.omnya`, and App Groups for `com.omnya.omnya.OmnyaWidget`. Then run `flutter build ipa` with the same `--dart-define` flags. In App Store Connect, create the monthly and yearly subscriptions (7-day free trial on yearly) and the lifetime non-consumable. In RevenueCat, attach them to the `pro` entitlement and to the current offering's monthly, annual and lifetime packages. The app is iPhone only, in portrait.

## Checks

```bash
flutter analyze
flutter test
flutter test integration_test -d <device id>
```

The integration test uses an in-memory backend, so it never writes to the live database.

## Data and privacy

- **Stays on the phone**: weekly photos, photo measurements, reminder settings and the Face ID lock.
- **Backed up to Supabase**: onboarding answers, compounds, dose logs and check-ins, including weight. Settings > Delete my data removes them from the phone and the backup.
- **Shared with a circle**: display name, the last time she logged a dose, and doses logged against doses planned this week.

## App Store rules followed

These come from the product spec:

- No vendor links or sourcing content.
- The calculator is framed as unit math and carries a disclaimer.
- Insights describe her own data and never recommend a dose.
- Onboarding shows a medical disclaimer.
- The paywall shows App Store prices only, offers the trial only to people eligible for it, has Restore, and links to the terms and privacy policy.
- `ios/Runner/PrivacyInfo.xcprivacy` and `ios/OmnyaWidget/PrivacyInfo.xcprivacy` declare the data backed up and the UserDefaults reasons.
