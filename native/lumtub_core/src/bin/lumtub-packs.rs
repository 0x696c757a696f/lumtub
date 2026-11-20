//! Checks and compiles the data pack catalog under `packs/` (see
//! packs/README.md).
//!
//! `lumtub-packs check DIR` reads every `*.json` in DIR as one pack and
//! checks it. `lumtub-packs build DIR OUT VERSION` writes the catalog that
//! the app downloads, to be signed with `lumtub-sign`.

use lumtub_core::packs::{self, Catalog, Pack};
use std::path::Path;
use std::process::ExitCode;

fn load(dir: &str) -> Result<Vec<Pack>, String> {
    let mut names: Vec<_> = std::fs::read_dir(dir)
        .map_err(|e| format!("{dir}: {e}"))?
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.extension().is_some_and(|e| e == "json"))
        .collect();
    names.sort();
    let mut all = Vec::new();
    let mut problems = Vec::new();
    for path in names {
        let shown = path.display();
        match std::fs::read(&path)
            .map_err(|e| e.to_string())
            .and_then(|bytes| serde_json::from_slice::<Pack>(&bytes).map_err(|e| e.to_string()))
        {
            Ok(pack) => {
                if path.file_stem().and_then(|s| s.to_str()) != Some(pack.id.as_str()) {
                    problems.push(format!(
                        "{shown}: the file is not named after the id {}",
                        pack.id
                    ));
                }
                all.push(pack);
            }
            Err(error) => problems.push(format!("{shown}: {error}")),
        }
    }
    let catalog = Catalog {
        version: 1,
        built: String::new(),
        packs: all,
    };
    problems.extend(packs::check(&catalog));
    if problems.is_empty() {
        Ok(catalog.packs)
    } else {
        for problem in &problems {
            eprintln!("{problem}");
        }
        Err(format!("{} problem(s) in {dir}", problems.len()))
    }
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
            let all = load(dir)?;
            let bytes: u64 = all.iter().map(Pack::size).sum();
            println!("{} pack(s), {bytes} bytes in all, all fine", all.len());
            Ok(())
        }
        ["build", dir, out, version] => {
            let version: u64 = version
                .parse()
                .map_err(|_| format!("{version} is not a number"))?;
            let packs = load(dir)?;
            let built = std::env::var("LUMTUB_PACKS_BUILT").unwrap_or_default();
            let json = serde_json::to_vec(&Catalog {
                version,
                built,
                packs,
            })
            .map_err(|e| e.to_string())?;
            // What the app will read back.
            packs::parse(&json).map_err(|problems| problems.join("; "))?;
            std::fs::write(Path::new(out), json).map_err(|e| format!("{out}: {e}"))
        }
        _ => Err("usage: lumtub-packs check DIR | build DIR OUT VERSION".into()),
    }
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("{error}");
            ExitCode::FAILURE
        }
    }
}
