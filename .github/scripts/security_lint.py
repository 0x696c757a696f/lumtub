#!/usr/bin/env python3
"""Checks the sources for the mistakes docs/SECURE-CODING.md rules out.

Each rule is a pattern that must not appear in the files it covers. A line
that really needs one carries `security-lint: allow <rule> (<reason>)` on
the line itself or one of the four lines above, so the exception is reviewed with the
code. Run from the repository root; exits 1 when anything is found.
"""

import fnmatch
import re
import subprocess
import sys

RULES = [
    # (name, file globs, pattern, why)
    ('shell-string', ['lib/**.dart'], r'runInShell:\s*true',
     'a command line goes through a shell; pass the program and a list of arguments'),
    ('shell-interpolation', ['lib/**.dart'], r"""['"]-(?:c|Command)['"]\s*,\s*(?:"[^"]*\$|'[^']*\$)""",
     "text is spliced into a shell or PowerShell command; use a raw string and pass values as arguments or environment variables"),
    ('ytdlp-separator', ['lib/**.dart'], r"""(?:\[\s*|(?<!'--'),\s*)'https://www\.youtube\.com/watch\?v=\$""",
     "a video address in an argument list without '--', right before it on the same line"),
    ('windows-bare-program', ['lib/**.dart'], r"""Process\.(?:start|run|runSync)\(\s*['"](?:[\w.-]+\.exe|reg|cmd|tar|powershell|explorer|rundll32|where)['"]""",
     "a Windows program started by bare name is looked for in the current folder first; use windowsProgram()"),
    ('device-reply', ['lib/cast/**.dart'], r'utf8\.decodeStream\(',
     'a reply from the network is read without a size limit; use readDeviceReply'),
    ('tls-bypass', ['lib/**.dart', 'native/**.rs', 'android/**.kt', 'macos/**.swift', 'ios/**.swift', 'linux/**.cc', 'windows/**.cpp'],
     r'badCertificateCallback|onBadCertificate|danger_accept_invalid|dangerous\(\)|\.dangerous_configuration|ServerCertVerifier for|onReceivedSslError|ALLOW_ALL_HOSTNAME|setHostnameVerifier',
     'certificate checks are turned off or replaced'),
    ('webview-bridge', ['android/**.kt'], r'addJavascriptInterface|allowFileAccess\s*=\s*true|allowUniversalAccessFromFileURLs|allowFileAccessFromFileURLs|setAllowFileAccess\(true\)',
     'a web page gets access to the app or to files'),
    ('world-readable', ['android/**.kt'], r'MODE_WORLD_(?:READABLE|WRITEABLE)',
     'a file is opened to every app'),
    ('mutable-intent', ['android/**.kt'], r'FLAG_MUTABLE',
     'a PendingIntent another app can fill in'),
    ('exported', ['android/**/AndroidManifest.xml'], r'android:exported="true"',
     'a component other apps can start'),
    ('rust-unsafe-fn', ['native/lumtub_core/src/**.rs'], r'#!\[allow\(unsafe_op_in_unsafe_fn\)\]',
     'unsafe operations hidden inside unsafe fns'),
    ('private-key', ['**'], r'-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----',
     'a private key is committed'),
    ('token', ['**'], r'\b(?:ghp|gho|ghs|ghu|github_pat)_[A-Za-z0-9_]{30,}|\bAKIA[0-9A-Z]{16}\b|\bxox[bap]-[0-9A-Za-z-]{20,}|\bsk-ant-[A-Za-z0-9_-]{20,}',
     'an access token is committed'),
]

ALLOW = re.compile(r'security-lint:\s*allow\s+([\w-]+)')
SKIP = ('vendor/', 'test/', 'native/lumtub_core/testdata/', 'website/', 'native/lumtub_core/fuzz/corpus/', 'assets/l10n/')


def matches(path, globs):
    # fnmatch's * also crosses '/', so 'lib/**.dart' is every Dart file under lib.
    return any(fnmatch.fnmatchcase(path, g) for g in globs)


def main():
    files = subprocess.run(['git', 'ls-files', '-z'], capture_output=True, check=True).stdout.decode().split('\0')
    found = 0
    compiled = [(name, globs, re.compile(pattern), why) for name, globs, pattern, why in RULES]
    for path in files:
        if not path or path.startswith(SKIP) or path == '.github/scripts/security_lint.py':
            continue
        wanted = [rule for rule in compiled if matches(path, rule[1])]
        if not wanted:
            continue
        try:
            with open(path, encoding='utf-8') as f:
                lines = f.read().split('\n')
        except (UnicodeDecodeError, IsADirectoryError, FileNotFoundError):
            continue
        for number, line in enumerate(lines, 1):
            for name, _, pattern, why in wanted:
                if not pattern.search(line):
                    continue
                allowed = {m.group(1) for text in lines[max(0, number - 5):number] for m in ALLOW.finditer(text)}
                if name in allowed:
                    continue
                found += 1
                print(f'{path}:{number}: [{name}] {why}\n    {line.strip()[:160]}')
    if found:
        print(f'\n{found} finding(s). Fix them, or mark a reviewed exception with "security-lint: allow <rule> (<reason>)"; see docs/SECURE-CODING.md.')
        return 1
    print('No findings.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
