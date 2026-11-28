# Releasing Lumtub

One click: GitHub › Actions › **Create Lumtub release** › **Run workflow** on `main`.

- **Version.** If the version in `pubspec.yaml` was not released yet, it is used. If it was, the workflow moves `main` on to the next patch version and build number by itself. To jump further, type a version such as `0.3.0` in the **Version** box.
- **Notes.** `release-notes/<version>.md` is used when it exists. Without it, GitHub writes the notes from the pull requests merged since the last release, grouped by `.github/release.yml`. Pull requests labelled `no-notes` and bot pull requests are left out.
- **Build.** The workflow tags `v<version>-<tree>` and starts the tagged build, which publishes the GitHub Release with every installer, usually within an hour.
- **Monthly.** A scheduled run releases by itself when the last release is more than 30 days old and `main` has changes since.
- **Nothing new.** With no commits since the last release tag, nothing is released.
- **A failed release** leaves its tag behind. Delete the tag on GitHub (Tags › the tag › Delete) before running again, or the next run takes the next patch version.
