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
    /// The chat's mode changed: slow mode, subscribers-only or members-only
    /// mode turned on or off.
    Mode,
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
    /// The colour YouTube gives a Super Chat or Super Sticker by its
    /// amount, as ARGB.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub color: Option<u32>,
    /// How long YouTube keeps a Super Chat of this colour in the strip
    /// over the chat, in seconds.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ticker_seconds: Option<u32>,
    #[serde(skip_serializing_if = "Emojis::is_empty")]
    pub emojis: Emojis,
}

/// Chat text: `simpleText`, or runs of text and emoji, custom emoji's
/// pictures going to [emojis].
fn chat_text(node: Option<&Value>, emojis: &mut Emojis) -> String {
    let Some(Value::Object(map)) = node else {
        return String::new();
    };
    if let Some(Value::String(simple)) = map.get("simpleText") {
        return simple.clone();
    }
    let Some(Value::Array(runs)) = map.get("runs") else {
        return String::new();
    };
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
    node?
        .get("thumbnails")?
        .as_array()?
        .iter()
        .filter_map(|t| t.get("url")?.as_str())
        .next_back()
        .map(str::to_owned)
}

fn integer(value: Option<&Value>) -> Option<i64> {
    display(value?).parse().ok()
}

fn message(item: &Value, offset_ms: Option<i64>) -> Option<Message> {
    const KINDS: [(&str, Kind); 6] = [
        ("liveChatTextMessageRenderer", Kind::Message),
        ("liveChatPaidMessageRenderer", Kind::PaidMessage),
        ("liveChatPaidStickerRenderer", Kind::PaidSticker),
        ("liveChatMembershipItemRenderer", Kind::Membership),
        ("liveChatViewerEngagementMessageRenderer", Kind::System),
        ("liveChatModeChangeMessageRenderer", Kind::Mode),
    ];
    let (kind, renderer) = KINDS
        .iter()
        .find_map(|(key, kind)| item.get(*key).filter(|r| r.is_object()).map(|r| (*kind, r)))?;
    let mut emojis = Emojis::new();
    let mut text = ["message", "headerSubtext", "headerPrimaryText", "text"]
        .iter()
        .map(|key| chat_text(renderer.get(*key), &mut emojis))
        .find(|t| !t.is_empty())
        .unwrap_or_default();
    if kind == Kind::Mode {
        let more = chat_text(renderer.get("subtext"), &mut emojis);
        if !more.is_empty() {
            text = if text.is_empty() {
                more
            } else {
                format!("{text} · {more}")
            };
        }
    }
    let mut id = renderer.get("id").map(display).unwrap_or_default();
    // A mode change may come without an id; the same change read twice
    // still gets the same one.
    if id.is_empty() && kind == Kind::Mode && !text.is_empty() {
        let time = renderer
            .get("timestampUsec")
            .map(display)
            .unwrap_or_default();
        id = format!("mode:{time}:{text}");
    }
    if id.is_empty() {
        return None;
    }
    let mut ignored = Emojis::new();
    let amount = chat_text(renderer.get("purchaseAmountText"), &mut ignored);
    let color = ["bodyBackgroundColor", "backgroundColor"]
        .iter()
        .find_map(|key| integer(renderer.get(*key)))
        .and_then(|c| u32::try_from(c).ok());
    Some(Message {
        id,
        kind,
        text,
        offset_ms,
        timestamp_usec: integer(renderer.get("timestampUsec")),
        author: chat_text(renderer.get("authorName"), &mut ignored),
        author_channel_id: renderer
            .get("authorExternalChannelId")
            .filter(|v| !v.is_null())
            .map(display),
        author_avatar: last_thumbnail(renderer.get("authorPhoto").filter(|p| p.is_object())),
        amount: (!amount.is_empty()).then_some(amount),
        sticker_url: last_thumbnail(renderer.get("sticker").filter(|s| s.is_object())),
        color,
        ticker_seconds: color.map(ticker_seconds).filter(|s| *s > 0),
        emojis,
    })
}

