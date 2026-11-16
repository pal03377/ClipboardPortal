# App Store release

Requires Xcode, Ruby/Bundler, and Mac App Store signing identities.

```sh
bundle install
bundle exec fastlane mac archive
bundle exec fastlane mac upload
bundle exec fastlane mac submit
```

`bundle exec fastlane mac release` runs all three steps. Submission enables automatic release after Apple approves the update.

The marketing version and build number are set explicitly in the Xcode project. Update `app_version` and `build_number` in the `submit` lane to match before each release. Archiving does not increment the build number.

Release notes live in `fastlane/metadata/<locale>/release_notes.txt`. The current App Store listing has only `en-US`. Keep notes for every configured localization when adding languages.

## Credentials and signing

Provide an App Store Connect API key JSON at `fastlane/api_key.json` (ignored by Git), or set `ASC_API_KEY_PATH` to an absolute path. The JSON uses Fastlane's `key_id`, `issuer_id`, `key` (PEM content), and `in_house` fields. Never commit credentials.

On a new Mac, run `bundle exec fastlane mac setup_signing` once to install Mac App Store application and installer certificates and a matching provisioning profile. This creates a dedicated release keychain, a random local password, and signing material in the ignored `build/signing` directory. The upload uses that profile explicitly, so it does not require cloud-managed certificate access. The release keychain is unlocked by the upload lane; no login-keychain password is required. Preserve this directory securely for future releases.

The signed universal archive is stored at `build/ClipboardPortal.xcarchive`, with build logs and symbols under `build/`. `upload` reuses this archive and sends it through Xcode's App Store export; it does not rebuild or change its version. `submit` uploads the release notes, selects the processed build, and submits it for review. Apple's processing and review must complete before distribution.

The age-rating config fills the required Social Media fields with `false`; this app provides private clipboard transfers. Existing messaging/chat and user-generated-content declarations are retained.

The export-compliance submission marks the build as not using non-exempt encryption: the app uses Apple's standard CryptoKit algorithms.
