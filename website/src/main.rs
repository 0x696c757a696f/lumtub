mod release;
mod text;

use leptos::mount::mount_to_body;
use leptos::prelude::*;
use leptos::task::spawn_local;
use release::{Os, Release};
use text::{Lang, Text};

const REPO: &str = "https://github.com/0x696c757a696f/lumtub";
const RELEASES: &str = "https://github.com/0x696c757a696f/lumtub/releases/latest";
const SPONSORS: &str = "https://github.com/sponsors/0x696c757a696f";
const AFDIAN: &str = "https://afdian.com/a/linmuqingfeng";

const ZH_SHOTS: [&str; 5] = [
    "home-reasons.png",
    "subtitles.jpg",
    "explore-language.png",
    "skin-aero.png",
    "skin-player.png",
];

fn shot(lang: Lang, name: &str) -> String {
    if lang == Lang::Zh && ZH_SHOTS.contains(&name) {
        format!("screenshots/zh/{name}")
    } else {
        format!("screenshots/{name}")
    }
}

fn dims(name: &str) -> (u32, u32) {
    match name {
        "watch.png" | "home-reasons.png" | "linux.png" | "search.png" | "explore-language.png" => (1280, 720),
        "macos.png" => (1052, 737),
        "danmaku.jpg" => (1646, 926),
        "subtitles.jpg" => (1450, 816),
        _ => (1266, 793),
    }
}

fn storage() -> Option<web_sys::Storage> {
    web_sys::window()?.local_storage().ok().flatten()
}

fn initial_lang() -> Lang {
    let window = web_sys::window();
    let from_query = window
        .as_ref()
        .and_then(|w| w.location().search().ok())
        .and_then(|s| web_sys::UrlSearchParams::new_with_str(&s).ok())
        .and_then(|p| p.get("lang"));
    let saved = storage().and_then(|s| s.get_item("lang").ok().flatten());
    let browser = window.and_then(|w| w.navigator().language());
    let pick = from_query.or(saved).or(browser).unwrap_or_default();
    if pick.to_lowercase().starts_with("zh") {
        Lang::Zh
    } else {
        Lang::En
    }
}

fn main() {
    console_error_panic_hook();
    mount_to_body(App);
}

fn console_error_panic_hook() {
    std::panic::set_hook(Box::new(|info| {
        web_sys_log(&info.to_string());
    }));
}

#[wasm_bindgen::prelude::wasm_bindgen]
extern "C" {
    #[wasm_bindgen::prelude::wasm_bindgen(js_namespace = console, js_name = error)]
    fn web_sys_log(s: &str);
}

#[component]
fn App() -> impl IntoView {
    let lang = RwSignal::new(initial_lang());
    let release = RwSignal::new(None::<Release>);
    let os = Os::detect();

    spawn_local(async move {
        if let Some(r) = Release::fetch().await {
            release.set(Some(r));
        }
    });

    Effect::new(move |_| {
        let l = lang.get();
        if let Some(doc) = web_sys::window().and_then(|w| w.document()) {
            doc.set_title(l.text().title);
            if let Some(root) = doc.document_element() {
                let _ = root.set_attribute("lang", l.code());
            }
        }
    });

    let toggle = move |_| {
        let next = if lang.get_untracked() == Lang::En { Lang::Zh } else { Lang::En };
        if let Some(s) = storage() {
            let _ = s.set_item("lang", next.code());
        }
        lang.set(next);
    };

    move || {
        let l = lang.get();
        let t = l.text();
        view! {
            <header class="nav">
                <div class="wrap nav-inner">
                    <a class="brand" href="#top">
                        <img src="icon.png" alt="" width="28" height="28"/>
                        <span>"Lumtub"</span>
                    </a>
                    <nav class="nav-links">
                        <a href="#features">{t.nav[0]}</a>
                        <a href="#download">{t.nav[1]}</a>
                        <a href="#privacy">{t.nav[2]}</a>
                        <a href="#faq">{t.nav[3]}</a>
                        <a href="#support">{t.nav[4]}</a>
                    </nav>
                    <div class="nav-actions">
                        <button class="lang" on:click=toggle aria-label="Language">{t.other_lang}</button>
                        <a class="gh" href=REPO aria-label="GitHub">{github_icon()}</a>
                    </div>
                </div>
            </header>
            <main id="top">
                <Hero t=t os=os release=release/>
                <Highlights t=t lang=l/>
                <Features t=t/>
                <Download t=t release=release/>
                <Privacy t=t/>
                <Faq t=t/>
                <Support t=t lang=l/>
            </main>
            <footer class="footer">
                <div class="wrap">
                    <p>{t.footer}</p>
                    <p>
                        <a href=REPO>"GitHub"</a>" · "
                        <a href=format!("{REPO}/issues")>"Issues"</a>" · "
                        <a href="https://hosted.weblate.org/engage/lumtub/">"Weblate"</a>
                    </p>
                </div>
            </footer>
        }
    }
}

