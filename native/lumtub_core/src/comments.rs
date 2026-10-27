//! Comment pages under a video or a community post. Both of YouTube's
//! comment formats are read: the older `commentRenderer`, and
//! `commentViewModel` whose content comes in `frameworkUpdates` entity
//! payloads (the paths follow yt-dlp's extractor/youtube/_video.py).

use serde::Serialize;
use serde_json::Value;
use std::collections::{BTreeMap, HashMap};
use std::os::raw::c_char;

use crate::innertube::at;
use crate::taste::{give_json, text};

/// Text from `simpleText`, `runs` or `content`.
pub(crate) fn plain_text(node: Option<&Value>) -> String {
    let Some(Value::Object(map)) = node else { return String::new() };
    if let Some(Value::String(simple)) = map.get("simpleText") {
        return simple.clone();
    }
    if let Some(Value::Array(runs)) = map.get("runs") {
        return runs.iter().filter_map(Value::as_object).map(|run| run.get("text").map(display).unwrap_or_default()).collect();
    }
    match map.get("content") {
        Some(Value::String(content)) => content.clone(),
        _ => String::new(),
    }
}

/// Custom emoji in a text: the shortcut written in it, such as
/// `:face-blue-smiling:`, and the address of its picture.
pub type Emojis = BTreeMap<String, String>;

/// What an `emoji` run reads as: a Unicode emoji as itself, a custom one
/// (YouTube's own or a channel's) as its shortcut, with its picture added
/// to [emojis].
pub(crate) fn emoji_run(emoji: &Value, emojis: &mut Emojis) -> String {
    let id = emoji.get("emojiId").map(display).unwrap_or_default();
    let custom = emoji.get("isCustomEmoji") == Some(&Value::Bool(true));
    if !custom && !id.is_empty() && !id.is_ascii() {
        return id;
    }
    let label = at(emoji, &["accessibility", "accessibilityData", "label"]).map(display).unwrap_or_default();
    let name = match emoji.get("shortcuts").and_then(Value::as_array).and_then(|s| s.first()) {
        Some(first) => display(first),
        None if !label.is_empty() => label,
        None => id,
    };
    let picture = at(emoji, &["image", "thumbnails"]).and_then(Value::as_array).and_then(|t| t.iter().filter_map(|t| https(t.get("url"))).next_back());
    if let Some(url) = picture
        && !name.is_empty()
    {
        emojis.insert(name.clone(), url);
    }
    name
}

/// [plain_text], with emoji runs read by [emoji_run].
pub(crate) fn rich_text(node: Option<&Value>, emojis: &mut Emojis) -> String {
    let Some(Value::Array(runs)) = node.and_then(|n| n.get("runs")) else { return plain_text(node) };
    runs.iter()
        .filter_map(Value::as_object)
        .map(|run| match (run.get("text"), run.get("emoji")) {
            (Some(text), _) => display(text),
            (None, Some(emoji @ Value::Object(_))) => emoji_run(emoji, emojis),
            _ => String::new(),
        })
        .collect()
}

/// The custom emoji of a `commentViewModel` text: each attachment covers
/// its shortcut in the text, counted in UTF-16 units as JavaScript does.
fn attached_emojis(content: Option<&Value>) -> Emojis {
    let mut emojis = Emojis::new();
    let (Some(text), Some(Value::Array(runs))) = (content.and_then(|c| c.get("content")).and_then(Value::as_str), content.and_then(|c| c.get("attachmentRuns"))) else {
        return emojis;
    };
    let units: Vec<u16> = text.encode_utf16().collect();
    for run in runs {
        let start = run.get("startIndex").and_then(Value::as_u64).unwrap_or(0) as usize;
        let Some(length) = run.get("length").and_then(Value::as_u64).map(|l| l as usize) else { continue };
        let Some(slice) = units.get(start..start + length) else { continue };
        let name = String::from_utf16_lossy(slice);
        let url = at(run, &["element", "type", "imageType", "image", "sources"]).and_then(Value::as_array).and_then(|s| s.iter().filter_map(|s| https(s.get("url"))).next_back());
        if let Some(url) = url
            && name.starts_with(':')
            && name.ends_with(':')
        {
            emojis.insert(name, url);
        }
    }
    emojis
}

