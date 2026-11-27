import 'explore_topics.dart';
import 'ui/app_icons.dart';

// The zones of 学术, one list per tab, grouped the way universities group
// their faculties. Each is a YouTube search that leans on lecture, course
// and talk words, so the lists bring up teaching rather than entertainment
// about the subject.

/// 人文: philosophy, theology and the other humanities.
final humanitiesTopics = <ExploreTopic>[
  ExploreTopic('Philosophy', AppIcons.lightbulb, '哲学 philosophy lecture', subs: [
    const ExploreSub('Ancient philosophy', 'ancient Greek philosophy Plato Aristotle 古希腊哲学', subs: [
      ExploreSub('Presocratics', 'Presocratic philosophers'),
      ExploreSub('Plato', 'Plato philosophy lecture 柏拉图'),
      ExploreSub('Aristotle', 'Aristotle philosophy lecture 亚里士多德'),
      ExploreSub('Stoicism', 'Stoicism lecture 斯多葛'),
      ExploreSub('Neoplatonism', 'Neoplatonism Plotinus'),
    ]),
    const ExploreSub('Medieval philosophy', 'medieval philosophy scholasticism 经院哲学', subs: [
      ExploreSub('Augustine', 'Augustine philosophy 奥古斯丁'),
      ExploreSub('Thomas Aquinas', 'Thomas Aquinas philosophy 托马斯 阿奎那'),
      ExploreSub('Islamic philosophy', 'Islamic philosophy Avicenna Averroes'),
      ExploreSub('Jewish philosophy', 'Maimonides Jewish philosophy'),
    ]),
    const ExploreSub('Modern philosophy', 'modern philosophy Descartes Kant 近代哲学', subs: [
      ExploreSub('Rationalism & empiricism', 'rationalism empiricism Descartes Hume'),
      ExploreSub('Kant', 'Kant philosophy lecture 康德'),
      ExploreSub('Hegel', 'Hegel philosophy lecture 黑格尔'),
      ExploreSub('Nietzsche', 'Nietzsche philosophy 尼采'),
    ]),
    const ExploreSub('Contemporary philosophy', '20th century philosophy 现代哲学', subs: [
      ExploreSub('Phenomenology', 'phenomenology Husserl Heidegger 现象学'),
      ExploreSub('Existentialism', 'existentialism Sartre Kierkegaard 存在主义'),
      ExploreSub('Analytic philosophy', 'analytic philosophy Wittgenstein 分析哲学'),
      ExploreSub('Critical theory', 'Frankfurt School critical theory'),
    ]),
    const ExploreSub('Ethics', 'ethics moral philosophy lecture 伦理学'),
    const ExploreSub('Logic', 'logic philosophy lecture 逻辑学'),
    const ExploreSub('Metaphysics', 'metaphysics lecture 形而上学'),
    const ExploreSub('Epistemology', 'epistemology lecture 认识论'),
    const ExploreSub('Philosophy of mind', 'philosophy of mind consciousness 心灵哲学'),
    const ExploreSub('Political philosophy', 'political philosophy lecture 政治哲学'),
    const ExploreSub('Philosophy of science', 'philosophy of science lecture 科学哲学'),
    const ExploreSub('Aesthetics', 'aesthetics philosophy of art lecture 美学'),
    const ExploreSub('Philosophy of religion', 'philosophy of religion lecture 宗教哲学 讲座'),
    const ExploreSub('Chinese philosophy', '中国哲学 儒家 道家 Chinese philosophy'),
  ]),
  ExploreTopic('Theology', AppIcons.handsPraying, '神学 theology lecture', subs: [
    const ExploreSub('Systematic theology', 'systematic theology lecture 系统神学', subs: [
      ExploreSub('Trinity', 'Trinity theology lecture 三位一体'),
      ExploreSub('Christology', 'Christology lecture 基督论'),
      ExploreSub('Ecclesiology', 'ecclesiology lecture 教会论'),
      ExploreSub('Eschatology', 'eschatology lecture 末世论'),
    ]),
    const ExploreSub('Biblical studies', 'biblical studies lecture 圣经学', subs: [
      ExploreSub('Old Testament', 'Old Testament lecture 旧约'),
      ExploreSub('New Testament', 'New Testament lecture 新约'),
      ExploreSub('Biblical languages', 'Biblical Hebrew Koine Greek 圣经原文'),
    ]),
    const ExploreSub('Fundamental theology', 'fundamental theology revelation faith and reason 基本神学'),
    const ExploreSub('Patristics', 'patristics Church Fathers lecture 教父学'),
    const ExploreSub('Church history', 'church history lecture 教会史'),
    const ExploreSub('Moral theology', 'moral theology lecture 伦理神学'),
    const ExploreSub('Liturgical studies', 'liturgical theology lecture 礼仪学'),
    const ExploreSub('Canon law', 'canon law lecture 教会法'),
    const ExploreSub('Spiritual theology', 'spiritual theology mysticism lecture 灵修神学'),
    const ExploreSub('Eastern theology', 'Eastern Orthodox theology lecture 东方神学'),
    const ExploreSub('Mariology', 'Mariology lecture 圣母论'),
    const ExploreSub('Sacramental theology', 'sacramental theology lecture 圣事神学'),
    const ExploreSub('Missiology', 'missiology lecture 宣教学'),
    const ExploreSub('Ecumenism', 'ecumenism ecumenical theology lecture 合一运动'),
  ]),
  ExploreTopic('History', AppIcons.scroll, '历史 history lecture', subs: [
    const ExploreSub('Ancient history', 'ancient history lecture 古代史'),
    const ExploreSub('Medieval history', 'medieval history lecture 中世纪史'),
    const ExploreSub('Modern history', 'modern history lecture 近代史'),
    const ExploreSub('Chinese history', '中国历史 讲座 Chinese history'),
    const ExploreSub('Historiography', 'historiography lecture 史学理论'),
    const ExploreSub('Byzantine history', 'Byzantine history lecture 拜占庭史'),
    const ExploreSub('History of science', 'history of science lecture 科学史'),
  ]),
  ExploreTopic('Literature', AppIcons.bookOpenText, '文学 literature lecture', subs: [
    const ExploreSub('Literary theory', 'literary theory lecture 文学理论'),
    const ExploreSub('Classical Chinese literature', '中国古典文学 讲座'),
    const ExploreSub('Western literature', 'Western literature lecture 西方文学'),
    const ExploreSub('Poetry', 'poetry lecture 诗歌 讲座'),
  ]),
  ExploreTopic('Linguistics', AppIcons.translate, '语言学 linguistics lecture', subs: [
    const ExploreSub('Phonetics', 'phonetics phonology lecture 语音学'),
    const ExploreSub('Syntax', 'syntax linguistics lecture 句法'),
    const ExploreSub('Historical linguistics', 'historical linguistics lecture 历史语言学'),
    const ExploreSub('Classical languages', 'Latin Ancient Greek lesson 拉丁语 古希腊语'),
  ]),
  ExploreTopic('Classics', AppIcons.bank, 'classics Greek Roman lecture 古典学'),
  ExploreTopic('Archaeology', AppIcons.compass, '考古 archaeology lecture', subs: [
    const ExploreSub('Egyptology', 'Egyptology lecture 埃及学'),
    const ExploreSub('Classical archaeology', 'classical archaeology Greece Rome lecture'),
    const ExploreSub('Biblical archaeology', 'biblical archaeology lecture 圣经考古'),
    const ExploreSub('Chinese archaeology', '中国考古 讲座'),
  ]),
  ExploreTopic('Art history', AppIcons.palette, '艺术史 art history lecture', subs: [
    const ExploreSub('Medieval art', 'medieval art history lecture 中世纪艺术'),
    const ExploreSub('Renaissance art', 'Renaissance art history lecture 文艺复兴艺术'),
    const ExploreSub('Modern art', 'modern art history lecture 现代艺术'),
    const ExploreSub('Chinese art history', '中国美术史 讲座'),
  ]),
  ExploreTopic('Musicology', AppIcons.musicNotes, '音乐学 musicology lecture', subs: [
    const ExploreSub('Music theory', 'music theory lecture 乐理 和声'),
    const ExploreSub('Music history', 'music history lecture 音乐史'),
    const ExploreSub('Ethnomusicology', 'ethnomusicology lecture 民族音乐学'),
  ]),
];

