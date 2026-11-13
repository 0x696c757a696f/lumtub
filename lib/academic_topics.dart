import 'explore_topics.dart';
import 'ui/app_icons.dart';

// The zones of 学术, one list per tab, grouped the way universities group
// their faculties. Each is a YouTube search that leans on lecture, course
// and talk words, so the lists bring up teaching rather than entertainment
// about the subject.

/// 人文: philosophy, theology and the other humanities.
final humanitiesTopics = <ExploreTopic>[
  ExploreTopic('Philosophy', AppIcons.lightbulb, '哲学 philosophy lecture', subs: [
    ExploreSub('Ancient philosophy', 'ancient Greek philosophy Plato Aristotle 古希腊哲学', subs: [
      ExploreSub('Presocratics', 'Presocratic philosophers'),
      ExploreSub('Plato', 'Plato philosophy lecture 柏拉图'),
      ExploreSub('Aristotle', 'Aristotle philosophy lecture 亚里士多德'),
      ExploreSub('Stoicism', 'Stoicism lecture 斯多葛'),
      ExploreSub('Neoplatonism', 'Neoplatonism Plotinus'),
    ]),
    ExploreSub('Medieval philosophy', 'medieval philosophy scholasticism 经院哲学', subs: [
      ExploreSub('Augustine', 'Augustine philosophy 奥古斯丁'),
      ExploreSub('Thomas Aquinas', 'Thomas Aquinas philosophy 托马斯 阿奎那'),
      ExploreSub('Islamic philosophy', 'Islamic philosophy Avicenna Averroes'),
      ExploreSub('Jewish philosophy', 'Maimonides Jewish philosophy'),
    ]),
    ExploreSub('Modern philosophy', 'modern philosophy Descartes Kant 近代哲学', subs: [
      ExploreSub('Rationalism & empiricism', 'rationalism empiricism Descartes Hume'),
      ExploreSub('Kant', 'Kant philosophy lecture 康德'),
      ExploreSub('Hegel', 'Hegel philosophy lecture 黑格尔'),
      ExploreSub('Nietzsche', 'Nietzsche philosophy 尼采'),
    ]),
    ExploreSub('Contemporary philosophy', '20th century philosophy 现代哲学', subs: [
      ExploreSub('Phenomenology', 'phenomenology Husserl Heidegger 现象学'),
      ExploreSub('Existentialism', 'existentialism Sartre Kierkegaard 存在主义'),
      ExploreSub('Analytic philosophy', 'analytic philosophy Wittgenstein 分析哲学'),
      ExploreSub('Critical theory', 'Frankfurt School critical theory'),
    ]),
    ExploreSub('Ethics', 'ethics moral philosophy lecture 伦理学'),
    ExploreSub('Logic', 'logic philosophy lecture 逻辑学'),
    ExploreSub('Metaphysics', 'metaphysics lecture 形而上学'),
    ExploreSub('Epistemology', 'epistemology lecture 认识论'),
    ExploreSub('Philosophy of mind', 'philosophy of mind consciousness 心灵哲学'),
    ExploreSub('Political philosophy', 'political philosophy lecture 政治哲学'),
    ExploreSub('Philosophy of science', 'philosophy of science lecture 科学哲学'),
    ExploreSub('Aesthetics', 'aesthetics philosophy of art lecture 美学'),
    ExploreSub('Philosophy of religion', 'philosophy of religion lecture 宗教哲学 讲座'),
    ExploreSub('Chinese philosophy', '中国哲学 儒家 道家 Chinese philosophy'),
  ]),
  ExploreTopic('Theology', AppIcons.handsPraying, '神学 theology lecture', subs: [
    ExploreSub('Systematic theology', 'systematic theology lecture 系统神学', subs: [
      ExploreSub('Trinity', 'Trinity theology lecture 三位一体'),
      ExploreSub('Christology', 'Christology lecture 基督论'),
      ExploreSub('Ecclesiology', 'ecclesiology lecture 教会论'),
      ExploreSub('Eschatology', 'eschatology lecture 末世论'),
    ]),
    ExploreSub('Biblical studies', 'biblical studies lecture 圣经学', subs: [
      ExploreSub('Old Testament', 'Old Testament lecture 旧约'),
      ExploreSub('New Testament', 'New Testament lecture 新约'),
      ExploreSub('Biblical languages', 'Biblical Hebrew Koine Greek 圣经原文'),
    ]),
    ExploreSub('Fundamental theology', 'fundamental theology revelation faith and reason 基本神学'),
    ExploreSub('Patristics', 'patristics Church Fathers lecture 教父学'),
    ExploreSub('Church history', 'church history lecture 教会史'),
    ExploreSub('Moral theology', 'moral theology lecture 伦理神学'),
    ExploreSub('Liturgical studies', 'liturgical theology lecture 礼仪学'),
    ExploreSub('Canon law', 'canon law lecture 教会法'),
    ExploreSub('Spiritual theology', 'spiritual theology mysticism lecture 灵修神学'),
    ExploreSub('Eastern theology', 'Eastern Orthodox theology lecture 东方神学'),
    ExploreSub('Mariology', 'Mariology lecture 圣母论'),
    ExploreSub('Sacramental theology', 'sacramental theology lecture 圣事神学'),
    ExploreSub('Missiology', 'missiology lecture 宣教学'),
    ExploreSub('Ecumenism', 'ecumenism ecumenical theology lecture 合一运动'),
  ]),
  ExploreTopic('History', AppIcons.scroll, '历史 history lecture', subs: [
    ExploreSub('Ancient history', 'ancient history lecture 古代史'),
    ExploreSub('Medieval history', 'medieval history lecture 中世纪史'),
    ExploreSub('Modern history', 'modern history lecture 近代史'),
    ExploreSub('Chinese history', '中国历史 讲座 Chinese history'),
    ExploreSub('Historiography', 'historiography lecture 史学理论'),
    ExploreSub('Byzantine history', 'Byzantine history lecture 拜占庭史'),
    ExploreSub('History of science', 'history of science lecture 科学史'),
  ]),
  ExploreTopic('Literature', AppIcons.bookOpenText, '文学 literature lecture', subs: [
    ExploreSub('Literary theory', 'literary theory lecture 文学理论'),
    ExploreSub('Classical Chinese literature', '中国古典文学 讲座'),
    ExploreSub('Western literature', 'Western literature lecture 西方文学'),
    ExploreSub('Poetry', 'poetry lecture 诗歌 讲座'),
  ]),
  ExploreTopic('Linguistics', AppIcons.translate, '语言学 linguistics lecture', subs: [
    ExploreSub('Phonetics', 'phonetics phonology lecture 语音学'),
    ExploreSub('Syntax', 'syntax linguistics lecture 句法'),
    ExploreSub('Historical linguistics', 'historical linguistics lecture 历史语言学'),
    ExploreSub('Classical languages', 'Latin Ancient Greek lesson 拉丁语 古希腊语'),
  ]),
  ExploreTopic('Classics', AppIcons.bank, 'classics Greek Roman lecture 古典学'),
  ExploreTopic('Archaeology', AppIcons.compass, '考古 archaeology lecture', subs: [
    ExploreSub('Egyptology', 'Egyptology lecture 埃及学'),
    ExploreSub('Classical archaeology', 'classical archaeology Greece Rome lecture'),
    ExploreSub('Biblical archaeology', 'biblical archaeology lecture 圣经考古'),
    ExploreSub('Chinese archaeology', '中国考古 讲座'),
  ]),
  ExploreTopic('Art history', AppIcons.palette, '艺术史 art history lecture', subs: [
    ExploreSub('Medieval art', 'medieval art history lecture 中世纪艺术'),
    ExploreSub('Renaissance art', 'Renaissance art history lecture 文艺复兴艺术'),
    ExploreSub('Modern art', 'modern art history lecture 现代艺术'),
    ExploreSub('Chinese art history', '中国美术史 讲座'),
  ]),
  ExploreTopic('Musicology', AppIcons.musicNotes, '音乐学 musicology lecture', subs: [
    ExploreSub('Music theory', 'music theory lecture 乐理 和声'),
    ExploreSub('Music history', 'music history lecture 音乐史'),
    ExploreSub('Ethnomusicology', 'ethnomusicology lecture 民族音乐学'),
  ]),
];

