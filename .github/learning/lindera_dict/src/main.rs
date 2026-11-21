//! Builds a Lindera dictionary folder for the learning packs workflow:
//! `lindera_dict METADATA.json SOURCE_DIR OUT_DIR [CONTEXT_ID_FREQ]`,
//! the metadata and frequencies being those of the matching lindera-*
//! crate, the source a MeCab dictionary.

use std::path::Path;

use lindera::dictionary::{DictionaryBuilder, Metadata};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.len() < 3 {
        eprintln!("usage: lindera_dict METADATA.json SOURCE_DIR OUT_DIR [CONTEXT_ID_FREQ]");
        std::process::exit(2);
    }
    let metadata: Metadata =
        serde_json::from_str(&std::fs::read_to_string(&args[0]).expect("metadata"))
            .expect("metadata JSON");
    let mut builder = DictionaryBuilder::new(metadata);
    if let Some(freq) = args.get(3) {
        builder = builder.with_context_id_freq(freq);
    }
    builder
        .build_dictionary(Path::new(&args[1]), Path::new(&args[2]))
        .expect("build");
}