/// 社会科学: psychology and the other social sciences.
final socialScienceTopics = <ExploreTopic>[
  ExploreTopic('Psychology', AppIcons.brain, '心理学 psychology lecture', subs: [
    const ExploreSub('Introduction to psychology', 'introduction to psychology course 心理学导论'),
    const ExploreSub('Cognitive psychology', 'cognitive psychology lecture 认知心理学'),
    const ExploreSub('Developmental psychology', 'developmental psychology lecture 发展心理学'),
    const ExploreSub('Social psychology', 'social psychology lecture 社会心理学'),
    const ExploreSub('Clinical psychology', 'clinical psychology lecture 临床心理学', subs: [
      ExploreSub('Psychotherapy', 'psychotherapy lecture 心理治疗'),
      ExploreSub('Cognitive behavioral therapy', 'CBT cognitive behavioral therapy 认知行为疗法'),
      ExploreSub('Psychopathology', 'psychopathology abnormal psychology 变态心理学'),
    ]),
    const ExploreSub('Personality psychology', 'personality psychology lecture 人格心理学'),
    const ExploreSub('Biological psychology', 'biological psychology neuroscience 生理心理学'),
    const ExploreSub('Psychoanalysis', 'psychoanalysis Freud Jung lecture 精神分析'),
    const ExploreSub('Neuropsychology', 'neuropsychology lecture 神经心理学'),
    const ExploreSub('Educational psychology', 'educational psychology lecture 教育心理学'),
    const ExploreSub('Organizational psychology', 'industrial organizational psychology lecture 管理心理学'),
    const ExploreSub('Positive psychology', 'positive psychology lecture 积极心理学'),
    const ExploreSub('Research methods', 'psychology research methods statistics 心理学研究方法'),
    const ExploreSub('Psychology of religion', 'psychology of religion lecture 宗教心理学'),
  ]),
  ExploreTopic('Sociology', AppIcons.usersThree, '社会学 sociology lecture', subs: [
    const ExploreSub('Social theory', 'social theory Weber Durkheim 社会理论'),
    const ExploreSub('Sociology of religion', 'sociology of religion lecture 宗教社会学'),
    const ExploreSub('Demography', 'demography population lecture 人口学'),
    const ExploreSub('Criminology', 'criminology lecture 犯罪学'),
    const ExploreSub('Urban sociology', 'urban sociology lecture 城市社会学'),
  ]),
  ExploreTopic('Economics', AppIcons.chartLine, '经济学 economics lecture', subs: [
    const ExploreSub('Microeconomics', 'microeconomics lecture 微观经济学'),
    const ExploreSub('Macroeconomics', 'macroeconomics lecture 宏观经济学'),
    const ExploreSub('Econometrics', 'econometrics lecture 计量经济学'),
    const ExploreSub('Economic history', 'economic history lecture 经济史'),
    const ExploreSub('Game theory', 'game theory lecture 博弈论'),
    const ExploreSub('Behavioral economics', 'behavioral economics lecture 行为经济学'),
    const ExploreSub('Development economics', 'development economics lecture 发展经济学'),
  ]),
  ExploreTopic('Political science', AppIcons.megaphone, '政治学 political science lecture', subs: [
    const ExploreSub('International relations', 'international relations lecture 国际关系'),
    const ExploreSub('Comparative politics', 'comparative politics lecture 比较政治'),
    const ExploreSub('Political theory', 'political theory lecture 政治理论'),
    const ExploreSub('Public policy', 'public policy lecture 公共政策'),
    const ExploreSub('Geopolitics', 'geopolitics lecture 地缘政治 讲座'),
  ]),
  ExploreTopic('Law', AppIcons.gavel, '法学 law lecture', subs: [
    const ExploreSub('Jurisprudence', 'jurisprudence philosophy of law 法理学'),
    const ExploreSub('Constitutional law', 'constitutional law lecture 宪法学'),
    const ExploreSub('Roman law', 'Roman law lecture 罗马法'),
    const ExploreSub('International law', 'international law lecture 国际法'),
    const ExploreSub('Criminal law', 'criminal law lecture 刑法学'),
    const ExploreSub('Civil law', 'civil law lecture 民法学'),
  ]),
  ExploreTopic('Anthropology', AppIcons.userCircle, '人类学 anthropology lecture', subs: [
    const ExploreSub('Cultural anthropology', 'cultural anthropology lecture 文化人类学'),
    const ExploreSub('Physical anthropology', 'biological anthropology human evolution lecture 体质人类学'),
    const ExploreSub('Anthropology of religion', 'anthropology of religion lecture 宗教人类学'),
  ]),
  ExploreTopic('Geography', AppIcons.globe, '地理学 geography lecture', subs: [
    const ExploreSub('Human geography', 'human geography lecture 人文地理'),
    const ExploreSub('Physical geography', 'physical geography lecture 自然地理'),
    const ExploreSub('GIS', 'GIS geographic information system course'),
  ]),
  ExploreTopic('Management', AppIcons.chartBar, '管理学 management lecture', subs: [
    const ExploreSub('Strategy', 'business strategy lecture 战略管理'),
    const ExploreSub('Marketing', 'marketing lecture 市场营销 课程'),
    const ExploreSub('Accounting', 'accounting course lecture 会计学'),
    const ExploreSub('Corporate finance', 'corporate finance lecture 公司金融'),
  ]),
  ExploreTopic('Education studies', AppIcons.graduationCap, '教育学 education theory lecture'),
  ExploreTopic('Media studies', AppIcons.newspaper, '传播学 media studies communication lecture'),
];

