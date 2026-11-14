mod icons;
mod motion;
mod release;
mod text;

use leptos::mount::mount_to_body;
use leptos::prelude::*;
use leptos::task::spawn_local;
use release::{Os, Release};
use text::{ALTSTORE_SOURCE, Lang, Text};

const REPO: &str = "https://github.com/0x696c757a696f/lumtub";
const RELEASES: &str = "https://github.com/0x696c757a696f/lumtub/releases/latest";
const SPONSORS: &str = "https://github.com/sponsors/0x696c757a696f";
const AFDIAN: &str = "https://afdian.com/a/linmuqingfeng";
const KOFI: &str = "https://ko-fi.com/0x696c757a696f";
const WEBLATE: &str = "https://hosted.weblate.org/engage/lumtub/";
const SECTIONS: [&str; 5] = ["features", "download", "privacy", "faq", "support"];

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
    std::panic::set_hook(Box::new(|info| console_error(&info.to_string())));
    mount_to_body(App);
}

#[wasm_bindgen::prelude::wasm_bindgen]
extern "C" {
    #[wasm_bindgen::prelude::wasm_bindgen(js_namespace = console, js_name = error)]
    fn console_error(s: &str);
}

fn icon(name: &'static str, size: u32) -> impl IntoView {
    view! {
        <svg class="icon" viewBox="0 0 256 256" width=size height=size fill="currentColor" aria-hidden="true" inner_html=icons::body(name)></svg>
    }
}

fn os_icon(platform: &str) -> &'static str {
    match platform {
        "Windows" => "windows-logo",
        "macOS" | "iOS" => "apple-logo",
        "Linux" => "linux-logo",
        _ => "android-logo",
    }
}

#[derive(Clone, Copy)]
struct Ctx {
    release: RwSignal<Option<Release>>,
    os: Os,
}

impl Ctx {
    fn link(self, suffix: &'static str) -> impl Fn() -> String + Copy {
        move || {
            self.release
                .get()
                .and_then(|r| r.asset(suffix))
                .unwrap_or_else(|| RELEASES.to_string())
        }
    }
}

