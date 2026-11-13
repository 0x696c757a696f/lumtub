use std::cell::RefCell;

use leptos::prelude::*;
use wasm_bindgen::JsCast;
use wasm_bindgen::prelude::Closure;
use web_sys::{IntersectionObserver, IntersectionObserverEntry, IntersectionObserverInit};

thread_local! {
    static OBSERVERS: RefCell<Vec<IntersectionObserver>> = const { RefCell::new(Vec::new()) };
}

fn observer(margin: &str, threshold: f64, on: impl Fn(&IntersectionObserverEntry, &IntersectionObserver) + 'static) -> Option<IntersectionObserver> {
    let callback = Closure::<dyn FnMut(js_sys::Array, IntersectionObserver)>::new(move |entries: js_sys::Array, obs: IntersectionObserver| {
        for entry in entries.iter() {
            if let Ok(entry) = entry.dyn_into::<IntersectionObserverEntry>() {
                on(&entry, &obs);
            }
        }
    });
    let init = IntersectionObserverInit::new();
    init.set_root_margin(margin);
    init.set_threshold(&threshold.into());
    let obs = IntersectionObserver::new_with_options(callback.as_ref().unchecked_ref(), &init).ok()?;
    callback.forget();
    Some(obs)
}

fn each(selector: &str, mut f: impl FnMut(web_sys::Element)) {
    let Some(doc) = web_sys::window().and_then(|w| w.document()) else { return };
    let Ok(list) = doc.query_selector_all(selector) else { return };
    for i in 0..list.length() {
        if let Some(el) = list.item(i).and_then(|n| n.dyn_into::<web_sys::Element>().ok()) {
            f(el);
        }
    }
}

/// Reveals sections once as they scroll in, lights the tagline word by word
/// as it crosses a line two thirds down the window, and marks the nav link
/// of the section in view. Runs again after every full re-render.
pub fn observe(active: RwSignal<String>) {
    OBSERVERS.with(|o| {
        for obs in o.borrow_mut().drain(..) {
            obs.disconnect();
        }
    });

    let reveal = observer("0px 0px -10% 0px", 0.0, |entry, obs| {
        if entry.is_intersecting() {
            let target = entry.target();
            let _ = target.class_list().add_1("in");
            obs.unobserve(&target);
        }
    });

    let words = observer("0px 0px -33% 0px", 1.0, |entry, obs| {
        if entry.is_intersecting() {
            let target = entry.target();
            let _ = target.class_list().add_1("lit");
            obs.unobserve(&target);
        }
    });

    let sections = observer("-45% 0px -50% 0px", 0.0, move |entry, _| {
        if entry.is_intersecting() {
            active.set(entry.target().id());
        }
    });

    if let Some(obs) = &reveal {
        each(".reveal:not(.in)", |el| obs.observe(&el));
    }
    if let Some(obs) = &words {
        let mut i = 0;
        each(".word:not(.lit)", |el| {
            if let Some(html) = el.dyn_ref::<web_sys::HtmlElement>() {
                let _ = html.style().set_property("--d", &format!("{}ms", (i % 6) * 60));
            }
            i += 1;
            obs.observe(&el);
        });
    }
    if let Some(obs) = &sections {
        each("main section[id]", |el| obs.observe(&el));
    }

    OBSERVERS.with(|o| o.borrow_mut().extend([reveal, words, sections].into_iter().flatten()));
}
