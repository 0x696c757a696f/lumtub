// Lists the built-in skins for the live preview: their ids in the order the
// app ships them (pubspec.yaml), names in English and Chinese, and the two
// colours on each picker button. The preview reads the skin files themselves
// at run time.

#[path = "src/jsonc.rs"]
mod jsonc;

use std::fmt::Write;
use std::{env, fs, path::Path};

use serde_json::Value;

fn main() {
    println!("cargo:rerun-if-changed=../skins");
    println!("cargo:rerun-if-changed=../pubspec.yaml");
    let pubspec = fs::read_to_string("../pubspec.yaml").expect("pubspec.yaml");
    let ids: Vec<&str> = pubspec
        .lines()
        .filter_map(|l| l.trim().strip_prefix("- skins/")?.strip_suffix('/'))
        .filter(|id| *id != "template" && *id != "fonts")
        .collect();
    let mut out = String::from("pub static SKINS: &[SkinInfo] = &[\n");
    for id in ids {
        let path = format!("../skins/{id}/skin.jsonc");
        println!("cargo:rerun-if-changed={path}");
        let json: Value = serde_json::from_str(&jsonc::strip(&fs::read_to_string(&path).expect(&path))).expect(&path);
        let name = json["name"].as_str().unwrap_or(id);
        let zh = json["names"]["zh-Hans"].as_str().unwrap_or(name);
        let side = json["brightness"].as_str().unwrap_or("light");
        // A colour scheme keeps Lumtub's own shapes: it draws no cards.
        let scheme = json.get("cards").is_none();
        let colors = &json["colors"];
        let page = colors["page"].as_str().unwrap_or("#ffffff");
        let accent = colors["accent"].as_str().unwrap_or("#e53935");
        let dark_page = json["overrides"]["dark"]["colors"]["page"].as_str().unwrap_or(page);
        writeln!(
            out,
            "    SkinInfo {{ id: {id:?}, en: {name:?}, zh: {zh:?}, side: {side:?}, scheme: {scheme}, page: {page:?}, dark_page: {dark_page:?}, accent: {accent:?} }},"
        )
        .unwrap();
    }
    out.push_str("];\n");
    fs::write(Path::new(&env::var("OUT_DIR").unwrap()).join("skins.rs"), out).unwrap();
}