/// How long a Super Chat stays in the strip over the chat, from the
/// colour of its amount tier: blue and cyan not at all, green 2 minutes,
/// yellow 5, orange 10, magenta 30 and red an hour.
fn ticker_seconds(argb: u32) -> u32 {
    let [r, g, b] =
        [(argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF].map(|c| c as f32 / 255.0);
    let (max, min) = (r.max(g).max(b), r.min(g).min(b));
    if max - min < 0.1 {
        return 120;
    }
    let delta = max - min;
    let hue = if max == r {
        60.0 * ((g - b) / delta).rem_euclid(6.0)
    } else if max == g {
        60.0 * ((b - r) / delta + 2.0)
    } else {
        60.0 * ((r - g) / delta + 4.0)
    };
    match hue {
        h if !(15.0..350.0).contains(&h) => 3600,
        h if h < 38.0 => 600,
        h if h < 75.0 => 300,
        h if h < 175.0 => 120,
        h if h < 290.0 => 0,
        _ => 1800,
    }
}

/// The chat items of one yt-dlp `live_chat` line. Status actions without a
/// chat item and unknown renderers are left out.
pub fn line(line: &str) -> Vec<Message> {
    let Ok(raw) = serde_json::from_str::<Value>(line) else {
        return Vec::new();
    };
    let action = raw
        .get("replayChatItemAction")
        .filter(|r| r.is_object())
        .unwrap_or(&raw);
    let offset_ms = integer(action.get("videoOffsetTimeMsec"));
    let Some(Value::Array(actions)) = action.get("actions") else {
        return Vec::new();
    };
    actions
        .iter()
        .filter_map(added_item)
        .filter_map(|item| message(item, offset_ms))
        .collect()
}

/// The item an `addChatItemAction` adds.
fn added_item(action: &Value) -> Option<&Value> {
    action
        .get("addChatItemAction")?
        .get("item")
        .filter(|i| i.is_object())
}

/// The most chat items read from one replay file.
const MAX_MESSAGES: usize = 200_000;

/// The chat items of every line of [contents], up to [MAX_MESSAGES].
pub fn lines(contents: &str) -> Vec<Message> {
    contents
        .lines()
        .filter(|l| !l.trim().is_empty())
        .flat_map(line)
        .take(MAX_MESSAGES)
        .collect()
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
            _ => map
                .values()
                .filter(|v| v.is_object() || v.is_array())
                .find_map(|v| find_object(v, name)),
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
    /// The channel's own emoji the chat offers.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub emojis: Vec<ChatEmoji>,
}

/// A channel emoji: what to send for it, how it is typed and its picture.
/// [locked] ones are for the channel's members.
#[derive(Serialize, Debug, PartialEq, Clone)]
pub struct ChatEmoji {
    pub id: String,
    pub shortcut: String,
    pub url: String,
    pub locked: bool,
}

/// The first array under key [name] anywhere in [node].
fn find_array<'a>(node: &'a Value, name: &str) -> Option<&'a Vec<Value>> {
    match node {
        Value::Object(map) => match map.get(name) {
            Some(Value::Array(found)) => Some(found),
            _ => map
                .values()
                .filter(|v| v.is_object() || v.is_array())
                .find_map(|v| find_array(v, name)),
        },
        Value::Array(list) => list.iter().find_map(|v| find_array(v, name)),
        _ => None,
    }
}

/// The channel emoji listed in a chat answer (`emojis` of the live chat).
fn chat_emojis(answer: &Value) -> Vec<ChatEmoji> {
    let Some(list) = find_array(answer, "emojis") else {
        return Vec::new();
    };
    list.iter()
        .filter(|e| e.get("isCustomEmoji").and_then(Value::as_bool) == Some(true))
        .filter_map(|e| {
            let id = e.get("emojiId")?.as_str()?.to_owned();
            let shortcut = e
                .get("shortcuts")?
                .as_array()?
                .iter()
                .filter_map(Value::as_str)
                .find(|s| s.starts_with(':') && s.ends_with(':'))?
                .to_owned();
            let url = e
                .pointer("/image/thumbnails")?
                .as_array()?
                .last()?
                .get("url")?
                .as_str()?;
            let url = if url.starts_with("//") {
                format!("https:{url}")
            } else {
                url.to_owned()
            };
            let locked = e.get("isLocked").and_then(Value::as_bool).unwrap_or(false);
            Some(ChatEmoji {
                id,
                shortcut,
                url,
                locked,
            })
        })
        .collect()
}

pub fn composer(answer: &Value) -> Composer {
    let continuation =
        find_object(answer, "liveChatRenderer").and_then(|chat| find_string(chat, "continuation"));
    let params = find_object(answer, "liveChatMessageInputRenderer")
        .and_then(|input| find_object(input, "sendLiveChatMessageEndpoint"))
        .and_then(|endpoint| endpoint.get("params")?.as_str().map(str::to_owned));
    let restricted = if params.is_some() {
        None
    } else {
        find_object(answer, "liveChatRestrictedParticipationRenderer")
            .map(|r| text_of(r.get("message")))
            .filter(|t| !t.is_empty())
    };
    Composer {
        continuation,
        params,
        restricted,
        emojis: chat_emojis(answer),
    }
}

