// The live skin preview: a small Lumtub window drawn with HTML and CSS from
// the real skin files in skins/, which the site serves next to the page.
// It follows lib/skins/skin.dart closely enough to show each skin's look;
// decorations, the player and the glass slider are left out.

use std::cell::RefCell;
use std::collections::HashMap;
use std::fmt::Write;
use std::sync::Arc;

use leptos::prelude::*;
use leptos::task::spawn_local;
use serde_json::{Map, Value};

use crate::icons;
use crate::jsonc;
use crate::text::{Lang, Text};

pub struct SkinInfo {
    pub id: &'static str,
    pub names: &'static [(&'static str, &'static str)],
    pub en: &'static str,
    /// light, dark or auto (both sides).
    pub side: &'static str,
    pub scheme: bool,
    pub page: &'static str,
    pub dark_page: &'static str,
    pub accent: &'static str,
}

include!(concat!(env!("OUT_DIR"), "/skins.rs"));

const FIRST: &str = "aero";

thread_local! {
    static CACHE: RefCell<HashMap<&'static str, Arc<Value>>> = RefCell::new(HashMap::new());
}

#[derive(Clone, Copy)]
pub struct SkinState {
    id: RwSignal<&'static str>,
    dark: RwSignal<bool>,
    json: RwSignal<Option<(&'static str, Arc<Value>)>>,
    failed: RwSignal<bool>,
}

impl SkinState {
    pub fn new() -> Self {
        let dark = web_sys::window()
            .and_then(|w| w.match_media("(prefers-color-scheme: dark)").ok().flatten())
            .is_some_and(|m| m.matches());
        SkinState { id: RwSignal::new(FIRST), dark: RwSignal::new(dark), json: RwSignal::new(None), failed: RwSignal::new(false) }
    }

    fn load(self, id: &'static str) {
        if let Some(json) = CACHE.with(|c| c.borrow().get(id).cloned()) {
            self.json.set(Some((id, json)));
            return;
        }
        self.failed.set(false);
        spawn_local(async move {
            let url = format!("skins/{id}/skin.jsonc");
            let text = match gloo_net::http::Request::get(&url).send().await {
                Ok(r) if r.ok() => r.text().await.ok(),
                _ => None,
            };
            match text.and_then(|t| serde_json::from_str::<Value>(&jsonc::strip(&t)).ok()) {
                Some(json) => {
                    let json = Arc::new(json);
                    CACHE.with(|c| c.borrow_mut().insert(id, json.clone()));
                    if self.id.get_untracked() == id {
                        self.json.set(Some((id, json)));
                    }
                }
                None => {
                    if self.id.get_untracked() == id {
                        self.failed.set(true);
                    }
                }
            }
        });
    }
}

fn info(id: &str) -> &'static SkinInfo {
    SKINS.iter().find(|s| s.id == id).unwrap_or(&SKINS[0])
}

fn ic(name: &'static str) -> impl IntoView {
    view! { <svg class="lp-i" viewBox="0 0 256 256" fill="currentColor" aria-hidden="true" inner_html=icons::body(name)></svg> }
}

