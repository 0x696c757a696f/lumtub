//! Pages of YouTube's TV app read into the flat entries the rest of Lumtub
//! lists (the shape `yt-dlp --flat-playlist --dump-json` prints): the
//! account's home feed, history, subscriptions, Watch Later and playlists,
//! fetched with the TV-code sign-in. Every item there is a `tileRenderer`;
//! the paths follow SmartTube's MediaServiceCore (browse/v2 and
//! common/models/gen).

use serde::Serialize;
use serde_json::{Map, Value, json};
use std::os::raw::c_char;

use crate::innertube::{at, seconds, text_of};
use crate::listing::count;
use crate::taste::{give_json, text};

#[derive(Serialize, Debug, Default, PartialEq)]
pub struct Page {
    /// Videos, in the order the page shows them.
    pub entries: Vec<Value>,
    /// Playlist tiles: `{id, title, count}`, `id` without its `VL`.
    pub playlists: Vec<Value>,
    pub continuation: Option<String>,
}

fn is_video_id(id: &str) -> bool {
    id.len() == 11 && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// The first value of [key] anywhere under [node].
fn find<'a>(node: &'a Value, key: &str) -> Option<&'a Value> {
    match node {
        Value::Object(map) => map.get(key).or_else(|| map.values().find_map(|v| find(v, key))),
        Value::Array(list) => list.iter().find_map(|v| find(v, key)),
        _ => None,
    }
}

/// The first channel id (`UC…`) a `browseEndpoint` under [node] leads to.
fn channel_id(node: &Value) -> Option<String> {
    match node {
        Value::Object(map) => {
            if let Some(id) = map.get("browseEndpoint").and_then(|e| e.get("browseId")).and_then(Value::as_str)
                && id.len() == 24
                && id.starts_with("UC")
            {
                return Some(id.to_owned());
            }
            map.values().find_map(channel_id)
        }
        Value::Array(list) => list.iter().find_map(channel_id),
        _ => None,
    }
}

/// The texts of one metadata line, separators left out.
fn line(lines: Option<&Value>, index: usize) -> Vec<String> {
    lines
        .and_then(|l| l.get(index))
        .and_then(|l| at(l, &["lineRenderer", "items"]))
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .map(|item| text_of(at(item, &["lineItemRenderer", "text"])).trim().to_owned())
        .filter(|t| !t.is_empty() && t != "•")
        .collect()
}

/// A video tile as a flat entry, with what the TV app adds: how much of it
/// was watched (`lumtub_watched`, percent) and the token that removes it
/// from history or says not interested (`lumtub_feedback`).
pub fn video(tile: &Value) -> Option<Value> {
    let kind = tile.get("contentType").and_then(Value::as_str).unwrap_or("TILE_CONTENT_TYPE_VIDEO");
    if !matches!(kind, "TILE_CONTENT_TYPE_VIDEO" | "TILE_CONTENT_TYPE_SHORTS") {
        return None;
    }
    let id = at(tile, &["onSelectCommand", "watchEndpoint", "videoId"]).or_else(|| tile.get("contentId")).and_then(Value::as_str).filter(|id| is_video_id(id))?;
    let metadata = at(tile, &["metadata", "tileMetadataRenderer"]);
    let lines = metadata.and_then(|m| m.get("lines"));
    let mut entry = Map::new();
    entry.insert("id".into(), id.into());
    entry.insert("title".into(), text_of(metadata.and_then(|m| m.get("title"))).into());
    entry.insert("channel".into(), line(lines, 0).join(" ").into());
    if let Some(channel) = channel_id(tile) {
        entry.insert("channel_id".into(), channel.into());
    }
    let details = line(lines, 1);
    if let Some(views) = details.iter().find_map(|t| count(t).filter(|_| t.chars().any(|c| c.is_ascii_digit())).filter(|_| details.len() > 1 || !t.contains(':'))) {
        entry.insert("view_count".into(), views.into());
    }
    let overlays = at(tile, &["header", "tileHeaderRenderer", "thumbnailOverlays"]).and_then(Value::as_array);
    let mut shorts = kind == "TILE_CONTENT_TYPE_SHORTS" || tile.get("style").and_then(Value::as_str) == Some("TILE_STYLE_YTLR_SHORTS");
    for overlay in overlays.into_iter().flatten() {
        if let Some(status) = overlay.get("thumbnailOverlayTimeStatusRenderer") {
            match status.get("style").and_then(Value::as_str) {
                Some("LIVE") => {
                    entry.insert("live_status".into(), "is_live".into());
                }
                Some("UPCOMING") => {
                    entry.insert("live_status".into(), "is_upcoming".into());
                }
                Some("SHORTS") => shorts = true,
                _ => {
                    if let Some(length) = seconds(&text_of(status.get("text"))) {
                        entry.insert("duration".into(), length.into());
                    }
                }
            }
        }
        if let Some(watched) = at(overlay, &["thumbnailOverlayResumePlaybackRenderer", "percentDurationWatched"]).and_then(Value::as_u64) {
            entry.insert("lumtub_watched".into(), watched.into());
        }
    }
    let url = if shorts { format!("https://www.youtube.com/shorts/{id}") } else { format!("https://www.youtube.com/watch?v={id}") };
    entry.insert("url".into(), url.clone().into());
    entry.insert("original_url".into(), url.into());
    let menu = tile.get("menu").or_else(|| at(tile, &["onLongPressCommand", "showMenuCommand", "menu"]));
    if let Some(token) = menu.and_then(|m| find(m, "feedbackToken")).and_then(Value::as_str) {
        entry.insert("lumtub_feedback".into(), token.into());
    }
    Some(Value::Object(entry))
}