/// One way of reading a chat as YouTube offers it: Top chat, which leaves
/// out messages such as possible spam, or Live chat, every message.
#[derive(Serialize, Debug, PartialEq)]
pub struct View {
    pub continuation: String,
    pub selected: bool,
}

/// What one answer of `next`, `live_chat/get_live_chat` or
/// `live_chat/get_live_chat_replay` says about the chat.
#[derive(Serialize, Debug, PartialEq, Default)]
#[serde(rename_all = "camelCase")]
pub struct Answer {
    /// From `next`: the request that opens the video's chat.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub start: Option<String>,
    /// The visitor id YouTube gave, sent back with the requests that follow.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub visitor: Option<String>,
    /// From `next`: whether that chat is a replay.
    #[serde(skip_serializing_if = "std::ops::Not::not")]
    pub replay: bool,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub messages: Vec<Message>,
    /// The request for what comes next; none once the chat has ended.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub next: Option<String>,
    /// How long YouTube asks to wait before [next].
    #[serde(skip_serializing_if = "Option::is_none")]
    pub timeout_ms: Option<u64>,
    /// The chat's views, Top chat first, when the answer names them.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub views: Vec<View>,
    /// Who may write, when not everyone may (members-only mode).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub restricted: Option<String>,
    /// Messages taken down by the channel's moderators.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub removed: Vec<String>,
    /// Channels whose messages were all taken down.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub removed_authors: Vec<String>,
}

/// The most messages, and the most ids taken down, read from one answer.
const ANSWER_ITEMS: usize = 20_000;
/// The most views read; YouTube offers two.
const VIEWS: usize = 4;

/// The continuation of a `continuations` entry, in the order the website
/// follows them, with its wait.
fn next_of(chat: &Value) -> Option<(String, Option<u64>)> {
    const KINDS: [&str; 4] = [
        "invalidationContinuationData",
        "timedContinuationData",
        "liveChatReplayContinuationData",
        "reloadContinuationData",
    ];
    let list = chat.get("continuations")?.as_array()?;
    KINDS.iter().find_map(|kind| {
        list.iter().find_map(|entry| {
            let data = entry.get(*kind)?;
            let continuation = data.get("continuation")?.as_str()?;
            if continuation.is_empty() {
                return None;
            }
            let wait = integer(data.get("timeoutMs")).and_then(|ms| u64::try_from(ms).ok());
            Some((continuation.to_owned(), wait))
        })
    })
}

/// The views of a chat's header.
fn views_of(chat: &Value) -> Vec<View> {
    let items = chat
        .pointer(
            "/header/liveChatHeaderRenderer/viewSelector/sortFilterSubMenuRenderer/subMenuItems",
        )
        .and_then(Value::as_array)
        .or_else(|| find_object(chat, "viewSelector").and_then(|s| find_array(s, "subMenuItems")));
    let Some(items) = items else {
        return Vec::new();
    };
    items
        .iter()
        .filter_map(|item| {
            let continuation = item
                .pointer("/continuation/reloadContinuationData/continuation")
                .and_then(Value::as_str)
                .map(str::to_owned)
                .or_else(|| find_string(item.get("continuation")?, "continuation"))?;
            let selected = item
                .get("selected")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            Some(View {
                continuation,
                selected,
            })
        })
        .take(VIEWS)
        .collect()
}

/// Reads one chat action into [out]; [offset_ms] is a replay's position.
fn read_action(action: &Value, offset_ms: Option<i64>, out: &mut Answer) {
    if let Some(item) = added_item(action) {
        if out.messages.len() < ANSWER_ITEMS
            && let Some(message) = message(item, offset_ms)
        {
            out.messages.push(message);
        }
        return;
    }
    let target = |key: &str, field: &str| {
        action
            .get(key)?
            .get(field)?
            .as_str()
            .filter(|id| !id.is_empty())
            .map(str::to_owned)
    };
    if let Some(id) = target("removeChatItemAction", "targetItemId")
        .or_else(|| target("markChatItemAsDeletedAction", "targetItemId"))
    {
        if out.removed.len() < ANSWER_ITEMS {
            out.removed.push(id);
        }
    } else if let Some(channel) = target("removeChatItemByAuthorAction", "externalChannelId")
        .or_else(|| target("markChatItemsByAuthorAsDeletedAction", "externalChannelId"))
        && out.removed_authors.len() < ANSWER_ITEMS
    {
        out.removed_authors.push(channel);
    }
}

