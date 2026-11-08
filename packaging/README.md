# Package manager manifests

Manifests for WinGet, Scoop and the AUR. They are filled with version 0.2.29, a placeholder commit (`0000000`) and all-zero SHA-256 values, because the release is not out yet. Nothing here is published automatically.

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

The script needs `bash`, `curl` and `python3`. It rewrites the version, URLs and SHA-256 values in place in all three manifests. Check the changes afterwards. For WinGet, also set `ReleaseDate` in `Lumtub.Lumtub.installer.yaml` by hand.

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

## AUR

`lumtub-bin` unpacks the AppImage into `/opt/lumtub` (so it needs no FUSE), adds a `/usr/bin/lumtub` launcher, the desktop file and the icon. `lumtub.png` and `io.github.lumtub.lumtub.desktop` in `packaging/aur/` are copies of the files under `linux/`; copy them again if those change.

1. Create an account at aur.archlinux.org and add your SSH key.
2. `git clone ssh://aur@aur.archlinux.org/lumtub-bin.git`
3. Copy `PKGBUILD`, `.SRCINFO`, `lumtub.png` and `io.github.lumtub.lumtub.desktop` into the clone, and put your name in the `Maintainer` line.
4. On an Arch system, run `makepkg -f` in that folder to test it. If you edit the PKGBUILD by hand, regenerate `.SRCINFO` with `makepkg --printsrcinfo > .SRCINFO`.
5. `git add PKGBUILD .SRCINFO lumtub.png io.github.lumtub.lumtub.desktop && git commit -m "lumtub-bin 0.2.29" && git push`

Unpacked, Lumtub is not running from an AppImage, so its own updater stays off and updates come from the package. Lumtub also leaves an AppImage it cannot write alone, such as one a package manager put in a system folder.
