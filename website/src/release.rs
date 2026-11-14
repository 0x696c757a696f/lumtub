use serde::Deserialize;

const API: &str = "https://api.github.com/repos/0x696c757a696f/lumtub/releases/latest";

#[derive(Clone, PartialEq, Eq)]
pub struct Release {
    pub version: String,
    assets: Vec<(String, String)>,
}

#[derive(Deserialize)]
struct ApiRelease {
    tag_name: String,
    assets: Vec<ApiAsset>,
}

#[derive(Deserialize)]
struct ApiAsset {
    name: String,
    browser_download_url: String,
}

impl Release {
    pub async fn fetch() -> Option<Release> {
        let response = gloo_net::http::Request::get(API)
            .header("Accept", "application/vnd.github+json")
            .send()
            .await
            .ok()?;
        if !response.ok() {
            return None;
        }
        let api: ApiRelease = response.json().await.ok()?;
        let version = api
            .tag_name
            .trim_start_matches('v')
            .split('-')
            .next()
            .unwrap_or_default()
            .to_string();
        let assets = api
            .assets
            .into_iter()
            .filter(|a| !a.name.ends_with(".sig"))
            .map(|a| (a.name, a.browser_download_url))
            .collect();
        Some(Release { version, assets })
    }

    pub fn asset(&self, suffix: &str) -> Option<String> {
        self.assets
            .iter()
            .find(|(name, _)| name == suffix || name.ends_with(&format!("_{suffix}")))
            .map(|(_, url)| url.clone())
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Os {
    Windows,
    Mac,
    Linux,
    LinuxArm,
    Android,
    Ios,
    Other,
}

impl Os {
    pub fn detect() -> Os {
        let ua = web_sys::window()
            .and_then(|w| w.navigator().user_agent().ok())
            .unwrap_or_default();
        if ua.contains("iPhone") || ua.contains("iPad") || ua.contains("iPod") {
            Os::Ios
        } else if ua.contains("Android") {
            Os::Android
        } else if ua.contains("Windows") {
            Os::Windows
        } else if ua.contains("Mac OS X") || ua.contains("Macintosh") {
            Os::Mac
        } else if ua.contains("Linux") || ua.contains("X11") {
            if ua.contains("aarch64") || ua.contains("arm") {
                Os::LinuxArm
            } else {
                Os::Linux
            }
        } else {
            Os::Other
        }
    }

    pub fn index(self) -> Option<usize> {
        match self {
            Os::Windows => Some(0),
            Os::Mac => Some(1),
            Os::Linux | Os::LinuxArm => Some(2),
            Os::Android => Some(3),
            Os::Ios => Some(4),
            Os::Other => None,
        }
    }

    pub fn suffix(self) -> &'static str {
        match self {
            Os::Windows => "windows-x64-v3-setup.exe",
            Os::Mac => "macos-arm64.dmg",
            Os::Linux => "linux-x64-v3.AppImage",
            Os::LinuxArm => "linux-arm64.AppImage",
            Os::Android => "android-arm64-v8a.apk",
            Os::Ios => "ios.ipa",
            Os::Other => "",
        }
    }
}