pub fn answer(value: &Value) -> Answer {
    let mut out = Answer {
        visitor: value
            .pointer("/responseContext/visitorData")
            .and_then(Value::as_str)
            .filter(|v| !v.is_empty() && v.len() <= 512)
            .map(str::to_owned),
        ..Answer::default()
    };
    if let Some(renderer) = value
        .pointer("/contents/twoColumnWatchNextResults/conversationBar/liveChatRenderer")
        .filter(|r| r.is_object())
    {
        out.start = renderer
            .get("continuations")
            .and_then(Value::as_array)
            .and_then(|list| {
                list.iter().find_map(|c| {
                    c.pointer("/reloadContinuationData/continuation")?
                        .as_str()
                        .filter(|c| !c.is_empty())
                        .map(str::to_owned)
                })
            });
        out.replay = renderer
            .get("isReplay")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        out.views = views_of(renderer);
        return out;
    }
    let Some(chat) = value
        .pointer("/continuationContents/liveChatContinuation")
        .or_else(|| value.pointer("/contents/liveChatRenderer"))
        .filter(|c| c.is_object())
    else {
        return out;
    };
    if let Some(Value::Array(actions)) = chat.get("actions") {
        for action in actions {
            match action.get("replayChatItemAction") {
                Some(replay @ Value::Object(_)) => {
                    let offset_ms = integer(replay.get("videoOffsetTimeMsec"));
                    if let Some(Value::Array(inner)) = replay.get("actions") {
                        for action in inner {
                            read_action(action, offset_ms, &mut out);
                        }
                    }
                }
                _ => read_action(action, None, &mut out),
            }
        }
    }
    if let Some((next, wait)) = next_of(chat) {
        out.next = Some(next);
        out.timeout_ms = wait;
    }
    out.views = views_of(chat);
    out.restricted = chat
        .pointer("/actionPanel/liveChatRestrictedParticipationRenderer")
        .map(|r| text_of(r.get("message")))
        .filter(|t| !t.is_empty());
    out
}

