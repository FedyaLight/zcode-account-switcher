# Contributing

Keep changes small and behavior-preserving unless the issue explicitly asks for
a broader redesign.

Before opening a pull request:

```sh
swift test
xcodegen generate
xcodebuild test \
  -project ZCodeAccountSwitcher.xcodeproj \
  -scheme ZCodeAccountSwitcher \
  -destination 'platform=macOS'
```

Do not commit local account data, switch backups, `.build`, `dist`, Xcode user
state, logs, exported snapshots, or environment files.

`project.yml` is the source of truth for the Xcode project. Regenerate
`ZCodeAccountSwitcher.xcodeproj` after changing targets, resources, or build
settings.
