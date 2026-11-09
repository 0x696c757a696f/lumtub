# Block lists

[中文说明在下面](#屏蔽列表)

Lumtub can hide channels of controversial religious groups and of state propaganda media. Nothing is blocked until you turn a list on: Settings › Home & search settings › Block controversial religious groups, or Block state propaganda media. Tap a group there to see every channel on it and untick any you want to keep.

The lists are the files in this folder, one file per group:

- [`religion/`](religion/): controversial religious groups
- [`state-media/`](state-media/): state propaganda media
- [`retired.txt`](retired.txt): keys of removed entries, which are never used again
- [`schema.md`](schema.md): the file format, the categories and the evidence each one needs
- [`template.txt`](template.txt): a filled-in list file to copy

When a change to these files is merged, GitHub Actions checks every list, compiles them into one `lists.json`, signs it with the same keys as Lumtub's own updates and publishes it on the [`lists` release](https://github.com/0x696c757a696f/lumtub/releases/tag/lists). Lumtub fetches it once a day and uses it from the next start, so a fix reaches everyone without a new app version. Settings › Home & search settings › Update block lists automatically turns this off.

## Suggesting a change

Anyone can suggest a channel to add, or report one listed by mistake. Every entry needs a public source that shows who runs the channel: Wikipedia, a news report, a regulator or a court. Entries without a source are not added.

**Without writing any code:** open an issue with the [Block list entry form](https://github.com/0x696c757a696f/lumtub/issues/new?template=block_list.yml). Give the list, the channel's link or @handle, and the source. The button in the app's block list pages opens the same form.

**With a pull request:**

1. Fork the repository and edit the list's file here, or copy [`template.txt`](template.txt) to start a new list.
2. Add one line per channel. The simplest is its @handle or channel id (`UC…`, on the channel's About page), with a comment if you like:

   ```
   @EpochTimes  # the group's newspaper
   ```

   When a channel goes by several names, put them all on one line, and add a `source:` line under it when the list's own source does not cover it:

   ```
   :epoch-times | UCxxxxxxxxxxxxxxxxxxxxxx | @EpochTimes | =The Epoch Times | =大纪元
       source: https://en.wikipedia.org/wiki/The_Epoch_Times
       reviewed: 2026-11-09
   ```

3. Open the pull request. The Block lists check reads every file as the app will and writes what your change adds or removes in the run's summary. A wrong prefix, a malformed channel id or a duplicate slug fails it.
4. To remove an entry, delete its line and add its key (`list-id/slug`) to `retired.txt`.

To run the same check on your own computer: `cargo run --manifest-path native/lumtub_core/Cargo.toml --bin lumtub-lists -- check lists`.

Only channel names, @handles and channel ids are matched, never video titles or descriptions, so other channels' reports about a group are not affected.

---

# 屏蔽列表

Lumtub 可以隐藏争议宗教团体和官方宣传媒体的频道。默认什么都不屏蔽，要在 设置 › 首页与搜索设置 › 屏蔽争议宗教团体 或 屏蔽官方宣传媒体 里自己打开。点进某一组能看到它包含的每个频道，不想屏蔽的可以单独取消勾选。

列表就是这个文件夹里的文件，每组一个文件：

- [`religion/`](religion/)：争议宗教团体
- [`state-media/`](state-media/)：官方宣传媒体
- [`retired.txt`](retired.txt)：已删除条目的键，永远不再使用
- [`schema.md`](schema.md)：文件格式、分类和每类需要的证据（英文）
- [`template.txt`](template.txt)：填好的示例文件，复制它就能新建列表

改动合并后，GitHub Actions 会检查所有列表，编译成一个 `lists.json`，用和 Lumtub 自身更新相同的密钥签名，发布到 [`lists` 发布页](https://github.com/0x696c757a696f/lumtub/releases/tag/lists)。Lumtub 每天检查一次，下次启动时生效，所以修正不用等新版本就能到每个人手里。设置 › 首页与搜索设置 › 自动更新屏蔽列表 可以关掉。

## 怎么贡献

谁都可以建议加入某个频道，或者报告被误列的频道。每个条目都要有能说明频道归谁运营的公开来源：维基百科、新闻报道、监管机构或法院。没有来源的条目不会加入。

**不会写代码：** 用 [屏蔽列表条目表单](https://github.com/0x696c757a696f/lumtub/issues/new?template=block_list.yml) 开一个 issue，填上列表、频道链接或 @handle、来源就行。应用里屏蔽列表页面的按钮打开的也是这个表单。

**提交 pull request：**

1. Fork 仓库，编辑这里对应列表的文件；新建列表就复制 [`template.txt`](template.txt)。
2. 每个频道一行。最简单的是只写它的 @handle 或频道 ID（`UC…`，在频道“简介”里），后面可以用 `#` 加注释，比如 `@EpochTimes  # 该团体的报纸`。同一个频道有好几个名字时，全写在一行里；列表本身的来源不能说明它时，下面加一行 `source:`。例子见上面英文部分。
3. 开 pull request。Block lists 检查会按应用的读法读一遍所有文件，并在运行摘要里列出你的改动加了什么、删了什么。前缀写错、频道 ID 格式不对或 slug 重复都会失败。
4. 删除条目时，删掉那一行，并把它的键（`列表id/slug`）加进 `retired.txt`。

只匹配频道名、@handle 和频道 ID，不看视频标题和简介，所以其他频道对这些团体的报道不受影响。
