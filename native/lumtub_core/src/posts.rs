//! A channel's posts tab and community post pages: the `ytInitialData` a
//! YouTube page embeds, the posts in it or in a browse response, and a post
//! page's comment section token.

use serde::Serialize;
use serde_json::Value;
use std::os::raw::c_char;

use crate::comments::{Rating, button_rating, display, https, plain_text, token};
use crate::innertube::at;
use crate::taste::{give_json, text};

/// The `ytInitialData` object embedded in a YouTube page.
pub fn initial_data(html: &str) -> Option<Value> {
    let marker = ["var ytInitialData", "window[\"ytInitialData\"]"].iter().filter_map(|m| html.find(m).map(|at| (at, m.len()))).min()?;
    let after = html[marker.0 + marker.1..].trim_start();
    let after = after.strip_prefix('=')?.trim_start();
    let start = html.len() - after.len();
    let bytes = html.as_bytes();
    let (mut depth, mut in_string, mut i) = (0usize, false, html[start..].find('{')? + start);
    let open = i;
    while i < bytes.len() {
        match bytes[i] {
            b'\\' if in_string => i += 1,
            b'"' => in_string = !in_string,
            b'{' if !in_string => depth += 1,
            b'}' if !in_string => {
                depth -= 1;
                if depth == 0 {
                    return serde_json::from_str(&html[open..=i]).ok();
                }
            }
            _ => {}
        }
        i += 1;
    }
    None
}

#[derive(Serialize, Debug, PartialEq)]
pub struct AttachedVideo {
    pub id: String,
    pub title: String,
    pub channel: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub duration: Option<u32>,
}

#[derive(Serialize, Debug, PartialEq, Default)]
pub struct Post {
    pub id: String,
    pub text: String,
    pub published: String,
    pub likes: String,
    pub comments: String,
    pub images: Vec<String>,
    pub video: Option<AttachedVideo>,
    pub poll: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rating: Option<Rating>,
}

#[derive(Serialize, Debug, PartialEq, Default)]
pub struct Page {
    pub posts: Vec<Post>,
    pub continuation: Option<String>,
}

fn image(renderer: Option<&Value>) -> Option<String> {
    https(at(renderer?, &["image", "thumbnails"])?.as_array()?.last()?.get("url"))
}

fn is_video_id(id: &str) -> bool {
    id.len() == 11 && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

fn post(post: &Value) -> Option<Post> {
    let id = post.get("postId").map(display).unwrap_or_default();
    if id.is_empty() {
        return None;
    }
    let attachment = post.get("backstageAttachment").filter(|v| !v.is_null());
    let of = |path: &[&str]| attachment.and_then(|a| at(a, path));
    let mut images: Vec<String> = image(of(&["backstageImageRenderer"])).into_iter().collect();
    if let Some(Value::Array(multi)) = of(&["postMultiImageRenderer", "images"]) {
        images.extend(multi.iter().filter_map(|item| image(item.get("backstageImageRenderer"))));
    }
    let video = of(&["videoRenderer"]).and_then(|renderer| {
        let id = renderer.get("videoId")?.as_str().filter(|id| is_video_id(id))?.to_owned();
        let length = plain_text(renderer.get("lengthText"));
        let parts: Option<Vec<u32>> = length.split(':').map(|n| n.parse().ok()).collect();
        Some(AttachedVideo {
            id,
            title: plain_text(renderer.get("title")),
            channel: plain_text(renderer.get("ownerText")),
            duration: parts.map(|parts| parts.iter().fold(0, |total, n| total * 60 + n)),
        })
    });
    let poll = match of(&["pollRenderer", "choices"]) {
        Some(Value::Array(choices)) => choices.iter().map(|c| plain_text(c.get("text"))).filter(|t| !t.is_empty()).collect(),
        _ => Vec::new(),
    };
    Some(Post {
        id,
        text: plain_text(post.get("contentText")),
        published: plain_text(post.get("publishedTimeText")),
        likes: plain_text(post.get("voteCount")),
        comments: plain_text(at(post, &["actionButtons", "commentActionButtonsRenderer", "replyButton", "buttonRenderer", "text"])),
        images,
        video,
        poll,
        rating: button_rating(at(post, &["actionButtons", "commentActionButtonsRenderer"])),
    })
}

/// Posts and the continuation token anywhere in a browse response or
/// `ytInitialData`. The tree is walked instead of followed by path, so
/// layout changes around the posts do not break reading them.
pub fn page(data: &Value) -> Page {
    fn walk(node: &Value, page: &mut Page) {
        match node {
            Value::Array(list) => list.iter().for_each(|child| walk(child, page)),
            Value::Object(map) => {
                if let Some(renderer) = map.get("backstagePostRenderer").filter(|v| !v.is_null()).or_else(|| map.get("postRenderer")).filter(|v| v.is_object()) {
                    if let Some(found) = post(renderer)
                        && !page.posts.iter().any(|p| p.id == found.id)
                    {
                        page.posts.push(found);
                    }
                    return;
                }
                if let Some(Value::String(token)) = at(node, &["continuationItemRenderer", "continuationEndpoint", "continuationCommand", "token"]) {
                    page.continuation = Some(token.clone());
                }
                map.values().filter(|v| v.is_object() || v.is_array()).for_each(|v| walk(v, page));
            }
            _ => {}
        }
    }
    let mut page = Page::default();
    walk(data, &mut page);
    page
}

/// The comment section's continuation token in a page's `ytInitialData`.
pub fn section_token(data: &Value) -> Option<String> {
    match data {
        Value::Array(list) => list.iter().find_map(section_token),
        Value::Object(map) => {
            if let Some(section) = map.get("itemSectionRenderer").filter(|v| v.is_object())
                && section.get("sectionIdentifier").and_then(Value::as_str) == Some("comment-item-section")
            {
                return token(section.get("contents"));
            }
            map.values().filter(|v| v.is_object() || v.is_array()).find_map(section_token)
        }
        _ => None,
    }
}

/// [page] of a browse response, or of the `ytInitialData` of the HTML page
/// [body], as JSON; null when there is neither.
///
/// # Safety
/// [body] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_youtube_posts(body: *const u8, length: usize) -> *mut c_char {
    let body = unsafe { text(body, length) };
    let data = if body.trim_start().starts_with('{') { serde_json::from_str(body).ok() } else { initial_data(body) };
    data.map_or(std::ptr::null_mut(), |data| give_json(&page(&data)))
}