/// 理科: mathematics and the natural sciences.
final naturalScienceTopics = <ExploreTopic>[
  ExploreTopic('Math', AppIcons.graph, '数学 mathematics lecture', subs: [
    const ExploreSub('Calculus', 'calculus lecture 微积分'),
    const ExploreSub('Linear algebra', 'linear algebra lecture 线性代数'),
    const ExploreSub('Abstract algebra', 'abstract algebra lecture 抽象代数'),
    const ExploreSub('Analysis', 'real analysis lecture 数学分析'),
    const ExploreSub('Geometry & topology', 'topology geometry lecture 拓扑 几何'),
    const ExploreSub('Number theory', 'number theory lecture 数论'),
    const ExploreSub('Probability & statistics', 'probability statistics lecture 概率论 数理统计'),
    const ExploreSub('Mathematical logic', 'mathematical logic set theory 数理逻辑'),
    const ExploreSub('Differential equations', 'differential equations lecture 微分方程'),
    const ExploreSub('Combinatorics', 'combinatorics graph theory lecture 组合数学 图论'),
  ]),
  ExploreTopic('Physics', AppIcons.lightning, '物理 physics lecture', subs: [
    const ExploreSub('Classical mechanics', 'classical mechanics lecture 经典力学'),
    const ExploreSub('Electromagnetism', 'electromagnetism lecture 电磁学'),
    const ExploreSub('Quantum mechanics', 'quantum mechanics lecture 量子力学'),
    const ExploreSub('Relativity', 'general relativity lecture 相对论'),
    const ExploreSub('Thermodynamics', 'thermodynamics statistical mechanics lecture 热力学'),
    const ExploreSub('Particle physics', 'particle physics lecture 粒子物理'),
    const ExploreSub('Condensed matter', 'condensed matter physics lecture 凝聚态'),
    const ExploreSub('Optics', 'optics lecture 光学'),
    const ExploreSub('Nuclear physics', 'nuclear physics lecture 核物理'),
  ]),
  ExploreTopic('Chemistry', AppIcons.flask, '化学 chemistry lecture', subs: [
    const ExploreSub('Organic chemistry', 'organic chemistry lecture 有机化学'),
    const ExploreSub('Inorganic chemistry', 'inorganic chemistry lecture 无机化学'),
    const ExploreSub('Physical chemistry', 'physical chemistry lecture 物理化学'),
    const ExploreSub('Biochemistry', 'biochemistry lecture 生物化学'),
    const ExploreSub('Analytical chemistry', 'analytical chemistry lecture 分析化学'),
  ]),
  ExploreTopic('Biology', AppIcons.tree, '生物 biology lecture', subs: [
    const ExploreSub('Molecular biology', 'molecular biology lecture 分子生物学'),
    const ExploreSub('Genetics', 'genetics lecture 遗传学'),
    const ExploreSub('Evolution', 'evolutionary biology lecture 进化生物学'),
    const ExploreSub('Ecology', 'ecology lecture 生态学'),
    const ExploreSub('Neuroscience', 'neuroscience lecture 神经科学'),
    const ExploreSub('Cell biology', 'cell biology lecture 细胞生物学'),
    const ExploreSub('Botany', 'botany plant biology lecture 植物学'),
    const ExploreSub('Zoology', 'zoology lecture 动物学'),
    const ExploreSub('Marine biology', 'marine biology lecture 海洋生物学'),
  ]),
  ExploreTopic('Astronomy', AppIcons.moonStars, '天文 astronomy astrophysics lecture', subs: [
    const ExploreSub('Astrophysics', 'astrophysics lecture 天体物理'),
    const ExploreSub('Cosmology', 'cosmology lecture 宇宙学'),
    const ExploreSub('Planetary science', 'planetary science lecture 行星科学'),
  ]),
  ExploreTopic('Earth science', AppIcons.mountains, '地球科学 geology lecture', subs: [
    const ExploreSub('Geology', 'geology lecture 地质学'),
    const ExploreSub('Meteorology & climate', 'meteorology climate science lecture 气象 气候'),
    const ExploreSub('Oceanography', 'oceanography lecture 海洋学'),
  ]),
  ExploreTopic('Statistics', AppIcons.chartBar, '统计学 statistics lecture', subs: [
    const ExploreSub('Bayesian statistics', 'Bayesian statistics lecture 贝叶斯统计'),
    const ExploreSub('Data science', 'data science course lecture 数据科学'),
  ]),
];

