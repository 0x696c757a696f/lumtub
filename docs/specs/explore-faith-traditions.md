# Explore: keeping faith zones to their tradition

What the zones of 宗教与信仰 promise about the tradition of the videos they
show, and how. Code: `lib/faith_traditions.dart`, `lib/faith_topics.dart`,
`exploreTraditionNow` and `where` in `lib/app/explore_controller.dart`.
Tests: `test/faith_traditions_test.dart`, `test/explore_page_test.dart`.

## Promise

A zone of one tradition shows that tradition's videos, not a neighbour's:
the Catholic zone shows no Protestant sermons, the Eastern Orthodox zone
no Byzantine Catholic liturgies, the Pure Land zone no Tibetan teachings.
This matters most in Chinese, where 天主教 is the Catholic Church and
基督教 is what Protestant churches call themselves, and YouTube's search
for one brings up the other.

Nothing here says what a channel or a person believes. The words only
sort a search's videos into the zone that searched for them.

## How

Each zone is a YouTube search. Its videos then pass a test of their own
words: title, channel name and the description's start.

- `FaithTradition` is a tree: Christianity → Catholic → Eastern Catholic;
  Christianity → Protestant → Lutheran, Reformed, Anglican, Methodist,
  Baptist, Pentecostal, Evangelical; Christianity → Eastern Orthodox,
  Oriental Orthodox, other churches (Latter-day Saints, Jehovah's
  Witnesses, the Local Church, True Jesus Church…), Messianic; Islam →
  Sunni, Shia, Ahmadiyya; Buddhism → Chinese, Zen, Pure Land, Tibetan,
  Theravada, Nichiren; Chinese religion → Taoism, Confucianism, folk
  religion; Yiguandao; Hinduism; Judaism; Sikhism; Jainism; Shinto;
  Baháʼí; Zoroastrianism.
- Each tradition lists strong words, which name it (天主教, Catholic,
  东正教, 浸信会), worth 2, and weak words, which lean to it (弥撒, 神父,
  牧师, 讲道, 和合本, sermon), worth 1. Words are written in simplified and
  traditional Chinese first, then English, Italian, Spanish, Portuguese,
  French, German, Polish, Russian, Ukrainian, Greek, Japanese and Korean.
  A Latin, Cyrillic or Greek word must start a word, or be a whole word
  when it ends in `$` (pope, not Popeye); a Chinese, Japanese or Korean
  word may stand anywhere.
- A video's own score is what it says of the zone's tradition and its
  branches. Its rival score is the most it says of any one other branch:
  a sibling of the tradition or of one of its ancestors, or another faith.
  Ancestors count neither way: 基督宗教 says nothing against a Catholic
  video.
- Kept when its own score is at least its rival score and above 0. A
  video about two traditions ("天主教和基督教的区别") is kept by both.
- A video saying nothing either way is kept, except in Christianity's
  churches (Catholic, Eastern Catholic, Orthodox, Oriental Orthodox,
  Protestant and its branches, other churches), which are strict: their
  videos are alike enough that a sermon saying nothing of its church is
  more likely another's. Strictness holds only for video tabs (live
  streams are seldom titled by their church) and only where the explore
  language is one the words are written in.
- A zone's tradition is its narrowest sub-category's that names one; a
  sub-category naming none keeps its zone's. 全部 and zones about many
  faiths (world religions, Study, most of Culture & art) name none.

## Search words

The Catholic sub-categories all search 天主教 as well, so that a Chinese
search asks for Catholic videos rather than any Christian ones; the
Protestant zone searches 新教 基督教 讲道, the Orthodox ones 东正教 with
their own words, and Eastern Catholic is its own sub-category of Catholic
(东方礼天主教). New Chinese words have their English in `searchPivots`.
