//! Lumtub's own updates: whether a GitHub release is newer than the running
//! build, which of its files to download, and the PowerShell script that
//! installs it once Lumtub has exited.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::os::raw::c_char;

use crate::taste::{give_json, text};

/// The `x.y.z` at the start of a version such as `0.2.1-72ec49d`.
fn numbers(version: &str) -> Option<[u64; 3]> {
    let version = version.strip_prefix('v').unwrap_or(version);
    let mut parts = version.splitn(3, '.');
    let major = parts.next()?.parse().ok()?;
    let minor = parts.next()?.parse().ok()?;
    let rest = parts.next()?;
    let digits = rest.find(|c: char| !c.is_ascii_digit()).unwrap_or(rest.len());
    Some([major, minor, rest[..digits].parse().ok()?])
}

/// Seconds since 1970 of an RFC 3339 time such as GitHub's
/// `2026-10-25T09:39:05Z` or git's `2026-10-25T17:39:05+08:00`.
pub fn unix_seconds(time: &str) -> Option<i64> {
    let b = time.as_bytes();
    if b.len() < 20 || b[4] != b'-' || b[7] != b'-' || !matches!(b[10], b'T' | b't' | b' ') || b[13] != b':' || b[16] != b':' {
        return None;
    }
    let field = |from: usize, to: usize| time.get(from..to)?.parse::<i64>().ok();
    let (year, month, day) = (field(0, 4)?, field(5, 7)?, field(8, 10)?);
    let (hour, minute, second) = (field(11, 13)?, field(14, 16)?, field(17, 19)?);
    if !(1..=12).contains(&month) || !(1..=31).contains(&day) || hour > 23 || minute > 59 || second > 60 {
        return None;
    }
    let mut zone = &time[19..];
    if let Some(fraction) = zone.strip_prefix('.') {
        zone = fraction.trim_start_matches(|c: char| c.is_ascii_digit());
    }
    let offset = match zone {
        "Z" | "z" => 0,
        _ if zone.len() == 6 && zone.as_bytes()[3] == b':' => {
            let sign = match zone.as_bytes()[0] {
                b'+' => 1,
                b'-' => -1,
                _ => return None,
            };
            sign * (zone[1..3].parse::<i64>().ok()? * 3600 + zone[4..6].parse::<i64>().ok()? * 60)
        }
        _ => return None,
    };
    // Days from the civil date, after Howard Hinnant's algorithm.
    let y = if month <= 2 { year - 1 } else { year };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (month + 9) % 12;
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146_097 + doe - 719_468;
    Some(days * 86_400 + hour * 3600 + minute * 60 + second - offset)
}

/// Whether the release [tag], published at [published], is newer than the
/// running [current] built at [built]: a higher version number, or the same
/// number from another commit published after this build.
pub fn is_newer(current: &str, tag: &str, published: Option<i64>, built: Option<i64>) -> bool {
    let (Some(have), Some(offered)) = (numbers(current), numbers(tag)) else {
        return false;
    };
    if offered != have {
        return offered > have;
    }
    let same_commit = tag.strip_prefix('v').unwrap_or(tag) == current;
    matches!((published, built), (Some(p), Some(b)) if !same_commit && p > b)
}

/// The file of a release for [package] (such as `windows-x64-v3`): the
/// portable ZIP or the installer.
pub fn asset_of<'a>(release: &'a Value, package: &str, portable: bool) -> Option<&'a Value> {
    if package.is_empty() {
        return None;
    }
    let suffix = if portable { format!("_{package}.zip") } else { format!("_{package}-setup.exe") };
    release.get("assets")?.as_array()?.iter().find(|asset| asset.get("name").and_then(Value::as_str).is_some_and(|name| name.ends_with(&suffix)))
}

/// The signature file published next to [asset].
pub fn signature_of<'a>(release: &'a Value, asset: &Value) -> Option<&'a Value> {
    let name = format!("{}.sig", asset.get("name")?.as_str()?);
    release.get("assets")?.as_array()?.iter().find(|other| other.get("name").and_then(Value::as_str) == Some(&name))
}