/// 社会科学: psychology and the other social sciences.
final socialScienceTopics = <ExploreTopic>[
  ExploreTopic('Psychology', AppIcons.brain, '心理学 psychology lecture', subs: [
    ExploreSub('Introduction to psychology', 'introduction to psychology course 心理学导论'),
    ExploreSub('Cognitive psychology', 'cognitive psychology lecture 认知心理学'),
    ExploreSub('Developmental psychology', 'developmental psychology lecture 发展心理学'),
    ExploreSub('Social psychology', 'social psychology lecture 社会心理学'),
    ExploreSub('Clinical psychology', 'clinical psychology lecture 临床心理学', subs: [
      ExploreSub('Psychotherapy', 'psychotherapy lecture 心理治疗'),
      ExploreSub('Cognitive behavioral therapy', 'CBT cognitive behavioral therapy 认知行为疗法'),
      ExploreSub('Psychopathology', 'psychopathology abnormal psychology 变态心理学'),
    ]),
    ExploreSub('Personality psychology', 'personality psychology lecture 人格心理学'),
    ExploreSub('Biological psychology', 'biological psychology neuroscience 生理心理学'),
    ExploreSub('Psychoanalysis', 'psychoanalysis Freud Jung lecture 精神分析'),
    ExploreSub('Neuropsychology', 'neuropsychology lecture 神经心理学'),
    ExploreSub('Educational psychology', 'educational psychology lecture 教育心理学'),
    ExploreSub('Organizational psychology', 'industrial organizational psychology lecture 管理心理学'),
    ExploreSub('Positive psychology', 'positive psychology lecture 积极心理学'),
    ExploreSub('Research methods', 'psychology research methods statistics 心理学研究方法'),
    ExploreSub('Psychology of religion', 'psychology of religion lecture 宗教心理学'),
  ]),
  ExploreTopic('Sociology', AppIcons.usersThree, '社会学 sociology lecture', subs: [
    ExploreSub('Social theory', 'social theory Weber Durkheim 社会理论'),
    ExploreSub('Sociology of religion', 'sociology of religion lecture 宗教社会学'),
    ExploreSub('Demography', 'demography population lecture 人口学'),
    ExploreSub('Criminology', 'criminology lecture 犯罪学'),
    ExploreSub('Urban sociology', 'urban sociology lecture 城市社会学'),
  ]),
  ExploreTopic('Economics', AppIcons.chartLine, '经济学 economics lecture', subs: [
    ExploreSub('Microeconomics', 'microeconomics lecture 微观经济学'),
    ExploreSub('Macroeconomics', 'macroeconomics lecture 宏观经济学'),
    ExploreSub('Econometrics', 'econometrics lecture 计量经济学'),
    ExploreSub('Economic history', 'economic history lecture 经济史'),
    ExploreSub('Game theory', 'game theory lecture 博弈论'),
    ExploreSub('Behavioral economics', 'behavioral economics lecture 行为经济学'),
    ExploreSub('Development economics', 'development economics lecture 发展经济学'),
  ]),
  ExploreTopic('Political science', AppIcons.megaphone, '政治学 political science lecture', subs: [
    ExploreSub('International relations', 'international relations lecture 国际关系'),
    ExploreSub('Comparative politics', 'comparative politics lecture 比较政治'),
    ExploreSub('Political theory', 'political theory lecture 政治理论'),
    ExploreSub('Public policy', 'public policy lecture 公共政策'),
    ExploreSub('Geopolitics', 'geopolitics lecture 地缘政治 讲座'),
  ]),
  ExploreTopic('Law', AppIcons.gavel, '法学 law lecture', subs: [
    ExploreSub('Jurisprudence', 'jurisprudence philosophy of law 法理学'),
    ExploreSub('Constitutional law', 'constitutional law lecture 宪法学'),
    ExploreSub('Roman law', 'Roman law lecture 罗马法'),
    ExploreSub('International law', 'international law lecture 国际法'),
    ExploreSub('Criminal law', 'criminal law lecture 刑法学'),
    ExploreSub('Civil law', 'civil law lecture 民法学'),
  ]),
  ExploreTopic('Anthropology', AppIcons.userCircle, '人类学 anthropology lecture', subs: [
    ExploreSub('Cultural anthropology', 'cultural anthropology lecture 文化人类学'),
    ExploreSub('Physical anthropology', 'biological anthropology human evolution lecture 体质人类学'),
    ExploreSub('Anthropology of religion', 'anthropology of religion lecture 宗教人类学'),
  ]),
  ExploreTopic('Geography', AppIcons.globe, '地理学 geography lecture', subs: [
    ExploreSub('Human geography', 'human geography lecture 人文地理'),
    ExploreSub('Physical geography', 'physical geography lecture 自然地理'),
    ExploreSub('GIS', 'GIS geographic information system course'),
  ]),
  ExploreTopic('Management', AppIcons.chartBar, '管理学 management lecture', subs: [
    ExploreSub('Strategy', 'business strategy lecture 战略管理'),
    ExploreSub('Marketing', 'marketing lecture 市场营销 课程'),
    ExploreSub('Accounting', 'accounting course lecture 会计学'),
    ExploreSub('Corporate finance', 'corporate finance lecture 公司金融'),
  ]),
  ExploreTopic('Education studies', AppIcons.graduationCap, '教育学 education theory lecture'),
  ExploreTopic('Media studies', AppIcons.newspaper, '传播学 media studies communication lecture'),
];

