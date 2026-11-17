mod icons;
mod motion;
mod jsonc;
mod release;
mod skins;
mod text;

use leptos::mount::mount_to_body;
use leptos::prelude::*;
use leptos::task::spawn_local;
use release::{Os, Release};
use skins::{SkinPreview, SkinState};
use text::{ALTSTORE_SOURCE, Lang, Text};

const REPO: &str = "https://github.com/0x696c757a696f/lumtub";
const RELEASES: &str = "https://github.com/0x696c757a696f/lumtub/releases/latest";
const SPONSORS: &str = "https://github.com/sponsors/0x696c757a696f";
const AFDIAN: &str = "https://afdian.com/a/linmuqingfeng";
const KOFI: &str = "https://ko-fi.com/0x696c757a696f";
const WEBLATE: &str = "https://hosted.weblate.org/engage/lumtub/";
const SECTIONS: [&str; 5] = ["features", "download", "privacy", "faq", "support"];

const ZH_SHOTS: [&str; 9] = [
    "watch.png",
    "windows.png",
    "macos.png",
    "linux.png",
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
    [from_query, saved, browser].into_iter().flatten().find_map(|c| Lang::from_code(&c)).unwrap_or(Lang::En)
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
    let skin = SkinState::new();

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

    let pick_lang = move |ev: leptos::ev::Event| {
        let Some(next) = Lang::from_code(&event_target_value(&ev)) else { return };
        if let Some(s) = storage() {
            let _ = s.set_item("lang", next.code());
        }
        menu.set(false);
        // A fresh load in the new language, so nothing on the page (or a
        // browser's own page translation) is left over from the old one.
        if let Some(w) = web_sys::window() {
            let loc = w.location();
            let hash = loc.hash().unwrap_or_default();
            let path = loc.pathname().unwrap_or_default();
            if loc.replace(&format!("{path}?lang={}{hash}", next.code())).is_ok() {
                return;
            }
        }
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
                        <label class="ghost lang">
                            {icon("translate", 16)}
                            <span>{t.lang_name}</span>
                            <select aria-label="Language" on:change=pick_lang>
                                {Lang::ALL.into_iter().map(|o| view! {
                                    <option value=o.code() selected=o == l>{o.text().lang_name}</option>
                                }).collect_view()}
                            </select>
                        </label>
                        <a class="ghost square" href=REPO aria-label="GitHub">{icon("github-logo", 20)}</a>
                        <a class="ghost square nav-heart" href="#support" aria-label=t.support_eyebrow>{icon("heart", 20)}</a>
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
                <Hero t=t ctx=ctx lang=l/>
                <Highlights t=t lang=l skin=skin/>
                <Tagline lang=l/>
                <Steps t=t/>
                <Features t=t/>
                <Download t=t ctx=ctx lang=l/>
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
fn Hero(t: &'static Text, ctx: Ctx, lang: Lang) -> impl IntoView {
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
                    <img src=shot(lang, "watch.png") alt=t.hero_alt width="1280" height="720" fetchpriority="high"/>
                </div>
            </div>
        </section>
    }
}

#[component]
fn Highlights(t: &'static Text, lang: Lang, skin: SkinState) -> impl IntoView {
    view! {
        <section id="features" class="section">
            <div class="wrap">
                <header class="section-head reveal">
                    <h2 class="heading-3">{t.why_title}</h2>
                    <p class="body-3 muted">{t.why_lead}</p>
                </header>
                {t.highlights.iter().enumerate().map(|(i, h)| {
                    let last = i == t.highlights.len() - 1;
                    let media = if last {
                        view! { <SkinPreview t=t lang=lang state=skin/> }.into_any()
                    } else {
                        let (w, hgt) = dims(h.shot);
                        view! {
                            <img class="shot" loading="lazy" src=shot(lang, h.shot) alt=h.alt width=w height=hgt/>
                        }.into_any()
                    };
                    view! {
                        <article class="highlight reveal" class:flip=i % 2 == 1 && !last class:stack=last>
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
    let sep = if lang.cjk() { "" } else { " " };
    let count = words.len();
    view! {
        <section class="tagline">
            <div class="wrap">
                <p class="heading-2 tagline-text" class:cjk=lang.cjk()>
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
fn Download(t: &'static Text, ctx: Ctx, lang: Lang) -> impl IntoView {
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
                                <img loading="lazy" src=shot(lang, s) alt=*name width=w height=h/>
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

const GITHUB_MARK: &str = "M17.625 1.499c-2.32 0-4.354 1.203-5.625 3.03-1.271-1.827-3.305-3.03-5.625-3.03C3.129 1.499 0 4.253 0 8.249c0 4.275 3.068 7.847 5.828 10.227a33.14 33.14 0 0 0 5.616 3.876l.028.017.008.003-.001.003c.163.085.342.126.521.125.179.001.358-.041.521-.125l-.001-.003.008-.003.028-.017a33.14 33.14 0 0 0 5.616-3.876C20.932 16.096 24 12.524 24 8.249c0-3.996-3.129-6.75-6.375-6.75zm-.919 15.275a30.766 30.766 0 0 1-4.703 3.316l-.004-.002-.004.002a30.955 30.955 0 0 1-4.703-3.316c-2.677-2.307-5.047-5.298-5.047-8.523 0-2.754 2.121-4.5 4.125-4.5 2.06 0 3.914 1.479 4.544 3.684.143.495.596.797 1.086.796.49.001.943-.302 1.085-.796.63-2.205 2.484-3.684 4.544-3.684 2.004 0 4.125 1.746 4.125 4.5 0 3.225-2.37 6.216-5.048 8.523z";
const KOFI_MARK: &str = "M11.351 2.715c-2.7 0-4.986.025-6.83.26C2.078 3.285 0 5.154 0 8.61c0 3.506.182 6.13 1.585 8.493 1.584 2.701 4.233 4.182 7.662 4.182h.83c4.209 0 6.494-2.234 7.637-4a9.5 9.5 0 0 0 1.091-2.338C21.792 14.688 24 12.22 24 9.208v-.415c0-3.247-2.13-5.507-5.792-5.87-1.558-.156-2.65-.208-6.857-.208m0 1.947c4.208 0 5.09.052 6.571.182 2.624.311 4.13 1.584 4.13 4v.39c0 2.156-1.792 3.844-3.87 3.844h-.935l-.156.649c-.208 1.013-.597 1.818-1.039 2.546-.909 1.428-2.545 3.064-5.922 3.064h-.805c-2.571 0-4.831-.883-6.078-3.195-1.09-2-1.298-4.155-1.298-7.506 0-2.181.857-3.402 3.012-3.714 1.533-.233 3.559-.26 6.39-.26m6.547 2.287c-.416 0-.65.234-.65.546v2.935c0 .311.234.545.65.545 1.324 0 2.051-.754 2.051-2s-.727-2.026-2.052-2.026m-10.39.182c-1.818 0-3.013 1.48-3.013 3.142 0 1.533.858 2.857 1.949 3.897.727.701 1.87 1.429 2.649 1.896a1.47 1.47 0 0 0 1.507 0c.78-.467 1.922-1.195 2.623-1.896 1.117-1.039 1.974-2.364 1.974-3.897 0-1.662-1.247-3.142-3.039-3.142-1.065 0-1.792.545-2.338 1.298-.493-.753-1.246-1.298-2.312-1.298";
const AFDIAN_MARK: &str = "M9 14.234a.567.567 0 1 0 0 1.134.567.567 0 0 0 0-1.134m5.351 1.705a.567.567 0 1 0 0 1.135.567.567 0 0 0 0-1.135M24 12.25c0 6.627-5.373 12-12 12s-12-5.373-12-12 5.373-12 12-12 12 5.373 12 12m-5.68-.708c.236-.46.367-.996.367-1.565 0-1.789-1.29-3.239-2.88-3.239-.893 0-1.692.457-2.22 1.175l-.008-.01-.017.025-.006.007-2.373 3.293c-1.53-1.135-3.592-1.598-5.693-1.104-1.95.459-3.519 1.682-4.383 3.247a.57.57 0 0 0 .249.79l.008.003a.58.58 0 0 0 .769-.245c.71-1.282 2.004-2.284 3.613-2.663 1.808-.426 3.578.006 4.837.99.032.03.069.056.11.075a.56.56 0 0 0 .72-.155l.003-.003 2.734-3.796c.312-.425.775-.705 1.288-.705.903 0 1.635.877 1.635 1.958 0 .493-.153.943-.403 1.287a.5.5 0 0 0 .087.672l.016.012a.5.5 0 0 0 .67-.081 3 3 0 0 0 .19-.25 3.4 3.4 0 0 1 .617 1.48c.226 1.648-.958 3.215-2.665 3.63l-.04.01c-.043.012-.088.02-.132.026l-1.168.198a.577.577 0 0 0-.465.656.58.58 0 0 0 .67.454l1.164-.198c.06-.008.12-.02.18-.034l.09-.02c2.293-.556 3.851-2.656 3.552-4.837a4.6 4.6 0 0 0-1.003-2.307z";

fn give(class: &'static str, href: &'static str, mark: &'static str, name: &'static str, note: &'static str) -> impl IntoView {
    view! {
        <a class=format!("give {class}") href=href>
            <svg class="give-mark" viewBox="0 0 24 24" width="32" height="32" fill="currentColor" aria-hidden="true">
                <path d=mark></path>
            </svg>
            <span class="give-text">
                <span class="give-name">{name}</span>
                <span class="give-note">{note}</span>
            </span>
        </a>
    }
}

#[component]
fn Support(t: &'static Text, lang: Lang) -> impl IntoView {
    let sponsor = give("github", SPONSORS, GITHUB_MARK, t.sponsor, t.sponsor_note);
    let afdian = give("afdian", AFDIAN, AFDIAN_MARK, t.afdian, t.afdian_note);
    let kofi = give("kofi", KOFI, KOFI_MARK, t.kofi, t.kofi_note);
    let buttons = match lang {
        Lang::Zh => view! { {afdian}{sponsor}{kofi} }.into_any(),
        Lang::En => view! { {sponsor}{kofi}{afdian} }.into_any(),
        _ => view! { {kofi}{sponsor}{afdian} }.into_any(),
    };
    let goals = t.goals.iter().map(|g| view! { <li>{*g}</li> }).collect_view();
    view! {
        <section id="support" class="section alt">
            <div class="wrap reveal">
                <div class="support-card">
                    <div class="aurora" aria-hidden="true">
                        <span></span>
                        <span></span>
                        <span></span>
                    </div>
                    <div class="hearts" aria-hidden="true">
                        <i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i>
                    </div>
                    <div class="support-body">
                        <div class="support-icon" aria-hidden="true">
                            <img src="icon.png" alt="" width="128" height="128"/>
                            <span class="support-heart">
                                <svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor">
                                    <path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"></path>
                                </svg>
                            </span>
                        </div>
                        <div class="support-text">
                            <p class="eyebrow"><span class="pulse-dot"></span>{t.support_eyebrow}</p>
                            <h2 class="support-title">{t.support_title}</h2>
                            <p class="support-lead">{t.support_body}</p>
                            <div class="goals">
                                <span class="goals-label">{t.goals_label}</span>
                                <ul>{goals}</ul>
                            </div>
                        </div>
                    </div>
                    <div class="give-row">{buttons}</div>
                </div>
                <p class="links caption-2">
                    <a class="text-link" href=format!("{REPO}/blob/main/SPONSORING.md")>{t.other_ways}</a>
                    <a class="text-link" href=REPO>{icon("star", 16)}{t.star}</a>
                </p>
            </div>
        </section>
    }
}