#[component]
pub fn SkinPreview(t: &'static Text, lang: Lang, state: SkinState) -> impl IntoView {
    Effect::new(move |_| state.load(state.id.get()));
    let look = Memo::new(move |_| {
        let id = state.id.get();
        let dark = state.dark.get();
        state.json.get().filter(|(j, _)| *j == id).map(|(_, json)| Look::build(&json, id, dark, lang))
    });
    let fixed = move || match info(state.id.get()).side {
        "auto" => None,
        side => Some(side == "dark"),
    };
    let m = &t.mock;
    let picker = move |scheme: bool| {
        SKINS
            .iter()
            .filter(move |s| s.scheme == scheme)
            .map(move |s| {
                let name = s.names.iter().find(|(c, _)| *c == lang.code()).map_or(s.en, |(_, n)| *n);
                let (page, night) = (s.page, if s.side == "auto" { s.dark_page } else { s.page });
                view! {
                    <button
                        class="sk-chip caption-1"
                        data-id=s.id
                        class:on=move || state.id.get() == s.id
                        aria-pressed=move || (state.id.get() == s.id).to_string()
                        on:click=move |_| state.id.set(s.id)
                    >
                        <span class="sk-dot" style=format!("--a:{page};--b:{night};--c:{}", s.accent)></span>
                        {name}
                    </button>
                }
            })
            .collect_view()
    };
    let menus = move |look: &Look| {
        let mut items: Vec<(&'static str, bool)> = Vec::new();
        if look.app_menu {
            items.push(("Lumtub", true));
        }
        items.extend(m.menus.iter().map(|s| (*s, false)));
        let underline = look.underline;
        view! {
            <div class="lp-menu">
                {items.into_iter().map(|(label, bold)| {
                    let (first, rest) = label.split_at(label.chars().next().map_or(0, char::len_utf8));
                    view! {
                        <span class="lp-mi" class:bold=bold>
                            {if underline && !lang.cjk() { view! { <u>{first.to_string()}</u> }.into_any() } else { first.to_string().into_any() }}
                            {rest.to_string()}
                        </span>
                    }
                }).collect_view()}
            </div>
        }
    };
    let window = move || {
        let look = look.get();
        let Some(look) = look else {
            return view! {
                <div class="lp-wait caption-1">{move || if state.failed.get() { t.skin_failed } else { t.skin_loading }}</div>
            }
            .into_any();
        };
        let title = look.title.then(|| {
            view! {
                <div class="lp-title" class:center=look.center>
                    {look.title_icon.then(|| view! { <span class="lp-ticon">{ic("play-circle")}</span> })}
                    <span class="lp-ttext">"Lumtub"</span>
                    {(look.menu == MenuAt::Title).then(|| menus(&look))}
                    <span class="lp-wb">
                        <span class="lp-b">{ic("minus")}</span>
                        <span class="lp-b">{ic("square")}</span>
                        <span class="lp-b close">{ic("x")}</span>
                    </span>
                </div>
            }
        });
        let menu = |at: MenuAt| (look.menu == at).then(|| view! { <div class="lp-menubar">{menus(&look)}</div> });
        view! {
            <style>{look.css.clone()}</style>
            <div class="lp" role="img" aria-label=look.label.clone()>
                {menu(MenuAt::Top)}
                {title}
                {menu(MenuAt::Below)}
                <div class="lp-top">
                    <span class="lp-logo">
                        <span class="lp-badge">{ic("play-circle")}</span>
                        <span class="lp-word">{look.logo.clone()}</span>
                    </span>
                    <span class="lp-search">{ic("magnifying-glass")}<span class="lp-ph">{m.search}</span><span class="lp-key">"Ctrl+K"</span></span>
                    <span class="lp-tools">{ic("eye-slash")}{ic("download-simple")}{ic("gear-six")}{ic("user-circle")}</span>
                </div>
                <div class="lp-body">
                    <nav class="lp-side">
                        {m.nav.iter().enumerate().map(|(i, label)| {
                            let name = ["house-fill", "compass", "stack", "clock-counter-clockwise", "playlist", "download-simple"][i];
                            view! { <span class="lp-nav" class:sel=i == 0>{ic(name)}<span>{*label}</span></span> }
                        }).collect_view()}
                    </nav>
                    <div class="lp-main">
                        <div class="lp-head">
                            <div>
                                <div class="lp-h">{m.for_you}</div>
                                <div class="lp-sub">{m.picked}</div>
                            </div>
                            <span class="lp-btn">{ic("shuffle")}{m.shuffle}</span>
                            <span class="lp-btn primary">{ic("arrows-clockwise")}{m.refresh}</span>
                        </div>
                        <div class="lp-chips">
                            {m.chips.iter().enumerate().map(|(i, c)| view! { <span class="lp-chip" class:sel=i == 0>{*c}</span> }).collect_view()}
                        </div>
                        <div class="lp-grid">
                            {m.videos.iter().enumerate().map(|(i, (title, channel, reason))| view! {
                                <div class="lp-card">
                                    <div class=format!("lp-th t{}", i + 1)>
                                        <span class="lp-dur">{["12:04", "8:31", "1:02:45", "21:17", "6:58", "44:10", "15:23", "9:47"][i]}</span>
                                    </div>
                                    <div class="lp-vt">{*title}</div>
                                    <div class="lp-vc">{*channel}</div>
                                    <div class="lp-vr">{ic("sparkle")}<span>{*reason}</span></div>
                                </div>
                            }).collect_view()}
                        </div>
                    </div>
                </div>
                {look.status.then(|| view! { <div class="lp-status">{m.status}</div> })}
            </div>
        }
        .into_any()
    };
    let description = move || look.get().map(|l| l.description);
    view! {
        <div class="sk">
            <div class="sk-bar">
                <div class="sk-mode" role="group" aria-label=t.skin_mode[0]>
                    <button
                        class="sk-seg caption-1"
                        class:on=move || !fixed().unwrap_or(state.dark.get())
                        disabled=move || fixed().is_some()
                        on:click=move |_| state.dark.set(false)
                    >
                        {icon_small("sun")}{t.skin_mode[1]}
                    </button>
                    <button
                        class="sk-seg caption-1"
                        class:on=move || fixed().unwrap_or(state.dark.get())
                        disabled=move || fixed().is_some()
                        on:click=move |_| state.dark.set(true)
                    >
                        {icon_small("moon")}{t.skin_mode[2]}
                    </button>
                </div>
                <span class="caption-2 muted">{move || match fixed() {
                    Some(true) => t.skin_only[1],
                    Some(false) => t.skin_only[0],
                    None => "",
                }}</span>
            </div>
            <div class="lp-frame">{window}</div>
            <p class="sk-desc caption-1 muted">{description}</p>
            <div class="sk-group">
                <span class="caption-3 sk-label">{t.skin_groups[0]}</span>
                <div class="sk-row">{picker(false)}</div>
            </div>
            <div class="sk-group">
                <span class="caption-3 sk-label">{t.skin_groups[1]}</span>
                <div class="sk-row">{picker(true)}</div>
            </div>
        </div>
    }
}

fn icon_small(name: &'static str) -> impl IntoView {
    view! { <svg class="icon" viewBox="0 0 256 256" width="16" height="16" fill="currentColor" aria-hidden="true" inner_html=icons::body(name)></svg> }
}

#[derive(Clone, Copy, PartialEq)]
enum MenuAt {
    Top,
    Title,
    Below,
    None,
}

#[derive(Clone, PartialEq)]
struct Look {
    css: String,
    label: String,
    description: String,
    logo: String,
    title: bool,
    title_icon: bool,
    center: bool,
    menu: MenuAt,
    app_menu: bool,
    underline: bool,
    status: bool,
}

// ---------------------------------------------------------------- colours

#[derive(Clone, Copy, PartialEq)]
struct Rgba(f64, f64, f64, f64);

impl Rgba {
    const WHITE: Rgba = Rgba(1.0, 1.0, 1.0, 1.0);
    const BLACK: Rgba = Rgba(0.0, 0.0, 0.0, 1.0);

    fn parse(v: &Value) -> Option<Rgba> {
        let s = v.as_str()?.trim();
        if s == "transparent" {
            return Some(Rgba(0.0, 0.0, 0.0, 0.0));
        }
        let hex = s.strip_prefix('#')?;
        if !hex.chars().all(|c| c.is_ascii_hexdigit()) {
            return None;
        }
        let full: String = match hex.len() {
            3 | 4 => hex.chars().flat_map(|c| [c, c]).collect(),
            6 | 8 => hex.to_string(),
            _ => return None,
        };
        let byte = |i: usize| u8::from_str_radix(&full[i..i + 2], 16).ok().map(|b| b as f64 / 255.0);
        Some(Rgba(byte(0)?, byte(2)?, byte(4)?, if full.len() == 8 { byte(6)? } else { 1.0 }))
    }

    /// This colour laid over an opaque [under].
    fn over(self, under: Rgba) -> Rgba {
        let a = self.3;
        Rgba(self.0 * a + under.0 * (1.0 - a), self.1 * a + under.1 * (1.0 - a), self.2 * a + under.2 * (1.0 - a), 1.0)
    }

    fn with_alpha(self, a: f64) -> Rgba {
        Rgba(self.0, self.1, self.2, a)
    }

    fn luminance(self) -> f64 {
        let ch = |c: f64| if c <= 0.03928 { c / 12.92 } else { ((c + 0.055) / 1.055).powf(2.4) };
        0.2126 * ch(self.0) + 0.7152 * ch(self.1) + 0.0722 * ch(self.2)
    }

    fn contrast(self, other: Rgba) -> f64 {
        let (a, b) = (self.luminance(), other.luminance());
        (a.max(b) + 0.05) / (a.min(b) + 0.05)
    }

    fn css(self) -> String {
        let c = |v: f64| (v * 255.0).round() as u8;
        if self.3 >= 1.0 {
            format!("#{:02x}{:02x}{:02x}", c(self.0), c(self.1), c(self.2))
        } else {
            format!("#{:02x}{:02x}{:02x}{:02x}", c(self.0), c(self.1), c(self.2), c(self.3))
        }
    }
}

// ---------------------------------------------------------------- reading

fn deep_merge(base: &Value, over: &Value) -> Value {
    match (base, over) {
        (Value::Object(b), Value::Object(o)) => {
            let mut out = b.clone();
            for (k, v) in o {
                let merged = match b.get(k) {
                    Some(old) if old.is_object() && v.is_object() => deep_merge(old, v),
                    _ => v.clone(),
                };
                out.insert(k.clone(), merged);
            }
            Value::Object(out)
        }
        (_, Value::Null) => base.clone(),
        _ => over.clone(),
    }
}

fn num(v: &Value) -> Option<f64> {
    v.as_f64()
}

/// A length in the preview's units: the window is drawn 960 pixels wide
/// at 12 pixels to the em, and scaled to fit.
fn em(px: f64) -> String {
    format!("{:.4}em", px / 12.0)
}

fn paints(v: &Value) -> Vec<&Value> {
    match v {
        Value::Null => vec![],
        Value::Array(items) => items.iter().collect(),
        other => vec![other],
    }
}

struct Cx<'a> {
    id: &'a str,
    page: Rgba,
}

