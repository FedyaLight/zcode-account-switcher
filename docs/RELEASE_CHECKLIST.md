# Release Checklist

This project can produce a local DMG, but it is not notarized unless a Developer
ID certificate and notarization credentials are configured outside the repo.

1. Make sure the tree does not contain local data:

   ```sh
   find . -maxdepth 4 \( -name accounts -o -name .last -o -name .build -o -name dist -o -name xcuserdata \) -print
   rg -n "/Users/|ZCODE_CREDENTIAL_SECRET|BEGIN .*PRIVATE|PASSWORD|TOKEN" .
   ```

2. Run tests:

   ```sh
   swift test
   xcodegen generate
   xcodebuild test \
     -project ZCodeAccountSwitcher.xcodeproj \
     -scheme ZCodeAccountSwitcher \
     -destination 'platform=macOS'
   ```

3. Build the DMG:

   ```sh
   ./script/package_release.sh
   ```

   The DMG should open as a plain Finder window with three items:

   - `ZCode Account Switcher.app`
   - `Applications`
   - `Run to Remove Quarantine.command`

4. Verify the output:

   ```sh
   hdiutil verify dist/ZCodeAccountSwitcher-*.dmg
   shasum -a 256 dist/ZCodeAccountSwitcher-*.dmg
   ```

5. Upload the `.dmg` and `.sha256` file to the GitHub release.

For non-notarized builds, include this install note in the release body:

```sh
xattr -dr com.apple.quarantine "/Applications/ZCode Account Switcher.app"
open "/Applications/ZCode Account Switcher.app"
```

Only recommend that command for users who trust the release source.