#[component]
fn App() -> impl IntoView {
    let lang = RwSignal::new(initial_lang());
    let menu = RwSignal::new(false);
    let active = RwSignal::new(String::new());
    let ctx = Ctx { release: RwSignal::new(None), os: Os::detect() };

    spawn_local(async move {
        if let Some(r) = Release::fetch().await {
            ctx.release.set(Some(r));
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
        request_animation_frame(move || motion::observe(active));
    });

    Effect::new(move |_| {
        let open = menu.get();
        if let Some(body) = web_sys::window().and_then(|w| w.document()).and_then(|d| d.body()) {
            let _ = body.class_list().toggle_with_force("menu-open", open);
        }
    });

    let toggle_lang = move |_| {
        let next = if lang.get_untracked() == Lang::En { Lang::Zh } else { Lang::En };
        if let Some(s) = storage() {
            let _ = s.set_item("lang", next.code());
        }
        menu.set(false);
        lang.set(next);
    };

    move || {
        let l = lang.get();
        let t = l.text();
        let links = move |mobile: bool| {
            SECTIONS
                .iter()
                .zip(t.nav)
                .enumerate()
                .map(|(i, (id, label))| {
                    let href = format!("#{id}");
                    view! {
                        <a
                            href=href
                            class:current=move || active.get() == *id
                            style=move || mobile.then(|| format!("--i:{i}"))
                            on:click=move |_| menu.set(false)
                        >
                            {label}
                        </a>
                    }
                })
                .collect_view()
        };
        view! {
            <a class="skip" href="#main">{t.skip}</a>
            <header class="nav-wrap">
                <nav class="nav" aria-label="Lumtub">
                    <a class="brand" href="#top" on:click=move |_| menu.set(false)>
                        <img src="icon.png" alt="" width="24" height="24"/>
                        <span>"Lumtub"</span>
                    </a>
                    <div class="nav-links">{links(false)}</div>
                    <div class="nav-actions">
                        <button class="ghost lang" on:click=toggle_lang>
                            {icon("translate", 16)}
                            <span>{t.other_lang}</span>
                        </button>
                        <a class="ghost square" href=REPO aria-label="GitHub">{icon("github-logo", 20)}</a>
                        <a class="btn primary small nav-cta" href="#download">{t.nav_download}</a>
                        <button
                            class="burger"
                            class:open=move || menu.get()
                            aria-label=t.menu
                            aria-expanded=move || menu.get().to_string()
                            on:click=move |_| menu.update(|m| *m = !*m)
                        >
                            <span></span>
                            <span></span>
                        </button>
                    </div>
                </nav>
            </header>
            <div class="menu-panel" class:open=move || menu.get() aria-hidden=move || (!menu.get()).to_string()>
                <div class="menu-links">{links(true)}</div>
            </div>
            <main id="main">
                <Hero t=t ctx=ctx/>
                <Highlights t=t lang=l/>
                <Tagline lang=l/>
                <Steps t=t/>
                <Features t=t/>
                <Download t=t ctx=ctx/>
                <Privacy t=t/>
                <Faq t=t/>
                <Final t=t ctx=ctx/>
                <Support t=t lang=l/>
            </main>
            <footer class="footer">
                <div class="wrap footer-inner">
                    <div class="brand muted">
                        <img src="icon.png" alt="" width="20" height="20"/>
                        <span>"Lumtub"</span>
                    </div>
                    <p class="caption-2">{t.footer}</p>
                    <p class="caption-2 footer-links">
                        <a href=REPO>{t.footer_links[0]}</a>
                        <a href=format!("{REPO}/issues")>{t.footer_links[1]}</a>
                        <a href=WEBLATE>{t.footer_links[2]}</a>
                        <a href=format!("{REPO}#privacy-what-stays-local-and-what-doesnt")>{t.footer_links[3]}</a>
                    </p>
                </div>
            </footer>
        }
    }
}

fn primary_button(t: &'static Text, ctx: Ctx, large: bool) -> impl IntoView {
    let (label, href): (&'static str, Box<dyn Fn() -> String + Send + Sync>) = match ctx.os.index() {
        Some(i) => {
            let suffix = ctx.os.suffix();
            (t.download_for[i], Box::new(ctx.link(suffix)))
        }
        None => (t.nav_download, Box::new(|| "#download".to_string())),
    };
    view! {
        <a class="btn primary" class:large=large href=href>
            {icon("download-simple", 20)}
            <span>{label}</span>
        </a>
    }
}

#[component]
fn Hero(t: &'static Text, ctx: Ctx) -> impl IntoView {
    let intel = (ctx.os == Os::Mac).then(|| {
        view! { <a class="text-link" href=ctx.link("macos-x64.dmg")>{t.mac_intel}</a> }
    });
    let version = move || {
        ctx.release
            .get()
            .map(|r| format!("{} {}", t.latest, r.version))
    };
    view! {
        <section class="hero" id="top">
            <div class="wrap hero-inner">
                <img class="hero-icon" src="icon.png" alt="" width="80" height="80"/>
                <h1 class="heading-1 gradient">
                    <span>{t.hero_title[0]}</span>
                    " "
                    <br/>
                    <span>{t.hero_title[1]}</span>
                </h1>
                <p class="lead body-lead">{t.hero_body}</p>
                <div class="cta">
                    {primary_button(t, ctx, true)}
                </div>
                <p class="cta-sub caption-2">
                    {version}
                    {intel}
                    <a class="text-link" href="#download">{t.other_systems}</a>
                </p>
                {(ctx.os == Os::Ios).then(|| view! { <p class="note caption-2">{t.ios_note}</p> })}
                <ul class="proof">
                    {t.proof.iter().map(|p| view! { <li class="caption-1">{icon("check", 16)}{*p}</li> }).collect_view()}
                </ul>
                <div class="hero-shot reveal">
                    <img src=shot(Lang::En, "watch.png") alt="Lumtub playing a video, with Up next beside it" width="1280" height="720" fetchpriority="high"/>
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
                <header class="section-head reveal">
                    <h2 class="heading-3">{t.why_title}</h2>
                    <p class="body-3 muted">{t.why_lead}</p>
                </header>
                {t.highlights.iter().enumerate().map(|(i, h)| {
                    let media = if i == t.highlights.len() - 1 {
                        view! {
                            <div class="skins">
                                <figure class="wide"><img loading="lazy" src=shot(lang, "skin-aero.png") alt=t.skins_caption[0] width="1266" height="793"/><figcaption class="caption-1">{t.skins_caption[0]}</figcaption></figure>
                                <figure><img loading="lazy" src=shot(lang, "skin-player.png") alt=t.skins_caption[1] width="1266" height="793"/><figcaption class="caption-1">{t.skins_caption[1]}</figcaption></figure>
                                <figure><img loading="lazy" src=shot(lang, "skin-onebit.png") alt=t.skins_caption[2] width="1266" height="793"/><figcaption class="caption-1">{t.skins_caption[2]}</figcaption></figure>
                                <figure class="wide azure">
                                    <img loading="lazy" src="img/azure-day.webp" alt=t.skins_caption[3] width="1200" height="675"/>
                                    <img loading="lazy" class="night" src="img/azure-night.webp" alt="" width="1200" height="675"/>
                                    <figcaption class="caption-1">{t.skins_caption[3]}</figcaption>
                                </figure>
                            </div>
                        }.into_any()
                    } else {
                        let (w, hgt) = dims(h.shot);
                        view! {
                            <img class="shot" loading="lazy" src=shot(lang, h.shot) alt=h.alt width=w height=hgt/>
                        }.into_any()
                    };
                    view! {
                        <article class="highlight reveal" class:flip=i % 2 == 1>
                            <div class="hl-text">
                                <span class="index caption-3">{format!("0{}", i + 1)}</span>
                                <h3 class="heading-5">{h.title}</h3>
                                <p class="body-3 muted">{h.body}</p>
                            </div>
                            {media}
                        </article>
                    }
                }).collect_view()}
            </div>
        </section>
    }
}

#[component]
fn Tagline(lang: Lang) -> impl IntoView {
    let words = lang.tagline_words();
    let sep = if lang == Lang::En { " " } else { "" };
    let count = words.len();
    view! {
        <section class="tagline">
            <div class="wrap">
                <p class="heading-2 tagline-text" class:cjk=lang == Lang::Zh>
                    {words.into_iter().enumerate().map(|(i, w)| view! {
                        <span class="word">{w}</span>
                        {(i + 1 < count).then(|| sep)}
                    }).collect_view()}
                </p>
            </div>
        </section>
    }
}

#[component]
fn Steps(t: &'static Text) -> impl IntoView {
    let icons = ["download-simple", "export", "sparkle"];
    view! {
        <section class="section">
            <div class="wrap">
                <header class="section-head reveal">
                    <h2 class="heading-3">{t.steps_title}</h2>
                </header>
                <ol class="steps">
                    {t.steps.iter().zip(icons).enumerate().map(|(i, ((title, body), ic))| view! {
                        <li class="step reveal">
                            <div class="step-top">
                                <span class="step-n caption-3">{format!("{}", i + 1)}</span>
                                <span class="step-icon">{icon(ic, 24)}</span>
                            </div>
                            <h3 class="title-1">{*title}</h3>
                            <p class="body-6 muted">{*body}</p>
                        </li>
                    }).collect_view()}
                </ol>
            </div>
        </section>
    }
}

#[component]
fn Features(t: &'static Text) -> impl IntoView {
    view! {
        <section class="section alt">
            <div class="wrap">
                <header class="section-head reveal">
                    <h2 class="heading-3">{t.features_title}</h2>
                </header>
                <div class="grid reveal">
                    {t.features.iter().map(|f| view! {
                        <div class="card">
                            <span class="card-icon">{icon(f.icon, 24)}</span>
                            <h3 class="title-2">{f.title}</h3>
                            <p class="body-6 muted">{f.body}</p>
                        </div>
                    }).collect_view()}
                </div>
            </div>
        </section>
    }
}

#[component]
fn Download(t: &'static Text, ctx: Ctx) -> impl IntoView {
    let shots = [("windows.png", "Windows"), ("macos.png", "macOS"), ("linux.png", "Linux")];
    let copied = RwSignal::new(false);
    let copy = move |_| {
        if let Some(w) = web_sys::window() {
            let _ = w.navigator().clipboard().write_text(ALTSTORE_SOURCE);
            copied.set(true);
            set_timeout(move || copied.set(false), std::time::Duration::from_millis(1600));
        }
    };
    view! {
        <section id="download" class="section">
            <div class="wrap">
                <header class="section-head reveal">
                    <h2 class="heading-3">{t.platforms_title}</h2>
                    <p class="body-3 muted">{t.platforms_body}</p>
                </header>
                <div class="platforms reveal">
                    {shots.iter().map(|(s, name)| {
                        let (w, h) = dims(s);
                        view! {
                            <figure>
                                <img loading="lazy" src=shot(Lang::En, s) alt=*name width=w height=h/>
                                <figcaption class="caption-1">{*name}</figcaption>
                            </figure>
                        }
                    }).collect_view()}
                </div>
                <div class="table reveal">
                    <div class="row head caption-3">
                        <span>{t.table_head[0]}</span>
                        <span>{t.table_head[1]}</span>
                    </div>
                    {t.packages.iter().map(|p| {
                        let href: Box<dyn Fn() -> String + Send + Sync> = if p.suffix == "altstore-source.json" {
                            Box::new(|| ALTSTORE_SOURCE.to_string())
                        } else {
                            Box::new(ctx.link(p.suffix))
                        };
                        view! {
                            <a class="row" href=href>
                                <span class="pkg title-3">
                                    <span class="os">{icon(os_icon(p.platform), 18)}</span>
                                    {p.label}
                                </span>
                                <span class="for body-6 muted">{p.note}</span>
                                <span class="arrow">{icon("download-simple", 18)}</span>
                            </a>
                        }
                    }).collect_view()}
                </div>
                <div class="notes reveal">
                    {t.install_notes.iter().map(|(os, note)| view! {
                        <div class="note-card">
                            <h4 class="title-3">{*os}</h4>
                            <p class="body-6 muted">{*note}</p>
                        </div>
                    }).collect_view()}
                    <div class="note-card source">
                        <h4 class="title-3">{t.altstore_label}</h4>
                        <div class="copy-row">
                            <code class="caption-2">{ALTSTORE_SOURCE}</code>
                            <button class="btn small" on:click=copy>
                                {move || if copied.get() { icon("check", 16).into_any() } else { icon("export", 16).into_any() }}
                                <span>{move || if copied.get() { t.copied } else { t.copy }}</span>
                            </button>
                        </div>
                    </div>
                </div>
                <p class="center"><a class="text-link" href=RELEASES>{t.all_releases}{icon("arrow-right", 16)}</a></p>
            </div>
        </section>
    }
}

#[component]
fn Privacy(t: &'static Text) -> impl IntoView {
    view! {
        <section id="privacy" class="section alt">
            <div class="wrap">
                <header class="section-head reveal">
                    <h2 class="heading-3">{t.privacy_title}</h2>
                    <p class="body-3 muted">{t.privacy_body}</p>
                </header>
                <div class="two reveal">
                    <div class="card">
                        <h3 class="title-2">{icon("shield-check", 20)}{t.stays_title}</h3>
                        <ul class="list">{t.stays.iter().map(|s| view! { <li class="body-6">{icon("check", 16)}<span>{*s}</span></li> }).collect_view()}</ul>
                    </div>
                    <div class="card">
                        <h3 class="title-2">{icon("arrow-up-right", 20)}{t.leaves_title}</h3>
                        <ul class="list out">{t.leaves.iter().map(|s| view! { <li class="body-6">{icon("arrow-up-right", 16)}<span>{*s}</span></li> }).collect_view()}</ul>
                    </div>
                </div>
                <p class="center">
                    <a class="text-link" href=format!("{REPO}#privacy-what-stays-local-and-what-doesnt")>{t.privacy_more}{icon("arrow-right", 16)}</a>
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
                <header class="section-head reveal">
                    <h2 class="heading-3">{t.faq_title}</h2>
                </header>
                <div class="faq reveal">
                    {t.faq.iter().map(|(q, a)| view! {
                        <details>
                            <summary class="title-2">{*q}<span class="chev">{icon("caret-down", 20)}</span></summary>
                            <p class="body-3 muted">{*a}</p>
                        </details>
                    }).collect_view()}
                </div>
            </div>
        </section>
    }
}

#[component]
fn Final(t: &'static Text, ctx: Ctx) -> impl IntoView {
    view! {
        <section class="section final">
            <div class="wrap center reveal">
                <img src="icon.png" alt="" width="64" height="64" class="final-icon"/>
                <h2 class="heading-3 gradient">{t.final_title}</h2>
                <p class="body-3 muted">{t.final_body}</p>
                <div class="cta">{primary_button(t, ctx, true)}</div>
                <p class="cta-sub caption-2"><a class="text-link" href="#download">{t.other_systems}</a></p>
            </div>
        </section>
    }
}

#[component]
fn Support(t: &'static Text, lang: Lang) -> impl IntoView {
    let sponsor = view! { <a class="btn" href=SPONSORS>{icon("heart", 18)}<span>{t.sponsor}</span></a> };
    let afdian = view! { <a class="btn" href=AFDIAN>{icon("lightning", 18)}<span>{t.afdian}</span></a> };
    let kofi = view! { <a class="btn" href=KOFI>{icon("coffee", 18)}<span>{t.kofi}</span></a> };
    let buttons = if lang == Lang::Zh {
        view! { {afdian}{sponsor}{kofi} }.into_any()
    } else {
        view! { {sponsor}{kofi}{afdian} }.into_any()
    };
    view! {
        <section id="support" class="section alt">
            <div class="wrap narrow center reveal">
                <h2 class="heading-4">{t.support_title}</h2>
                <p class="body-3 muted">{t.support_body}</p>
                <div class="cta support-buttons">{buttons}</div>
                <p class="links caption-2">
                    <a class="text-link" href=format!("{REPO}/blob/main/SPONSORING.md")>{t.other_ways}</a>
                    <a class="text-link" href=REPO>{icon("star", 16)}{t.star}</a>
                </p>
            </div>
        </section>
    }
}