#[derive(Serialize, Debug, PartialEq)]
pub struct Offer<'a> {
    /// Such as `0.2.2-1234567`.
    pub version: &'a str,
    pub page: &'a str,
    pub asset: Option<&'a Value>,
    /// The asset's signature file, `<asset name>.sig`.
    pub signature: Option<&'a Value>,
}

/// The update [release] offers the running build, if it is newer.
pub fn offer<'a>(release: &'a Value, current: &str, built: Option<i64>, package: &str, portable: bool) -> Option<Offer<'a>> {
    let tag = release.get("tag_name").and_then(Value::as_str).unwrap_or_default();
    let published = release.get("published_at").and_then(Value::as_str).and_then(unix_seconds);
    if !is_newer(current, tag, published, built) {
        return None;
    }
    let asset = asset_of(release, package, portable);
    Some(Offer {
        version: tag.strip_prefix('v').unwrap_or(tag),
        page: release.get("html_url").and_then(Value::as_str).unwrap_or_default(),
        asset,
        signature: asset.and_then(|asset| signature_of(release, asset)),
    })
}

/// The folder of a Windows path.
fn parent(path: &str) -> &str {
    path.rfind(['\\', '/']).map_or("", |at| &path[..at])
}

/// A PowerShell single-quoted string.
fn quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "''"))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Install {
    /// The downloaded installer or ZIP.
    pub package: String,
    /// Lumtub's process, waited for.
    pub process_id: u32,
    /// lumtub.exe.
    pub executable: String,
    pub portable: bool,
    pub relaunch: bool,
}

/// A script that waits for Lumtub to end, then runs the installer silently
/// or unpacks the portable ZIP over Lumtub's folder, removes the package and
/// starts Lumtub again when asked. It notes what happened in update.log next
/// to the package.
pub fn script(install: &Install) -> String {
    let package = quote(&install.package);
    let log = quote(&format!("{}\\update.log", parent(&install.package)));
    let folder = parent(&install.executable);
    let mut lines = vec![
        "$ErrorActionPreference = 'Stop'".to_owned(),
        "try {".to_owned(),
        format!("  Wait-Process -Id {} -Timeout 120 -ErrorAction SilentlyContinue", install.process_id),
    ];
    if install.portable {
        lines.extend([
            "  $unpacked = Join-Path $env:TEMP ('lumtub-update-' + [guid]::NewGuid())".to_owned(),
            format!("  Expand-Archive -LiteralPath {package} -DestinationPath $unpacked -Force"),
            format!("  Copy-Item -Path (Join-Path $unpacked '*') -Destination {} -Recurse -Force", quote(folder)),
            "  Remove-Item -LiteralPath $unpacked -Recurse -Force".to_owned(),
        ]);
    } else {
        // Into the folder this Lumtub runs from, wherever that is, asking
        // for administrator rights only when the folder needs them.
        let setup_log = quote(&format!("{}\\setup.log", parent(&install.package)));
        lines.extend([
            format!("  $folder = {}", quote(folder)),
            "  $elevate = $false".to_owned(),
            "  try { $probe = Join-Path $folder ('.update-' + [guid]::NewGuid()); [IO.File]::WriteAllText($probe, ''); Remove-Item -LiteralPath $probe -Force } catch { $elevate = $true }".to_owned(),
            format!("  $arguments = @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/CLOSEAPPLICATIONS',('/DIR=\"' + $folder + '\"'),('/LOG=\"' + {setup_log} + '\"'))"),
            format!("  if ($elevate) {{ $setup = Start-Process -FilePath {package} -ArgumentList $arguments -Verb RunAs -Wait -PassThru }} else {{ $setup = Start-Process -FilePath {package} -ArgumentList $arguments -Wait -PassThru }}"),
            "  if ($setup.ExitCode -ne 0) { throw \"Setup exited with $($setup.ExitCode)\" }".to_owned(),
        ]);
    }
    lines.extend([
        format!("  Remove-Item -LiteralPath {package} -Force"),
        format!("  \"$(Get-Date -Format o) updated\" | Out-File -FilePath {log} -Append"),
        "} catch {".to_owned(),
        format!("  \"$(Get-Date -Format o) $_\" | Out-File -FilePath {log} -Append"),
        "}".to_owned(),
    ]);
    if install.relaunch {
        lines.push(format!("Start-Process -FilePath {}", quote(&install.executable)));
    }
    lines.join("\r\n")
}

