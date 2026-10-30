//! yt-dlp's `live_chat` subtitle stream: one JSON action per line. Replay
//! actions carry an offset into the video; current live chat does not.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::os::raw::c_char;

use crate::comments::{Emojis, display, emoji_run, find_string};
use crate::innertube::text_of;
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

/// The first object under key [name] anywhere in [node].
fn find_object<'a>(node: &'a Value, name: &str) -> Option<&'a Value> {
    match node {
        Value::Object(map) => match map.get(name) {
            Some(found @ Value::Object(_)) => Some(found),
            _ => map.values().filter(|v| v.is_object() || v.is_array()).find_map(|v| find_object(v, name)),
        },
        Value::Array(list) => list.iter().find_map(|v| find_object(v, name)),
        _ => None,
    }
}

/// What the website's chat box offers, read from a `next` answer (the
/// chat's [continuation]) or a `live_chat/get_live_chat` answer ([params]
/// to send with, or why this account may not write).
#[derive(Serialize, Debug, PartialEq, Default)]
#[serde(rename_all = "camelCase")]
pub struct Composer {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub continuation: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub params: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub restricted: Option<String>,
}

pub fn composer(answer: &Value) -> Composer {
    let continuation = find_object(answer, "liveChatRenderer").and_then(|chat| find_string(chat, "continuation"));
    let params = find_object(answer, "liveChatMessageInputRenderer")
        .and_then(|input| find_object(input, "sendLiveChatMessageEndpoint"))
        .and_then(|endpoint| endpoint.get("params")?.as_str().map(str::to_owned));
    let restricted = if params.is_some() {
        None
    } else {
        find_object(answer, "liveChatRestrictedParticipationRenderer").map(|r| text_of(r.get("message"))).filter(|t| !t.is_empty())
    };
    Composer { continuation, params, restricted }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Send {
    params: String,
    text: String,
    client_message_id: String,
}

/// The `live_chat/send_message` request for [text].
fn send_body(send: &Send) -> Value {
    serde_json::json!({
        "params": send.params,
        "clientMessageId": send.client_message_id,
        "richMessage": {"textSegments": [{"text": send.text}]},
    })
}

/// [composer] of the answer [json].
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_live_chat_composer(json: *const u8, length: usize) -> *mut c_char {
    let answer = serde_json::from_str::<Value>(unsafe { text(json, length) }).unwrap_or(Value::Null);
    give_json(&composer(&answer))
}

/// The send request of [json] `{params, text, clientMessageId}`, or null.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_live_chat_send_body(json: *const u8, length: usize) -> *mut c_char {
    match serde_json::from_str::<Send>(unsafe { text(json, length) }) {
        Ok(send) if !send.text.trim().is_empty() => give_json(&send_body(&send)),
        _ => std::ptr::null_mut(),
    }
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

    #[test]
    fn reads_the_websites_chat_box() {
        let next = json!({"contents": {"twoColumnWatchNextResults": {"conversationBar": {"liveChatRenderer": {
            "continuations": [{"reloadContinuationData": {"continuation": "0ofMyAN"}}]}}}}});
        assert_eq!(composer(&next).continuation.as_deref(), Some("0ofMyAN"));
        let chat = json!({"continuationContents": {"liveChatContinuation": {"actionPanel": {"liveChatMessageInputRenderer": {
            "sendButton": {"buttonRenderer": {"serviceEndpoint": {"sendLiveChatMessageEndpoint": {"params": "Q2lrcU"}}}}}}}}});
        assert_eq!(composer(&chat), Composer { continuation: None, params: Some("Q2lrcU".into()), restricted: None });
        let members = json!({"continuationContents": {"liveChatContinuation": {"actionPanel": {"liveChatRestrictedParticipationRenderer": {
            "message": {"runs": [{"text": "Chat is in "}, {"text": "members-only mode"}]}}}}}});
        assert_eq!(composer(&members).restricted.as_deref(), Some("Chat is in members-only mode"));
        let body = send_body(&Send { params: "p".into(), text: "hi".into(), client_message_id: "c".into() });
        assert_eq!(body, json!({"params": "p", "clientMessageId": "c", "richMessage": {"textSegments": [{"text": "hi"}]}}));
    }
}