/// What liking a comment or a post takes: the signed-in state and the
/// `performCommentActionEndpoint` actions of its buttons. Present only in
/// pages loaded signed in; signed out the buttons lead to a sign-in.
#[derive(Serialize, Debug, PartialEq, Default)]
#[serde(rename_all = "camelCase")]
pub struct Rating {
    /// `like`, `dislike` or empty.
    pub state: String,
    pub like: Option<String>,
    pub unlike: Option<String>,
    pub dislike: Option<String>,
    pub undislike: Option<String>,
}

/// The first `performCommentActionEndpoint` action under [node].
fn comment_action(node: Option<&Value>) -> Option<String> {
    match node? {
        Value::Object(map) => {
            if let Some(Value::String(action)) = map.get("performCommentActionEndpoint").and_then(|e| e.get("action")) {
                return Some(action.clone());
            }
            map.values().filter(|v| v.is_object() || v.is_array()).find_map(|v| comment_action(Some(v)))
        }
        Value::Array(list) => list.iter().find_map(|v| comment_action(Some(v))),
        _ => None,
    }
}

/// The rating of the like and dislike toggle buttons under [buttons]
/// (`commentActionButtonsRenderer`), as old comments and posts have them.
pub(crate) fn button_rating(buttons: Option<&Value>) -> Option<Rating> {
    let button = |name: &str| buttons.and_then(|b| at(b, &[name, "toggleButtonRenderer"]));
    let (like, dislike) = (button("likeButton"), button("dislikeButton"));
    let toggled = |b: Option<&Value>| b.and_then(|b| b.get("isToggled")) == Some(&Value::Bool(true));
    let rating = Rating {
        state: if toggled(like) { "like" } else if toggled(dislike) { "dislike" } else { "" }.to_owned(),
        like: comment_action(like.and_then(|b| b.get("defaultServiceEndpoint"))),
        unlike: comment_action(like.and_then(|b| b.get("toggledServiceEndpoint"))),
        dislike: comment_action(dislike.and_then(|b| b.get("defaultServiceEndpoint"))),
        undislike: comment_action(dislike.and_then(|b| b.get("toggledServiceEndpoint"))),
    };
    (rating.like.is_some() || rating.dislike.is_some()).then_some(rating)
}

/// The rating of a `commentViewModel`, from its toolbar entities.
fn view_model_rating(surface: Option<&Value>, state: Option<&Value>) -> Option<Rating> {
    let surface = surface?.get("engagementToolbarSurfaceEntityPayload")?;
    let rating = Rating {
        state: match state.and_then(|s| at(s, &["engagementToolbarStateEntityPayload", "likeState"])).and_then(Value::as_str) {
            Some("TOOLBAR_LIKE_STATE_LIKED") => "like",
            Some("TOOLBAR_LIKE_STATE_DISLIKED") => "dislike",
            _ => "",
        }
        .to_owned(),
        like: comment_action(surface.get("likeCommand")),
        unlike: comment_action(surface.get("unlikeCommand")),
        dislike: comment_action(surface.get("dislikeCommand")),
        undislike: comment_action(surface.get("undislikeCommand")),
    };
    (rating.like.is_some() || rating.dislike.is_some()).then_some(rating)
}

/// A value as Dart's `'$value'` writes it, with null as empty.
pub(crate) fn display(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Null => String::new(),
        other => other.to_string(),
    }
}