/// The update a GitHub release offers, as JSON `{version, page, asset,
/// signature}`, or JSON `null` when it is not newer. [json] is `{release, current, built,
/// package, portable}` with `built` in seconds since 1970.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_update_offer(json: *const u8, length: usize) -> *mut c_char {
    #[derive(Deserialize)]
    struct Ask {
        release: Value,
        current: String,
        built: Option<i64>,
        #[serde(default)]
        package: String,
        #[serde(default)]
        portable: bool,
    }
    let Ok(ask) = serde_json::from_str::<Ask>(unsafe { text(json, length) }) else {
        return std::ptr::null_mut();
    };
    give_json(&offer(&ask.release, &ask.current, ask.built, &ask.package, ask.portable))
}

/// The install script for [json], an [Install] as JSON.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_update_script(json: *const u8, length: usize) -> *mut c_char {
    let Ok(install) = serde_json::from_str::<Install>(unsafe { text(json, length) }) else {
        return std::ptr::null_mut();
    };
    give_json(&script(&install))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    const BUILT: i64 = 1_761_393_600; // 2025-10-25T12:00:00Z

    #[test]
    fn reads_rfc3339_times() {
        assert_eq!(unix_seconds("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(unix_seconds("2025-10-25T12:00:00Z"), Some(BUILT));
        assert_eq!(unix_seconds("2025-10-25T20:00:00+08:00"), Some(BUILT));
        assert_eq!(unix_seconds("2025-10-25T07:00:00.250-05:00"), Some(BUILT));
        assert_eq!(unix_seconds("2024-02-29T00:00:00Z"), Some(1_709_164_800));
        assert_eq!(unix_seconds("yesterday"), None);
        assert_eq!(unix_seconds("2025-13-01T00:00:00Z"), None);
    }

    #[test]
    fn a_higher_version_is_newer() {
        assert!(is_newer("0.2.1-72ec49d", "v0.2.2-1234567", None, None));
        assert!(is_newer("0.2.1-72ec49d", "v0.3.0-1234567", None, None));
        assert!(is_newer("0.9.9-72ec49d", "v1.0.0-1234567", None, None));
        assert!(!is_newer("0.2.1-72ec49d", "v0.2.0-1234567", Some(BUILT + 86_400), Some(BUILT)));
        assert!(!is_newer("1.0.0-72ec49d", "v0.10.0-1234567", None, None));
    }

    #[test]
    fn the_same_version_is_newer_only_from_a_later_commit() {
        assert!(!is_newer("0.2.1-72ec49d", "v0.2.1-72ec49d", Some(BUILT + 3600), Some(BUILT)));
        assert!(is_newer("0.2.1-aaaaaaa", "v0.2.1-72ec49d", Some(BUILT + 3600), Some(BUILT)));
        assert!(!is_newer("0.2.1-aaaaaaa", "v0.2.1-72ec49d", Some(BUILT - 3600), Some(BUILT)));
        assert!(!is_newer("0.2.1-aaaaaaa", "v0.2.1-72ec49d", None, None));
    }

    #[test]
    fn a_development_build_never_updates() {
        assert!(!is_newer("开发版", "v9.0.0-1234567", None, None));
    }

    fn release() -> Value {
        json!({
            "tag_name": "v0.2.2-1234567",
            "html_url": "https://github.com/0x696c757a696f/lumtub/releases/tag/v0.2.2-1234567",
            "published_at": "2025-10-26T08:00:00Z",
            "assets": [
                {"name": "Lumtub_0.2.2-1234567_windows-x64-v3-setup.exe"},
                {"name": "Lumtub_0.2.2-1234567_windows-x64-v3.zip"},
                {"name": "Lumtub_0.2.2-1234567_windows-x64-setup.exe.sig"},
                {"name": "Lumtub_0.2.2-1234567_windows-x64-setup.exe"},
                {"name": "Lumtub_0.2.2-1234567_windows-x64.zip"},
            ],
        })
    }

    #[test]
    fn picks_the_package_file() {
        let release = release();
        let name = |package, portable| asset_of(&release, package, portable).and_then(|a| a["name"].as_str());
        assert_eq!(name("windows-x64", false), Some("Lumtub_0.2.2-1234567_windows-x64-setup.exe"));
        assert_eq!(name("windows-x64", true), Some("Lumtub_0.2.2-1234567_windows-x64.zip"));
        assert_eq!(name("windows-x64-v3", true), Some("Lumtub_0.2.2-1234567_windows-x64-v3.zip"));
        assert_eq!(name("windows-arm64", false), None);
        assert_eq!(name("", false), None);
    }

    #[test]
    fn offers_a_newer_release() {
        let release = release();
        let offered = offer(&release, "0.2.1-72ec49d", Some(BUILT), "windows-x64", false).unwrap();
        assert_eq!(offered.version, "0.2.2-1234567");
        assert!(offered.page.ends_with("v0.2.2-1234567"));
        assert_eq!(offered.asset.unwrap()["name"], "Lumtub_0.2.2-1234567_windows-x64-setup.exe");
        assert_eq!(offered.signature.unwrap()["name"], "Lumtub_0.2.2-1234567_windows-x64-setup.exe.sig");
        assert_eq!(offer(&release, "0.2.1-72ec49d", Some(BUILT), "windows-x64", true).unwrap().signature, None);
        assert_eq!(offer(&release, "0.2.2-1234567", Some(BUILT), "windows-x64", false), None);
        assert_eq!(offer(&release, "0.2.2-aaaaaaa", Some(BUILT), "windows-x64", false).unwrap().version, "0.2.2-1234567");
    }

    #[test]
    fn installs_silently_after_exit() {
        let script = script(&Install {
            package: r"C:\cache\updates\Lumtub_0.2.2_windows-x64-setup.exe".into(),
            process_id: 42,
            executable: r"C:\Lumtub\lumtub.exe".into(),
            portable: false,
            relaunch: false,
        });
        assert!(script.contains("Wait-Process -Id 42"));
        assert!(script.contains(r"$folder = 'C:\Lumtub'"));
        assert!(script.contains(r#"('/DIR="' + $folder + '"')"#));
        assert!(script.contains(r#"('/LOG="' + 'C:\cache\updates\setup.log' + '"')"#));
        assert!(script.contains(r"Start-Process -FilePath 'C:\cache\updates\Lumtub_0.2.2_windows-x64-setup.exe' -ArgumentList $arguments -Verb RunAs -Wait -PassThru"));
        assert!(script.contains(r"-FilePath 'C:\cache\updates\update.log'"));
        assert!(!script.contains("Expand-Archive"));
        assert!(!script.contains(r"Start-Process -FilePath 'C:\Lumtub\lumtub.exe'"));
    }

    #[test]
    fn unpacks_the_portable_zip_and_relaunches() {
        let script = script(&Install {
            package: r"C:\it's\Lumtub_0.2.2_windows-x64.zip".into(),
            process_id: 7,
            executable: r"C:\Lumtub\lumtub.exe".into(),
            portable: true,
            relaunch: true,
        });
        assert!(script.contains(r"Expand-Archive -LiteralPath 'C:\it''s\Lumtub_0.2.2_windows-x64.zip'"));
        assert!(script.contains(r"-Destination 'C:\Lumtub'"));
        assert!(!script.contains("/VERYSILENT"));
        assert!(script.ends_with(r"Start-Process -FilePath 'C:\Lumtub\lumtub.exe'"));
    }
}