/// 理科: mathematics and the natural sciences.
final naturalScienceTopics = <ExploreTopic>[
  ExploreTopic('Math', AppIcons.graph, '数学 mathematics lecture', subs: [
    ExploreSub('Calculus', 'calculus lecture 微积分'),
    ExploreSub('Linear algebra', 'linear algebra lecture 线性代数'),
    ExploreSub('Abstract algebra', 'abstract algebra lecture 抽象代数'),
    ExploreSub('Analysis', 'real analysis lecture 数学分析'),
    ExploreSub('Geometry & topology', 'topology geometry lecture 拓扑 几何'),
    ExploreSub('Number theory', 'number theory lecture 数论'),
    ExploreSub('Probability & statistics', 'probability statistics lecture 概率论 数理统计'),
    ExploreSub('Mathematical logic', 'mathematical logic set theory 数理逻辑'),
    ExploreSub('Differential equations', 'differential equations lecture 微分方程'),
    ExploreSub('Combinatorics', 'combinatorics graph theory lecture 组合数学 图论'),
  ]),
  ExploreTopic('Physics', AppIcons.lightning, '物理 physics lecture', subs: [
    ExploreSub('Classical mechanics', 'classical mechanics lecture 经典力学'),
    ExploreSub('Electromagnetism', 'electromagnetism lecture 电磁学'),
    ExploreSub('Quantum mechanics', 'quantum mechanics lecture 量子力学'),
    ExploreSub('Relativity', 'general relativity lecture 相对论'),
    ExploreSub('Thermodynamics', 'thermodynamics statistical mechanics lecture 热力学'),
    ExploreSub('Particle physics', 'particle physics lecture 粒子物理'),
    ExploreSub('Condensed matter', 'condensed matter physics lecture 凝聚态'),
    ExploreSub('Optics', 'optics lecture 光学'),
    ExploreSub('Nuclear physics', 'nuclear physics lecture 核物理'),
  ]),
  ExploreTopic('Chemistry', AppIcons.flask, '化学 chemistry lecture', subs: [
    ExploreSub('Organic chemistry', 'organic chemistry lecture 有机化学'),
    ExploreSub('Inorganic chemistry', 'inorganic chemistry lecture 无机化学'),
    ExploreSub('Physical chemistry', 'physical chemistry lecture 物理化学'),
    ExploreSub('Biochemistry', 'biochemistry lecture 生物化学'),
    ExploreSub('Analytical chemistry', 'analytical chemistry lecture 分析化学'),
  ]),
  ExploreTopic('Biology', AppIcons.tree, '生物 biology lecture', subs: [
    ExploreSub('Molecular biology', 'molecular biology lecture 分子生物学'),
    ExploreSub('Genetics', 'genetics lecture 遗传学'),
    ExploreSub('Evolution', 'evolutionary biology lecture 进化生物学'),
    ExploreSub('Ecology', 'ecology lecture 生态学'),
    ExploreSub('Neuroscience', 'neuroscience lecture 神经科学'),
    ExploreSub('Cell biology', 'cell biology lecture 细胞生物学'),
    ExploreSub('Botany', 'botany plant biology lecture 植物学'),
    ExploreSub('Zoology', 'zoology lecture 动物学'),
    ExploreSub('Marine biology', 'marine biology lecture 海洋生物学'),
  ]),
  ExploreTopic('Astronomy', AppIcons.moonStars, '天文 astronomy astrophysics lecture', subs: [
    ExploreSub('Astrophysics', 'astrophysics lecture 天体物理'),
    ExploreSub('Cosmology', 'cosmology lecture 宇宙学'),
    ExploreSub('Planetary science', 'planetary science lecture 行星科学'),
  ]),
  ExploreTopic('Earth science', AppIcons.mountains, '地球科学 geology lecture', subs: [
    ExploreSub('Geology', 'geology lecture 地质学'),
    ExploreSub('Meteorology & climate', 'meteorology climate science lecture 气象 气候'),
    ExploreSub('Oceanography', 'oceanography lecture 海洋学'),
  ]),
  ExploreTopic('Statistics', AppIcons.chartBar, '统计学 statistics lecture', subs: [
    ExploreSub('Bayesian statistics', 'Bayesian statistics lecture 贝叶斯统计'),
    ExploreSub('Data science', 'data science course lecture 数据科学'),
  ]),
];