/// 工科: engineering and computing.
final engineeringTopics = <ExploreTopic>[
  ExploreTopic('Computer science', AppIcons.code, '计算机科学 computer science lecture', subs: [
    const ExploreSub('Algorithms & data structures', 'algorithms data structures lecture 算法 数据结构'),
    const ExploreSub('Theory of computation', 'theory of computation lecture 计算理论'),
    const ExploreSub('Operating systems', 'operating systems course lecture 操作系统 课程'),
    const ExploreSub('Computer networks', 'computer networks lecture 计算机网络'),
    const ExploreSub('Databases', 'database systems lecture 数据库'),
    const ExploreSub('Compilers', 'compilers course lecture 编译原理'),
    const ExploreSub('Machine learning', 'machine learning course lecture 机器学习 课程'),
    const ExploreSub('Computer graphics', 'computer graphics course lecture 计算机图形学'),
    const ExploreSub('Distributed systems', 'distributed systems lecture 分布式系统'),
    const ExploreSub('Programming languages', 'programming language theory lecture 程序设计语言'),
    const ExploreSub('Human-computer interaction', 'human computer interaction HCI lecture 人机交互'),
  ]),
  ExploreTopic('Cybersecurity', AppIcons.shield, '网络空间安全 cybersecurity lecture', subs: [
    const ExploreSub('Cryptography', 'cryptography lecture 密码学'),
    const ExploreSub('Network security', 'network security course 网络安全 课程'),
    const ExploreSub('Web security', 'web security OWASP lecture Web安全'),
    const ExploreSub('Reverse engineering & binaries', 'reverse engineering binary exploitation 逆向工程 二进制安全'),
    const ExploreSub('System security', 'operating system security lecture 系统安全'),
    const ExploreSub('Penetration testing', 'penetration testing course 渗透测试'),
    const ExploreSub('CTF', 'CTF writeup walkthrough'),
    const ExploreSub('Security conferences', 'DEF CON Black Hat talk 安全大会'),
  ]),
  ExploreTopic('Electrical engineering', AppIcons.circuitry, '电子工程 electrical engineering lecture', subs: [
    const ExploreSub('Circuits', 'circuit analysis lecture 电路'),
    const ExploreSub('Signals & systems', 'signals and systems lecture 信号与系统'),
    const ExploreSub('Semiconductors & chips', 'semiconductor chip design lecture 半导体 芯片'),
    const ExploreSub('Communications', 'communication engineering lecture 通信原理'),
    const ExploreSub('Power systems', 'power systems engineering lecture 电力系统'),
    const ExploreSub('Embedded systems', 'embedded systems course 嵌入式'),
  ]),
  ExploreTopic('Mechanical engineering', AppIcons.gear, '机械工程 mechanical engineering lecture', subs: [
    const ExploreSub('Engineering mechanics', 'engineering mechanics statics dynamics 工程力学'),
    const ExploreSub('Fluid mechanics', 'fluid mechanics lecture 流体力学'),
    const ExploreSub('Manufacturing', 'manufacturing engineering lecture 制造'),
    const ExploreSub('Thermal engineering', 'heat transfer thermal engineering lecture 传热学'),
    const ExploreSub('Mechanical design', 'mechanical design machine elements lecture 机械设计'),
  ]),
  ExploreTopic('Civil engineering & architecture', AppIcons.buildings, '土木工程 建筑学 civil engineering architecture lecture', subs: [
    const ExploreSub('Structural engineering', 'structural engineering lecture 结构工程'),
    const ExploreSub('Architecture', 'architecture lecture 建筑学'),
    const ExploreSub('Urban planning', 'urban planning lecture 城市规划'),
  ]),
  ExploreTopic('Control & robotics', AppIcons.robot, '自动化 控制理论 robotics lecture', subs: [
    const ExploreSub('Control theory', 'control theory lecture 控制理论'),
    const ExploreSub('Robotics', 'robotics course lecture 机器人学'),
  ]),
  ExploreTopic('Aerospace engineering', AppIcons.airplaneTakeoff, '航空航天 aerospace engineering lecture', subs: [
    const ExploreSub('Aerodynamics', 'aerodynamics lecture 空气动力学'),
    const ExploreSub('Rocket propulsion', 'rocket propulsion lecture 火箭推进'),
    const ExploreSub('Orbital mechanics', 'orbital mechanics lecture 轨道力学'),
  ]),
  ExploreTopic('Materials science', AppIcons.drop, '材料科学 materials science lecture'),
  ExploreTopic('Chemical engineering', AppIcons.flask, '化学工程 chemical engineering lecture'),
  ExploreTopic('Energy engineering', AppIcons.sunHorizon, '能源工程 energy engineering lecture'),
  ExploreTopic('Environmental engineering', AppIcons.tree, '环境工程 environmental engineering lecture'),
  const ExploreTopic('Biomedical engineering', AppIcons.heartFill, '生物医学工程 biomedical engineering lecture'),
  ExploreTopic('Industrial engineering', AppIcons.chartLine, '工业工程 运筹学 operations research lecture'),
];

