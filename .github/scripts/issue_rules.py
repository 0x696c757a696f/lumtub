"""Checks a new issue against the issue rules.

Reads the issue from the event file GitHub passes in GITHUB_EVENT_PATH (or
the file named on the command line) and prints the reply explaining what is
wrong, or nothing when the issue keeps to the rules.

The rules:
  1. The issue is opened from one of the forms, so every answer sits under
     its "### Label" heading.
  2. The answers the form asks for are really there, not "none", "see above"
     and the like.
  3. One problem or one idea per issue: the title does not say "some
     problems", the description is not a numbered list of separate points,
     and the "one problem" box is ticked.
  4. A bug report says which version of Lumtub it is about.
"""

import json
import os
import re
import sys
import unicodedata

BUG = 'bug'
FEATURE = 'feature'
BLOCK_LIST = 'block list'

WHAT_HAPPENED = 'What happened / 发生了什么'
STEPS = 'Steps to reproduce / 复现步骤'
DIAGNOSTICS = 'Diagnostics / 诊断信息'
PROBLEM = 'What would it help with / 想解决什么问题'
IDEA = 'Your idea / 你的想法'
ONE = 'One problem per issue / 一个 issue 一个问题'
CHANNEL = 'Channel / 频道'
SOURCE = 'Source / 来源'

FORMS = {
    BUG: {'first': WHAT_HAPPENED, 'required': [WHAT_HAPPENED, STEPS, DIAGNOSTICS], 'single': [WHAT_HAPPENED]},
    FEATURE: {'first': PROBLEM, 'required': [PROBLEM, IDEA], 'single': [PROBLEM]},
    BLOCK_LIST: {'first': 'Add or remove / 添加还是移除', 'required': [CHANNEL, SOURCE], 'single': []},
}

FILLER = {
    '', '无', '没', '没有', '暂无', '略', '空', '如上', '同上', '见上', '见上文', '见上面', '上面', '如题', '同标题',
    '见标题', '不知道', '不清楚', '测试', 'none', 'no', 'na', 'nil', 'null', 'nothing', 'same', 'above',
    'asabove', 'seeabove', 'seetitle', 'idk', 'test', 'tbd',
}

TOO_MANY = re.compile(
    r'(一些|几个|多个|若干|各种|一堆|好几个|几点|多处|多项)(小)?(问题|建议|bug|毛病|缺陷|改进)'
    r'|问题汇总|建议汇总|问题合集|建议合集|问题集合'
    r'|\b(some|several|multiple|various|many|few|misc|miscellaneous)\s+(small\s+|minor\s+)?'
    r'(issues|problems|bugs|suggestions|ideas|requests|things|improvements)\b',
    re.IGNORECASE,
)

NUMBERED = re.compile(r'^\s*[(（]?([1-9])\s*[.。,，、)）:：]')
VERSION = re.compile(r'\b\d+\.\d+\.\d+')
EXEMPT = {'OWNER', 'MEMBER', 'COLLABORATOR'}


def sections(body):
    """The form's answers by their heading."""
    found = {}
    heading = None
    lines = []
    for line in (body or '').replace('\r\n', '\n').split('\n'):
        if line.startswith('### '):
            if heading is not None:
                found[heading] = '\n'.join(lines).strip()
            heading = line[4:].strip()
            lines = []
        elif heading is not None:
            lines.append(line)
    if heading is not None:
        found[heading] = '\n'.join(lines).strip()
    return found


def form_of(found):
    for name, form in FORMS.items():
        if form['first'] in found:
            return name
    return None


def plain(text):
    """The answer without fences, "_No response_", spaces and punctuation."""
    text = '\n'.join(line for line in text.split('\n') if not line.strip().startswith('```'))
    text = text.replace('_No response_', '')
    return ''.join(c for c in text.lower() if not c.isspace() and unicodedata.category(c)[0] not in 'PSZ')


def numbered_points(text):
    numbers = set()
    fenced = False
    for line in text.split('\n'):
        if line.strip().startswith('```'):
            fenced = not fenced
            continue
        match = None if fenced else NUMBERED.match(line)
        if match:
            numbers.add(match.group(1))
    return '1' in numbers and '2' in numbers


def problems(issue):
    """What the issue gets wrong, as (English, Chinese) pairs."""
    found = sections(issue.get('body'))
    form = form_of(found)
    if form is None:
        return [(
            'It was not opened from one of the issue forms. Please open it again with '
            '"Bug report" or "Feature request" and fill in every field.',
            '没有用 issue 表单提交。请用「问题反馈」或「功能建议」重新提交，并填好每一项。',
        )]
    wrong = []
    empty = [name for name in FORMS[form]['required'] if plain(found.get(name, '')) in FILLER]
    if empty:
        names = ', '.join(f'"{name}"' for name in empty)
        wrong.append((
            f'These fields are empty or only say something like "none" or "see above": {names}.',
            f'这些项是空的，或者只写了“无”“如上”之类：{names}。',
        ))
    if form == BUG and DIAGNOSTICS not in empty and not VERSION.search(found.get(DIAGNOSTICS, '')):
        wrong.append((
            'The version is missing. Paste the diagnostics (Settings › About › Copy diagnostics); '
            'if Lumtub does not start, write the version you downloaded, such as 0.2.56.',
            '缺少版本号。请粘贴诊断信息（设置 › 关于 › 复制诊断信息）；如果 Lumtub 打不开，请写下载的版本号，比如 0.2.56。',
        ))
    title = issue.get('title') or ''
    several = TOO_MANY.search(title) or any(numbered_points(found.get(name, '')) for name in FORMS[form]['single'])
    unticked = form != BLOCK_LIST and '- [x]' not in found.get(ONE, '').lower()
    if several or unticked:
        wrong.append((
            'Each issue should be about one problem or one idea, so each can be followed and closed on its own. '
            'Please open a separate issue for each.',
            '一个 issue 只写一个问题或一个建议，这样每个都能单独跟进和关闭。请把它们分别开成单独的 issue。',
        ))
    return wrong


def reply(wrong):
    english = '\n'.join(f'- {en}' for en, _ in wrong)
    chinese = '\n'.join(f'- {zh}' for _, zh in wrong)
    return (
        'Thanks for taking the time to write this. It was closed automatically because it does not '
        'follow the issue rules yet:\n\n'
        f'{english}\n\n'
        'Edit the issue to fix this and it reopens by itself. Questions and loose ideas are welcome in '
        '[Discussions](https://github.com/0x696c757a696f/lumtub/discussions).\n\n'
        '感谢花时间反馈。这个 issue 还不符合提交规范，所以被自动关闭了：\n\n'
        f'{chinese}\n\n'
        '编辑这个 issue 改好以后会自动重新打开。使用问题和还没想清楚的点子，欢迎发到 '
        '[讨论区](https://github.com/0x696c757a696f/lumtub/discussions)。\n'
    )


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.environ['GITHUB_EVENT_PATH']
    with open(path, encoding='utf-8') as file:
        issue = json.load(file)['issue']
    if issue.get('author_association') in EXEMPT or (issue.get('user') or {}).get('type') == 'Bot':
        return
    wrong = problems(issue)
    if wrong:
        sys.stdout.write(reply(wrong))


if __name__ == '__main__':
    main()
