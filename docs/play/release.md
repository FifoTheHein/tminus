# Releasing T-Minus

How a release build of T-Minus is versioned, signed, checked and uploaded to Google Play. The store listing is in [listing.md](listing.md), and the answers for Play Console's forms are in [declarations.md](declarations.md).

The first release goes to the internal testing track. A later release changes the version (below) and repeats the same steps.

## Versioning

`pubspec.yaml` holds the version as `<name>+<code>`, for example `1.0.0+1`. Flutter passes the name to Android as `versionName` and the code as `versionCode`.

- **The build number** (the part after `+`) goes up by one for every upload to any Play track, internal testing included. Play refuses a version code that an earlier upload already used. The first upload is `1.0.0+1`.
- **The version name** follows semver: `MAJOR.MINOR.PATCH`. A fix raises the patch number and a new feature raises the minor number. Several uploads can share one name, because only the build number has to change.
- Edit `pubspec.yaml` in the commit that prepares the release, and build from that commit. Do not set the version with `--build-name` or `--build-number` for a release: the repository should say what was uploaded.

## The upload key

Google Play signs the app that people install with an app signing key that Google holds (Play App Signing, accepted on the first upload). The key we hold is the **upload key**. It signs each bundle we upload, so Play can tell that the upload is ours.

**The keystore** is a `.jks` file kept outside the repository, for example under `%USERPROFILE%\keys\`. It is created once, in PowerShell:

```powershell
keytool -genkey -v -keystore $env:USERPROFILE\keys\<name>.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

keytool asks for the passwords. **Back up the keystore and both passwords**: a password manager for the passwords, and a copy of the file in a second place that is not this machine. The repository holds none of them, so a lost machine would lose the key.

**`android/key.properties`** tells Gradle where the keystore is. It is git-ignored and written by hand:

```properties
storeFile=C:\\Users\\<you>\\keys\\<name>.jks
storePassword=<the store password>
keyAlias=upload
keyPassword=<the key password>
```

Use an absolute path and double each backslash, because a Java properties file reads a single one as an escape. A relative `storeFile` resolves against `android/app/`, not against `android/`, so an absolute path is the safe choice. All four entries are needed. If the file exists and one is missing, Gradle stops and names the missing entries. Only the names are printed, never a value.

Gradle reads the file as ISO-8859-1. Save it as plain ASCII, or as UTF-8 without a byte-order mark: a BOM makes `storeFile` look missing, and the build stops. A password with non-ASCII characters is read garbled and will not match the keystore's, so use ASCII characters in both passwords.

**Without `android/key.properties`**, a release build is signed with the debug key. Gradle prints a warning when a release is asked for, but do not rely on seeing it: check the signature (below). Play refuses a debug-signed bundle, so this mistake cannot ship. Debug builds and the unit tests do not need the file.

**Nothing from this section goes into git.** `android/.gitignore` ignores `key.properties`, `*.keystore`, `*.jks` and `*.p12`, and `test/no_signing_material_test.dart` fails if git tracks any of them.

### If the upload key is lost or leaked

Users are not affected, because the app signing key is Google's and it has not changed. In Play Console, open App integrity, then App signing, and request an upload key reset. Create a new keystore as above and give Play its certificate when it asks. Wait for Google to confirm the reset before the new key signs an upload.

Request the same reset if the keystore and its password may have been exposed, for example if either was pushed to a public repository. That way a copy of the old key stops being valid.

## Build

From the repository root, with `android/key.properties` in place:

```bash
flutter pub get
flutter build appbundle --release    # build/app/outputs/bundle/release/app-release.aab
flutter build apk --release          # build/app/outputs/flutter-apk/app-release.apk
```

Play takes the bundle. The APK is the same build, for `adb install`, an emulator test and the checks below.