/// 医学: medicine and the health sciences.
final medicineTopics = <ExploreTopic>[
  ExploreTopic('Basic medical sciences', AppIcons.flask, '基础医学 medical school lecture', subs: [
    const ExploreSub('Anatomy', 'anatomy lecture 解剖学'),
    const ExploreSub('Physiology', 'physiology lecture 生理学'),
    const ExploreSub('Pathology', 'pathology lecture 病理学'),
    const ExploreSub('Immunology', 'immunology lecture 免疫学'),
    const ExploreSub('Microbiology', 'microbiology lecture 微生物学'),
  ]),
  ExploreTopic('Clinical medicine', AppIcons.heart, '临床医学 clinical medicine lecture', subs: [
    const ExploreSub('Internal medicine', 'internal medicine lecture 内科学'),
    const ExploreSub('Surgery', 'surgery lecture 外科学'),
    const ExploreSub('Pediatrics', 'pediatrics lecture 儿科学'),
    const ExploreSub('Neurology', 'neurology lecture 神经病学'),
    const ExploreSub('Cardiology', 'cardiology lecture 心脏病学'),
    const ExploreSub('Oncology', 'oncology lecture 肿瘤学'),
    const ExploreSub('Obstetrics & gynecology', 'obstetrics gynecology lecture 妇产科学'),
    const ExploreSub('Emergency medicine', 'emergency medicine lecture 急诊医学'),
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

/// 前沿研究: this year's research as the people doing it present it, in
/// seminars, colloquia, conference talks and paper walkthroughs, rather
/// than courses on settled knowledge. Searched within the past year.
final frontierTopics = <ExploreTopic>[
  ExploreTopic('AI & machine learning', AppIcons.robot, 'machine learning research talk paper NeurIPS ICML ICLR 人工智能 前沿', subs: [
    const ExploreSub('Large language models', 'large language models research talk paper 大模型 论文'),
    const ExploreSub('Reinforcement learning', 'reinforcement learning research talk paper'),
    const ExploreSub('Computer vision', 'computer vision research talk CVPR paper'),
    const ExploreSub('AI safety & alignment', 'AI alignment safety research talk'),
    const ExploreSub('Robotics', 'robotics research talk RSS CoRL paper 机器人 前沿'),
  ]),
  ExploreTopic('Physics', AppIcons.lightning, 'physics colloquium research seminar new results 物理 前沿', subs: [
    const ExploreSub('Particle physics', 'particle physics seminar CERN new results'),
    const ExploreSub('Quantum physics', 'quantum physics research seminar quantum computing results 量子'),
    const ExploreSub('Condensed matter', 'condensed matter physics seminar superconductivity'),
    const ExploreSub('Fusion & plasma', 'fusion energy plasma physics research update'),
  ]),
  ExploreTopic('Astronomy & space', AppIcons.moonStars, 'astronomy colloquium JWST new discovery research 天文 前沿', subs: [
    const ExploreSub('Cosmology', 'cosmology seminar new results dark energy dark matter'),
    const ExploreSub('Exoplanets', 'exoplanet research talk JWST'),
    const ExploreSub('Gravitational waves', 'gravitational waves LIGO research talk'),
  ]),
  ExploreTopic('Mathematics', AppIcons.graph, 'mathematics seminar new proof colloquium 数学 前沿'),
  ExploreTopic('Life sciences', AppIcons.tree, 'biology research seminar new discovery 生命科学 前沿', subs: [
    const ExploreSub('Genetics & genomics', 'genomics CRISPR gene editing research talk 基因'),
    const ExploreSub('Neuroscience', 'neuroscience research seminar brain new findings 神经科学'),
    const ExploreSub('Evolution', 'evolutionary biology research talk new findings'),
    const ExploreSub('Synthetic biology', 'synthetic biology research talk'),
  ]),
  ExploreTopic('Medical research', AppIcons.heart, 'medical research clinical trial results grand rounds 医学 前沿', subs: [
    const ExploreSub('Cancer research', 'cancer research new treatment trial results talk'),
    const ExploreSub('Vaccines & infectious disease', 'vaccine infectious disease research talk'),
    const ExploreSub('Aging & longevity', 'aging longevity research talk'),
  ]),
  ExploreTopic('Chemistry & materials', AppIcons.flask, 'chemistry materials science research seminar new 材料 前沿'),
  ExploreTopic('Climate & Earth', AppIcons.globe, 'climate science research talk new study 气候 前沿'),
  ExploreTopic('Energy & engineering', AppIcons.gear, 'engineering research breakthrough battery energy research talk 工程 前沿'),
  ExploreTopic('Computing', AppIcons.code, 'computer science research talk systems security paper 计算机 前沿'),
  ExploreTopic('Social sciences', AppIcons.chartBar, 'social science research seminar new study economics psychology 社科 前沿'),
  ExploreTopic('Humanities', AppIcons.scroll, 'humanities research lecture new findings archaeology discovery 人文 前沿'),
  ExploreTopic('Theology & religious studies', AppIcons.handsPraying, 'theology research conference paper religious studies new scholarship 神学 研究'),
];
