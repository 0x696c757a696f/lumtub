//! Checks and compiles the block lists under `lists/` (see lists/schema.md).
//!
//! `lumtub-lists check DIR [--base OLD_DIR]` reads every list strictly and,
//! with a base, prints what changed. `lumtub-lists build DIR OUT VERSION`
//! writes the compiled lists.json.

use lumtub_core::lists;
use std::path::Path;
use std::process::ExitCode;

fn load(dir: &str) -> Result<(Vec<lists::List>, std::collections::HashSet<String>), String> {
    lists::load_dir(Path::new(dir)).map_err(|problems| {
        for problem in &problems {
            eprintln!("{problem}");
        }
        format!("{} problem(s) in {dir}", problems.len())
    })
}

fn run() -> Result<(), String> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args
        .iter()
        .map(String::as_str)
        .collect::<Vec<_>>()
        .as_slice()
    {
        ["check", dir] => {
            let (all, _) = load(dir)?;
            let records: usize = all.iter().map(|l| l.records.len()).sum();
            println!("{} lists, {records} records, all fine", all.len());
            Ok(())
        }
        ["check", dir, "--base", base] => {
            let (all, retired) = load(dir)?;
            // No base folder means the lists are new; a base that does not
            // read is an error, not an empty start.
            let old = if Path::new(base).is_dir() {
                load(base).map_err(|e| format!("the base lists: {e}"))?.0
            } else {
                Vec::new()
            };
            let lines = lists::diff(&old, &all, &retired);
            let problems = lists::unretired(&old, &all, &retired);
            if lines.is_empty() {
                println!("No change to the lists");
            }
            for line in lines {
                println!("{line}");
            }
            for problem in &problems {
                eprintln!("{problem}");
            }
            if problems.is_empty() {
                Ok(())
            } else {
                Err(format!(
                    "{} removed record(s) missing from retired.txt",
                    problems.len()
                ))
            }
        }
        ["build", dir, out, version] => {
            let version: u64 = version
                .parse()
                .map_err(|_| format!("{version} is not a version number"))?;
            let (all, _) = load(dir)?;
            let built = std::process::Command::new("date")
                .args(["-u", "+%Y-%m-%dT%H:%M:%SZ"])
                .output()
                .ok()
                .and_then(|o| String::from_utf8(o.stdout).ok())
                .map(|s| s.trim().to_string())
                .unwrap_or_default();
            let json = serde_json::to_string(&lists::Bundle {
                version,
                built: &built,
                lists: &all,
            })
            .map_err(|e| e.to_string())?;
            std::fs::write(out, json).map_err(|e| format!("{out}: {e}"))?;
            println!("Wrote {out}: version {version}, {} lists", all.len());
            Ok(())
        }
        _ => Err("usage: lumtub-lists check DIR [--base OLD_DIR] | build DIR OUT VERSION".into()),
    }
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("lumtub-lists: {e}");
            ExitCode::FAILURE
        }
    }
}
