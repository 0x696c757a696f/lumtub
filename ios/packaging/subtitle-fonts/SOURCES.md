# Subtitle fonts for iOS

libmpv on iOS draws subtitles with these fonts and the app's own Noto Sans
SC only (`sub-font-provider=none`), never looking through Core Text: on
iOS 27 that search ran for seconds on mpv's video thread, which stalled
playback and got the app killed. As on Android, the font is picked by the
script of the text on screen (lib/android_subtitle_fonts.dart).

All are Noto fonts under the SIL Open Font License 1.1
(assets/fonts/OFL.txt), Regular weight, copied unchanged from:

- NotoSansKR-Regular.otf: https://github.com/googlefonts/noto-cjk
  (Sans/SubsetOTF/KR)
- NotoSans<Script>-Regular.ttf: https://github.com/notofonts/notofonts.github.io
  (fonts/NotoSans<Script>/hinted/ttf)
- NotoSans-Regular.ttf: the same, fonts/NotoSans/hinted/ttf. Latin, Greek
  and Cyrillic with every accented letter (Polish, Czech, Vietnamese,
  Ukrainian and so on), which Noto Sans SC lacks.

SHA-256:

```
bdff3e5659d67e67def05b33f749683b9376ae819d65d3dd62ac4640b3aaef48  NotoSansArabic-Regular.ttf
720df88c332417a235b4d6209d14ec2e2bf4bfe2a954b7453d869ea593bfce1e  NotoSansArmenian-Regular.ttf
b55c62ee531e3214da6c0701daecea89a52ba42db7d8206b92e6b51f397a3193  NotoSansBengali-Regular.ttf
4e3c66638958c3e2ab5d37f47a8deb89fffeb7be9985c665a519bbc7ba762313  NotoSansDevanagari-Regular.ttf
f6f7fc379db9438959a2b0527e7a2cf36ea9c84626d56ec444fff37fc24c3c10  NotoSansEthiopic-Regular.ttf
d3e33254b09e7bb2c5cf0f17e554b80462056c5a107097f258d495168c3a9346  NotoSansGeorgian-Regular.ttf
9b5a7aaeeb649a2e75a49d8b006a1f87db1b61c0df3b001609f4e0725d88dbf6  NotoSansGujarati-Regular.ttf
658d0207da305a1411c539a8b0bbeda64d4146e54fb4827facddb890b6b90d74  NotoSansGurmukhi-Regular.ttf
cdefaf8efd47045f6820928eba84db5bed7557539328952b5f828315485e02ee  NotoSansHebrew-Regular.ttf
478c558ea716033cd60c03438f628dfa75694dcf6b5f6d505a2f05fd2b4f3823  NotoSans-Regular.ttf
69975a0ac8472717870aefeab0a4d52739308d90856b9955313b2ad5e0148d68  NotoSansKR-Regular.otf
9ad74dc64838c6855b96f671fc08e425a58921b9d0c71712ea79c328a27e6e38  NotoSansKannada-Regular.ttf
e66675f2082788f0511a714bef5a1748928294b38c8e286a96ea73a864b5e605  NotoSansKhmer-Regular.ttf
0a86e5e1ccfe34ca78c43fac6829dc751b42bcc469272a9a55325aae587bfbe7  NotoSansLao-Regular.ttf
c08de7fa8d032a5d6a4d120fb82c78cec60b362a4e73fa26360d89759ff2a7f9  NotoSansMalayalam-Regular.ttf
fafce4db400bc0b214907ccdbfb0ad2f18a57bfefd08c8a571830b84088cf2fc  NotoSansMyanmar-Regular.ttf
a16645d056017927406546aa78e4ce15e782fd8783467267b75450453d007415  NotoSansOriya-Regular.ttf
9e32612d47004552f3125e78648a9e2e7899a216ccd3cefbb93a9b5f4c809feb  NotoSansSinhala-Regular.ttf
3c0a186feb3c63c7f6d63e1511dcdc144e745ae09b98e217c83f3e317974f6f9  NotoSansTamil-Regular.ttf
b274780b69d1d23fe84b55e809a152cb2ac5306d33864b1f87622f6971871aae  NotoSansTelugu-Regular.ttf
61cf814eec46b294d6ea4401ac295d0cecd5207bd2331dcc5a15e7301d30ee44  NotoSansThai-Regular.ttf
```
