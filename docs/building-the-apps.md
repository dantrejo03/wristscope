# Building the iPhone and watch apps

You need a Mac with Xcode for this step.

1. Copy `xcode/Config/Local.xcconfig.template` to `xcode/Config/Local.xcconfig` (git ignores it).
2. Set `DEVELOPMENT_TEAM` to your Apple Developer team ID and `BUNDLE_ID_PREFIX` to something unique to you.
   The apps become `<prefix>.Wristscope` and `<prefix>.Wristscope.watchkitapp`.
3. Open `xcode/Wristscope.xcodeproj` in Xcode and run the Wristscope scheme on your iPhone.

The project targets the latest OS releases, so it needs a current Xcode. The watch app uses
HealthKit for its workout session; if your account can't sign that capability, the build will
fail at signing.