/// 工科: engineering and computing.
final engineeringTopics = <ExploreTopic>[
  ExploreTopic('Computer science', AppIcons.code, '计算机科学 computer science lecture', subs: [
    ExploreSub('Algorithms & data structures', 'algorithms data structures lecture 算法 数据结构'),
    ExploreSub('Theory of computation', 'theory of computation lecture 计算理论'),
    ExploreSub('Operating systems', 'operating systems course lecture 操作系统 课程'),
    ExploreSub('Computer networks', 'computer networks lecture 计算机网络'),
    ExploreSub('Databases', 'database systems lecture 数据库'),
    ExploreSub('Compilers', 'compilers course lecture 编译原理'),
    ExploreSub('Machine learning', 'machine learning course lecture 机器学习 课程'),
    ExploreSub('Computer graphics', 'computer graphics course lecture 计算机图形学'),
    ExploreSub('Distributed systems', 'distributed systems lecture 分布式系统'),
    ExploreSub('Programming languages', 'programming language theory lecture 程序设计语言'),
    ExploreSub('Human-computer interaction', 'human computer interaction HCI lecture 人机交互'),
  ]),
  ExploreTopic('Cybersecurity', AppIcons.shield, '网络空间安全 cybersecurity lecture', subs: [
    ExploreSub('Cryptography', 'cryptography lecture 密码学'),
    ExploreSub('Network security', 'network security course 网络安全 课程'),
    ExploreSub('Web security', 'web security OWASP lecture Web安全'),
    ExploreSub('Reverse engineering & binaries', 'reverse engineering binary exploitation 逆向工程 二进制安全'),
    ExploreSub('System security', 'operating system security lecture 系统安全'),
    ExploreSub('Penetration testing', 'penetration testing course 渗透测试'),
    ExploreSub('CTF', 'CTF writeup walkthrough'),
    ExploreSub('Security conferences', 'DEF CON Black Hat talk 安全大会'),
  ]),
  ExploreTopic('Electrical engineering', AppIcons.circuitry, '电子工程 electrical engineering lecture', subs: [
    ExploreSub('Circuits', 'circuit analysis lecture 电路'),
    ExploreSub('Signals & systems', 'signals and systems lecture 信号与系统'),
    ExploreSub('Semiconductors & chips', 'semiconductor chip design lecture 半导体 芯片'),
    ExploreSub('Communications', 'communication engineering lecture 通信原理'),
    ExploreSub('Power systems', 'power systems engineering lecture 电力系统'),
    ExploreSub('Embedded systems', 'embedded systems course 嵌入式'),
  ]),
  ExploreTopic('Mechanical engineering', AppIcons.gear, '机械工程 mechanical engineering lecture', subs: [
    ExploreSub('Engineering mechanics', 'engineering mechanics statics dynamics 工程力学'),
    ExploreSub('Fluid mechanics', 'fluid mechanics lecture 流体力学'),
    ExploreSub('Manufacturing', 'manufacturing engineering lecture 制造'),
    ExploreSub('Thermal engineering', 'heat transfer thermal engineering lecture 传热学'),
    ExploreSub('Mechanical design', 'mechanical design machine elements lecture 机械设计'),
  ]),
  ExploreTopic('Civil engineering & architecture', AppIcons.buildings, '土木工程 建筑学 civil engineering architecture lecture', subs: [
    ExploreSub('Structural engineering', 'structural engineering lecture 结构工程'),
    ExploreSub('Architecture', 'architecture lecture 建筑学'),
    ExploreSub('Urban planning', 'urban planning lecture 城市规划'),
  ]),
  ExploreTopic('Control & robotics', AppIcons.robot, '自动化 控制理论 robotics lecture', subs: [
    ExploreSub('Control theory', 'control theory lecture 控制理论'),
    ExploreSub('Robotics', 'robotics course lecture 机器人学'),
  ]),
  ExploreTopic('Aerospace engineering', AppIcons.airplaneTakeoff, '航空航天 aerospace engineering lecture', subs: [
    ExploreSub('Aerodynamics', 'aerodynamics lecture 空气动力学'),
    ExploreSub('Rocket propulsion', 'rocket propulsion lecture 火箭推进'),
    ExploreSub('Orbital mechanics', 'orbital mechanics lecture 轨道力学'),
  ]),
  ExploreTopic('Materials science', AppIcons.drop, '材料科学 materials science lecture'),
  ExploreTopic('Chemical engineering', AppIcons.flask, '化学工程 chemical engineering lecture'),
  ExploreTopic('Energy engineering', AppIcons.sunHorizon, '能源工程 energy engineering lecture'),
  ExploreTopic('Environmental engineering', AppIcons.tree, '环境工程 environmental engineering lecture'),
  ExploreTopic('Biomedical engineering', AppIcons.heartFill, '生物医学工程 biomedical engineering lecture'),
  ExploreTopic('Industrial engineering', AppIcons.chartLine, '工业工程 运筹学 operations research lecture'),
];