fn playlist(tile: &Value) -> Option<Value> {
    if tile.get("contentType").and_then(Value::as_str) != Some("TILE_CONTENT_TYPE_PLAYLIST") {
        return None;
    }
    let browse = at(tile, &["onSelectCommand", "browseEndpoint", "browseId"]).and_then(Value::as_str);
    let id = browse.and_then(|b| b.strip_prefix("VL")).or_else(|| at(tile, &["onSelectCommand", "watchEndpoint", "playlistId"]).and_then(Value::as_str)).or_else(|| tile.get("contentId").and_then(Value::as_str))?;
    let overlays = at(tile, &["header", "tileHeaderRenderer", "thumbnailOverlays"]).and_then(Value::as_array);
    let count_text = overlays.into_iter().flatten().find_map(|o| o.get("thumbnailOverlayTimeStatusRenderer")).map(|s| text_of(s.get("text"))).unwrap_or_default();
    let thumbnail = at(tile, &["header", "tileHeaderRenderer", "thumbnail", "thumbnails"])
        .and_then(Value::as_array)
        .and_then(|list| list.iter().rev().find_map(|t| t.get("url").and_then(Value::as_str)))
        .map(|url| if url.starts_with("//") { format!("https:{url}") } else { url.to_owned() });
    Some(json!({
        "id": id,
        "title": text_of(at(tile, &["metadata", "tileMetadataRenderer", "title"])),
        "count": count(&count_text),
        "thumbnail": thumbnail,
    }))
}

/// Every tile under [node], in order, skipping the rows the TV app marks as
/// Shorts when [shorts] is false.
fn tiles<'a>(node: &'a Value, shorts: bool, out: &mut Vec<&'a Value>) {
    match node {
        Value::Object(map) => {
            if let Some(tile) = map.get("tileRenderer") {
                out.push(tile);
                return;
            }
            if !shorts && map.get("tvhtml5ShelfRendererType").and_then(Value::as_str) == Some("TVHTML5_SHELF_RENDERER_TYPE_SHORTS") {
                return;
            }
            for value in map.values() {
                tiles(value, shorts, out);
            }
        }
        Value::Array(list) => list.iter().for_each(|v| tiles(v, shorts, out)),
        _ => {}
    }
}

/// The page-level continuation: the section list's, the grid's or the
/// playlist's, not a single row's.
fn continuation(response: &Value) -> Option<String> {
    fn token(list: Option<&Value>) -> Option<String> {
        list?.as_array()?.iter().find_map(|c| {
            ["nextContinuationData", "reloadContinuationData"].iter().find_map(|k| at(c, &[k, "continuation"]).and_then(Value::as_str).map(str::to_owned))
        })
    }
    fn search(node: &Value) -> Option<String> {
        match node {
            Value::Object(map) => {
                for owner in ["sectionListRenderer", "sectionListContinuation", "gridRenderer", "gridContinuation", "playlistVideoListRenderer", "playlistVideoListContinuation"] {
                    if let Some(found) = map.get(owner).and_then(|o| token(o.get("continuations"))) {
                        return Some(found);
                    }
                }
                map.iter().filter(|(k, _)| k.as_str() != "horizontalListRenderer").find_map(|(_, v)| search(v))
            }
            Value::Array(list) => list.iter().find_map(search),
            _ => None,
        }
    }
    search(response.get("continuationContents").unwrap_or(response))
}

