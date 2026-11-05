import 'blocked_groups.dart';

/// Channels of media that a government runs to speak for it, grouped by
/// country, for blocking all at once: propaganda outlets, not public
/// broadcasters with editorial independence (BBC, NHK, PBS and the like
/// stay). Matched against the channel's name only, so a video that merely
/// mentions CGTN stays: a name that is one of these or starts with one
/// followed by a space or sign ("RT Documentary", "CGTN Français") counts.
/// YouTube marks such channels on its site, but that mark does not reach
/// yt-dlp's listings, hence the list.
const stateMedia = <BlockedGroup>[
  BlockedGroup('中国官方媒体', 'Chinese state media', note: 'State-run media and ruling-party papers', [
    'CGTN', 'China Global Television', '中国国际电视台', 'CCTV', '央视', '中国中央电视台', '中央电视台', '中央广播电视总台', 'China Media Group',
    'China Daily', '中国日报', 'Global Times', '环球时报', '環球時報', 'Xinhua', 'China Xinhua', 'New China TV', '新华社', '新華社', '新华网',
    "People's Daily", 'People’s Daily', '人民日报', '人民日報', '人民网', 'China News Service', '中国新闻社', '中国新闻网', '中國新聞網', '中新网', '中新社', 'ChinaNews',
    'China Radio International', '中国国际广播电台', '国际在线', 'China Plus', '中国之声', 'China.org.cn', '参考消息', 'Reference News', '光明日报', '经济日报', '中国青年报',
    'iPanda', '熊猫频道', '中国军网', '解放军报', 'PLA Daily', '大公报', '大公報', '文汇报', '文匯報', '大公文汇', '大公文匯', 'Ta Kung Pao', 'Wen Wei Po',
  ], exact: ['CRI', 'CNR', 'CMG', '中国网']),
  BlockedGroup('俄罗斯官方媒体', 'Russian state media', note: 'State-run or state-controlled; NTV, REN TV and Izvestia are owned by state or pro-government capital rather than run by the state', [
    'Russia Today', 'RT Arabic', 'RT en Español', 'RT Documentary', 'RT Balkan', 'RT India', 'RT DE', 'RT France', 'RT News', 'RT на русском', '今日俄罗斯', '今日俄羅斯',
    'Sputnik', '卫星通讯社', '衛星通訊社', 'TASS', 'ТАСС', '塔斯社', 'RIA Novosti', 'РИА Новости', '俄新社', 'Rossiya Segodnya', 'Россия сегодня', 'Ruptly',
    'Россия 1', 'Россия 24', 'Россия К', 'Rossiya 1', 'Rossiya 24', 'ВГТРК', 'VGTRK', 'Вести', 'Vesti', 'Первый канал', 'Channel One Russia', '俄罗斯第一频道',
    'Телеканал Звезда', 'ТВ Центр', 'TV Tsentr', 'Российская газета', 'Rossiyskaya Gazeta', 'Известия', 'Izvestia', 'НТВ', 'РЕН ТВ', 'REN TV',
  ], exact: ['RT', 'NTV', 'Звезда', 'Zvezda', 'ОТР']),
  BlockedGroup('伊朗官方媒体', 'Iranian state media', note: 'IRIB channels and IRNA are state media; Fars, Tasnim and Mehr are tied to the Revolutionary Guards or state bodies', [
    'Press TV', 'PressTV', 'IRIB', 'Islamic Republic of Iran Broadcasting', '伊朗国家广播电视台', 'HispanTV', 'Al-Alam', 'Al Alam', 'IRINN', 'IRNA', 'Islamic Republic News Agency',
    'Pars Today', 'Sahar TV', 'Al-Kawthar', 'Al Kawthar', 'Fars News', 'Tasnim', 'Mehr News',
  ], exact: ['العالم', 'ISNA']),
  BlockedGroup('朝鲜官方媒体', 'North Korean state media', note: 'Uriminzokkiri and other outward-facing outlets stopped in 2024; listed to block old channels', [
    'KCTV', 'Korean Central Television', '조선중앙TV', '조선중앙텔레비죤', '朝鲜中央电视台', '朝鮮中央電視台', 'KCNA', 'Korean Central News Agency', '조선중앙통신', '朝鲜中央通讯社',
    'Rodong Sinmun', '로동신문', '劳动新闻', '勞動新聞', 'Voice of Korea', '조선의 소리', '朝鲜之声', 'Korean Central Broadcasting', '조선중앙방송', 'Naenara', '내나라',
    'Uriminzokkiri', '우리민족끼리', 'DPRK Today', 'Ryomyong', 'Arirang Meari',
  ]),
  BlockedGroup('白俄罗斯官方媒体', 'Belarusian state media', note: 'State broadcaster and state news agency', [
    'Belarus 1', 'Belarus 2', 'Belarus 24', 'Belarus 5', 'Беларусь 1', 'Беларусь 2', 'Беларусь 24', 'Беларусь 5', 'BelTA', 'БелТА', 'Belteleradiocompany', 'Белтелерадиокомпания',
    'ОНТ', 'СТВ', 'Первый информационный', 'Radio Belarus', 'Радио Беларусь', 'Belarus Segodnya', 'СБ Беларусь сегодня', 'СБ. Беларусь сегодня', 'Звязда',
  ], exact: ['ONT', 'STV', 'BTRC']),
  BlockedGroup('委内瑞拉官方媒体', 'Venezuelan state media', note: "teleSUR is funded by several governments, not Venezuela's alone", [
    'teleSUR', 'Venezolana de Televisión', 'TVes', 'ViVe TV', 'Ávila TV', 'Agencia Venezolana de Noticias', 'Radio Nacional de Venezuela', 'Correo del Orinoco',
  ], exact: ['VTV', 'AVN', 'RNV']),
  BlockedGroup('古巴官方媒体', 'Cuban state media', note: 'State television, news agency and Communist Party papers', [
    'Cubadebate', 'Canal Caribe', 'Televisión Cubana', 'TV Cubana', 'Cubavisión', 'Prensa Latina', 'Granma', 'Agencia Cubana de Noticias', 'Radio Habana Cuba', 'Radio Rebelde',
    'Juventud Rebelde', 'Canal Habana',
  ], exact: ['ACN']),
  BlockedGroup('尼加拉瓜官方媒体', 'Nicaraguan state media', note: 'Some are run by the government, others by the ruling party or family', [
    'Canal 6 Nicaragua', 'El 19 Digital', 'El 19 TV', 'Radio Nicaragua', 'La Nueva Radio Ya',
  ], exact: ['Barricada']),
  // YouTube labels the groups below government funded too, but they have
  // editorial independence of some degree, so they start unticked.
  BlockedGroup('美国政府国际广播', 'US government international broadcasting', onByDefault: false, note: 'Funded by the US Agency for Global Media with editorial independence in law, unlike media whose content a government controls', [
    'VOA', 'Voice of America', '美国之音', '美國之音', 'Radio Free Asia', '自由亚洲电台', '自由亞洲電台', 'Radio Free Europe', 'RFE/RL', 'Radio Liberty', 'Радио Свобода', 'Radio Svoboda',
    'Current Time', 'Настоящее время', 'Radio Martí', 'TV Martí', 'Martí Noticias', 'Alhurra', 'الحرة', 'Radio Sawa', 'Middle East Broadcasting Networks',
  ], exact: ['RFA', 'OCB', 'MBN']),
  BlockedGroup('卡塔尔国家资助媒体', 'Qatari state-funded media', onByDefault: false, note: "Al Jazeera is funded by Qatar's government with some editorial autonomy, unlike the official news agency", [
    'Al Jazeera', 'الجزيرة', '半岛电视台', '半島電視台', 'AJ+', 'AJ Plus', 'Qatar TV', 'Qatar Media Corporation', 'Qatar News Agency', 'Al Kass',
  ], exact: ['QNA', 'QMC']),
  BlockedGroup('沙特官方及国家控股媒体', 'Saudi state and state-owned media', onByDefault: false, note: "The Saudi Press Agency and others are state media; Al Arabiya and MBC belong to state-owned groups. Korea's MBC shares the name, so MBC alone is not matched", [
    'Saudi Press Agency', 'Saudi Broadcasting Authority', 'Al Saudiya', 'Al Ekhbariya', 'Al Arabiya', 'Al Hadath', 'MBC Group', 'Asharq News', 'Asharq Al-Awsat', 'Arab News',
  ], exact: ['SPA', 'SBA', 'الإخبارية', 'العربية', 'الحدث']),
  BlockedGroup('土耳其国家媒体', 'Turkish state media', onByDefault: false, note: "Turkey's state broadcaster and official news agency", [
    'TRT World', 'TRT Haber', 'TRT عربي', 'TRT Arabic', 'TRT Deutsch', 'TRT Balkan', 'TRT Afrika', 'TRT Français', 'TRT Русский', 'Anadolu Agency', 'Anadolu Ajansı', '阿纳多卢通讯社',
  ], exact: ['TRT', 'AA']),
  BlockedGroup('阿联酋官方及国家关联媒体', 'Emirati state and state-linked media', onByDefault: false, note: 'WAM is state media; Sky News Arabia is state-linked rather than a government body', [
    'Emirates News Agency', '阿联酋通讯社', 'Abu Dhabi Media', 'Abu Dhabi TV', 'Dubai Media', 'Dubai TV', 'Al Emarat TV', 'Sky News Arabia', 'سكاي نيوز عربية',
  ], exact: ['WAM']),
];


final _all = BlockMatcher(stateMedia.where((g) => g.onByDefault).toList());

/// Whether a channel called [channel] is one of [stateMedia], other than
/// the groups the user [allowed].
bool isStateMediaChannel(String channel, [Set<String>? allowed]) =>
    (allowed == null ? _all : BlockMatcher(stateMedia, allowedGroups: allowed)).channel(channel);
