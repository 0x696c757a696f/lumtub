use rquickjs::{Context, Function, Object, Runtime};

fn main() {
    let path = std::env::args().nth(1).expect("script path");
    let source = std::fs::read_to_string(path).expect("read script");
    let runtime = Runtime::new().unwrap();
    runtime.set_max_stack_size(64 * 1024 * 1024);
    let context = Context::full(&runtime).unwrap();
    context.with(|ctx| {
        let console = Object::new(ctx.clone()).unwrap();
        console
            .set("log", Function::new(ctx.clone(), |text: String| println!("{text}")).unwrap())
            .unwrap();
        ctx.globals().set("console", console).unwrap();
        if let Err(e) = ctx.eval::<(), _>(source) {
            let detail = ctx.catch();
            eprintln!("{e}: {detail:?}");
            std::process::exit(1);
        }
    });
}