#[component]
fn Hero(t: &'static Text, os: Os, release: RwSignal<Option<Release>>) -> impl IntoView {
    let primary = move || {
        let r = release.get();
        let (label, href) = match os.index() {
            Some(i) => (
                t.download_for[i],
                r.as_ref()
                    .and_then(|r| r.asset(os.suffix()))
                    .unwrap_or_else(|| RELEASES.to_string()),
            ),
            None => (t.download_all, "#download".to_string()),
        };
        view! { <a class="btn primary" href=href>{download_icon()}{label}</a> }
    };
    let intel = move || {
        (os == Os::Mac).then(|| {
            let href = release
                .get()
                .and_then(|r| r.asset("macos-x64.dmg"))
                .unwrap_or_else(|| RELEASES.to_string());
            view! { <a class="sub-link" href=href>{t.mac_intel}</a> }
        })
    };
    let version = move || {
        release
            .get()
            .map(|r| format!("{} {} · ", t.latest, r.version))
            .unwrap_or_default()
    };
    view! {
        <section class="hero">
            <div class="wrap hero-inner">
                <img class="hero-icon" src="icon.png" alt="Lumtub" width="96" height="96"/>
                <h1>{t.hero_title}</h1>
                <p class="lead">{t.hero_body}</p>
                <div class="cta">
                    {primary}
                    <a class="btn" href="#download">{t.download_all}</a>
                </div>
                {intel}
                {(os == Os::Ios).then(|| view! { <p class="note">{t.ios}</p> })}
                <p class="meta">{version}{t.hero_meta}</p>
                <div class="hero-shot">
                    <img src=shot(Lang::En, "watch.png") alt="Lumtub playing a video" width="1280" height="720"/>
                </div>
            </div>
        </section>
    }
}

#[component]
fn Highlights(t: &'static Text, lang: Lang) -> impl IntoView {
    view! {
        <section id="features" class="section">
            <div class="wrap">
                <h2>{t.why_title}</h2>
                {t.highlights.iter().enumerate().map(|(i, h)| {
                    let skins = (i == t.highlights.len() - 1).then(|| view! {
                        <div class="skins">
                            <figure><img loading="lazy" src=shot(lang, "skin-aero.png") width="1266" height="793" alt=t.skins_caption[0]/><figcaption>{t.skins_caption[0]}</figcaption></figure>
                            <figure><img loading="lazy" src=shot(lang, "skin-player.png") width="1266" height="793" alt=t.skins_caption[1]/><figcaption>{t.skins_caption[1]}</figcaption></figure>
                            <figure><img loading="lazy" src=shot(lang, "skin-onebit.png") width="1266" height="793" alt=t.skins_caption[2]/><figcaption>{t.skins_caption[2]}</figcaption></figure>
                        </div>
                    });
                    view! {
                        <article class="highlight" class:flip=i % 2 == 1>
                            <div class="hl-text">
                                <h3>{h.title}</h3>
                                <p>{h.body}</p>
                            </div>
                            {match skins {
                                Some(s) => s.into_any(),
                                None => view! {
                                    <img class="shot" loading="lazy" src=shot(lang, h.shot) alt=h.alt width=dims(h.shot).0 height=dims(h.shot).1/>
                                }.into_any(),
                            }}
                        </article>
                    }
                }).collect_view()}
            </div>
        </section>
    }
}

#[component]
fn Features(t: &'static Text) -> impl IntoView {
    view! {
        <section class="section alt">
            <div class="wrap">
                <h2>{t.features_title}</h2>
                <div class="grid">
                    {t.features.iter().map(|f| view! {
                        <div class="card">
                            <div class="card-icon" aria-hidden="true">{f.icon}</div>
                            <h3>{f.title}</h3>
                            <p>{f.body}</p>
                        </div>
                    }).collect_view()}
                </div>
            </div>
        </section>
    }
}

