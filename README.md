# Tuck

Keep the menu bar icons you use, and tuck the rest into one tidy dropdown. Built for macOS 27's new menu bar.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/bluejay-io/tuck/main/install.sh | bash
```

Tuck installs into `/Applications` (macOS 27 requires it) and opens a short setup:

1. Allow Tuck in **Device Control and Data Access** (Accessibility on older macOS). A small guide docks under System Settings with Tuck's icon to drag into the list.
2. Pick **Inline** or **Tucked** for each menu bar app.
3. Hold ⌘ and drag Tuck's icon to where your inline icons should end.

Run the same command again to update. Updates keep the permission because every release is signed with the same certificate.

## How it works

- **Hiding** uses macOS 27's menu bar assessment mode (`MBAssessmentModeAssertion` in the private `MenuBarClientCore` framework): while Tuck holds it, only the apps you keep inline stay on the bar. Clock, Wi-Fi, battery and Control Centre always stay. Quitting Tuck shows everything again.
- **Opening** a tucked app presses its hidden menu bar item through Accessibility, so its own menu or panel opens without the icon coming back. If that fails, Tuck shows the icon for a moment and presses it there.
- Hiding works per app: an app with two icons keeps both together. Apps outside `/Applications` can't be kept visible while hiding, and Tuck warns about them.

The hiding interface is private, so a macOS update can change it.

## Build

```sh
./scripts/bundle.sh                 # dist/Tuck.app, ad hoc signed
SIGN_IDENTITY=<sha1> SIGN_KEYCHAIN=<path> ./scripts/bundle.sh   # stable signature, as releases use
./scripts/make-icon.sh              # regenerate Resources/AppIcon.icns
```

Pushing a `v*` tag builds and signs the app on GitHub Actions and publishes `Tuck.zip`, which `install.sh` downloads.

## Uninstall

```sh
/Applications/Tuck.app/Contents/MacOS/Tuck --reset && rm -rf /Applications/Tuck.app
```
