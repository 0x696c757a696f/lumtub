//! yt-dlp's `live_chat` subtitle stream: one JSON action per line. Replay
//! actions carry an offset into the video; current live chat does not.

use serde::Serialize;
use serde_json::Value;
use std::os::raw::c_char;

use crate::comments::{Emojis, display, emoji_run};
use crate::taste::{give_json, text};

#[derive(Serialize, Debug, PartialEq, Clone, Copy)]
#[serde(rename_all = "camelCase")]
pub enum Kind {
    Message,
    PaidMessage,
    PaidSticker,
    Membership,
    System,
}

#[derive(Serialize, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Message {
    pub id: String,
    pub kind: Kind,
    pub text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub offset_ms: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub timestamp_usec: Option<i64>,
    pub author: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub author_channel_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub author_avatar: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub amount: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sticker_url: Option<String>,
    #[serde(skip_serializing_if = "Emojis::is_empty")]
    pub emojis: Emojis,
}

/// Chat text: `simpleText`, or runs of text and emoji, custom emoji's
/// pictures going to [emojis].
fn chat_text(node: Option<&Value>, emojis: &mut Emojis) -> String {
    let Some(Value::Object(map)) = node else { return String::new() };
    if let Some(Value::String(simple)) = map.get("simpleText") {
        return simple.clone();
    }
    let Some(Value::Array(runs)) = map.get("runs") else { return String::new() };
    runs.iter()
        .filter(|run| run.is_object())
        .map(|run| {
            if let Some(Value::String(text)) = run.get("text") {
                return text.clone();
            }
            match run.get("emoji") {
                Some(emoji @ Value::Object(_)) => emoji_run(emoji, emojis),
                _ => String::new(),
            }
        })
        .collect()
}

/// The last thumbnail address under [node]'s `thumbnails`.
fn last_thumbnail(node: Option<&Value>) -> Option<String> {
    node?.get("thumbnails")?.as_array()?.iter().filter_map(|t| t.get("url")?.as_str()).next_back().map(str::to_owned)
}

fn integer(value: Option<&Value>) -> Option<i64> {
    display(value?).parse().ok()
}

fn message(item: &Value, offset_ms: Option<i64>) -> Option<Message> {
    const KINDS: [(&str, Kind); 5] = [
        ("liveChatTextMessageRenderer", Kind::Message),
        ("liveChatPaidMessageRenderer", Kind::PaidMessage),
        ("liveChatPaidStickerRenderer", Kind::PaidSticker),
        ("liveChatMembershipItemRenderer", Kind::Membership),
        ("liveChatViewerEngagementMessageRenderer", Kind::System),
    ];
    let (kind, renderer) = KINDS.iter().find_map(|(key, kind)| item.get(*key).filter(|r| r.is_object()).map(|r| (*kind, r)))?;
    let id = renderer.get("id").map(display).unwrap_or_default();
    if id.is_empty() {
        return None;
    }
    let mut emojis = Emojis::new();
    let text = ["message", "headerSubtext", "headerPrimaryText"].iter().map(|key| chat_text(renderer.get(*key), &mut emojis)).find(|t| !t.is_empty()).unwrap_or_default();
    let mut ignored = Emojis::new();
    let amount = chat_text(renderer.get("purchaseAmountText"), &mut ignored);
    Some(Message {
        id,
        kind,
        text,
        offset_ms,
        timestamp_usec: integer(renderer.get("timestampUsec")),
        author: chat_text(renderer.get("authorName"), &mut ignored),
        author_channel_id: renderer.get("authorExternalChannelId").filter(|v| !v.is_null()).map(display),
        author_avatar: last_thumbnail(renderer.get("authorPhoto").filter(|p| p.is_object())),
        amount: (!amount.is_empty()).then_some(amount),
        sticker_url: last_thumbnail(renderer.get("sticker").filter(|s| s.is_object())),
        emojis,
    })
}