/// The comment section token of a community post's HTML page, as a JSON
/// string or null.
///
/// # Safety
/// [html] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_youtube_post_comments(html: *const u8, length: usize) -> *mut c_char {
    give_json(&initial_data(unsafe { text(html, length) }).and_then(|data| section_token(&data)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn finds_the_initial_data() {
        let html = r#"<script>var ytInitialData = {"a":"};{","b":{"c":1},"d":"\"}"};</script>"#;
        assert_eq!(initial_data(html), Some(json!({"a": "};{", "b": {"c": 1}, "d": "\"}"})));
        assert_eq!(initial_data(r#"window["ytInitialData"]={"x":[1]};"#), Some(json!({"x": [1]})));
        assert_eq!(initial_data("<html></html>"), None);
    }

    #[test]
    fn reads_posts_and_the_next_token() {
        let data = json!({"contents": [
            {"backstagePostThreadRenderer": {"post": {"backstagePostRenderer": {
                "postId": "P1",
                "contentText": {"runs": [{"text": "你好 "}, {"text": "世界"}]},
                "publishedTimeText": {"runs": [{"text": "3天前"}]},
                "voteCount": {"simpleText": "12"},
                "actionButtons": {"commentActionButtonsRenderer": {"replyButton": {"buttonRenderer": {"text": {"simpleText": "4"}}}}},
                "backstageAttachment": {"postMultiImageRenderer": {"images": [
                    {"backstageImageRenderer": {"image": {"thumbnails": [{"url": "//small"}, {"url": "//yt3.ggpht.com/big"}]}}},
                    {"backstageImageRenderer": {"image": {"thumbnails": [{"url": "http://insecure"}]}}}
                ]}}
            }}}},
            {"postRenderer": {"postId": "P2", "backstageAttachment": {"videoRenderer": {
                "videoId": "dQw4w9WgXcQ", "title": {"runs": [{"text": "视频"}]}, "ownerText": {"runs": [{"text": "频道"}]}, "lengthText": {"simpleText": "1:02:03"}
            }}}},
            {"postRenderer": {"postId": "P3", "backstageAttachment": {"pollRenderer": {"choices": [{"text": {"runs": [{"text": "是"}]}}, {"text": {}}]}}}},
            {"postRenderer": {"postId": "P1"}},
            {"continuationItemRenderer": {"continuationEndpoint": {"continuationCommand": {"token": "NEXT"}}}}
        ]});
        let page = page(&data);
        assert_eq!(page.continuation.as_deref(), Some("NEXT"));
        assert_eq!(page.posts.len(), 3);
        let first = &page.posts[0];
        assert_eq!((first.text.as_str(), first.published.as_str(), first.likes.as_str(), first.comments.as_str()), ("你好 世界", "3天前", "12", "4"));
        assert_eq!(first.images, ["https://yt3.ggpht.com/big"]);
        assert_eq!(page.posts[1].video, Some(AttachedVideo { id: "dQw4w9WgXcQ".into(), title: "视频".into(), channel: "频道".into(), duration: Some(3723) }));
        assert_eq!(page.posts[2].poll, ["是"]);
    }

    #[test]
    fn finds_the_comment_section_of_a_post_page() {
        let continuation = |token: &str| json!({"continuationItemRenderer": {"continuationEndpoint": {"continuationCommand": {"token": token}}}});
        let data = json!({"contents": [
            {"itemSectionRenderer": {"sectionIdentifier": "other", "contents": [continuation("NO")]}},
            {"itemSectionRenderer": {"sectionIdentifier": "comment-item-section", "contents": [continuation("POST-COMMENTS")]}}
        ]});
        assert_eq!(section_token(&data).as_deref(), Some("POST-COMMENTS"));
        assert_eq!(section_token(&json!({})), None);
    }
}
