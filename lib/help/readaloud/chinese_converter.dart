/// 简繁转换工具（对齐 legado-E 的 ChineseConverter）。
/// 内置常用繁简对照表，用于阅读正文的简繁转换。
class ChineseConverter {
  static const String _pairData = 
      '萬万與与專专業业叢丛東东絲丝丟丢兩两嚴严喪丧個个臨临為为麗丽舉举麼么義义烏乌樂乐喬乔習习鄉乡書书買买亂乱爭争於于虧亏雲云亞亚產产畝亩親亲億亿僅仅從从侖仑倉仓儀仪'
      '們们價价眾众優优會会傭佣偽伪傳传傷伤傾倾僱雇儉俭兒儿兌兑黨党蘭兰關关興兴養养獸兽內内冊册寫写軍军農农凍冻衝冲決决況况淨净淒凄準准湊凑減减幾几鳳凤憑凭凱凯擊击劃划'
      '劉刘則则剛刚創创刪删別别剎刹劑剂勸劝辦办務务動动勵励勁劲勞劳勢势區区醫医華华協协單单賣卖盧卢衛卫卻却廠厂廳厅厲厉壓压厭厌縣县隻只雙双發发臺台葉叶號号嘆叹嗎吗噸吨'
      '聽听啟启吳吴吶呐嚇吓呂吕嘍喽囑嘱場场塊块壇坛壘垒墾垦壯壮聲声壺壶處处復复頭头奮奋獎奖婦妇媽妈嫵妩嬰婴孫孙學学寧宁寶宝實实寵宠審审寬宽尋寻對对導导壽寿將将爾尔塵尘'
      '層层屬属嶼屿歲岁豈岂嶄崭嶺岭島岛峽峡師师帶带幫帮幹干莊庄廣广廢废張张彈弹強强歸归當当錄录徹彻誌志懷怀態态恆恒憶忆懼惧憂忧懸悬惡恶惱恼愴怆懲惩慣惯應应懶懒戰战戲戏'
      '戶户紮扎拋抛掃扫揚扬換换揮挥損损搖摇搶抢擁拥擇择擠挤擺摆擴扩攏拢攔拦攙搀攪搅敵敌敘叙數数斂敛斷断無无舊旧時时晉晋曉晓曠旷條条棟栋楊杨極极構构樹树權权樣样欄栏橫横'
      '檔档檢检檜桧檻槛櫃柜歡欢歐欧歷历殘残殺杀殼壳毀毁畢毕氣气漢汉湯汤沒没沖冲洶汹澤泽潔洁灑洒淺浅漿浆濁浊濃浓濕湿濟济濤涛瀉泻瀏浏灣湾瀰弥瀟潇災灾熱热煥焕煩烦燒烧燙烫'
      '燦灿營营燭烛爺爷牆墙犧牺狀状猶犹獨独獅狮獄狱獻献現现瑣琐環环畫画異异療疗癢痒皺皱盜盗盡尽監监盤盘睜睁睏困瞇眯瞭了礙碍礦矿礫砾礎础禮礼禱祷種种積积稱称穩稳窮穷窺窥'
      '竄窜窩窝竅窍競竞筆笔筍笋築筑簡简簽签糧粮級级紀纪約约紅红紆纡純纯納纳紙纸紛纷紋纹紡纺細细紳绅紹绍終终給给統统絹绢綁绑綢绸維维緒绪續续纓缨縮缩縱纵縷缕總总績绩繁繁'
      '織织繞绕繪绘繩绳繼继纜缆罰罚罷罢羅罗職职聯联聳耸聰聪肅肃腸肠膚肤膽胆脅胁脈脉腳脚臉脸脫脱脹胀腎肾腫肿臘腊舖铺艱艰艙舱藝艺藥药蘇苏蟲虫蠶蚕裡里補补裝装褲裤複复見见'
      '觀观覓觅規规視视覺觉覽览觸触訂订計计訊讯討讨訓训訪访設设許许訴诉診诊詞词譯译試试詩诗誠诚話话該该詳详認认說说請请諸诸讀读課课誰谁調调談谈謀谋謂谓講讲謝谢證证識识'
      '議议護护變变讓让豐丰貝贝責责貨货費费資资賓宾賢贤賬账質质賴赖賺赚賽赛贊赞贈赠贏赢趙赵趨趋車车軌轨軟软轉转輪轮轟轰辭辞辯辩連连進进遠远違违遲迟遷迁選选遺遗邁迈還还'
      '邊边邏逻鄰邻鄭郑釋释裏里針针釘钉釣钓鈣钙鈉钠鋼钢鍾钟鍵键鎖锁鎮镇鏡镜鏈链錯错鍛锻鍍镀鑑鉴長长門门閉闭問问開开間间閒闲闖闯隊队陽阳陰阴陣阵階阶際际陸陆陳陈險险隨随'
      '隱隐雖虽雜杂難难電电霧雾靈灵靜静頁页頂顶項项順顺須须預预頑顽領领頻频顆颗題题額额顏颜顧顾風风飛飞餘余館馆馬马驅驱驗验驚惊體体髮发鬥斗魚鱼鮮鲜鯽鲫鳥鸟鴨鸭鴻鸿鵝鹅'
      '鶴鹤麥麦黃黄點点齊齐齡龄龍龙龜龟'
      ;

  static final Map<String, String> _t2s = _parse();
  static final Map<String, String> _s2t = _parseReverse();

  static Map<String, String> _parse() {
    final m = <String, String>{};
    for (var i = 0; i + 1 < _pairData.length; i += 2) {
      m[_pairData[i]] = _pairData[i + 1];
    }
    return m;
  }

  static Map<String, String> _parseReverse() {
    final m = <String, String>{};
    _t2s.forEach((k, v) { m.putIfAbsent(v, () => k); });
    return m;
  }

  /// 转换正文。mode: 0=不转换 1=转简体 2=转繁体
  static String convert(String text, int mode) {
    if (mode == 1) return _toSimplified(text);
    if (mode == 2) return _toTraditional(text);
    return text;
  }

  static String _toSimplified(String text) => _map(text, _t2s);
  static String _toTraditional(String text) => _map(text, _s2t);

  static String _map(String text, Map<String, String> table) {
    if (text.isEmpty) return text;
    final sb = StringBuffer();
    for (final ch in text.split('')) {
      sb.write(table[ch] ?? ch);
    }
    return sb.toString();
  }
}
