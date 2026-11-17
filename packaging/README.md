# Package manager manifests

Manifests for WinGet, Scoop, the AUR and Flatpak, filled in for the latest release.

After each release, the **Packages** workflow (`.github/workflows/packages.yml`) fills them in for that release and:

- builds a Flatpak bundle for x86_64 and aarch64 and adds `Lumtub_<version>_linux-<arch>.flatpak` with its `.sig` (signed like every other package) to the release;
- opens a pull request to [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs) for the new version;
- opens a pull request adding Lumtub to [ScoopInstaller/Extras](https://github.com/ScoopInstaller/Extras), once: after it is merged, Extras' own bot follows new releases;
- pushes the new version to the AUR package `lumtub-bin`.

The last three need secrets in the repository settings (Settings › Secrets and variables › Actions); without one, that step is skipped:

| Secret | For | What it is |
|---|---|---|
| `PACKAGES_TOKEN` | WinGet, Scoop | A classic personal access token of the account the pull requests come from, with the scopes `public_repo` and `workflow`. The workflow forks the two repositories into that account. |
| `AUR_SSH_KEY` | AUR | The private SSH key whose public key is in your aur.archlinux.org account: ed25519, or a post-quantum hybrid `mldsa44-ed25519` key if the AUR accepts one (that step runs in an Arch Linux container with the newest OpenSSH). Variables `AUR_NAME` and `AUR_EMAIL` fill the PKGBUILD's Maintainer line. |

To send a release again, run **Packages** by hand with its tag. A pull request that changes `packaging/` builds the Flatpak of the latest release without sending anything.

## Where Lumtub is listed

| Where | State |
|---|---|
| WinGet (`Lumtub.Lumtub`) | First version sent 2026-11-17 ([winget-pkgs#482133](https://github.com/microsoft/winget-pkgs/pull/482133)); each release sends a new one. |
| Scoop Extras (`extras/lumtub`) | Sent 2026-11-17 ([Extras#19396](https://github.com/ScoopInstaller/Extras/pull/19396)); Extras' bot follows releases once merged. |
| Flatpak bundles | On every release since 0.2.49. |
| AUR (`lumtub-bin`) | **Not yet.** AUR sign-ups were closed on 2026-11-17. To do: register at aur.archlinux.org, add the public key of `ssh-keygen -t mldsa44-ed25519` (or ed25519 if the AUR refuses it) to the account, save the private key as the `AUR_SSH_KEY` secret, then run **Packages** by hand. |
| Flathub | **Not planned.** Flathub's [generative AI policy](https://docs.flathub.org/docs/for-app-authors/requirements#generative-ai-policy) rules out this repository's packaging; the first request (flathub/flathub#11236) was closed on 2026-11-17. Linux users get the Flatpak bundles and AppImages from the releases. |

## Release tags and file names

Releases are tagged `v<version>-<7-character commit>`, for example `v0.2.29-1a2b3c4`, and the assets are named with the whole `<version>-<commit>` part:

- `Lumtub_0.2.29-1a2b3c4_windows-x64-setup.exe` and `..._windows-arm64-setup.exe`
- `Lumtub_0.2.29-1a2b3c4_windows-x64.zip` and `..._windows-arm64.zip` (portable)
- `Lumtub_0.2.29-1a2b3c4_linux-x64.AppImage` and `..._linux-arm64.AppImage`

The x64 packages are the baseline build. The `x64-v3` build (for CPUs with AVX2) is not listed in any manifest.

## Refresh the manifests for a release

```sh
packaging/update-manifests.sh v0.2.29-1a2b3c4              # downloads the assets with curl
packaging/update-manifests.sh v0.2.29-1a2b3c4 ~/Downloads  # or use assets you already have
```

The script needs `bash`, `curl` and `python3`. It rewrites the version, URLs, SHA-256 values and release date in place in all four manifests (the date is the release's, or `RELEASE_DATE`). Check the changes afterwards.

## WinGet

The installer is an Inno Setup program that installs for the current user only, so `Scope: user` is set. WinGet runs it silently on its own.

1. Fork [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs).
2. Copy the three files from `packaging/winget/` to `manifests/l/Lumtub/Lumtub/<version>/` in your fork, for example `manifests/l/Lumtub/Lumtub/0.2.29/`.
3. Validate on Windows with `winget validate --manifest <folder>`, then test with `winget install --manifest <folder>` (enable it first with `winget settings --enable LocalManifestFiles`).
4. Open a pull request. A bot checks the installer and a maintainer approves it. For later versions, add a new folder, or run `wingetcreate update Lumtub.Lumtub --urls <url-x64> <url-arm64> --version <version> --submit`.

## Scoop

The manifest uses the portable ZIP. The ZIP contains a `portable.txt` marker, so Lumtub keeps its data in `userdata` next to `lumtub.exe`, and the manifest persists that folder across updates.

1. Test locally with `scoop install .\packaging\scoop\lumtub.json`.
2. Fork [ScoopInstaller/Extras](https://github.com/ScoopInstaller/Extras) and add the file as `bucket/lumtub.json`.
3. Open a pull request. After it is merged, the Extras bot picks up new releases through `checkver` and `autoupdate`, so later releases normally need nothing from you.

The Scoop version is `<version>-<commit>`, because the commit is part of the download URL. Lumtub's built-in updater does not know it was installed by Scoop, so tell Scoop users to update with `scoop update lumtub`.

## Flatpak

`flatpak/io.github.lumtub.lumtub.yml` puts the AppImage's files under `/app/lumtub` on the freedesktop runtime and starts them through `AppRun`. Inside the Flatpak, Lumtub's own updater stays off: it only replaces an AppImage. Install a bundle from the release with `flatpak install --user Lumtub_<version>_linux-x64.flatpak`.

The Flatpak sees the Downloads, Videos and Pictures folders only, so signing in from a browser's cookies does not find the browser's data.

Lumtub is not sent to Flathub (see the table above). The manifest is used only to build the bundles attached to each release.

## AUR

`lumtub-bin` unpacks the AppImage into `/opt/lumtub` (so it needs no FUSE), adds a `/usr/bin/lumtub` launcher, the desktop file and the icon. `lumtub.png` and `io.github.lumtub.lumtub.desktop` in `packaging/aur/` are copies of the files under `linux/`; copy them again if those change.

1. Create an account at aur.archlinux.org and add your SSH key.
2. `git clone ssh://aur@aur.archlinux.org/lumtub-bin.git`
3. Copy `PKGBUILD`, `.SRCINFO`, `lumtub.png` and `io.github.lumtub.lumtub.desktop` into the clone, and put your name in the `Maintainer` line.
4. On an Arch system, run `makepkg -f` in that folder to test it. If you edit the PKGBUILD by hand, regenerate `.SRCINFO` with `makepkg --printsrcinfo > .SRCINFO`.
5. `git add PKGBUILD .SRCINFO lumtub.png io.github.lumtub.lumtub.desktop && git commit -m "lumtub-bin 0.2.29" && git push`

Unpacked, Lumtub is not running from an AppImage, so its own updater stays off and updates come from the package. Lumtub also leaves an AppImage it cannot write alone, such as one a package manager put in a system folder.