/// The chat items of one yt-dlp `live_chat` line. Status actions without a
/// chat item and unknown renderers are left out.
pub fn line(line: &str) -> Vec<Message> {
    let Ok(raw) = serde_json::from_str::<Value>(line) else { return Vec::new() };
    let action = raw.get("replayChatItemAction").filter(|r| r.is_object()).unwrap_or(&raw);
    let offset_ms = integer(action.get("videoOffsetTimeMsec"));
    let Some(Value::Array(actions)) = action.get("actions") else { return Vec::new() };
    actions.iter().filter_map(|entry| entry.get("addChatItemAction")?.get("item").filter(|i| i.is_object())).filter_map(|item| message(item, offset_ms)).collect()
}

/// The chat items of every line of [contents].
pub fn lines(contents: &str) -> Vec<Message> {
    contents.lines().filter(|l| !l.trim().is_empty()).flat_map(line).collect()
}

/// [lines] as JSON.
///
/// # Safety
/// [contents] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_live_chat(contents: *const u8, length: usize) -> *mut c_char {
    give_json(&lines(unsafe { text(contents, length) }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn reads_replay_and_live_lines() {
        let replay = json!({"replayChatItemAction": {"videoOffsetTimeMsec": "61500", "actions": [
            {"addChatItemAction": {"item": {"liveChatTextMessageRenderer": {
                "id": "m1", "timestampUsec": "1700000000000000",
                "message": {"runs": [{"text": "hi "}, {"emoji": {"shortcuts": [":wave:"]}}, {"emoji": {"accessibility": {"accessibilityData": {"label": "smile"}}}}]},
                "authorName": {"simpleText": "Ann"}, "authorExternalChannelId": "UCann",
                "authorPhoto": {"thumbnails": [{"url": "https://a/s"}, {"url": "https://a/l"}]}
            }}}},
            {"addChatItemAction": {"item": {"liveChatPlaceholderItemRenderer": {"id": "x"}}}},
            {"markChatItemAsDeletedAction": {}}
        ]}});
        let live = json!({"actions": [{"addChatItemAction": {"item": {"liveChatPaidStickerRenderer": {
            "id": "s1", "purchaseAmountText": {"simpleText": "$5.00"}, "sticker": {"thumbnails": [{"url": "https://s/1"}]}
        }}}}]});
        let messages = lines(&format!("{replay}\n\n{live}\nnot json\n"));
        assert_eq!(messages.len(), 2);
        assert_eq!(
            messages[0],
            Message {
                id: "m1".into(),
                kind: Kind::Message,
                text: "hi :wave:smile".into(),
                offset_ms: Some(61_500),
                timestamp_usec: Some(1_700_000_000_000_000),
                author: "Ann".into(),
                author_channel_id: Some("UCann".into()),
                author_avatar: Some("https://a/l".into()),
                amount: None,
                sticker_url: None,
                emojis: Emojis::new(),
            }
        );
        let sticker = &messages[1];
        let custom = json!({"addChatItemAction": {"item": {"liveChatTextMessageRenderer": {
            "id": "m3", "authorName": {"simpleText": "Bo"},
            "message": {"runs": [
                {"emoji": {"emojiId": "\u{1F600}", "shortcuts": [":grinning:"], "image": {"thumbnails": [{"url": "https://e/g"}]}}},
                {"text": " "},
                {"emoji": {"emojiId": "UC/abc", "isCustomEmoji": true, "shortcuts": [":_wave:"], "image": {"thumbnails": [{"url": "//yt3/s"}, {"url": "https://yt3/l"}]}}},
            ]},
        }}}});
        let custom = &lines(&json!({"actions": [custom]}).to_string())[0];
        assert_eq!(custom.text, "\u{1F600} :_wave:");
        assert_eq!(custom.emojis, Emojis::from([(":_wave:".into(), "https://yt3/l".into())]));
        assert_eq!((sticker.kind, sticker.offset_ms, sticker.amount.as_deref(), sticker.sticker_url.as_deref()), (Kind::PaidSticker, None, Some("$5.00"), Some("https://s/1")));
    }
}