- R8 shrinks the Kotlin and Java code in a release build (Flutter's default), and the bundle carries R8's mapping file, so Play can read the stack traces of Java and Kotlin crashes. If a release ever needs an R8 keep rule, it goes in `android/app/proguard-rules.pro`, which Flutter's Gradle plugin reads when the file exists.
- The bundle also carries native debug symbols (`ndk.debugSymbolLevel` is `SYMBOL_TABLE` in `android/app/build.gradle.kts`), so Play can read native crashes.
- The Dart code is not obfuscated. It holds no secrets, and readable stack traces matter more.

## Check the build before uploading

The commands below run in Git Bash from the repository root, and they use `$ANDROID_HOME`, the Android SDK folder. If Git Bash does not have it set, run this one line first. It reads `sdk.dir` from `android/local.properties`:

```bash
[ -n "$ANDROID_HOME" ] || ANDROID_HOME=$(sed -n 's/^sdk\.dir=//p' android/local.properties | tr -d '\r' | sed 's/\\\\/\//g; s/\\:/:/')
```

**1. The signature.** The bundle must be signed with the upload key, not the debug key:

```bash
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
"$ANDROID_HOME/build-tools/36.0.0/apksigner.bat" verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

Git Bash can run `apksigner.bat` directly, with no `cmd /c` in front. Both commands print the upload certificate. If either shows `CN=Android Debug`, `android/key.properties` was missing or was not read: Play will refuse the bundle. Once the app exists in Play Console, App integrity, then App signing, shows the upload key certificate's fingerprints to compare with.

**2. What is in the release.** The privacy policy and the Play declarations are true only while this holds. Run it on the release APK, in Git Bash:

```bash
APK=build/app/outputs/flutter-apk/app-release.apk
"$ANDROID_HOME/build-tools/36.0.0/aapt2.exe" dump permissions "$APK"
"$ANDROID_HOME/build-tools/36.0.0/aapt2.exe" dump xmltree --file AndroidManifest.xml "$APK" | grep -n "foregroundServiceType\|AD_ID"
grep -n "firebase\|crashlytics\|analytics\|ads" pubspec.lock
```

- The permissions are exactly the ones in the Manifest reference table of [declarations.md](declarations.md). Libraries add two of them: `ACCESS_NETWORK_STATE` (WorkManager) and `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`, a signature-level permission named after the app. Any other permission needs a reason, and an entry in that table, before the upload.
- No `com.google.android.gms.permission.AD_ID` appears: the policy says the app has no advertising id.
- Only one `foregroundServiceType` appears, `0x00000400` (`systemExempted`), which is `RingingService`.
- `pubspec.lock` has no analytics, advertising or crash-reporting package, so the last command prints nothing.
- The merged manifest is also under `build/app/intermediates/merged_manifests/release/`. Any exported component that is new needs a reason written down before the upload.

**3. 16 KB pages.** Play requires 16 KB page support for new apps and for updates that target Android 15 or later, so the native libraries must run on devices with 16 KB memory pages. Check the current date for this in Play Console's help. A library qualifies when every `LOAD` segment in its ELF headers is aligned to at least `0x4000`, and an uncompressed library in an APK must also be zip-aligned to 16 KB. Nothing needs bundletool: the check reads the libraries straight out of the APK and the bundle. It needs two tools that the Android SDK already holds:

- `zipalign` from build-tools **35.0.0 or later**. Older versions have no `-P` option.
- `llvm-readelf` from the NDK that the build uses. That is Flutter's `ndkVersion` (`28.2.13676358` for Flutter 3.47, the version this was written with), and the tool is under `$ANDROID_HOME/ndk/<version>/toolchains/llvm/prebuilt/windows-x86_64/bin/`.

In Git Bash, from the repository root, with the scratch files kept outside the repository:

```bash
ZIPALIGN="$ANDROID_HOME/build-tools/36.0.0/zipalign.exe"
READELF="$ANDROID_HOME/ndk/<version>/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-readelf.exe"
APK=build/app/outputs/flutter-apk/app-release.apk
AAB=build/app/outputs/bundle/release/app-release.aab
S=$(mktemp -d)

# The APK: zip alignment, then each arm64 library.
"$ZIPALIGN" -c -P 16 -v 4 "$APK" | tail -3
for so in $(unzip -l "$APK" | awk '/lib\/arm64-v8a\/.*\.so$/{print $4}'); do
  unzip -p "$APK" "$so" > "$S/lib.so"
  echo "$so $("$READELF" -l "$S/lib.so" | awk '/LOAD/{print $NF}' | sort -u | tr '\n' ' ')"
done

# The bundle: the same libraries sit under base/lib/arm64-v8a/.
for so in $(unzip -l "$AAB" | awk '/base\/lib\/arm64-v8a\/.*\.so$/{print $4}'); do
  unzip -p "$AAB" "$so" > "$S/lib.so"
  echo "$so $("$READELF" -l "$S/lib.so" | awk '/LOAD/{print $NF}' | sort -u | tr '\n' ' ')"
done
```

Expected: `Verification successful` from `zipalign`, and every library listed with `0x4000` or more (`0x10000` is fine). That covers Flutter's engine, `libapp.so` and the SQLite library. Play applies the same rule to `x86_64` libraries, so change `arm64-v8a` to `x86_64` to check those too.

A library that shows `0x1000` blocks the upload. Find the package that ships it and write down its name and version. Fix it by upgrading that package within the pins in `android/app/build.gradle.kts` and `pubspec.yaml`, or ask before moving a pin.

## Upload to internal testing

1. In Play Console: Testing, then Internal testing, then **Create new release**.
2. On the first upload only, accept Play App Signing (Google holds the app signing key, and ours is the upload key).
3. Upload `app-release.aab`. The first upload is version `1.0.0+1`.
4. Play refuses a debug-signed bundle here. If that happens, `android/key.properties` was missing: see the signature check above.
5. Write the release notes, then review and start the rollout. The first release's note is "First internal test build."
6. Open App bundle explorer for the new version. R8's mapping file (`mapping.txt`) is inside the bundle, so there is nothing to upload by hand, but check that Play lists it and the native debug symbols. If either is missing, upload `build/app/outputs/mapping/release/mapping.txt` for that version from the release's page.
7. Testers: add Google accounts to the internal testing list, then open the opt-in link on the phone.

The Play Console forms (App content, the foreground service declaration and the rest) are answered from [declarations.md](declarations.md).

## Moving a phone from a debug build to the Play build

The debug build and the Play build share one application id, so two copies can never ring the same meetings. They are signed with different keys, so Android will not update one with the other. Switching means uninstalling the debug build, which deletes its data, so export first:

1. On the debug build, open Settings and choose **Export settings** (profiles, rules and sources, without their links). Save the file somewhere that outlives the uninstall, for example Downloads.
2. Uninstall the debug build.
3. Install the Play build from the internal testing link.
4. Go through onboarding, then open Settings and choose **Import settings**.
5. Paste each calendar link again and pick each phone calendar again. The export holds neither.
