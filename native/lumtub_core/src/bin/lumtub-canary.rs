//! Checks that YouTube still answers the quick start the way Lumtub reads it,
//! for the daily canary workflow (.github/workflows/canary.yml).
//!
//! `lumtub-canary body ID` prints the `/player` request body for ID,
//! `lumtub-canary headers` its headers, one `Name: value` per line, and
//! `lumtub-canary check FILE` reads YouTube's answer from FILE and prints
//! what the quick start makes of it. `check` exits with 0 when the video
//! plays, 2 when YouTube turned the machine away (a bot check: nothing
//! learnt about Lumtub), and 1 when the answer no longer gives what Lumtub
//! needs.

use lumtub_core::format_policy::Settings;
use lumtub_core::quick;
use serde_json::Value;
use std::process::ExitCode;

fn check(path: &str) -> ExitCode {
    let text = match std::fs::read_to_string(path) {
        Ok(text) => text,
        Err(e) => {
            println!("broken: {path}: {e}");
            return ExitCode::from(1);
        }
    };
    let Ok(player) = serde_json::from_str::<Value>(&text) else {
        println!(
            "broken: the answer is not JSON: {}",
            text.chars().take(200).collect::<String>()
        );
        return ExitCode::from(1);
    };
    let playability = &player["playabilityStatus"];
    let status = playability["status"].as_str().unwrap_or("none");
    let reason = playability["reason"].as_str().unwrap_or("");
    if status != "OK" {
        let lower = reason.to_lowercase();
        if lower.contains("bot") || lower.contains("sign in to confirm") {
            println!("blocked: {status}: {reason}");
            return ExitCode::from(2);
        }
        println!("broken: playability {status}: {reason}");
        return ExitCode::from(1);
    }
    let adaptive = player["streamingData"]["adaptiveFormats"]
        .as_array()
        .map(Vec::as_slice)
        .unwrap_or_default();
    if adaptive.is_empty() {
        println!("broken: no adaptive formats");
        return ExitCode::from(1);
    }
    let ciphered = adaptive.iter().filter(|f| f.get("url").is_none()).count();
    if ciphered > 0 {
        println!(
            "broken: {ciphered} of {} formats need YouTube's JavaScript",
            adaptive.len()
        );
        return ExitCode::from(1);
    }
    let Some(info) = quick::info(&player, &Settings::default()) else {
        println!("broken: the quick start picked no formats");
        return ExitCode::from(1);
    };
    let picked: Vec<String> = info["requested_formats"]
        .as_array()
        .map(Vec::as_slice)
        .unwrap_or_default()
        .iter()
        .map(|f| {
            let id = f["format_id"].as_str().unwrap_or("?");
            match f["height"].as_u64() {
                Some(height) => format!("{id} {height}p {}", f["vcodec"].as_str().unwrap_or("")),
                None => format!("{id} {}", f["acodec"].as_str().unwrap_or("")),
            }
        })
        .collect();
    println!(
        "ok: {} formats, picked {}",
        adaptive.len(),
        picked.join(" + ")
    );
    ExitCode::SUCCESS
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args
        .iter()
        .map(String::as_str)
        .collect::<Vec<_>>()
        .as_slice()
    {
        ["body", id] => {
            println!("{}", quick::request(id));
            ExitCode::SUCCESS
        }
        ["headers"] => {
            for (name, value) in quick::headers().as_object().into_iter().flatten() {
                println!("{name}: {}", value.as_str().unwrap_or_default());
            }
            ExitCode::SUCCESS
        }
        ["check", path] => check(path),
        _ => {
            eprintln!("usage: lumtub-canary body ID | headers | check FILE");
            ExitCode::from(64)
        }
    }
}
