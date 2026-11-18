# Security

## Reporting a problem

Please report a security problem privately, through **Security › Report a
vulnerability** on GitHub, rather than in a public issue.

## Checking a download

Every package on the Releases page comes with two independent proofs.

- **The update signature** (`<package>.sig`): Ed25519 and ML-DSA-65 (FIPS 204)
  over the file's name and SHA-256. Lumtub installs an update only when both
  hold, so breaking one of the two schemes is not enough to push a package.
- **Build provenance**: a Sigstore-signed statement that the file was built by
  this repository's `Build` workflow from a given commit. Check it with the
  GitHub CLI:

  ```
  gh attestation verify Lumtub_0.2.50-abc1234_windows-x64-setup.exe --repo 0x696c757a696f/lumtub
  ```

Each release also lists its software bill of materials
(`Lumtub_<version>_sbom.cdx.json`, CycloneDX): every Rust crate and Dart
package by version and checksum, the Flutter SDK and the Linux libmpv build.

## What the app does to stay safe

- **Updates** install only when both signatures hold, only for a newer version,
  and only for the package of the running architecture. On Windows the
  installer is checked once more through a handle that keeps the file from
  changing until it has started.
- **Connections** use rustls with the X25519MLKEM768 post-quantum hybrid key
  exchange first, and the operating system's certificate check.
- **Sign-ins** are sealed with AES-256-GCM under a key the system keeps: a TPM
  key with DPAPI on Windows, the keychain on macOS, the Secret Service keyring
  on Linux. In memory they stay in locked pages that are wiped after use.
- **yt-dlp** runs with `--ignore-config --no-plugin-dirs`: no yt-dlp
  configuration file or plugin left on the computer changes what it does.
- **Windows**: Control Flow Guard in the app and the core; DLLs load only from
  Lumtub's folder and System32, never from the current folder or `PATH`.
- **Linux**: stack protection, fortified libc calls and read-only relocations.
- **Dependencies**: GitHub Actions are pinned by commit; new versions of
  dependencies wait a week before they are taken; `cargo deny` checks the
  Rust core's advisories and sources; the parsers of outside data are fuzzed
  every night.

## For contributors

The rules code and workflows follow are in [SECURE-CODING.md](SECURE-CODING.md);
the Security job of Checks enforces the ones a machine can check.

## For maintainers: the "release" environment

The signing keys belong in a GitHub environment that only `main` and release
tags may use, so a workflow on any other branch, or a compromised dependency
in a pull request build, cannot read them. The workflows already ask for the
environment; until the keys are moved, the repository-level secrets keep
working as before.

1. **Settings › Environments › New environment**, name it `release`.
2. Under **Deployment branches and tags**, choose **Selected branches and
   tags** and add the branch rule `main` and the tag rule `v*`.
3. Optionally, under **Required reviewers**, add yourself: every main build and
   release then waits for your approval before it can sign.
4. Under **Environment secrets**, add these with the same values as the
   repository secrets of the same names:
   `LUMTUB_UPDATE_KEY`, `LUMTUB_ANDROID_KEYSTORE`,
   `LUMTUB_ANDROID_KEYSTORE_PASSWORD`, `LUMTUB_ANDROID_HYBRID_CLASSICAL_KEY`,
   `LUMTUB_ANDROID_HYBRID_CLASSICAL_CERT`, `LUMTUB_ANDROID_HYBRID_PQC_KEY`,
   `LUMTUB_ANDROID_HYBRID_PQC_CERT`, and, if set, `APPLE_CERTIFICATE_P12`,
   `APPLE_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`,
   `APPLE_APP_PASSWORD`.
5. Delete those secrets under **Settings › Secrets and variables › Actions ›
   Repository secrets**.
6. Run **Build** on `main` once and check the Android APKs are signed with the
   release key (the job prints a warning when it falls back to the debug key).