/// The first `continuationCommand` token anywhere under [node].
pub(crate) fn token(node: Option<&Value>) -> Option<String> {
    match node? {
        Value::Object(map) => {
            if let Some(Value::String(token)) = map.get("continuationCommand").and_then(|c| c.get("token")) {
                return Some(token.clone());
            }
            map.values().filter(|v| v.is_object() || v.is_array()).find_map(|v| token(Some(v)))
        }
        Value::Array(list) => list.iter().find_map(|v| token(Some(v))),
        _ => None,
    }
}

/// An `https://` address, completing `//host/…`.
pub(crate) fn https(url: Option<&Value>) -> Option<String> {
    let text = url.map(display).unwrap_or_default();
    let full = if text.starts_with("//") { format!("https:{text}") } else { text };
    full.starts_with("https://").then_some(full)
}

#[derive(Serialize, Debug, PartialEq, Default)]
#[serde(rename_all = "camelCase")]
pub struct Comment {
    pub id: String,
    pub author: String,
    pub text: String,
    pub avatar: Option<String>,
    pub channel_id: Option<String>,
    pub published: String,
    pub likes: String,
    pub reply_count: i64,
    pub replies_token: Option<String>,
    pub pinned: bool,
    pub hearted: bool,
    pub by_uploader: bool,
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    pub emojis: Emojis,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rating: Option<Rating>,
}

#[derive(Serialize, Debug, PartialEq, Default)]
#[serde(rename_all = "camelCase")]
pub struct Page {
    pub comments: Vec<Comment>,
    pub continuation: Option<String>,
    pub count: String,
    pub top_token: Option<String>,
    pub newest_token: Option<String>,
}

fn comment(node: &Value, entities: &HashMap<&str, &Value>, replies: Option<&Value>) -> Option<Comment> {
    let replies_token = token(replies);
    let entity = |model: &Value, key: &str| model.get(key).and_then(Value::as_str).and_then(|k| entities.get(k).copied());
    if let Some(model) = at(node, &["commentViewModel", "commentViewModel"]).filter(|v| !v.is_null()).or_else(|| node.get("commentViewModel")).filter(|v| v.is_object()) {
        let payload = entity(model, "commentKey").and_then(|e| e.get("commentEntityPayload"));
        let field = |path: &[&str]| payload.and_then(|p| at(p, path));
        let id = field(&["properties", "commentId"]).and_then(Value::as_str)?.to_owned();
        let toolbar = entity(model, "toolbarStateKey").and_then(|e| e.get("engagementToolbarStateEntityPayload"));
        let author = field(&["author"]);
        let of_author = |key: &str| author.and_then(|a| a.get(key));
        let reply_count: String = field(&["toolbar", "replyCount"]).map(display).unwrap_or_default().chars().filter(char::is_ascii_digit).collect();
        return Some(Comment {
            id,
            author: of_author("displayName").map(display).unwrap_or_default(),
            text: field(&["properties", "content", "content"]).map(display).unwrap_or_default(),
            avatar: https(of_author("avatarThumbnailUrl")),
            channel_id: of_author("channelId").and_then(Value::as_str).map(str::to_owned),
            published: field(&["properties", "publishedTime"]).map(display).unwrap_or_default(),
            likes: field(&["toolbar", "likeCountNotliked"]).map(display).unwrap_or_default().trim().to_owned(),
            reply_count: reply_count.parse().unwrap_or(0),
            replies_token,
            pinned: model.get("pinnedText").is_some_and(|v| !v.is_null()),
            hearted: toolbar.and_then(|t| t.get("heartState")).and_then(Value::as_str) == Some("TOOLBAR_HEART_STATE_HEARTED"),
            by_uploader: of_author("isCreator") == Some(&Value::Bool(true)),
            emojis: attached_emojis(field(&["properties", "content"])),
            rating: view_model_rating(entity(model, "toolbarSurfaceKey"), entity(model, "toolbarStateKey")),
        });
    }
    let renderer = at(node, &["comment", "commentRenderer"]).filter(|v| !v.is_null()).or_else(|| node.get("commentRenderer"))?;
    let id = renderer.get("commentId")?.as_str()?.to_owned();
    let avatar = at(renderer, &["authorThumbnail", "thumbnails"]).and_then(Value::as_array).and_then(|t| t.last()).and_then(|t| https(t.get("url")));
    let present = |path: &[&str]| at(renderer, path).is_some_and(|v| !v.is_null());
    let mut emojis = Emojis::new();
    let text = rich_text(renderer.get("contentText"), &mut emojis);
    Some(Comment {
        id,
        author: plain_text(renderer.get("authorText")),
        text,
        avatar,
        channel_id: at(renderer, &["authorEndpoint", "browseEndpoint", "browseId"]).and_then(Value::as_str).map(str::to_owned),
        published: plain_text(renderer.get("publishedTimeText")),
        likes: plain_text(renderer.get("voteCount")),
        reply_count: renderer.get("replyCount").and_then(Value::as_i64).unwrap_or(0),
        replies_token,
        pinned: present(&["pinnedCommentBadge"]),
        hearted: present(&["actionButtons", "commentActionButtonsRenderer", "creatorHeart"]),
        by_uploader: renderer.get("authorIsChannelOwner") == Some(&Value::Bool(true)),
        emojis,
        rating: button_rating(at(renderer, &["actionButtons", "commentActionButtonsRenderer"])),
    })
}

