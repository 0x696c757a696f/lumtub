"""Checks the translation files a pull request changes against its base.

Weblate's pull requests are merged without a person reading them (see
dependabot-merge.yml), so this stops the kinds of damage seen in #250:

  1. The file is written as the repository writes it: two-space JSON with
     keys in the base's order and no ASCII escapes, so a pull request never
     rewrites a whole file to change a few lines.
  2. No new backslashes: a translation has no more backslashes than its
     English source, so quotes do not show up as \\" in the app.
  3. No values moved to other keys: a changed translation is not the old
     translation of another key whose translation also changed, which is
     how lines shifted by one look.
  4. Placeholders such as {0} and line breaks match the English source.
  5. Only keys simplified Chinese has, and none of its keys the base had
     translated dropped.

Usage: l10n_review.py BASE_REF. Prints GitHub annotations and exits 1 when
something is wrong.
"""

import json
import re
import subprocess
import sys

L10N = 'assets/l10n/'
SOURCE = L10N + 'zh-Hans.json'
PLACEHOLDER = re.compile(r'\{\d+\}')


def git(*args):
    command = ['git', *args]
    done = subprocess.run(command, check=True, capture_output=True, text=True, encoding='utf-8')
    return done.stdout


def changed_files(base):
    names = git('diff', '--name-only', '--diff-filter=AM', f'{base}...HEAD', '--', L10N).split()
    return [n for n in names if n.endswith('.json')]


def at_base(base, path):
    try:
        return json.loads(git('show', f'{base}:{path}'))
    except subprocess.CalledProcessError:
        return {}


def written(data):
    return json.dumps(data, ensure_ascii=False, indent=2) + '\n'


def review(path, text, old, known):
    problems = []
    try:
        new = json.loads(text)
    except json.JSONDecodeError as error:
        return [f'not valid JSON: {error}']
    if not isinstance(new, dict) or not all(isinstance(v, str) for v in new.values()):
        return ['not a map of strings']

    if text != written(new):
        problems.append('formatting changed: the file must stay two-space JSON without escapes')
    elif old and [k for k in new if k in old] != [k for k in old if k in new]:
        problems.append('keys reordered')

    unknown = [k for k in new if k not in known]
    if unknown:
        problems.append(f'{len(unknown)} keys not in simplified Chinese, first: {unknown[0]!r}')
    dropped = [k for k in old if k not in new and k in known]
    if dropped:
        problems.append(f'{len(dropped)} keys dropped, first: {dropped[0]!r}')

    changed = {k for k, v in new.items() if old.get(k) != v}
    old_owner = {}
    for k, v in old.items():
        old_owner.setdefault(v, []).append(k)
    for key in sorted(changed):
        value = new[key]
        if value.count('\\') > key.count('\\'):
            problems.append(f'new backslash in {key!r}: {value!r}')
        if set(PLACEHOLDER.findall(value)) != set(PLACEHOLDER.findall(key)):
            problems.append(f'placeholders differ in {key!r}: {value!r}')
        if value.count('\n') != key.count('\n'):
            problems.append(f'line breaks differ in {key!r}')
        moved = [k for k in old_owner.get(value, []) if k != key and k in changed]
        if moved:
            problems.append(f'{key!r} took the old translation of {moved[0]!r}: {value!r}')
    return problems


def main():
    if len(sys.argv) != 2:
        sys.exit('usage: l10n_review.py BASE_REF')
    base = sys.argv[1]
    files = changed_files(base)
    if not files:
        print('No translation files changed.')
        return
    with open(SOURCE, encoding='utf-8') as source:
        known = set(json.load(source))
    failed = False
    for path in files:
        with open(path, encoding='utf-8') as f:
            text = f.read()
        problems = review(path, text, at_base(base, path), known)
        for problem in problems[:50]:
            print(f'::error file={path}::{problem}')
        if len(problems) > 50:
            print(f'::error file={path}::{len(problems) - 50} more problems')
        failed = failed or bool(problems)
        print(f'{path}: {len(problems)} problems')
    if failed:
        sys.exit(1)


if __name__ == '__main__':
    main()