/// 医学: medicine and the health sciences.
final medicineTopics = <ExploreTopic>[
  ExploreTopic('Basic medical sciences', AppIcons.flask, '基础医学 medical school lecture', subs: [
    ExploreSub('Anatomy', 'anatomy lecture 解剖学'),
    ExploreSub('Physiology', 'physiology lecture 生理学'),
    ExploreSub('Pathology', 'pathology lecture 病理学'),
    ExploreSub('Immunology', 'immunology lecture 免疫学'),
    ExploreSub('Microbiology', 'microbiology lecture 微生物学'),
  ]),
  ExploreTopic('Clinical medicine', AppIcons.heart, '临床医学 clinical medicine lecture', subs: [
    ExploreSub('Internal medicine', 'internal medicine lecture 内科学'),
    ExploreSub('Surgery', 'surgery lecture 外科学'),
    ExploreSub('Pediatrics', 'pediatrics lecture 儿科学'),
    ExploreSub('Neurology', 'neurology lecture 神经病学'),
    ExploreSub('Cardiology', 'cardiology lecture 心脏病学'),
    ExploreSub('Oncology', 'oncology lecture 肿瘤学'),
    ExploreSub('Obstetrics & gynecology', 'obstetrics gynecology lecture 妇产科学'),
    ExploreSub('Emergency medicine', 'emergency medicine lecture 急诊医学'),
  ]),
  ExploreTopic('Psychiatry', AppIcons.brain, '精神医学 psychiatry lecture'),
  ExploreTopic('Pharmacology', AppIcons.drop, '药理学 pharmacology lecture'),
  ExploreTopic('Public health', AppIcons.shield, '公共卫生 public health epidemiology lecture'),
  ExploreTopic('Medical ethics', AppIcons.handHeart, '医学伦理 bioethics lecture'),
  ExploreTopic('Traditional Chinese medicine', AppIcons.drop, '中医 讲座 traditional Chinese medicine lecture'),
  ExploreTopic('Nursing', AppIcons.handHeart, '护理学 nursing lecture'),
  ExploreTopic('Dentistry', AppIcons.smiley, '口腔医学 dentistry lecture'),
  ExploreTopic('Nutrition science', AppIcons.forkKnife, '营养学 nutrition science lecture'),
];

/// 学术直播: lectures, conferences and science events streamed live.
final academicLiveTopics = <ExploreTopic>[
  ExploreTopic('Lectures', AppIcons.microphoneStage, 'lecture live 讲座 直播'),
  ExploreTopic('Conferences', AppIcons.usersThree, 'conference symposium live 学术会议 直播'),
  ExploreTopic('University events', AppIcons.graduationCap, 'university live stream 大学 直播'),
  ExploreTopic('Space & observatories', AppIcons.moonStars, 'NASA live launch observatory live'),
  ExploreTopic('Science talks', AppIcons.lightbulb, 'science talk live 科学 直播'),
  ExploreTopic('Thesis defenses', AppIcons.sealCheck, 'PhD defense live 博士答辩 直播'),
  ExploreTopic('Museum & library talks', AppIcons.bank, 'museum talk library lecture live 博物馆 讲座 直播'),
];
