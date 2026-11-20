# Data packs

Models, language data, shaders and runtimes that Lumtub downloads only when
a feature needs them. Nothing here is part of the installer.

Each pack is one file, `<id>.json`, named after its id:

```json
{
  "id": "shaders-upscale",
  "version": "1.0.0",
  "kind": "shader",
  "title": {"en": "Upscaling shaders", "zh-Hans": "超分着色器"},
  "description": {"en": "FSR, ArtCNN and Anime4K for the Picture settings."},
  "license": "MIT",
  "notice": "Copyright and attribution the license asks to show",
  "source": "https://github.com/...",
  "minApp": "0.2.59",
  "platforms": [],
  "files": [
    {"path": "FSR.glsl", "url": "https://github.com/0x696c757a696f/lumtub/releases/download/packs/FSR.glsl", "sha256": "…", "size": 12345}
  ]
}
```

- `kind` is `runtime` (a library the app loads), `model`, `language` or
  `shader`. A runtime's files must come from Lumtub's own releases; other
  files from `github.com` or `huggingface.co`.
- `path` is where the file goes inside the pack's folder: plain names joined
  by `/`, nothing hidden and no `..`.
- `platforms` lists the release packages a pack is for, named as the
  update packages are (`windows-x64`, `windows-x64-v3`, `windows-arm64`,
  `linux-x64`, `linux-arm64`, `macos-arm64`, `macos-x64`,
  `android-arm64-v8a`, `ios` …); empty means all.
- `sha256` is lowercase hex and `size` is in bytes. The app checks both after
  the download, so a file is trusted only through the signed catalog.

On `main`, the *Data packs* workflow checks every file, builds `packs.json`,
signs it like the app's packages and puts it on the `packs` release. Lumtub
reads that catalog under Settings › Storage & updates › Components & data
packs. Check locally with:

```
cargo run --manifest-path native/lumtub_core/Cargo.toml --bin lumtub-packs -- check packs
```
