use boa_engine::{Context, Source};

fn main() {
    let path = std::env::args().nth(1).expect("script path");
    let source = std::fs::read_to_string(path).expect("read script");
    let mut context = Context::default();
    boa_runtime::register(boa_runtime::extensions::ConsoleExtension::default(), None, &mut context)
        .expect("console");
    if let Err(e) = context.eval(Source::from_bytes(&source)) {
        eprintln!("{e}");
        std::process::exit(1);
    }
}