/// A TV app `/browse` response, first page or continuation. [shorts] keeps
/// the Shorts rows.
pub fn page(response: &Value, shorts: bool) -> Page {
    let mut found = Vec::new();
    // The subscriptions page lists the channels as tabs; their videos are
    // under the selected tab, so only the selected one is read.
    let root = at(response, &["contents", "tvBrowseRenderer", "content", "tvSecondaryNavRenderer", "sections"])
        .and_then(Value::as_array)
        .and_then(|sections| {
            let tabs = sections.iter().filter_map(|s| at(s, &["tvSecondaryNavSectionRenderer", "tabs"])).filter_map(Value::as_array).flatten();
            let tabs: Vec<&Value> = tabs.filter_map(|t| t.get("tabRenderer")).collect();
            let tab = tabs.iter().find(|t| t.get("selected") == Some(&Value::Bool(true))).or(tabs.first())?;
            tab.get("content")
        })
        .unwrap_or(response);
    tiles(root, shorts, &mut found);
    let mut page = Page { continuation: continuation(root).or_else(|| continuation(response)), ..Default::default() };
    let mut seen = std::collections::HashSet::new();
    for tile in found {
        if let Some(entry) = video(tile) {
            if entry.get("id").and_then(Value::as_str).is_some_and(|id| seen.insert(id.to_owned())) {
                page.entries.push(entry);
            }
        } else if let Some(list) = playlist(tile) {
            page.playlists.push(list);
        }
    }
    page
}