impl Cx<'_> {
    fn color(&self, v: &Value) -> Option<String> {
        Rgba::parse(v).map(Rgba::css)
    }

    fn stops(&self, m: &Map<String, Value>) -> Option<String> {
        let colors: Vec<String> = m.get("colors")?.as_array()?.iter().filter_map(|c| self.color(c)).collect();
        if colors.len() < 2 {
            return None;
        }
        let stops: Vec<f64> = m.get("stops").and_then(Value::as_array).map(|s| s.iter().filter_map(num).collect()).unwrap_or_default();
        Some(
            colors
                .iter()
                .enumerate()
                .map(|(i, c)| match stops.get(i) {
                    Some(s) if stops.len() == colors.len() => format!("{c} {:.2}%", s * 100.0),
                    _ => c.clone(),
                })
                .collect::<Vec<_>>()
                .join(", "),
        )
    }

    /// One paint as CSS background layers, topmost first.
    fn paint(&self, v: &Value) -> Vec<String> {
        if v.is_string() {
            return self.color(v).map(|c| vec![format!("linear-gradient({c}, {c})")]).unwrap_or_default();
        }
        let Some(m) = v.as_object() else { return vec![] };
        if let Some(Value::Object(l)) = m.get("linear") {
            let angle = l.get("angle").and_then(num).unwrap_or(180.0);
            return self.stops(l).map(|s| vec![format!("linear-gradient({angle}deg, {s})")]).unwrap_or_default();
        }
        if let Some(Value::Object(r)) = m.get("radial") {
            let center: Vec<f64> = r.get("center").and_then(Value::as_array).map(|c| c.iter().filter_map(num).collect()).unwrap_or_default();
            let (x, y) = (center.first().copied().unwrap_or(0.5), center.get(1).copied().unwrap_or(0.5));
            let radius = r.get("radius").and_then(num).unwrap_or(0.5) * 100.0;
            return self
                .stops(r)
                .map(|s| vec![format!("radial-gradient(ellipse {radius:.1}% {radius:.1}% at {:.1}% {:.1}%, {s})", x * 100.0, y * 100.0)])
                .unwrap_or_default();
        }
        if let Some(Value::String(name)) = m.get("image") {
            if name.contains("..") || name.starts_with('/') || name.contains(':') {
                return vec![];
            }
            let focus: Vec<f64> = m.get("focus").and_then(Value::as_array).map(|c| c.iter().filter_map(num).collect()).unwrap_or_default();
            let (x, y) = (focus.first().copied().unwrap_or(0.5), focus.get(1).copied().unwrap_or(0.5));
            let fit = match m.get("fit").and_then(Value::as_str).unwrap_or("cover") {
                "contain" => "contain no-repeat",
                "fill" => "100% 100% no-repeat",
                "tile" => "auto repeat",
                _ => "cover no-repeat",
            };
            return vec![format!("url(\"skins/{}/{name}\") {:.0}% {:.0}% / {fit}", self.id, x * 100.0, y * 100.0)];
        }
        if let Some(Value::Object(p)) = m.get("pattern") {
            let Some(c) = p.get("color").and_then(|c| self.color(c)) else { return vec![] };
            let step = p.get("spacing").and_then(num).unwrap_or(4.0).max(1.0);
            let size = p.get("size").and_then(num).unwrap_or(1.0).max(0.5).min(step);
            let (s, w) = (em(step), em(size));
            return match p.get("type").and_then(Value::as_str).unwrap_or("") {
                "dots" => vec![format!("radial-gradient(circle at {h} {h}, {c} {h}, transparent calc({h} + 0.5px)) 0 0 / {s} {s}", h = em(size / 2.0))],
                "lines" | "scanlines" | "grain" | "stitch" => vec![format!("linear-gradient({c} {w}, transparent {w}) 0 0 / 100% {s}")],
                "grid" => vec![
                    format!("linear-gradient({c} {w}, transparent {w}) 0 0 / 100% {s}"),
                    format!("linear-gradient(90deg, {c} {w}, transparent {w}) 0 0 / {s} 100%"),
                ],
                "checker" => vec![format!("repeating-conic-gradient({c} 0 25%, transparent 0 50%) 0 0 / {d} {d}", d = em(step * 2.0))],
                _ => vec![],
            };
        }
        vec![]
    }

    /// A fill (one paint or a list, bottom first) as CSS layers, topmost first.
    fn fill(&self, v: &Value) -> Vec<String> {
        paints(v).into_iter().rev().flat_map(|p| self.paint(p)).collect()
    }

    /// The colour text on a fill is read against, laid over the page.
    fn ground(&self, v: &Value) -> Vec<Rgba> {
        let fill = match v {
            Value::Object(m) => m.get("fill").unwrap_or(&Value::Null),
            other => other,
        };
        let mut tones = vec![self.page];
        for p in paints(fill) {
            if let Some(c) = Rgba::parse(p) {
                tones = tones.iter().map(|u| c.over(*u)).collect();
            } else if let Some(m) = p.as_object() {
                if let Some(Value::Object(g)) = m.get("linear").or_else(|| m.get("radial")) {
                    let colors: Vec<Rgba> = g.get("colors").and_then(Value::as_array).map(|c| c.iter().filter_map(Rgba::parse).collect()).unwrap_or_default();
                    if !colors.is_empty() {
                        tones = tones.iter().flat_map(|u| colors.iter().map(move |c| c.over(*u))).collect();
                    }
                }
            }
        }
        tones
    }

    /// The box declarations for a surface: fill, gloss, edges, corners, shadow.
    fn surface(&self, v: &Value, radius: f64) -> String {
        let mut out = String::new();
        let (fill, m) = match v {
            Value::Object(m) => (m.get("fill").unwrap_or(&Value::Null), Some(m)),
            Value::Null => return out,
            other => (other, None),
        };
        let mut layers = Vec::new();
        let gloss = m.and_then(|m| m.get("gloss")).and_then(num).unwrap_or(0.0).clamp(0.0, 1.0);
        if gloss > 0.0 {
            layers.push(format!(
                "linear-gradient(180deg, rgb(255 255 255 / {:.2}), rgb(255 255 255 / {:.2}) 50%, transparent 50%)",
                0.9 * gloss,
                0.12 * gloss
            ));
        }
        layers.extend(self.fill(fill));
        if !layers.is_empty() || m.is_some_and(|m| m.contains_key("fill")) {
            let _ = write!(out, "background:{};", if layers.is_empty() { "transparent".to_string() } else { layers.join(", ") });
        }
        let Some(m) = m else { return out };
        let r = m.get("radius").and_then(num).unwrap_or(radius);
        let _ = write!(out, "border-radius:{};", em(r));
        match m.get("border") {
            Some(Value::String(_)) => {
                if let Some(c) = m.get("border").and_then(|c| self.color(c)) {
                    let _ = write!(out, "border:max(1px, {}) solid {c};", em(1.0));
                }
            }
            Some(Value::Object(b)) => {
                if let Some(c) = b.get("color").and_then(|c| self.color(c)) {
                    let w = b.get("width").and_then(num).unwrap_or(1.0);
                    let line = format!("max(1px, {}) solid {c}", em(w));
                    match b.get("sides").and_then(Value::as_array) {
                        Some(sides) => {
                            out.push_str("border:0 solid transparent;");
                            for side in sides.iter().filter_map(Value::as_str) {
                                if matches!(side, "top" | "bottom" | "left" | "right") {
                                    let _ = write!(out, "border-{side}:{line};");
                                }
                            }
                        }
                        None => {
                            let _ = write!(out, "border:{line};");
                        }
                    }
                }
            }
            _ => {}
        }
        let mut shadows = Vec::new();
        if let Some(list) = m.get("shadow").and_then(Value::as_array) {
            for s in list {
                let c = s.get("color").and_then(|c| self.color(c)).unwrap_or_else(|| "#00000040".into());
                let n = |k: &str| em(s.get(k).and_then(num).unwrap_or(0.0));
                shadows.push(format!("{} {} {} {} {c}", n("x"), n("y"), n("blur"), n("spread")));
            }
        }
        if let Some(c) = m.get("glow").and_then(|c| self.color(c)) {
            shadows.push(format!("0 0 {} {} {c}", em(10.0), em(1.0)));
        }
        if let Some(Value::Object(b)) = m.get("bevel") {
            let w = b.get("width").and_then(num).unwrap_or(1.0);
            let sunk = b.get("sunk").and_then(Value::as_bool).unwrap_or(false);
            let pair = |light: Option<&Value>, dark: Option<&Value>, k: f64, shadows: &mut Vec<String>| {
                let (Some(l), Some(d)) = (light.and_then(|c| self.color(c)), dark.and_then(|c| self.color(c))) else { return };
                let (l, d) = if sunk { (d, l) } else { (l, d) };
                let o = format!("max(1px, {})", em(w * k));
                shadows.push(format!("inset {o} {o} 0 {l}"));
                shadows.push(format!("inset calc(-1 * {o}) calc(-1 * {o}) 0 {d}"));
            };
            let mut inner = Vec::new();
            pair(b.get("innerLight"), b.get("innerDark"), 2.0, &mut inner);
            pair(b.get("light"), b.get("dark"), 1.0, &mut shadows);
            shadows.extend(inner);
        }
        if !shadows.is_empty() {
            let _ = write!(out, "box-shadow:{};", shadows.join(", "));
        }
        out
    }

    /// The look while hovered or pressed: the surface with [over]'s fields.
    fn merged(base: &Value, over: Option<&Value>) -> Option<Value> {
        let over = over?;
        let base = match base {
            Value::Object(m) => m.clone(),
            Value::Null => Map::new(),
            other => Map::from_iter([("fill".to_string(), other.clone())]),
        };
        let over = match over {
            Value::Object(m) => m.clone(),
            other => Map::from_iter([("fill".to_string(), other.clone())]),
        };
        let mut out = base;
        for k in ["fill", "border", "bevel", "radius", "shadow", "gloss", "glow"] {
            if let Some(v) = over.get(k) {
                out.insert(k.to_string(), v.clone());
            }
        }
        Some(Value::Object(out))
    }

    fn rule(&self, css: &mut String, selector: &str, v: &Value, radius: f64) {
        if v.is_null() {
            return;
        }
        let _ = writeln!(css, ".lp {selector}{{{}}}", self.surface(v, radius));
        if let Some(h) = Self::merged(v, v.get("hover")) {
            let _ = writeln!(css, ".lp {selector}:hover{{{}}}", self.surface(&h, radius));
        }
        if let Some(p) = Self::merged(v, v.get("pressed").or_else(|| v.get("hover"))) {
            let _ = writeln!(css, ".lp {selector}:active{{{}}}", self.surface(&p, radius));
        }
    }
}