/// A `/next` or `/browse` response with comment section items.
pub fn page(response: &Value) -> Page {
    let mut entities = HashMap::new();
    if let Some(Value::Array(mutations)) = at(response, &["frameworkUpdates", "entityBatchUpdate", "mutations"]) {
        for mutation in mutations {
            if let (Some(Value::String(key)), Some(payload @ Value::Object(_))) = (mutation.get("entityKey"), mutation.get("payload")) {
                entities.insert(key.as_str(), payload);
            }
        }
    }
    let mut items: Vec<&Value> = Vec::new();
    if let Some(Value::Array(endpoints)) = response.get("onResponseReceivedEndpoints") {
        for endpoint in endpoints {
            let command = endpoint.get("reloadContinuationItemsCommand").filter(|v| !v.is_null()).or_else(|| endpoint.get("appendContinuationItemsAction"));
            if let Some(Value::Array(list)) = command.and_then(|c| c.get("continuationItems")) {
                items.extend(list.iter().filter(|v| v.is_object()));
            }
        }
    }
    let mut page = Page::default();
    for item in items {
        if let Some(header @ Value::Object(_)) = item.get("commentsHeaderRenderer") {
            let count = plain_text(header.get("countText"));
            page.count = if count.is_empty() { plain_text(header.get("commentsCount")) } else { count };
            if let Some(Value::Array(sorts)) = at(header, &["sortMenu", "sortFilterSubMenuRenderer", "subMenuItems"]) {
                page.top_token = token(sorts.first());
                page.newest_token = token(sorts.get(1));
            }
            continue;
        }
        let thread = item.get("commentThreadRenderer").filter(|v| v.is_object());
        let found = comment(thread.unwrap_or(item), &entities, thread.and_then(|t| at(t, &["replies", "commentRepliesRenderer"])));
        if let Some(found) = found {
            if !page.comments.iter().any(|c| c.id == found.id) {
                page.comments.push(found);
            }
            continue;
        }
        if let Some(more) = item.get("continuationItemRenderer").filter(|v| !v.is_null()) {
            page.continuation = token(Some(more)).or(page.continuation);
        }
    }
    page
}