/// [page] of a TV app `/browse` response [body] as JSON, Shorts rows kept
/// when [shorts]; null when it is not JSON.
///
/// # Safety
/// [body] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_tv_browse(body: *const u8, length: usize, shorts: bool) -> *mut c_char {
    let Ok(data) = serde_json::from_str::<Value>(unsafe { text(body, length) }) else {
        return std::ptr::null_mut();
    };
    give_json(&page(&data, shorts))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tile(id: &str, overlays: Value) -> Value {
        json!({"tileRenderer": {
            "style": "TILE_STYLE_YTLR_DEFAULT", "contentId": id, "contentType": "TILE_CONTENT_TYPE_VIDEO",
            "header": {"tileHeaderRenderer": {"thumbnailOverlays": overlays}},
            "metadata": {"tileMetadataRenderer": {
                "title": {"simpleText": format!("Video {id}")},
                "lines": [
                    {"lineRenderer": {"items": [{"lineItemRenderer": {"text": {"runs": [{"text": "Chan"}]}}}]}},
                    {"lineRenderer": {"items": [
                        {"lineItemRenderer": {"text": {"simpleText": "358K views"}}},
                        {"lineItemRenderer": {"text": {"simpleText": "•"}}},
                        {"lineItemRenderer": {"text": {"simpleText": "3 months ago"}}}
                    ]}}
                ]
            }},
            "onSelectCommand": {"watchEndpoint": {"videoId": id}},
            "onLongPressCommand": {"showMenuCommand": {"menu": {"menuRenderer": {"items": [
                {"menuServiceItemRenderer": {"serviceEndpoint": {"feedbackEndpoint": {"feedbackToken": format!("FB-{id}")}}}},
                {"menuNavigationItemRenderer": {"navigationEndpoint": {"browseEndpoint": {"browseId": "UCIGSeb72lRj7Jxlwt63OmMQ"}}}}
            ]}}}}
        }})
    }

    #[test]
    fn reads_the_home_feed() {
        let home = json!({"contents": {"tvBrowseRenderer": {"content": {"tvSurfaceContentRenderer": {"content": {"sectionListRenderer": {
            "contents": [
                {"shelfRenderer": {"tvhtml5ShelfRendererType": "GRID_XL", "content": {"horizontalListRenderer": {
                    "items": [
                        {"adSlotRenderer": {}},
                        tile("K3nvny5x47w", json!([{"thumbnailOverlayTimeStatusRenderer": {"text": {"simpleText": "34:12"}, "style": "DEFAULT"}}])),
                        tile("liveliveliv", json!([{"thumbnailOverlayResumePlaybackRenderer": {"percentDurationWatched": 100}}, {"thumbnailOverlayTimeStatusRenderer": {"text": {"runs": [{"text": "LIVE"}]}, "style": "LIVE"}}]))
                    ],
                    "continuations": [{"nextContinuationData": {"continuation": "ROW"}}]
                }}}},
                {"shelfRenderer": {"tvhtml5ShelfRendererType": "TVHTML5_SHELF_RENDERER_TYPE_SHORTS", "content": {"horizontalListRenderer": {"items": [tile("shortshorts", json!([]))]}}}}
            ],
            "continuations": [{"nextContinuationData": {"continuation": "NEXT"}}]
        }}}}}}});
        let page = page(&home, false);
        assert_eq!(page.continuation.as_deref(), Some("NEXT"));
        assert_eq!(page.entries.len(), 2);
        let first = &page.entries[0];
        assert_eq!(first["id"], "K3nvny5x47w");
        assert_eq!(first["title"], "Video K3nvny5x47w");
        assert_eq!(first["channel"], "Chan");
        assert_eq!(first["channel_id"], "UCIGSeb72lRj7Jxlwt63OmMQ");
        assert_eq!(first["duration"], 2052);
        assert_eq!(first["view_count"], 358_000);
        assert_eq!(first["lumtub_feedback"], "FB-K3nvny5x47w");
        assert_eq!(page.entries[1]["live_status"], "is_live");
        assert_eq!(page.entries[1]["lumtub_watched"], 100);
    }

    #[test]
    fn reads_the_selected_subscriptions_tab_and_continuations() {
        let subs = json!({"contents": {"tvBrowseRenderer": {"content": {"tvSecondaryNavRenderer": {"sections": [{"tvSecondaryNavSectionRenderer": {"tabs": [
            {"tabRenderer": {"selected": true, "content": {"tvSurfaceContentRenderer": {"content": {"sectionListRenderer": {
                "contents": [{"shelfRenderer": {"content": {"horizontalListRenderer": {"items": [tile("aaaaaaaaaaa", json!([]))]}}}}],
                "continuations": [{"nextContinuationData": {"continuation": "SUBS2"}}]
            }}}}}},
            {"tabRenderer": {"content": {"tvSurfaceContentRenderer": {"content": {"sectionListRenderer": {"contents": [
                {"shelfRenderer": {"content": {"horizontalListRenderer": {"items": [tile("bbbbbbbbbbb", json!([]))]}}}}
            ]}}}}}}
        ]}}]}}}}});
        let page = page(&subs, false);
        assert_eq!(page.entries.iter().map(|e| e["id"].as_str().unwrap()).collect::<Vec<_>>(), ["aaaaaaaaaaa"]);
        assert_eq!(page.continuation.as_deref(), Some("SUBS2"));

        let more = json!({"continuationContents": {"playlistVideoListContinuation": {
            "contents": [tile("ccccccccccc", json!([]))],
            "continuations": [{"nextContinuationData": {"continuation": "WL3"}}]
        }}});
        let next = super::page(&more, false);
        assert_eq!((next.entries.len(), next.continuation.as_deref()), (1, Some("WL3")));
    }

    #[test]
    fn reads_playlist_tiles() {
        let lists = json!({"contents": {"tvBrowseRenderer": {"content": {"tvSurfaceContentRenderer": {"content": {"gridRenderer": {"items": [
            {"tileRenderer": {"contentType": "TILE_CONTENT_TYPE_PLAYLIST", "onSelectCommand": {"browseEndpoint": {"browseId": "VLWL"}},
                "metadata": {"tileMetadataRenderer": {"title": {"simpleText": "Watch later"}}},
                "header": {"tileHeaderRenderer": {"thumbnailOverlays": [{"thumbnailOverlayTimeStatusRenderer": {"text": {"simpleText": "27 videos"}}}]}}}}
        ]}}}}}}});
        let page = page(&lists, false);
        assert_eq!(page.playlists, vec![json!({"id": "WL", "title": "Watch later", "count": 27, "thumbnail": null})]);
    }
}