/// [answer] of the answer [json]; an empty one for anything else.
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_live_chat_answer(json: *const u8, length: usize) -> *mut c_char {
    // SAFETY: the caller gives [length] bytes at [json].
    let value = serde_json::from_str::<Value>(unsafe { crate::taste::outside(json, length) })
        .unwrap_or(Value::Null);
    give_json(&answer(&value))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Send {
    params: String,
    text: String,
    client_message_id: String,
    /// Shortcut to emoji id of the channel emoji that can be sent.
    #[serde(default)]
    emojis: std::collections::HashMap<String, String>,
}

/// [text] as the website's message segments: each known channel emoji
/// shortcut (`:_wave:`) as its emoji, the rest as text.
fn segments(text: &str, emojis: &std::collections::HashMap<String, String>) -> Vec<Value> {
    let mut out = Vec::new();
    let mut plain = String::new();
    let mut rest = text;
    while let Some(start) = rest.find(':') {
        let after = &rest[start + 1..];
        let found = after
            .find(':')
            .map(|end| &rest[start..start + end + 2])
            .filter(|code| emojis.contains_key(*code));
        match found {
            Some(code) => {
                plain.push_str(&rest[..start]);
                if !plain.is_empty() {
                    out.push(serde_json::json!({"text": std::mem::take(&mut plain)}));
                }
                out.push(serde_json::json!({"emojiId": emojis[code]}));
                rest = &rest[start + code.len()..];
            }
            None => {
                plain.push_str(&rest[..=start]);
                rest = after;
            }
        }
    }
    plain.push_str(rest);
    if !plain.is_empty() {
        out.push(serde_json::json!({"text": plain}));
    }
    out
}

/// The `live_chat/send_message` request for [text].
fn send_body(send: &Send) -> Value {
    serde_json::json!({
        "params": send.params,
        "clientMessageId": send.client_message_id,
        "richMessage": {"textSegments": segments(&send.text, &send.emojis)},
    })
}

/// [composer] of the answer [json].
///
/// # Safety
/// [json] must point to [length] bytes of UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lumtub_live_chat_composer(json: *const u8, length: usize) -> *mut c_char {
    let answer = serde_json::from_str::<Value>(unsafe { crate::taste::outside(json, length) })
        .unwrap_or(Value::Null);
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
            "id": "s1", "purchaseAmountText": {"simpleText": "$5.00"}, "backgroundColor": 4280150454u32, "sticker": {"thumbnails": [{"url": "https://s/1"}]}
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
                color: None,
                ticker_seconds: None,
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
        assert_eq!(
            custom.emojis,
            Emojis::from([
                (":_wave:".into(), "https://yt3/l".into()),
                ("\u{1F600}".into(), "https://e/g".into())
            ])
        );
        assert_eq!(
            (
                sticker.kind,
                sticker.offset_ms,
                sticker.amount.as_deref(),
                sticker.sticker_url.as_deref()
            ),
            (Kind::PaidSticker, None, Some("$5.00"), Some("https://s/1"))
        );
        assert_eq!(
            (sticker.color, sticker.ticker_seconds),
            (Some(0xFF1DE9B6), Some(120))
        );
        let tiers = [
            0xFF1E88E5u32,
            0xFF00E5FF,
            0xFF1DE9B6,
            0xFFFFCA28,
            0xFFF57C00,
            0xFFE91E63,
            0xFFE62117,
        ]
        .map(ticker_seconds);
        assert_eq!(tiers, [0, 0, 120, 300, 600, 1800, 3600]);
    }

    #[test]
    fn reads_chat_answers() {
        let next = json!({"contents": {"twoColumnWatchNextResults": {"conversationBar": {"liveChatRenderer": {
            "continuations": [{"reloadContinuationData": {"continuation": "start"}}], "isReplay": true}}}}});
        let mut next = next;
        next["responseContext"] = json!({"visitorData": "Cgt2"});
        let opened = answer(&next);
        assert_eq!(opened.visitor.as_deref(), Some("Cgt2"));
        assert_eq!(opened.start.as_deref(), Some("start"));
        assert!(opened.replay);
        let live = json!({"continuationContents": {"liveChatContinuation": {
        "continuations": [{"invalidationContinuationData": {"continuation": "next", "timeoutMs": 5000}}],
        "header": {"liveChatHeaderRenderer": {"viewSelector": {"sortFilterSubMenuRenderer": {"subMenuItems": [
            {"title": "Top chat", "selected": true, "continuation": {"reloadContinuationData": {"continuation": "top"}}},
            {"title": "Live chat", "selected": false, "continuation": {"reloadContinuationData": {"continuation": "all"}}}]}}}},
        "actionPanel": {"liveChatRestrictedParticipationRenderer": {"message": {"runs": [{"text": "Members-only mode"}]}}},
        "actions": [
            {"addChatItemAction": {"item": {"liveChatTextMessageRenderer": {"id": "m1", "message": {"simpleText": "hi"}, "authorName": {"simpleText": "a"}}}}},
            {"addChatItemAction": {"item": {"liveChatModeChangeMessageRenderer": {"timestampUsec": "7",
                "icon": {"iconType": "SLOW_MODE"}, "text": {"runs": [{"text": "Slow mode is on", "bold": true}]},
                "subtext": {"runs": [{"text": "Send a message every "}, {"text": "30 seconds"}]}}}}},
            {"markChatItemAsDeletedAction": {"targetItemId": "m0"}},
            {"removeChatItemByAuthorAction": {"externalChannelId": "UCspam"}},
            {"addLiveChatTickerItemAction": {}},
            "nonsense"
        ]}}});
        let read = answer(&live);
        assert_eq!(read.next.as_deref(), Some("next"));
        assert_eq!(read.timeout_ms, Some(5000));
        assert_eq!(
            read.views,
            vec![
                View {
                    continuation: "top".into(),
                    selected: true
                },
                View {
                    continuation: "all".into(),
                    selected: false
                }
            ]
        );
        assert_eq!(read.restricted.as_deref(), Some("Members-only mode"));
        assert_eq!(read.messages.len(), 2);
        assert_eq!(read.messages[1].kind, Kind::Mode);
        assert_eq!(
            read.messages[1].text,
            "Slow mode is on · Send a message every 30 seconds"
        );
        assert_eq!(
            read.messages[1].id,
            "mode:7:Slow mode is on · Send a message every 30 seconds"
        );
        assert_eq!(read.removed, vec!["m0".to_string()]);
        assert_eq!(read.removed_authors, vec!["UCspam".to_string()]);
        let replay = json!({"continuationContents": {"liveChatContinuation": {
            "continuations": [{"playerSeekContinuationData": {"continuation": "seek"}}, {"liveChatReplayContinuationData": {"continuation": "more"}}],
            "actions": [{"replayChatItemAction": {"videoOffsetTimeMsec": "1500", "actions": [
                {"addChatItemAction": {"item": {"liveChatTextMessageRenderer": {"id": "r1", "message": {"simpleText": "old"}}}}}]}}]}}});
        let read = answer(&replay);
        assert_eq!(read.next.as_deref(), Some("more"));
        assert_eq!(read.messages[0].offset_ms, Some(1500));
        assert_eq!(
            answer(&json!({"continuationContents": {"liveChatContinuation": {}}})),
            Answer::default()
        );
        assert_eq!(answer(&json!([1, 2])), Answer::default());
        let ended = json!({"continuationContents": {"liveChatContinuation": {"continuations": [{"timedContinuationData": {"continuation": "", "timeoutMs": -5}}]}}});
        assert_eq!(answer(&ended).next, None);
    }

    #[test]
    fn reads_the_websites_chat_box() {
        let next = json!({"contents": {"twoColumnWatchNextResults": {"conversationBar": {"liveChatRenderer": {
            "continuations": [{"reloadContinuationData": {"continuation": "0ofMyAN"}}]}}}}});
        assert_eq!(composer(&next).continuation.as_deref(), Some("0ofMyAN"));
        let chat = json!({"continuationContents": {"liveChatContinuation": {"actionPanel": {"liveChatMessageInputRenderer": {
            "sendButton": {"buttonRenderer": {"serviceEndpoint": {"sendLiveChatMessageEndpoint": {"params": "Q2lrcU"}}}}}}}}});
        assert_eq!(
            composer(&chat),
            Composer {
                continuation: None,
                params: Some("Q2lrcU".into()),
                restricted: None,
                emojis: vec![]
            }
        );
        let members = json!({"continuationContents": {"liveChatContinuation": {"actionPanel": {"liveChatRestrictedParticipationRenderer": {
            "message": {"runs": [{"text": "Chat is in "}, {"text": "members-only mode"}]}}}}}});
        assert_eq!(
            composer(&members).restricted.as_deref(),
            Some("Chat is in members-only mode")
        );
        let body = send_body(&Send {
            params: "p".into(),
            text: "hi".into(),
            client_message_id: "c".into(),
            emojis: Default::default(),
        });
        assert_eq!(
            body,
            json!({"params": "p", "clientMessageId": "c", "richMessage": {"textSegments": [{"text": "hi"}]}})
        );
    }

    #[test]
    fn reads_and_sends_channel_emoji() {
        let chat = json!({"continuationContents": {"liveChatContinuation": {"emojis": [
            {"emojiId": "UCx/wave", "shortcuts": [":_wave:", ":_hello:"], "isCustomEmoji": true, "image": {"thumbnails": [{"url": "//yt3/s"}, {"url": "//yt3/l"}]}},
            {"emojiId": "UCx/vip", "shortcuts": [":_vip:"], "isCustomEmoji": true, "isLocked": true, "image": {"thumbnails": [{"url": "https://yt3/v"}]}},
            {"emojiId": "\u{1F600}", "shortcuts": [":grinning:"], "image": {"thumbnails": [{"url": "https://e/g"}]}}
        ]}}});
        assert_eq!(
            composer(&chat).emojis,
            vec![
                ChatEmoji {
                    id: "UCx/wave".into(),
                    shortcut: ":_wave:".into(),
                    url: "https://yt3/l".into(),
                    locked: false
                },
                ChatEmoji {
                    id: "UCx/vip".into(),
                    shortcut: ":_vip:".into(),
                    url: "https://yt3/v".into(),
                    locked: true
                },
            ]
        );
        let emojis =
            std::collections::HashMap::from([(":_wave:".to_string(), "UCx/wave".to_string())]);
        assert_eq!(
            segments("hi :_wave::_wave: at 10:30 :_nope: 😀", &emojis),
            vec![
                json!({"text": "hi "}),
                json!({"emojiId": "UCx/wave"}),
                json!({"emojiId": "UCx/wave"}),
                json!({"text": " at 10:30 :_nope: 😀"}),
            ]
        );
        assert_eq!(
            segments(":_wave:", &emojis),
            vec![json!({"emojiId": "UCx/wave"})]
        );
        assert_eq!(segments("a:b", &emojis), vec![json!({"text": "a:b"})]);
    }
}
