//! Embeds the block lists under the repository's `lists/` folder, so the
//! library carries the lists it was built with (see src/lists.rs).

use std::fmt::Write;
use std::path::Path;

fn main() {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../lists");
    println!("cargo:rerun-if-changed={}", dir.display());
    let mut out = String::from("pub static FILES: &[(&str, &str, &str)] = &[\n");
    let mut folders: Vec<_> = std::fs::read_dir(&dir).into_iter().flatten().filter_map(Result::ok).map(|e| e.path()).filter(|p| p.is_dir()).collect();
    folders.sort();
    for folder in folders {
        println!("cargo:rerun-if-changed={}", folder.display());
        let category = folder.file_name().and_then(|n| n.to_str()).unwrap_or_default().to_string();
        let mut files: Vec<_> = std::fs::read_dir(&folder).into_iter().flatten().filter_map(Result::ok).map(|e| e.path()).filter(|p| p.is_file()).collect();
        files.sort();
        for file in files {
            println!("cargo:rerun-if-changed={}", file.display());
            let name = file.file_name().and_then(|n| n.to_str()).unwrap_or_default().to_string();
            writeln!(out, "    ({category:?}, {name:?}, include_str!({:?})),", file.display().to_string()).unwrap();
        }
    }
    out.push_str("];\n");
    // The lists' version: LUMTUB_LISTS_VERSION when set, else the commit
    // time of the source, which the lists workflow publishes them under.
    println!("cargo:rerun-if-env-changed=LUMTUB_LISTS_VERSION");
    let head = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../.git/HEAD");
    println!("cargo:rerun-if-changed={}", head.display());
    let version = std::env::var("LUMTUB_LISTS_VERSION").ok().filter(|v| v.parse::<u64>().is_ok()).or_else(|| {
        let out = std::process::Command::new("git").args(["log", "-1", "--format=%ct"]).current_dir(env!("CARGO_MANIFEST_DIR")).output().ok()?;
        let text = String::from_utf8(out.stdout).ok()?.trim().to_string();
        text.parse::<u64>().is_ok().then_some(text)
    });
    println!("cargo:rustc-env=LUMTUB_LISTS_VERSION={}", version.unwrap_or_else(|| "0".into()));
    let target = Path::new(&std::env::var("OUT_DIR").unwrap()).join("lists_files.rs");
    std::fs::write(target, out).unwrap();
}
