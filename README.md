# Enersol Customer App

Flutter app for Enersol **customers**. Same brand system as the Angular admin
panel (`enersol-admin-fe`) — ember→amber gradient, glass surfaces, light/dark.

Staff, vendors and dealers are rejected at sign-in; they use the web panel.

## Screens

| Area | What it does |
|---|---|
| **Login** | Username + password, fingerprint sign-in, app version, SAVA credit |
| **Home** | Greeting, active project progress, generation snapshot, quick actions |
| **Application** | *My Applications* (status + milestone timeline) · *New Application* (apply for solar) |
| **Documents** | *Warranty* (panel/inverter cards) · *Other* (government + personal papers) |
| **Generation** | Live output dial, today/month/lifetime totals, 7-day bar chart, CO₂ impact |
| **Service (O&M)** | Raise a service request, follow its log/history |
| **Refer & Earn** | Referral code, loyalty points, referral list |
| **Profile** | Read-only customer details |
| **Settings** | Light/dark/system theme, font size, fingerprint toggle |

Shell: header = back (left) · logo (centre) · menu (right, opens sidebar).
Footer = 5 tabs in order **Home · Apply · Power · Docs · Service**; the app opens
on **Power**. Back appears on every tab except Home and returns there when there
is nothing to pop. The sidebar repeats all five and adds Refer & Earn, Profile,
Settings, Sign out.

Tab positions are named in `ShellTab` (`shared/widgets/app_shell.dart`) — the
drawer and Home's quick actions navigate by index, so reordering the footer
without it would silently send them to the wrong screen.

## Running

```bash
flutter pub get
flutter run
```

## Building the APK

The Gradle wrapper needs **Java 17–24**. If your default JDK is newer (e.g. 25),
point the build at 17 for the duration of the command:

```bash
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home

flutter build apk --release                  # one fat APK (~52 MB)
flutter build apk --release --split-per-abi  # per-architecture (~17–21 MB each)
```

Output lands in `build/app/outputs/flutter-apk/`. For most phones install
`app-arm64-v8a-release.apk`.

### Launcher icon

Generated from the brand bulb by `flutter_launcher_icons` (config in
`pubspec.yaml`); regenerate with `dart run flutter_launcher_icons`. The source
PNGs in `assets/icon/` were rasterised from `assets/logo/enersol-bulb.svg`.

The bulb path is drawn at ~70% opacity — it is built to sit on white (as
`enersol-logo-white-bg.svg` does) and turns muddy over a dark ground, which is
why the icon keeps a light background. The Android splash
(`res/drawable*/splash_logo.png`) uses a copy that has been flattened against
white and renormalised to full opacity, so it stays true-coloured on the dark
night-mode splash too.

> Release builds are currently signed with the **debug** key
> (`android/app/build.gradle.kts`). Add a real signing config before shipping to
> the Play Store.

## Backend

Configured in `lib/core/config/env.dart`, pointing at the same API Maker
instance as the admin panel:

- Host `https://gbs.dev.be.savaapi.com`, user path `enersol`
- Login: `POST /api/custom-api/enersol/login` → `{ens_userName_str, ens_pass_str}`
- Two tokens travel on `x-am-authorization` and `x-am-user-authorization`
- Session is persisted with `flutter_secure_storage`

## Data

Every screen reads live data, scoped to the signed-in customer. All queries live
in `lib/core/data/customer_repository.dart`.

The scoping hinges on one link: `eesl_customerUserId_obj` on the project (and
`elead_customerUserId_obj` on an application not yet converted). Staff set it
from the admin panel — **Confirm Leads → row menu → Create customer login** —
which writes a CUSTOMER-type `ens_users` row and stamps its id onto the ESL.

**Until that link exists for a customer, their screens are legitimately empty.**
That is the correct behaviour, not a bug: the app has no way to guess which
project belongs to whom.

| Screen | Reads |
|---|---|
| Applications | `ens_esls` + `ens_leads`; the timeline after "Order confirmed" comes from the real `ens_liaisings` workflow steps, so it always matches what liaising actually recorded |
| New Application | Writes an `ens_leads` row tagged `elead_leadOrigin_str: 'Customer App'` |
| Documents | `ens_customer_documents`, split by `ecd_group_str` (warranty / other). Only rows with `ecd_isPublished_bl: true` are visible — staff upload first, release later |
| Service (O&M) | `ens_service_requests`; log entries marked `log_isVisibleToCustomer_bl: false` stay internal |
| Refer & Earn | `ens_referrals` |
| Generation | ⚠️ **sample figures** — see below |

### Generation is the one exception

`ens_generation_readings` and the query against it are both finished, but nothing
populates them yet: the inverter-portal sync needs the vendor's API and
credentials. Rather than show every customer an empty chart, the screen renders a
fixed sample week and says "Work in progress" at the top.

Flip `CustomerRepository.generationIsSample` to `false` the day the sync lands —
`_liveGeneration()` is already wired. Staff can meanwhile key readings by hand in
the admin panel (Process → After Sales → Generation); those are stamped `Manual`.

## Structure

```
lib/
  core/
    api/         ApiClient — custom-api + schema CRUD, token headers
    config/      Env — backend host, user path
    data/        CustomerRepository — the single swap point for real data
    models/      AppUser/Session + customer domain models
    state/       AuthService (login, biometrics), SettingsService (theme, font)
    theme/       AppColors / AppRadius / AppTheme — ported from styles.scss
  features/      auth · home · application · documents · generation ·
                 service · referral · profile · settings
  shared/widgets/ AppHeader · AppShell (footer nav) · AppDrawer · GlassCard ·
                  GradientButton · StatusChip · AppBackdrop · PageScaffold
```

---
Developed by SAVA Info Systems Pvt. Ltd.