/// [fg] if it stands out 4.5:1 (or [min]) on every tone, else black or white.
fn readable(fg: Rgba, bgs: &[Rgba], min: f64) -> Rgba {
    let worst = |c: Rgba| bgs.iter().map(|bg| c.over(*bg).contrast(*bg)).fold(f64::MAX, f64::min);
    if worst(fg) >= min {
        return fg;
    }
    if worst(Rgba::WHITE) >= worst(Rgba::BLACK) { Rgba::WHITE } else { Rgba::BLACK }
}

fn font(name: Option<&str>) -> String {
    match name {
        Some(n) if !n.contains(['"', ';', '{', '}', '<']) => format!("\"{n}\", "),
        _ => String::new(),
    }
}

impl Look {
    fn build(raw: &Value, id: &str, want_dark: bool, lang: Lang) -> Look {
        let mut json = deep_merge(raw, &raw["overrides"]["desktop"]);
        let side = raw["brightness"].as_str().unwrap_or("light");
        let dark = match side {
            "auto" => {
                let mode = if want_dark { "dark" } else { "light" };
                json = deep_merge(&json, &raw["overrides"][mode]);
                want_dark
            }
            other => other == "dark",
        };
        let j = &json;
        let colors = &j["colors"];
        let page = Rgba::parse(&colors["page"])
            .unwrap_or(if dark { Rgba(0.067, 0.067, 0.075, 1.0) } else { Rgba::WHITE })
            .over(if dark { Rgba::BLACK } else { Rgba::WHITE });
        let cx = Cx { id, page };
        let text = readable(Rgba::parse(&colors["text"]).unwrap_or(if dark { Rgba::WHITE } else { Rgba(0.035, 0.035, 0.043, 1.0) }), &[page], 4.5);
        let accent = readable(Rgba::parse(&colors["accent"]).unwrap_or(Rgba(0.898, 0.224, 0.208, 1.0)), &[page], 3.0);
        let muted = Rgba::parse(&colors["muted"]).map(|c| readable(c, &[page], 4.5));
        let quiet = muted.unwrap_or(if dark { Rgba(0.63, 0.63, 0.67, 1.0) } else { Rgba(0.32, 0.32, 0.36, 1.0) });
        let border = Rgba::parse(&colors["border"]).unwrap_or(if dark { Rgba(1.0, 1.0, 1.0, 0.12) } else { Rgba(0.0, 0.0, 0.0, 0.1) });
        let card = Rgba::parse(&colors["card"]);
        let selected = Rgba::parse(&colors["selected"]).unwrap_or(accent.with_alpha(0.16));
        let on_accent = Rgba::parse(&colors["onAccent"]).unwrap_or(readable(Rgba::WHITE, &[accent], 4.5));
        let chrome = Rgba::parse(&colors["chrome"]);
        let reason = Rgba::parse(&colors["reason"]).unwrap_or(accent);

        let shape = &j["shape"];
        let card_r = num(&shape["cardRadius"]).unwrap_or(8.0);
        let control_r = num(&shape["controlRadius"]).unwrap_or(6.0);
        let thumb_r = num(&shape["thumbnailRadius"]).unwrap_or(8.0);

        let window = &j["window"];
        let controls = &j["controls"];
        let cards = &j["cards"];
        let t = &j["text"];
        let body_font = font(t["font"].as_str());
        let display_font = font(t["displayFont"].as_str());
        let mono_font = font(t["monoFont"].as_str());

        // How much of the page lies over the backdrop, so text reads there.
        let background = &window["background"];
        let glass = window["glass"].is_boolean() && window["glass"] == true || window["glass"].is_object();
        let asked = num(&window["veil"]).unwrap_or(0.0).clamp(0.0, 0.9);
        let has_image = paints(background).iter().any(|p| p.get("image").is_some());
        let veil = if glass || has_image {
            asked
        } else {
            let mut tones = vec![page];
            for p in paints(background) {
                if let Some(c) = Rgba::parse(p) {
                    tones = vec![c.over(page)];
                } else if let Some(m) = p.as_object() {
                    if let Some(Value::Object(g)) = m.get("linear").or_else(|| m.get("radial")) {
                        let cs: Vec<Rgba> = g.get("colors").and_then(Value::as_array).map(|c| c.iter().filter_map(Rgba::parse).collect()).unwrap_or_default();
                        tones = tones.iter().flat_map(|u| cs.iter().map(move |c| c.over(*u))).collect();
                    } else if let Some(Value::Object(pt)) = m.get("pattern") {
                        if let Some(c) = pt.get("color").and_then(Rgba::parse) {
                            let more: Vec<Rgba> = tones.iter().map(|u| c.over(*u)).collect();
                            tones.extend(more);
                        }
                    }
                }
            }
            let fg: Vec<Rgba> = [Some(text), muted].into_iter().flatten().collect();
            let reads = |v: f64| tones.iter().all(|u| {
                let bg = page.with_alpha(v).over(*u);
                fg.iter().all(|f| f.contrast(bg) >= 4.5)
            });
            let mut v = asked;
            while v < 0.9 && !reads(v) {
                v += 0.05;
            }
            v.min(0.9)
        };

        let mut css = String::new();
        let mut back = cx.fill(background);
        back.push(format!("linear-gradient({p}, {p})", p = page.css()));
        let _ = writeln!(
            css,
            ".lp{{background:{};color:{};font-family:{body_font}system-ui, -apple-system, \"Segoe UI\", \"PingFang SC\", \"Microsoft YaHei\", sans-serif;--muted:{};--accent:{};--reason:{};--mono:{mono_font}ui-monospace, monospace;--display:{display_font}{body_font}system-ui, sans-serif;--sel:{};--border:{};}}",
            back.join(", "),
            text.css(),
            quiet.css(),
            accent.css(),
            reason.css(),
            selected.css(),
            border.css(),
        );
        let _ = writeln!(css, ".lp-main{{background:{};}}", page.with_alpha(veil).css());

        // Title bar.
        let tb = &window["titleBar"];
        let _ = writeln!(css, ".lp .lp-title{{height:{};color:{};{}}}", em(num(&tb["height"]).unwrap_or(30.0)), cx.color(&tb["text"]).unwrap_or(text.css()), cx.surface(&tb["surface"], 0.0));
        if let Some(c) = cx.color(&tb["titlePlate"]) {
            let _ = writeln!(css, ".lp .lp-ttext{{background:{c};padding:0 0.5em;}}");
        }
        let buttons = &tb["buttons"];
        let size: Vec<f64> = buttons["size"].as_array().map(|s| s.iter().filter_map(num).collect()).unwrap_or_default();
        let _ = writeln!(
            css,
            ".lp .lp-b{{width:{};height:{};color:{};}}",
            em(size.first().copied().unwrap_or(40.0)),
            em(size.get(1).copied().unwrap_or(26.0)),
            cx.color(&buttons["icon"]).unwrap_or(text.css())
        );
        cx.rule(&mut css, ".lp-b", &buttons["surface"], 0.0);
        cx.rule(&mut css, ".lp-b.close", &buttons["close"], 0.0);

        // Menu bar.
        let mb = &window["menuBar"];
        let menu = if mb["enabled"] == false {
            MenuAt::None
        } else {
            match mb["position"].as_str() {
                Some("top") => MenuAt::Top,
                Some("title") => MenuAt::Title,
                _ => MenuAt::Below,
            }
        };
        let _ = writeln!(css, ".lp .lp-menubar{{color:{};{}}}", cx.color(&mb["text"]).unwrap_or(text.css()), cx.surface(&mb["surface"], 0.0));
        let hl = match &mb["highlight"] {
            Value::Null => format!("background:{};", selected.css()),
            h => cx.surface(h, control_r.min(4.0)),
        };
        let _ = writeln!(css, ".lp .lp-mi:hover{{{hl}color:{};}}", cx.color(&mb["highlightText"]).unwrap_or(text.css()));

        // Top bar, logo and search.
        let top = &window["topBar"];
        let top_fill = if top.is_null() { Value::String(chrome.unwrap_or(page).css()) } else { top.clone() };
        let top_tones = cx.ground(&top_fill);
        let top_text = Rgba::parse(&window["topBarText"]).unwrap_or(readable(text, &top_tones, 3.0));
        let _ = writeln!(css, ".lp .lp-top{{color:{};{}}}", top_text.css(), cx.surface(&top_fill, 0.0));
        let field = match &controls["field"] {
            Value::Null => serde_json::json!({ "fill": card.unwrap_or(page).css(), "border": border.css() }),
            f => f.clone(),
        };
        let _ = writeln!(css, ".lp .lp-search{{{}}}", cx.surface(&field, control_r.min(20.0).max(control_r)));
        let logo = &j["logo"];
        let badge = match &logo["badge"] {
            Value::Null => serde_json::json!({ "fill": accent.css() }),
            b => b.clone(),
        };
        let _ = writeln!(css, ".lp .lp-badge{{color:{};{}}}", cx.color(&logo["badgeIcon"]).unwrap_or(on_accent.css()), cx.surface(&badge, 8.0));
        let logo_size = num(&logo["size"]).unwrap_or(22.0);
        let mut word = format!("font-size:{};font-family:{}var(--display);", em(logo_size), font(logo["font"].as_str()));
        let logo_fill = cx.fill(&logo["fill"]);
        match (logo_fill.len(), Rgba::parse(&logo["fill"])) {
            (_, Some(c)) => {
                let _ = write!(word, "color:{};", c.css());
            }
            (0, None) => {}
            _ => {
                let _ = write!(word, "background:{};-webkit-background-clip:text;background-clip:text;color:transparent;", logo_fill.join(", "));
            }
        }
        let mut glows = Vec::new();
        if let Some(c) = cx.color(&logo["shadow"]) {
            glows.push(format!("0 {} 0 {c}", em(1.5)));
        }
        if let Some(c) = cx.color(&logo["glow"]) {
            glows.push(format!("0 0 {} {c}", em(8.0)));
        }
        if !glows.is_empty() {
            let _ = write!(word, "filter:{};", glows.iter().map(|g| format!("drop-shadow({g})")).collect::<Vec<_>>().join(" "));
        }
        if let Some(c) = cx.color(&logo["stroke"]) {
            let _ = write!(word, "-webkit-text-stroke:max(1px, {}) {c};", em(1.0));
        }
        let _ = writeln!(css, ".lp .lp-word{{{word}}}");

        // Side rail.
        let side_fill = match &window["sideBar"] {
            Value::Null => Value::String(chrome.unwrap_or(page).css()),
            s => s.clone(),
        };
        let side_tones = cx.ground(&side_fill);
        let nav_text = Rgba::parse(&controls["navText"]).unwrap_or(readable(quiet, &side_tones, 4.5));
        let _ = writeln!(css, ".lp .lp-side{{color:{};{}}}", nav_text.css(), cx.surface(&side_fill, 0.0));
        let nav_sel = match &controls["navSelected"] {
            Value::Null => serde_json::json!({ "fill": selected.css() }),
            s => s.clone(),
        };
        let nav_sel_text = Rgba::parse(&controls["navSelectedText"]).or(Rgba::parse(&colors["onSelected"])).unwrap_or(text);
        cx.rule(&mut css, ".lp-nav.sel", &nav_sel, card_r.min(14.0).max(control_r.min(14.0)));
        let _ = writeln!(css, ".lp .lp-nav.sel{{color:{};}}", nav_sel_text.css());
        let _ = writeln!(css, ".lp .lp-nav:not(.sel):hover{{background:{};border-radius:{};}}", selected.with_alpha(selected.3 * 0.6).css(), em(control_r.min(14.0)));

        // Buttons and chips.
        let button = match &controls["button"] {
            Value::Null => serde_json::json!({ "fill": "transparent", "border": border.css() }),
            b => b.clone(),
        };
        let button_text = Rgba::parse(&controls["buttonText"]).unwrap_or(readable(text, &cx.ground(&button), 4.5));
        cx.rule(&mut css, ".lp-btn", &button, control_r);
        let _ = writeln!(css, ".lp .lp-btn{{color:{};}}", button_text.css());
        let primary = match &controls["primaryButton"] {
            Value::Null => serde_json::json!({ "fill": accent.css() }),
            b => b.clone(),
        };
        let primary_text = Rgba::parse(&controls["primaryButtonText"]).unwrap_or(on_accent);
        cx.rule(&mut css, ".lp-btn.primary", &primary, control_r);
        let _ = writeln!(css, ".lp .lp-btn.primary{{color:{};}}", primary_text.css());
        let chip = match &controls["chip"] {
            Value::Null => serde_json::json!({ "fill": card.map(|c| c.css()).unwrap_or("transparent".into()), "border": border.css() }),
            c => c.clone(),
        };
        let chip_text = Rgba::parse(&controls["chipText"]).or(Rgba::parse(&controls["buttonText"])).unwrap_or(text);
        cx.rule(&mut css, ".lp-chip", &chip, control_r);
        let _ = writeln!(css, ".lp .lp-chip{{color:{};}}", readable(chip_text, &cx.ground(&chip), 4.5).css());
        let chip_sel = match &controls["chipSelected"] {
            Value::Null => serde_json::json!({ "fill": text.css() }),
            c => c.clone(),
        };
        let chip_sel_text = Rgba::parse(&controls["chipSelectedText"]).unwrap_or(readable(page, &cx.ground(&chip_sel), 4.5));
        cx.rule(&mut css, ".lp-chip.sel", &chip_sel, control_r);
        let _ = writeln!(css, ".lp .lp-chip.sel{{color:{};}}", chip_sel_text.css());

        // Video cards.
        let video = &cards["video"];
        if video.is_null() {
            let _ = writeln!(css, ".lp .lp-card{{padding:0;}}");
        } else {
            cx.rule(&mut css, ".lp-card", video, card_r);
            let _ = writeln!(css, ".lp .lp-card{{padding:{};}}", em(num(&cards["padding"]).unwrap_or(8.0)));
        }
        let _ = writeln!(css, ".lp .lp-th{{border-radius:{};}}", em(thumb_r));
        let badge_v = match &cards["durationBadge"] {
            Value::Null => serde_json::json!({ "fill": "#000000b3" }),
            b => b.clone(),
        };
        let _ = writeln!(css, ".lp .lp-dur{{color:{};{}}}", cx.color(&cards["durationText"]).unwrap_or("#ffffff".into()), cx.surface(&badge_v, 4.0));

        // Status bar.
        let status = &window["statusBar"];
        if !status.is_null() {
            let st = Rgba::parse(&window["statusBarText"]).unwrap_or(readable(quiet, &cx.ground(status), 4.5));
            let _ = writeln!(css, ".lp .lp-status{{color:{};{}}}", st.css(), cx.surface(status, 0.0));
        }

        let name_key = lang.code();
        let label = raw["names"][name_key].as_str().or(raw["name"].as_str()).unwrap_or(id).to_string();
        let description = raw["descriptions"][name_key].as_str().or(raw["description"].as_str()).unwrap_or("").to_string();
        Look {
            css,
            label,
            description,
            logo: logo["text"].as_str().unwrap_or("Lumtub").to_string(),
            title: tb["enabled"] != false,
            title_icon: tb["icon"] == true,
            center: tb["align"] == "center",
            menu,
            app_menu: mb["appMenu"] == true,
            underline: mb["underlineKeys"] == true,
            status: !status.is_null(),
        }
    }
}