#[component]
fn Download(t: &'static Text, release: RwSignal<Option<Release>>) -> impl IntoView {
    let shots = ["windows.png", "macos.png", "linux.png"];
    view! {
        <section id="download" class="section">
            <div class="wrap">
                <h2>{t.platforms_title}</h2>
                <p class="section-lead">{t.platforms_body}</p>
                <div class="platforms">
                    {shots.iter().zip(t.platform_shots).map(|(s, name)| view! {
                        <figure>
                            <img loading="lazy" src=shot(Lang::En, s) alt=name width=dims(s).0 height=dims(s).1/>
                            <figcaption>{name}</figcaption>
                        </figure>
                    }).collect_view()}
                </div>
                <div class="table">
                    <div class="row head">
                        <span>{t.table_head[0]}</span>
                        <span>{t.table_head[1]}</span>
                    </div>
                    {t.packages.iter().map(|p| {
                        let href = move || release
                            .get()
                            .and_then(|r| r.asset(p.suffix))
                            .unwrap_or_else(|| RELEASES.to_string());
                        view! {
                            <a class="row" href=href>
                                <span class="pkg">
                                    <span class="tag">{p.platform}</span>
                                    {p.label}
                                </span>
                                <span class="for">{p.note}</span>
                                <span class="arrow" aria-hidden="true">{download_icon()}</span>
                            </a>
                        }
                    }).collect_view()}
                </div>
                <div class="notes">
                    {t.install_notes.iter().map(|(os, note)| view! {
                        <div class="note-card"><h4>{*os}</h4><p>{*note}</p></div>
                    }).collect_view()}
                </div>
                <p class="center"><a class="sub-link" href=RELEASES>{t.download_all}" →"</a></p>
            </div>
        </section>
    }
}

#[component]
fn Privacy(t: &'static Text) -> impl IntoView {
    view! {
        <section id="privacy" class="section alt">
            <div class="wrap">
                <h2>{t.privacy_title}</h2>
                <p class="section-lead">{t.privacy_body}</p>
                <div class="two">
                    <div class="card">
                        <h3>{t.stays_title}</h3>
                        <ul class="check">{t.stays.iter().map(|s| view! { <li>{*s}</li> }).collect_view()}</ul>
                    </div>
                    <div class="card">
                        <h3>{t.leaves_title}</h3>
                        <ul class="out">{t.leaves.iter().map(|s| view! { <li>{*s}</li> }).collect_view()}</ul>
                    </div>
                </div>
                <p class="center">
                    <a class="sub-link" href=format!("{REPO}#privacy-what-stays-local-and-what-doesnt")>{t.privacy_more}" →"</a>
                </p>
            </div>
        </section>
    }
}

#[component]
fn Faq(t: &'static Text) -> impl IntoView {
    view! {
        <section id="faq" class="section">
            <div class="wrap narrow">
                <h2>{t.faq_title}</h2>
                {t.faq.iter().map(|(q, a)| view! {
                    <details>
                        <summary>{*q}</summary>
                        <p>{*a}</p>
                    </details>
                }).collect_view()}
            </div>
        </section>
    }
}

#[component]
fn Support(t: &'static Text, lang: Lang) -> impl IntoView {
    let sponsor = view! { <a class="btn primary" href=SPONSORS>"♥ "{t.sponsor}</a> };
    let afdian = view! { <a class="btn afdian" href=AFDIAN>"⚡ "{t.afdian}</a> };
    let buttons = if lang == Lang::Zh {
        view! { {afdian}{sponsor} }.into_any()
    } else {
        view! { {sponsor}{afdian} }.into_any()
    };
    view! {
        <section id="support" class="section alt">
            <div class="wrap narrow center">
                <h2>{t.support_title}</h2>
                <p class="section-lead">{t.support_body}</p>
                <div class="cta">{buttons}</div>
                <p class="links">
                    <a href=format!("{REPO}/blob/main/SPONSORING.md")>{t.other_ways}</a>" · "
                    <a href=REPO>"★ "{t.star}</a>" · "
                    <a href=REPO>{t.source}</a>
                </p>
            </div>
        </section>
    }
}

fn download_icon() -> impl IntoView {
    view! {
        <svg class="icon" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
            <path d="M12 3v12m0 0l-5-5m5 5l5-5M4 20h16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>
    }
}

fn github_icon() -> impl IntoView {
    view! {
        <svg viewBox="0 0 16 16" width="22" height="22" aria-hidden="true">
            <path fill="currentColor" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/>
        </svg>
    }
}