/// [page] of a comments response [body] as JSON; null when it is not JSON.
///
/// # Safety
/// [body] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_youtube_comments(body: *const u8, length: usize) -> *mut c_char {
    let Ok(data) = serde_json::from_str::<Value>(unsafe { text(body, length) }) else {
        return std::ptr::null_mut();
    };
    give_json(&page(&data))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn reads_the_header_and_both_comment_formats() {
        let data = json!({
            "onResponseReceivedEndpoints": [
                {"reloadContinuationItemsCommand": {"continuationItems": [
                    {"commentsHeaderRenderer": {
                        "countText": {"runs": [{"text": "1,234"}, {"text": " 条评论"}]},
                        "sortMenu": {"sortFilterSubMenuRenderer": {"subMenuItems": [
                            {"serviceEndpoint": {"continuationCommand": {"token": "TOP"}}},
                            {"serviceEndpoint": {"continuationCommand": {"token": "NEW"}}}
                        ]}}
                    }}
                ]}},
                {"appendContinuationItemsAction": {"continuationItems": [
                    {"commentThreadRenderer": {
                        "commentViewModel": {"commentViewModel": {"commentKey": "k1", "toolbarStateKey": "t1", "pinnedText": "置顶"}},
                        "replies": {"commentRepliesRenderer": {"contents": [{"continuationItemRenderer": {"continuationEndpoint": {"continuationCommand": {"token": "REPLIES"}}}}]}}
                    }},
                    {"commentRenderer": {
                        "commentId": "old", "authorText": {"simpleText": "老用户"}, "contentText": {"runs": [{"text": "你"}, {"text": "好"}]},
                        "authorThumbnail": {"thumbnails": [{"url": "//small"}, {"url": "//yt3.ggpht.com/big"}]},
                        "authorEndpoint": {"browseEndpoint": {"browseId": "UCold"}}, "voteCount": {"simpleText": "5"}, "replyCount": 2,
                        "authorIsChannelOwner": true, "actionButtons": {"commentActionButtonsRenderer": {"creatorHeart": {}}}
                    }},
                    {"commentRenderer": {"commentId": "old"}},
                    {"continuationItemRenderer": {"continuationEndpoint": {"continuationCommand": {"token": "NEXT"}}}}
                ]}}
            ],
            "frameworkUpdates": {"entityBatchUpdate": {"mutations": [
                {"entityKey": "k1", "payload": {"commentEntityPayload": {
                    "properties": {"commentId": "new", "content": {"content": "内容"}, "publishedTime": "3天前"},
                    "author": {"displayName": "@someone", "avatarThumbnailUrl": "https://yt3.ggpht.com/a", "channelId": "UCnew", "isCreator": false},
                    "toolbar": {"likeCountNotliked": " 12 ", "replyCount": "1,024"}
                }}},
                {"entityKey": "t1", "payload": {"engagementToolbarStateEntityPayload": {"heartState": "TOOLBAR_HEART_STATE_HEARTED"}}}
            ]}}
        });
        let page = page(&data);
        assert_eq!(page.count, "1,234 条评论");
        assert_eq!((page.top_token.as_deref(), page.newest_token.as_deref()), (Some("TOP"), Some("NEW")));
        assert_eq!(page.continuation.as_deref(), Some("NEXT"));
        assert_eq!(page.comments.len(), 2);
        assert_eq!(
            page.comments[0],
            Comment {
                id: "new".into(),
                author: "@someone".into(),
                text: "内容".into(),
                avatar: Some("https://yt3.ggpht.com/a".into()),
                channel_id: Some("UCnew".into()),
                published: "3天前".into(),
                likes: "12".into(),
                reply_count: 1024,
                replies_token: Some("REPLIES".into()),
                pinned: true,
                hearted: true,
                by_uploader: false,
                emojis: Emojis::new(),
                rating: None,
            }
        );
        let old = &page.comments[1];
        assert_eq!((old.author.as_str(), old.text.as_str(), old.avatar.as_deref(), old.channel_id.as_deref()), ("老用户", "你好", Some("https://yt3.ggpht.com/big"), Some("UCold")));
        assert!(old.hearted && old.by_uploader && !old.pinned && old.reply_count == 2);
    }

    #[test]
    fn finds_custom_emoji_by_utf16_position() {
        let content = json!({
            "content": "好😀 :_hi: ok",
            "attachmentRuns": [
                {"startIndex": 4, "length": 5, "element": {"type": {"imageType": {"image": {"sources": [{"url": "https://yt3/hi"}]}}}}},
                {"startIndex": 0, "length": 1, "element": {"type": {"imageType": {"image": {"sources": [{"url": "https://yt3/x"}]}}}}},
            ],
        });
        assert_eq!(attached_emojis(Some(&content)), Emojis::from([(":_hi:".into(), "https://yt3/hi".into())]));
        let mut emojis = Emojis::new();
        let runs = json!({"runs": [{"text": "a "}, {"emoji": {"emojiId": "x", "isCustomEmoji": true, "shortcuts": [":x:"], "image": {"thumbnails": [{"url": "https://yt3/x"}]}}}]});
        assert_eq!(rich_text(Some(&runs), &mut emojis), "a :x:");
        assert_eq!(emojis.get(":x:").map(String::as_str), Some("https://yt3/x"));
    }

    #[test]
    fn reads_the_signed_in_rating() {
        let action = |a: &str| json!({"innertubeCommand": {"performCommentActionEndpoint": {"action": a}}});
        let response = json!({
            "frameworkUpdates": {"entityBatchUpdate": {"mutations": [
                {"entityKey": "c", "payload": {"commentEntityPayload": {"properties": {"commentId": "C1", "content": {"content": "x"}}}}},
                {"entityKey": "s", "payload": {"engagementToolbarStateEntityPayload": {"likeState": "TOOLBAR_LIKE_STATE_LIKED"}}},
                {"entityKey": "t", "payload": {"engagementToolbarSurfaceEntityPayload": {
                    "likeCommand": action("L"), "unlikeCommand": action("UL"), "dislikeCommand": action("D"), "undislikeCommand": action("UD"),
                }}},
            ]}},
            "onResponseReceivedEndpoints": [{"appendContinuationItemsAction": {"continuationItems": [
                {"commentThreadRenderer": {"commentViewModel": {"commentViewModel": {"commentKey": "c", "toolbarStateKey": "s", "toolbarSurfaceKey": "t"}}}},
                {"commentRenderer": {"commentId": "C2", "actionButtons": {"commentActionButtonsRenderer": {
                    "likeButton": {"toggleButtonRenderer": {"isToggled": false, "defaultServiceEndpoint": {"performCommentActionEndpoint": {"action": "L2"}}, "toggledServiceEndpoint": {"performCommentActionEndpoint": {"action": "UL2"}}}},
                    "dislikeButton": {"toggleButtonRenderer": {"isToggled": true, "defaultServiceEndpoint": {"commandExecutorCommand": {"commands": [{"performCommentActionEndpoint": {"action": "D2"}}]}}}},
                }}}},
                {"commentRenderer": {"commentId": "C3", "actionButtons": {"commentActionButtonsRenderer": {
                    "likeButton": {"toggleButtonRenderer": {"defaultServiceEndpoint": {"signInEndpoint": {}}}},
                }}}},
            ]}}],
        });
        let page = page(&response);
        let rating = |i: usize| page.comments[i].rating.as_ref();
        assert_eq!(rating(0), Some(&Rating { state: "like".into(), like: Some("L".into()), unlike: Some("UL".into()), dislike: Some("D".into()), undislike: Some("UD".into()) }));
        assert_eq!(rating(1), Some(&Rating { state: "dislike".into(), like: Some("L2".into()), unlike: Some("UL2".into()), dislike: Some("D2".into()), undislike: None }));
        assert_eq!(rating(2), None);
    }

    #[test]
    fn reads_nothing_from_other_responses() {
        assert_eq!(page(&json!({})), Page::default());
    }
}
