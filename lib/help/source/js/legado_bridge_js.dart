/// 注入到无头 WebView（V8）中的 legado 兼容桥。
///
/// 对齐 legado（legado/app/src/main/java/io/legado/app/help/JsExtensions.kt
/// 与 AnalyzeUrl / AnalyzeRule）在书源脚本里使用的运行时环境：
///
///   * 全局对象：java / cookie / source / book / cache / result / key / page / baseUrl
///   * java.ajax / get / post / connect —— 以「同步 XHR」实现，由原生
///     shouldInterceptRequest 接管发请求（绕过 CORS、统一 Cookie/编码）。
///   * source.getVariable/setVariable/getLoginInfo/putLoginInfo
///   * cookie.getCookie/setCookie/removeCookie/getKey
///   * cache / java.put / java.get 跨阶段键值
///   * 编码：base64、hex；时间格式化；deviceID/androidId；UA
///   * startBrowser* / showBrowser* / reLoginView —— 走原生可见 WebView 交互登录
///
/// 该脚本在每个书源的无头 WebView 创建后于「全局作用域」执行一次；
/// 书源的 jsLib / loginUrl 随后也在全局作用域执行（定义全局函数）。
class LegadoBridgeJs {
  static const String code = r'''
(function () {
  if (globalThis.__legadoBridgeReady) return;
  globalThis.__legadoBridgeReady = true;

  var __state = {
    meta: { url: "", name: "", httpUrl: "", group: "", comment: "", type: 0, concurrentRate: 0, enabledExplore: false, header: "", loginUrl: "", jsLib: "", bookUrlPattern: "" },
    variable: "",
    variableComment: "",
    lastUpdateTime: 0,
    loginInfo: "",
    loginHeader: "",
    kv: {},
    cookies: {},
    logs: [],
    toasts: [],
    hosts: [],
    browser: [],
    deviceId: "",
    ua: (typeof navigator !== "undefined" && navigator.userAgent) ? navigator.userAgent :
        "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
  };
  globalThis.__state = __state;

  // 简繁转换（常用字对照表，覆盖高频小说用字）
  var __T2S = {"萬": "万", "與": "与", "醜": "丑", "專": "专", "業": "业", "叢": "丛", "東": "东", "絲": "丝", "丟": "丢", "兩": "两", "嚴": "严", "喪": "丧", "個": "个", "臨": "临", "為": "为", "麗": "丽", "舉": "举", "麼": "么", "義": "义", "烏": "乌", "樂": "乐", "喬": "乔", "習": "习", "鄉": "乡", "書": "书", "買": "买", "亂": "乱", "爭": "争", "於": "于", "虧": "亏", "雲": "云", "亞": "亚", "產": "产", "畝": "亩", "親": "亲", "褻": "亵", "億": "亿", "僅": "仅", "從": "从", "侖": "仑", "倉": "仓", "儀": "仪", "們": "们", "價": "价", "眾": "众", "優": "优", "會": "会", "傭": "佣", "偽": "伪", "傳": "传", "傷": "伤", "傾": "倾", "僱": "雇", "儉": "俭", "兒": "儿", "兌": "兑", "黨": "党", "蘭": "兰", "關": "关", "興": "兴", "養": "养", "獸": "兽", "內": "内", "冊": "册", "寫": "写", "軍": "军", "農": "农", "凍": "冻", "衝": "冲", "決": "决", "況": "况", "淨": "净", "淒": "凄", "準": "准", "湊": "凑", "減": "减", "幾": "几", "鳳": "凤", "憑": "凭", "凱": "凯", "擊": "击", "鑿": "凿", "劃": "划", "劉": "刘", "則": "则", "剛": "刚", "創": "创", "刪": "删", "別": "别", "剎": "刹", "劊": "刽", "劑": "剂", "勸": "劝", "辦": "办", "務": "务", "動": "动", "勵": "励", "勁": "劲", "勞": "劳", "勢": "势", "勛": "勋", "匭": "匦", "區": "区", "醫": "医", "華": "华", "協": "协", "單": "单", "賣": "卖", "盧": "卢", "衛": "卫", "卻": "却", "廠": "厂", "廳": "厅", "厲": "厉", "壓": "压", "厭": "厌", "厙": "厍", "縣": "县", "隻": "只", "雙": "双", "發": "发", "臺": "台", "葉": "叶", "號": "号", "嘆": "叹", "嗎": "吗", "噸": "吨", "聽": "听", "啟": "启", "吳": "吴", "吶": "呐", "嚇": "吓", "呂": "吕", "嘍": "喽", "囑": "嘱", "場": "场", "塊": "块", "壇": "坛", "壘": "垒", "墾": "垦", "壯": "壮", "聲": "声", "壺": "壶", "處": "处", "復": "复", "頭": "头", "奮": "奋", "獎": "奖", "婦": "妇", "媽": "妈", "嫵": "妩", "嬰": "婴", "孫": "孙", "學": "学", "寧": "宁", "寶": "宝", "實": "实", "寵": "宠", "審": "审", "寬": "宽", "尋": "寻", "對": "对", "導": "导", "壽": "寿", "將": "将", "爾": "尔", "塵": "尘", "層": "层", "屬": "属", "嶼": "屿", "歲": "岁", "豈": "岂", "嶄": "崭", "嶺": "岭", "島": "岛", "峽": "峡", "嶸": "嵘", "師": "师", "帶": "带", "幫": "帮", "幹": "干", "莊": "庄", "廣": "广", "廬": "庐", "廢": "废", "張": "张", "彈": "弹", "強": "强", "歸": "归", "當": "当", "錄": "录", "彫": "雕", "徹": "彻", "誌": "志", "懷": "怀", "態": "态", "恆": "恒", "憶": "忆", "懼": "惧", "憂": "忧", "懸": "悬", "惡": "恶", "惱": "恼", "愴": "怆", "懲": "惩", "慣": "惯", "懟": "怼", "應": "应", "懶": "懒", "戰": "战", "戲": "戏", "戶": "户", "紮": "扎", "拋": "抛", "掃": "扫", "揚": "扬", "換": "换", "揮": "挥", "損": "损", "搖": "摇", "搶": "抢", "擁": "拥", "擇": "择", "擠": "挤", "擺": "摆", "擴": "扩", "攏": "拢", "攔": "拦", "攙": "搀", "攣": "挛", "攪": "搅", "攬": "揽", "敵": "敌", "敘": "叙", "數": "数", "斂": "敛", "斃": "毙", "斷": "断", "無": "无", "舊": "旧", "時": "时", "晉": "晋", "曉": "晓", "曠": "旷", "條": "条", "棟": "栋", "楊": "杨", "極": "极", "構": "构", "樹": "树", "權": "权", "樣": "样", "欄": "栏", "橫": "横", "檔": "档", "檢": "检", "檜": "桧", "檻": "槛", "櫃": "柜", "欖": "榄", "歡": "欢", "歐": "欧", "歷": "历", "殘": "残", "殺": "杀", "殼": "壳", "毀": "毁", "毆": "殴", "畢": "毕", "氣": "气", "漢": "汉", "湯": "汤", "沒": "没", "沖": "冲", "洶": "汹", "澤": "泽", "潔": "洁", "灑": "洒", "淺": "浅", "漿": "浆", "濁": "浊", "濃": "浓", "濕": "湿", "濟": "济", "濤": "涛", "瀉": "泻", "瀏": "浏", "灣": "湾", "瀰": "弥", "瀟": "潇", "災": "灾", "烴": "烃", "熱": "热", "煥": "焕", "煩": "烦", "燒": "烧", "燙": "烫", "燦": "灿", "營": "营", "燭": "烛", "爺": "爷", "牆": "墙", "犧": "牺", "狀": "状", "猶": "犹", "獨": "独", "獅": "狮", "獄": "狱", "獻": "献", "現": "现", "瑣": "琐", "環": "环", "畫": "画", "異": "异", "療": "疗", "癌": "癌", "癢": "痒", "皺": "皱", "盜": "盗", "盡": "尽", "監": "监", "盤": "盘", "睜": "睁", "睏": "困", "瞇": "眯", "瞧": "瞧", "瞭": "了", "礙": "碍", "礦": "矿", "礫": "砾", "礎": "础", "禮": "礼", "禱": "祷", "種": "种", "積": "积", "稱": "称", "穩": "稳", "窮": "穷", "窺": "窥", "竄": "窜", "窩": "窝", "竅": "窍", "競": "竞", "筆": "笔", "筍": "笋", "築": "筑", "簡": "简", "簽": "签", "簍": "篓", "糧": "粮", "級": "级", "紀": "纪", "約": "约", "紅": "红", "紆": "纡", "純": "纯", "納": "纳", "紙": "纸", "紛": "纷", "紋": "纹", "紡": "纺", "索": "索", "細": "细", "紳": "绅", "紹": "绍", "終": "终", "給": "给", "統": "统", "絹": "绢", "綁": "绑", "綢": "绸", "維": "维", "緒": "绪", "續": "续", "纓": "缨", "縮": "缩", "縱": "纵", "縷": "缕", "總": "总", "績": "绩", "繁": "繁", "織": "织", "繞": "绕", "繪": "绘", "繩": "绳", "繼": "继", "纜": "缆", "罰": "罚", "罷": "罢", "羅": "罗", "職": "职", "聯": "联", "聳": "耸", "聰": "聪", "肅": "肃", "腸": "肠", "膚": "肤", "膽": "胆", "脅": "胁", "脈": "脉", "腳": "脚", "臉": "脸", "脫": "脱", "脹": "胀", "腎": "肾", "腫": "肿", "臘": "腊", "臚": "胪", "舖": "铺", "艱": "艰", "艙": "舱", "藝": "艺", "藥": "药", "蘇": "苏", "蟲": "虫", "蠶": "蚕", "裡": "里", "補": "补", "裝": "装", "褲": "裤", "複": "复", "覆": "覆", "見": "见", "觀": "观", "覓": "觅", "規": "规", "視": "视", "覺": "觉", "覽": "览", "觸": "触", "訂": "订", "訃": "讣", "計": "计", "訊": "讯", "討": "讨", "訓": "训", "訪": "访", "設": "设", "許": "许", "訴": "诉", "診": "诊", "詞": "词", "譯": "译", "試": "试", "詩": "诗", "誠": "诚", "話": "话", "該": "该", "詳": "详", "認": "认", "說": "说", "請": "请", "諸": "诸", "讀": "读", "課": "课", "誰": "谁", "調": "调", "談": "谈", "謀": "谋", "謂": "谓", "講": "讲", "謝": "谢", "證": "证", "識": "识", "議": "议", "護": "护", "變": "变", "讓": "让", "豐": "丰", "貝": "贝", "責": "责", "貨": "货", "費": "费", "資": "资", "賓": "宾", "賢": "贤", "賬": "账", "質": "质", "賴": "赖", "賺": "赚", "賽": "赛", "贊": "赞", "贈": "赠", "贏": "赢", "趙": "赵", "趨": "趋", "車": "车", "軌": "轨", "軟": "软", "轉": "转", "輪": "轮", "轟": "轰", "辭": "辞", "辯": "辩", "連": "连", "進": "进", "遠": "远", "違": "违", "遲": "迟", "遷": "迁", "選": "选", "遺": "遗", "邁": "迈", "還": "还", "邊": "边", "邏": "逻", "鄰": "邻", "鄭": "郑", "釋": "释", "裏": "里", "針": "针", "釘": "钉", "釣": "钓", "鈣": "钙", "鈉": "钠", "鋼": "钢", "鍾": "钟", "鍵": "键", "鎖": "锁", "鎮": "镇", "鏡": "镜", "鏈": "链", "錯": "错", "鍛": "锻", "鍍": "镀", "鑑": "鉴", "長": "长", "門": "门", "閉": "闭", "問": "问", "開": "开", "間": "间", "閒": "闲", "闖": "闯", "隊": "队", "陽": "阳", "陰": "阴", "陣": "阵", "階": "阶", "際": "际", "陸": "陆", "陳": "陈", "險": "险", "隨": "随", "隱": "隐", "雖": "虽", "雜": "杂", "難": "难", "電": "电", "霧": "雾", "靈": "灵", "靜": "静", "頁": "页", "頂": "顶", "項": "项", "順": "顺", "須": "须", "預": "预", "頑": "顽", "領": "领", "頻": "频", "顆": "颗", "題": "题", "額": "额", "顏": "颜", "顧": "顾", "風": "风", "飛": "飞", "餘": "余", "館": "馆", "馬": "马", "驅": "驱", "驗": "验", "驚": "惊", "體": "体", "髮": "发", "鬥": "斗", "魚": "鱼", "鮮": "鲜", "鯽": "鲫", "鳥": "鸟", "鴨": "鸭", "鴻": "鸿", "鵝": "鹅", "鶴": "鹤", "麥": "麦", "黃": "黄", "點": "点", "齊": "齐", "齡": "龄", "龍": "龙", "龜": "龟"};
  var __S2T = {"万": "萬", "与": "與", "丑": "醜", "专": "專", "业": "業", "丛": "叢", "东": "東", "丝": "絲", "丢": "丟", "两": "兩", "严": "嚴", "丧": "喪", "个": "個", "临": "臨", "为": "為", "丽": "麗", "举": "舉", "么": "麼", "义": "義", "乌": "烏", "乐": "樂", "乔": "喬", "习": "習", "乡": "鄉", "书": "書", "买": "買", "乱": "亂", "争": "爭", "于": "於", "亏": "虧", "云": "雲", "亚": "亞", "产": "產", "亩": "畝", "亲": "親", "亵": "褻", "亿": "億", "仅": "僅", "从": "從", "仑": "侖", "仓": "倉", "仪": "儀", "们": "們", "价": "價", "众": "眾", "优": "優", "会": "會", "佣": "傭", "伪": "偽", "传": "傳", "伤": "傷", "倾": "傾", "雇": "僱", "俭": "儉", "儿": "兒", "兑": "兌", "党": "黨", "兰": "蘭", "关": "關", "兴": "興", "养": "養", "兽": "獸", "内": "內", "册": "冊", "写": "寫", "军": "軍", "农": "農", "冻": "凍", "冲": "衝", "决": "決", "况": "況", "净": "淨", "凄": "淒", "准": "準", "凑": "湊", "减": "減", "几": "幾", "凤": "鳳", "凭": "憑", "凯": "凱", "击": "擊", "凿": "鑿", "划": "劃", "刘": "劉", "则": "則", "刚": "剛", "创": "創", "删": "刪", "别": "別", "刹": "剎", "刽": "劊", "剂": "劑", "劝": "勸", "办": "辦", "务": "務", "动": "動", "励": "勵", "劲": "勁", "劳": "勞", "势": "勢", "勋": "勛", "匦": "匭", "区": "區", "医": "醫", "华": "華", "协": "協", "单": "單", "卖": "賣", "卢": "盧", "卫": "衛", "却": "卻", "厂": "廠", "厅": "廳", "厉": "厲", "压": "壓", "厌": "厭", "厍": "厙", "县": "縣", "只": "隻", "双": "雙", "发": "發", "台": "臺", "叶": "葉", "号": "號", "叹": "嘆", "吗": "嗎", "吨": "噸", "听": "聽", "启": "啟", "吴": "吳", "呐": "吶", "吓": "嚇", "吕": "呂", "喽": "嘍", "嘱": "囑", "场": "場", "块": "塊", "坛": "壇", "垒": "壘", "垦": "墾", "壮": "壯", "声": "聲", "壶": "壺", "处": "處", "复": "復", "头": "頭", "奋": "奮", "奖": "獎", "妇": "婦", "妈": "媽", "妩": "嫵", "婴": "嬰", "孙": "孫", "学": "學", "宁": "寧", "宝": "寶", "实": "實", "宠": "寵", "审": "審", "宽": "寬", "寻": "尋", "对": "對", "导": "導", "寿": "壽", "将": "將", "尔": "爾", "尘": "塵", "层": "層", "属": "屬", "屿": "嶼", "岁": "歲", "岂": "豈", "崭": "嶄", "岭": "嶺", "岛": "島", "峡": "峽", "嵘": "嶸", "师": "師", "带": "帶", "帮": "幫", "干": "幹", "庄": "莊", "广": "廣", "庐": "廬", "废": "廢", "张": "張", "弹": "彈", "强": "強", "归": "歸", "当": "當", "录": "錄", "雕": "彫", "彻": "徹", "志": "誌", "怀": "懷", "态": "態", "恒": "恆", "忆": "憶", "惧": "懼", "忧": "憂", "悬": "懸", "恶": "惡", "恼": "惱", "怆": "愴", "惩": "懲", "惯": "慣", "怼": "懟", "应": "應", "懒": "懶", "战": "戰", "戏": "戲", "户": "戶", "扎": "紮", "抛": "拋", "扫": "掃", "扬": "揚", "换": "換", "挥": "揮", "损": "損", "摇": "搖", "抢": "搶", "拥": "擁", "择": "擇", "挤": "擠", "摆": "擺", "扩": "擴", "拢": "攏", "拦": "攔", "搀": "攙", "挛": "攣", "搅": "攪", "揽": "攬", "敌": "敵", "叙": "敘", "数": "數", "敛": "斂", "毙": "斃", "断": "斷", "无": "無", "旧": "舊", "时": "時", "晋": "晉", "晓": "曉", "旷": "曠", "条": "條", "栋": "棟", "杨": "楊", "极": "極", "构": "構", "树": "樹", "权": "權", "样": "樣", "栏": "欄", "横": "橫", "档": "檔", "检": "檢", "桧": "檜", "槛": "檻", "柜": "櫃", "榄": "欖", "欢": "歡", "欧": "歐", "历": "歷", "残": "殘", "杀": "殺", "壳": "殼", "毁": "毀", "殴": "毆", "毕": "畢", "气": "氣", "汉": "漢", "汤": "湯", "没": "沒", "汹": "洶", "泽": "澤", "洁": "潔", "洒": "灑", "浅": "淺", "浆": "漿", "浊": "濁", "浓": "濃", "湿": "濕", "济": "濟", "涛": "濤", "泻": "瀉", "浏": "瀏", "湾": "灣", "弥": "瀰", "潇": "瀟", "灾": "災", "烃": "烴", "热": "熱", "焕": "煥", "烦": "煩", "烧": "燒", "烫": "燙", "灿": "燦", "营": "營", "烛": "燭", "爷": "爺", "墙": "牆", "牺": "犧", "状": "狀", "犹": "猶", "独": "獨", "狮": "獅", "狱": "獄", "献": "獻", "现": "現", "琐": "瑣", "环": "環", "画": "畫", "异": "異", "疗": "療", "癌": "癌", "痒": "癢", "皱": "皺", "盗": "盜", "尽": "盡", "监": "監", "盘": "盤", "睁": "睜", "困": "睏", "眯": "瞇", "瞧": "瞧", "了": "瞭", "碍": "礙", "矿": "礦", "砾": "礫", "础": "礎", "礼": "禮", "祷": "禱", "种": "種", "积": "積", "称": "稱", "稳": "穩", "穷": "窮", "窥": "窺", "窜": "竄", "窝": "窩", "窍": "竅", "竞": "競", "笔": "筆", "笋": "筍", "筑": "築", "简": "簡", "签": "簽", "篓": "簍", "粮": "糧", "级": "級", "纪": "紀", "约": "約", "红": "紅", "纡": "紆", "纯": "純", "纳": "納", "纸": "紙", "纷": "紛", "纹": "紋", "纺": "紡", "索": "索", "细": "細", "绅": "紳", "绍": "紹", "终": "終", "给": "給", "统": "統", "绢": "絹", "绑": "綁", "绸": "綢", "维": "維", "绪": "緒", "续": "續", "缨": "纓", "缩": "縮", "纵": "縱", "缕": "縷", "总": "總", "绩": "績", "繁": "繁", "织": "織", "绕": "繞", "绘": "繪", "绳": "繩", "继": "繼", "缆": "纜", "罚": "罰", "罢": "罷", "罗": "羅", "职": "職", "联": "聯", "耸": "聳", "聪": "聰", "肃": "肅", "肠": "腸", "肤": "膚", "胆": "膽", "胁": "脅", "脉": "脈", "脚": "腳", "脸": "臉", "脱": "脫", "胀": "脹", "肾": "腎", "肿": "腫", "腊": "臘", "胪": "臚", "铺": "舖", "艰": "艱", "舱": "艙", "艺": "藝", "药": "藥", "苏": "蘇", "虫": "蟲", "蚕": "蠶", "里": "裡", "补": "補", "装": "裝", "裤": "褲", "覆": "覆", "见": "見", "观": "觀", "觅": "覓", "规": "規", "视": "視", "觉": "覺", "览": "覽", "触": "觸", "订": "訂", "讣": "訃", "计": "計", "讯": "訊", "讨": "討", "训": "訓", "访": "訪", "设": "設", "许": "許", "诉": "訴", "诊": "診", "词": "詞", "译": "譯", "试": "試", "诗": "詩", "诚": "誠", "话": "話", "该": "該", "详": "詳", "认": "認", "说": "說", "请": "請", "诸": "諸", "读": "讀", "课": "課", "谁": "誰", "调": "調", "谈": "談", "谋": "謀", "谓": "謂", "讲": "講", "谢": "謝", "证": "證", "识": "識", "议": "議", "护": "護", "变": "變", "让": "讓", "丰": "豐", "贝": "貝", "责": "責", "货": "貨", "费": "費", "资": "資", "宾": "賓", "贤": "賢", "账": "賬", "质": "質", "赖": "賴", "赚": "賺", "赛": "賽", "赞": "贊", "赠": "贈", "赢": "贏", "赵": "趙", "趋": "趨", "车": "車", "轨": "軌", "软": "軟", "转": "轉", "轮": "輪", "轰": "轟", "辞": "辭", "辩": "辯", "连": "連", "进": "進", "远": "遠", "违": "違", "迟": "遲", "迁": "遷", "选": "選", "遗": "遺", "迈": "邁", "还": "還", "边": "邊", "逻": "邏", "邻": "鄰", "郑": "鄭", "释": "釋", "针": "針", "钉": "釘", "钓": "釣", "钙": "鈣", "钠": "鈉", "钢": "鋼", "钟": "鍾", "键": "鍵", "锁": "鎖", "镇": "鎮", "镜": "鏡", "链": "鏈", "错": "錯", "锻": "鍛", "镀": "鍍", "鉴": "鑑", "长": "長", "门": "門", "闭": "閉", "问": "問", "开": "開", "间": "間", "闲": "閒", "闯": "闖", "队": "隊", "阳": "陽", "阴": "陰", "阵": "陣", "阶": "階", "际": "際", "陆": "陸", "陈": "陳", "险": "險", "随": "隨", "隐": "隱", "虽": "雖", "杂": "雜", "难": "難", "电": "電", "雾": "霧", "灵": "靈", "静": "靜", "页": "頁", "顶": "頂", "项": "項", "顺": "順", "须": "須", "预": "預", "顽": "頑", "领": "領", "频": "頻", "颗": "顆", "题": "題", "额": "額", "颜": "顏", "顾": "顧", "风": "風", "飞": "飛", "余": "餘", "馆": "館", "马": "馬", "驱": "驅", "验": "驗", "惊": "驚", "体": "體", "斗": "鬥", "鱼": "魚", "鲜": "鮮", "鲫": "鯽", "鸟": "鳥", "鸭": "鴨", "鸿": "鴻", "鹅": "鵝", "鹤": "鶴", "麦": "麥", "黄": "黃", "点": "點", "齐": "齊", "龄": "齡", "龙": "龍", "龟": "龜"};
  function __convert(text, table) {
    var s = String(text == null ? "" : text);
    var out = "";
    for (var i = 0; i < s.length; i++) {
      var ch = s[i];
      var mapped = table[ch];
      out += (mapped !== undefined) ? mapped : ch;
    }
    return out;
  }
  globalThis.__pendings = {};

  // ---- Rhino（legado 安卓）Java 互操作垫片：V8 无 Java，
  // 让 jsLib 顶部的 JavaImporter/CompatibilityUtils 能安全加载；
  // 真正访问 Packages.xxx 的分支会抛错并被书源自身 try/catch 捕获后回退。----
  function JavaImporterShim() { this.importClass = function () {}; this.importPackage = function () {}; }
  globalThis.JavaImporter = JavaImporterShim;
  globalThis.importClass = function () {};
  globalThis.importPackage = function () {};
  // 任意 Packages.xxx 取值返回 null：hasJavaClass 判定为 false、new Packages.x() 抛错（被捕获）
  globalThis.Packages = new Proxy({}, { get: function () { return null; } });

  function __hostOf(url) {
    if (!url) return "";
    var s = String(url).trim();
    try {
      if (/^https?:\/\//i.test(s)) {
        return new URL(s).host.replace(/:\d+$/, "");
      }
      if (s.indexOf("/") < 0 && s.indexOf(".") >= 0) {
        return s.replace(/:\d+$/, "").replace(/^\/+/, "");
      }
    } catch (e) {}
    return s.replace(/^https?:\/\//i, "").replace(/^\/+/, "").split("/")[0].replace(/:\d+$/, "");
  }

  function __matchCookieHost(host) {
    if (!host) return "";
    if (__state.cookies[host]) return host;
    var keys = Object.keys(__state.cookies);
    for (var i = 0; i < keys.length; i++) {
      var k = keys[i];
      if (host === k || host.endsWith("." + k) || k.endsWith("." + host)) return k;
    }
    return "";
  }

  function __parseCookiePairs(str) {
    var out = {};
    String(str || "").split(/;|\n/).forEach(function (part) {
      var p = part.trim();
      if (!p) return;
      var idx = p.indexOf("=");
      if (idx <= 0) return;
      var name = p.substring(0, idx).trim();
      if (/^(path|domain|expires|max-age|secure|httponly|samesite)$/i.test(name)) return;
      out[name] = p.substring(idx + 1).trim();
    });
    return out;
  }

  function __ingestSetCookie(url, setCookieHeader) {
    if (!setCookieHeader) return;
    var host = __hostOf(url);
    var jar = __parseCookiePairs(__state.cookies[host] || "");
    var fresh = __parseCookiePairs(setCookieHeader);
    Object.keys(fresh).forEach(function (k) { jar[k] = fresh[k]; });
    __state.cookies[host] = Object.keys(jar).map(function (k) { return k + "=" + jar[k]; }).join("; ");
  }

  function __resolve(url, base) {
    var s = String(url == null ? "" : url).trim();
    if (!s) return s;
    if (/^https?:\/\//i.test(s) || s.indexOf("data:") === 0 || s.indexOf("javascript:") === 0) return s;
    if (s.indexOf("//") === 0) return "https:" + s;
    var b = base || __state.meta.httpUrl || "";
    try {
      if (b) return new URL(s, b).toString();
    } catch (e) {}
    return s;
  }

  function __b64Unicode(str) {
    var bytes = new TextEncoder().encode(String(str));
    var bin = "";
    for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    return btoa(bin);
  }
  function __unb64Unicode(str) {
    var bin = atob(String(str));
    var bytes = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return new TextDecoder("utf-8").decode(bytes);
  }
  function __hexToBytes(hex) {
    var h = String(hex).replace(/[^0-9a-fA-F]/g, "");
    var out = new Uint8Array(Math.floor(h.length / 2));
    for (var i = 0; i < out.length; i++) out[i] = parseInt(h.substr(i * 2, 2), 16);
    return out;
  }
  function __bytesToHex(bytes) {
    var s = "";
    for (var i = 0; i < bytes.length; i++) s += ("0" + bytes[i].toString(16)).slice(-2);
    return s;
  }

  // ---- AES（基于注入的 aes-js；ECB/CBC + PKCS7，同步）----
  function __b64ToBytes(b64) {
    var bin = atob(String(b64));
    var out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  // 用标准 TextEncoder/Decoder（aes-js 自带 utf8 工具对 4 字节字符处理有缺陷）
  function __utf8ToBytes(s) {
    return new Uint8Array(new TextEncoder().encode(String(s)));
  }
  function __bytesToUtf8(b) {
    return new TextDecoder("utf-8").decode(b);
  }
  function __aesKeyBytes(key) {
    var kb = __utf8ToBytes(String(key));
    var sizes = [16, 24, 32];
    for (var i = 0; i < sizes.length; i++) {
      if (kb.length <= sizes[i]) {
        var out = new Uint8Array(sizes[i]);
        out.set(kb);
        return out;
      }
    }
    return Uint8Array.from(kb.slice(0, 32));
  }
  function __aesIv(iv) {
    var b = __utf8ToBytes(String(iv || ""));
    var out = new Uint8Array(16);
    out.set(b.slice(0, 16));
    return out;
  }
  function __unpadPkcs7(bytes) {
    try {
      var p = bytes[bytes.length - 1];
      if (p > 0 && p <= 16) {
        for (var i = bytes.length - p; i < bytes.length; i++) {
          if (bytes[i] !== p) return bytes;
        }
        return bytes.slice(0, bytes.length - p);
      }
    } catch (e) {}
    return bytes;
  }
  function __aesDecryptToString(data, key, transformation, iv) {
    var cipher = __b64ToBytes(data);
    var kb = __aesKeyBytes(key);
    var mode = String(transformation || "AES/ECB/PKCS7Padding").toUpperCase();
    var dec;
    if (mode.indexOf("CBC") >= 0) {
      dec = new aesjs.ModeOfOperation.cbc(kb, __aesIv(iv)).decrypt(cipher);
    } else {
      dec = new aesjs.ModeOfOperation.ecb(kb).decrypt(cipher);
    }
    dec = __unpadPkcs7(dec);
    return __bytesToUtf8(dec);
  }
  function __aesEncryptToString(text, key, transformation, iv) {
    var kb = __aesKeyBytes(key);
    var data = __utf8ToBytes(String(text));
    var pad = 16 - (data.length % 16);
    var padded = new Uint8Array(data.length + pad);
    padded.set(data);
    for (var i = data.length; i < padded.length; i++) padded[i] = pad;
    var mode = String(transformation || "AES/ECB/PKCS7Padding").toUpperCase();
    var enc;
    if (mode.indexOf("CBC") >= 0) {
      enc = new aesjs.ModeOfOperation.cbc(kb, __aesIv(iv)).encrypt(padded);
    } else {
      enc = new aesjs.ModeOfOperation.ecb(kb).encrypt(padded);
    }
    var bin = "";
    for (var j = 0; j < enc.length; j++) bin += String.fromCharCode(enc[j]);
    return btoa(bin);
  }

  // ============================ cookie ============================
  var cookie = {
    getCookie: function (url) {
      var host = __matchCookieHost(__hostOf(url));
      return host ? (__state.cookies[host] || "") : "";
    },
    setCookie: function (url, cookieStr) {
      var host = __hostOf(url);
      var jar = __parseCookiePairs(__state.cookies[host] || "");
      var add = __parseCookiePairs(cookieStr);
      Object.keys(add).forEach(function (k) { jar[k] = add[k]; });
      __state.cookies[host] = Object.keys(jar).map(function (k) { return k + "=" + jar[k]; }).join("; ");
      return true;
    },
    removeCookie: function (url) {
      var host = __hostOf(url);
      var k = __matchCookieHost(host);
      if (k) delete __state.cookies[k];
      return true;
    },
    getKey: function (url, name) {
      var c = this.getCookie(url);
      var m = String(c).match(new RegExp("(?:^|;\\s*)" + name + "=([^;]*)"));
      return m ? m[1] : "";
    },
    replaceCookie: function (url, c) { return this.setCookie(url, c); }
  };
  globalThis.cookie = cookie;

  // ============================ cache ============================
  var cache = {
    get: function (key) {
      var v = __state.kv[key];
      if (v === undefined || v === null) return null;
      try { return JSON.parse(v); } catch (e) { return v; }
    },
    put: function (key, value) {
      __state.kv[key] = (typeof value === "string") ? value : JSON.stringify(value);
      return true;
    },
    remove: function (key) { delete __state.kv[key]; }
  };
  globalThis.cache = cache;

  // ============================ source ============================
  var source = {
    getBookSourceUrl: function () { return __state.meta.url; },
    getBookSourceName: function () { return __state.meta.name; },
    getKey: function () { return __state.meta.url; },
    getOrigin: function () {
      try { var u = new URL(__state.meta.httpUrl || __state.meta.url); return u.origin; } catch (e) { return ""; }
    },
    getBookSourceGroup: function () { return __state.meta.group || ""; },
    getBookSourceComment: function () { return __state.meta.comment || ""; },
    getBookSourceType: function () { return __state.meta.type || 0; },
    getConcurrentRate: function () { return __state.meta.concurrentRate || 0; },
    getEnabledExplore: function () { return !!__state.meta.enabledExplore; },
    getHeader: function () { return __state.meta.header || ""; },
    getLoginUrl: function () { return __state.meta.loginUrl || ""; },
    getJsLib: function () { return __state.meta.jsLib || ""; },
    getBookUrlPattern: function () { return __state.meta.bookUrlPattern || ""; },
    // 变量注释 / 更新时间（部分订阅源以属性方式访问）
    get variableComment() { return __state.variableComment || ""; },
    get lastUpdateTime() { return __state.lastUpdateTime || 0; },
    getVariable: function (key) {
      if (key === undefined || key === null || key === "") return __state.variable;
      try {
        var o = JSON.parse(__state.variable || "{}");
        var v = o[key];
        return v === undefined ? "" : (typeof v === "string" ? v : JSON.stringify(v));
      } catch (e) { return ""; }
    },
    setVariable: function (v) {
      __state.variable = (typeof v === "string") ? v : JSON.stringify(v);
      return __state.variable;
    },
    getLoginInfo: function () { return __state.loginInfo || ""; },
    getLoginInfoMap: function () {
      try { return JSON.parse(__state.loginInfo || "{}"); } catch (e) { return {}; }
    },
    setLoginInfo: function (v) {
      __state.loginInfo = (typeof v === "string") ? v : JSON.stringify(v);
      return true;
    },
    putLoginInfo: function (v) {
      __state.loginInfo = (typeof v === "string") ? v : JSON.stringify(v);
      return true;
    },
    getCookie: function (url) { return cookie.getCookie(url); },
    setCookie: function (url, c) { return cookie.setCookie(url, c); },
    removeCookie: function (url) { return cookie.removeCookie(url); },
    // 移除登录头（清空登录信息与由登录派生的状态）
    removeLoginHeader: function () {
      __state.loginInfo = "";
      return true;
    },
    getCookieStore: function () { return cookie; },
    // loginUi：legado 安卓版中为方法，书源常用 typeof source.loginUi == 'function' 判断平台
    loginUi: function () { return ""; },
    // 登录头管理
    getLoginHeader: function () { return __state.loginHeader || ""; },
    putLoginHeader: function (header) { __state.loginHeader = header; return true; },
    removeLoginHeader: function () { __state.loginHeader = ""; return true; },
    // 变量管理（putVariable 是 setVariable 的别名）
    putVariable: function (v) { this.setVariable(v); return true; },
    removeLoginInfo: function () { __state.loginInfo = ""; return true; },
    // 源专属键值（v_{sourceKey}_{key} 命名空间，区别于全局 cache）
    put: function (key, value) {
      __state.kv["v_" + __state.meta.url + "_" + key] = (typeof value === "string") ? value : JSON.stringify(value);
      return value;
    },
    get: function (key) {
      var v = __state.kv["v_" + __state.meta.url + "_" + key];
      if (v === undefined || v === null) return "";
      try { return JSON.parse(v); } catch (e) { return v; }
    },
    // 刷新
    refreshJSLib: function () { return true; },
    putConcurrent: function (value) { __state.meta.concurrentRate = value; return true; },
    // 登录
    login: function () { return true; },
    getLoginJs: function () { return __state.meta.loginUrl || ""; },
    getHeaderMap: function (hasLoginHeader) {
      try {
        var h = __state.meta.header ? JSON.parse(__state.meta.header) : {};
        if (hasLoginHeader && __state.loginHeader) {
          try { Object.assign(h, JSON.parse(__state.loginHeader)); } catch (e) {}
        }
        return h;
      } catch (e) { return {}; }
    }
  };
  globalThis.source = source;
  // Legado 标准全局变量：sourceUrl / sourceName（loadSource/eval 时会覆盖为实际值）
  globalThis.sourceUrl = "";
  globalThis.sourceName = "";
  // Legado 标准全局函数 getKey()：返回书源地址
  globalThis.getKey = function () { return __state.meta.url; };
  // getBookSourceUrl / getBookSourceName 全局别名
  globalThis.getBookSourceUrl = function () { return __state.meta.url; };
  globalThis.getBookSourceName = function () { return __state.meta.name; };

  function putLoginInfo(info) {
    __state.loginInfo = (typeof info === "string") ? info : JSON.stringify(info);
    return true;
  }
  globalThis.putLoginInfo = putLoginInfo;
  globalThis.setLoginInfo = putLoginInfo;
  globalThis.getLoginInfo = function () { return __state.loginInfo || ""; };
  globalThis.removeLoginInfo = function () { __state.loginInfo = ""; return true; };
  // 全局变量函数
  globalThis.getVariable = function (key) { return source.getVariable(key); };
  globalThis.setVariable = function (v) { return source.setVariable(v); };
  globalThis.putVariable = function (v) { return source.putVariable(v); };
  // 全局登录头函数
  globalThis.getLoginHeader = function () { return source.getLoginHeader(); };
  globalThis.putLoginHeader = function (h) { return source.putLoginHeader(h); };
  globalThis.removeLoginHeader = function () { return source.removeLoginHeader(); };

  // 默认的 getArgument/setArgument（书源 jsLib 通常会自带；缺失时兜底）
  if (typeof globalThis.getArgument !== "function") {
    globalThis.getArgument = function (key) {
      var o = {};
      try { o = JSON.parse(__state.variable || "{}"); } catch (e) { o = {}; }
      return o[key];
    };
  }
  if (typeof globalThis.setArgument !== "function") {
    globalThis.setArgument = function (key, value) {
      var o = {};
      try { o = JSON.parse(__state.variable || "{}"); } catch (e) { o = {}; }
      o[key] = value;
      __state.variable = JSON.stringify(o);
      return __state.variable;
    };
  }
  // getArguments（复数）：从 JSON 字符串或对象中按键取值，jsLib 通常自带，此处兜底
  if (typeof globalThis.getArguments !== "function") {
    globalThis.getArguments = function (openArgument, key) {
      try {
        var o = (typeof openArgument === "string") ? JSON.parse(openArgument || "{}") : (openArgument || {});
        var v = o[key];
        if (v === undefined || v === null) return "";
        return (typeof v === "string") ? v : JSON.stringify(v);
      } catch (e) { return ""; }
    };
  }
  if (typeof globalThis.setArguments !== "function") {
    globalThis.setArguments = function (openArgument, key, value) {
      try {
        var o = (typeof openArgument === "string") ? JSON.parse(openArgument || "{}") : (openArgument || {});
        o[key] = value;
        return JSON.stringify(o);
      } catch (e) { return openArgument; }
    };
  }
  // 全局 host 兜底（jsLib 通常会定义 var host = [...]；若未定义则为空数组）
  if (typeof globalThis.host === "undefined") {
    globalThis.host = [];
  }

  // ============================ 网络（同步 XHR，原生拦截） ============================
  function __parseUrlOptions(arg, extra) {
    var url = arg, opt = { method: "GET", headers: {}, body: null };
    if (typeof arg === "object" && arg !== null) {
      url = arg.url;
      if (arg.method) opt.method = String(arg.method).toUpperCase();
      if (arg.headers) Object.assign(opt.headers, arg.headers);
      if (arg.body !== undefined && arg.body !== null) opt.body = arg.body;
      if (arg.data !== undefined && arg.data !== null) opt.body = arg.data;
      if (arg.webView) opt.webView = true;
    } else if (typeof arg === "string") {
      var comma = arg.indexOf(",{");
      if (comma >= 0) {
        url = arg.substring(0, comma);
        try {
          var o = JSON.parse(arg.substring(comma + 1));
          if (o.method) opt.method = String(o.method).toUpperCase();
          if (o.headers) Object.assign(opt.headers, o.headers);
          if (o.body !== undefined && o.body !== null) opt.body = o.body;
          if (o.charset) opt.charset = o.charset;
          if (o.webView) opt.webView = true;
        } catch (e) {}
      }
      var m = /,(POST|GET|PUT|DELETE)(?::([\s\S]*))?$/i.exec(url);
      if (m) { url = url.substring(0, m.index); opt.method = m[1].toUpperCase(); if (m[2]) opt.body = m[2]; }
    }
    if (extra && typeof extra === "object") {
      if (extra.method) opt.method = String(extra.method).toUpperCase();
      if (extra.headers) Object.assign(opt.headers, extra.headers);
      if (extra.body !== undefined && extra.body !== null) opt.body = extra.body;
    }
    return { url: url, opt: opt };
  }

  function __doXhr(url, opt, respType) {
    url = __resolve(url);
    var method = opt.method || "GET";
    var headers = {};
    Object.keys(opt.headers || {}).forEach(function (k) {
      if (opt.headers[k] !== undefined && opt.headers[k] !== null) headers[k] = String(opt.headers[k]);
    });
    var bodyStr = null;
    if (opt.body !== undefined && opt.body !== null) {
      bodyStr = (typeof opt.body === "string") ? opt.body : JSON.stringify(opt.body);
    }
    if (bodyStr !== null && method !== "GET" && method !== "HEAD") {
      headers["X-Legado-Body"] = __b64Unicode(bodyStr);
      if (!__hasHeader(headers, "Content-Type")) headers["Content-Type"] = "application/x-www-form-urlencoded";
    }
    if (!__hasHeader(headers, "Cookie") && !__hasHeader(headers, "cookie")) {
      var c = cookie.getCookie(url);
      if (c) headers["Cookie"] = c;
    }
    var x = new XMLHttpRequest();
    x.open(method, url, false);
    Object.keys(headers).forEach(function (k) {
      try { x.setRequestHeader(k, headers[k]); } catch (e) {}
    });
    if (respType === "arraybuffer") x.responseType = "arraybuffer";
    x.send(bodyStr);
    var sc = null;
    try { sc = x.getResponseHeader("X-Set-Cookie"); } catch (e) {}
    if (sc) __ingestSetCookie(url, sc);
    if (__state.hosts.indexOf(__hostOf(url)) < 0) __state.hosts.push(__hostOf(url));
    if (x.status === 0) throw new Error("网络请求失败: " + url);
    if (x.status >= 400) throw new Error("HTTP " + x.status + " " + url);
    if (respType === "arraybuffer") return x.response;
    return x.responseText;
  }
  function __hasHeader(headers, name) {
    var lk = name.toLowerCase();
    return Object.keys(headers).some(function (k) { return k.toLowerCase() === lk; });
  }

  function __connect(url) {
    var conn = {
      __url: url, __method: "GET", __headers: {}, __body: null,
      headers: function (h) { if (h) Object.keys(h).forEach((k) => { this.__headers[k] = h[k]; }); return this; },
      addHeader: function (k, v) { this.__headers[k] = v; return this; },
      header: function (k, v) { this.__headers[k] = v; return this; },
      method: function (m) { this.__method = String(m).toUpperCase(); return this; },
      setBody: function (b) { this.__body = b; return this; },
      body: function (b) { this.__body = b; this.__method = "POST"; return this; },
      get: function () { this.__method = "GET"; return this; },
      post: function (b) { this.__method = "POST"; if (b !== undefined) this.__body = b; return this; },
      followRedirects: function () { return this; },
      timeout: function () { return this; },
      execute: function () {
        var text = __doXhr(this.__url, { method: this.__method, headers: this.__headers, body: this.__body });
        return {
          code: 200,
          url: this.__url,
          body: function () { return { string: function () { return text; }, bytes: function () { return new TextEncoder().encode(text); }, text: function () { return text; } }; },
          headers: {},
          header: function () { return null; },
          raw: text
        };
      }
    };
    return conn;
  }

  // ============================ 浏览器交互登录 ============================
  function __openBrowser(url, title, awaitFlag) {
    var id = "b" + Date.now() + Math.floor(Math.random() * 1000);
    __state.browser.push({ id: id, url: __resolve(url), title: title || "" });
    return new Promise(function (resolve) {
      __pendings[id] = resolve;
      try {
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
          window.flutter_inappwebview.callHandler("legadoBrowser", JSON.stringify({
            id: id, url: __resolve(url), title: title || ""
          }));
        }
      } catch (e) {}
      if (!awaitFlag) {
        setTimeout(function () { if (__pendings[id]) { delete __pendings[id]; resolve(""); } }, 0);
      }
    });
  }
  globalThis.__resolveBrowser = function (id, cookieStr, finalUrl) {
    if (cookieStr) __ingestSetCookie(finalUrl || "", cookieStr);
    if (__pendings[id]) { var r = __pendings[id]; delete __pendings[id]; r(cookieStr || ""); }
  };
  globalThis.__cancelBrowser = function (id) {
    if (__pendings[id]) { var r = __pendings[id]; delete __pendings[id]; r(""); }
  };

  // ============================ MD5（纯 JS 实现）============================
  function __md5(str) {
    function rotl(n, s) { return (n << s) | (n >>> (32 - s)); }
    function toHex(num) {
      var s = "";
      for (var j = 0; j < 4; j++) s += ((num >> (j * 8 + 4)) & 0x0F).toString(16) + ((num >> (j * 8)) & 0x0F).toString(16);
      return s;
    }
    var msg = unescape(encodeURIComponent(str));
    var len = msg.length;
    var wordCount = (((len + 8) >> 6) + 1) * 16;
    var words = new Array(wordCount - 1);
    for (var i = 0; i < len; i++) words[i >> 2] |= msg.charCodeAt(i) << ((i % 4) * 8);
    words[i >> 2] |= 0x80 << ((i % 4) * 8);
    words[wordCount - 2] = len * 8;
    var a = 1732584193, b = -271733879, c = -1732584194, d = 271733878;
    for (var i = 0; i < words.length; i += 16) {
      var oa = a, ob = b, oc = c, od = d;
      a = __md5ff(a, b, c, d, words[i + 0], 7, -680876936);
      d = __md5ff(d, a, b, c, words[i + 1], 12, -389564586);
      c = __md5ff(c, d, a, b, words[i + 2], 17, 606105819);
      b = __md5ff(b, c, d, a, words[i + 3], 22, -1044525330);
      a = __md5ff(a, b, c, d, words[i + 4], 7, -176418897);
      d = __md5ff(d, a, b, c, words[i + 5], 12, 1200080426);
      c = __md5ff(c, d, a, b, words[i + 6], 17, -1473231341);
      b = __md5ff(b, c, d, a, words[i + 7], 22, -45705983);
      a = __md5ff(a, b, c, d, words[i + 8], 7, 1770035416);
      d = __md5ff(d, a, b, c, words[i + 9], 12, -1958414417);
      c = __md5ff(c, d, a, b, words[i + 10], 17, -42063);
      b = __md5ff(b, c, d, a, words[i + 11], 22, -1990404162);
      a = __md5ff(a, b, c, d, words[i + 12], 7, 1804603682);
      d = __md5ff(d, a, b, c, words[i + 13], 12, -40341101);
      c = __md5ff(c, d, a, b, words[i + 14], 17, -1502002290);
      b = __md5ff(b, c, d, a, words[i + 15], 22, 1236535329);
      a = __md5gg(a, b, c, d, words[i + 1], 5, -165796510);
      d = __md5gg(d, a, b, c, words[i + 6], 9, -1069501632);
      c = __md5gg(c, d, a, b, words[i + 11], 14, 643717713);
      b = __md5gg(b, c, d, a, words[i + 0], 20, -373897302);
      a = __md5gg(a, b, c, d, words[i + 5], 5, -701558691);
      d = __md5gg(d, a, b, c, words[i + 10], 9, 38016083);
      c = __md5gg(c, d, a, b, words[i + 15], 14, -660478335);
      b = __md5gg(b, c, d, a, words[i + 4], 20, -405537848);
      a = __md5gg(a, b, c, d, words[i + 9], 5, 568446438);
      d = __md5gg(d, a, b, c, words[i + 14], 9, -1019803690);
      c = __md5gg(c, d, a, b, words[i + 3], 14, -187363961);
      b = __md5gg(b, c, d, a, words[i + 8], 20, 1163531501);
      a = __md5gg(a, b, c, d, words[i + 13], 5, -1444681467);
      d = __md5gg(d, a, b, c, words[i + 2], 9, -51403784);
      c = __md5gg(c, d, a, b, words[i + 7], 14, 1735328473);
      b = __md5gg(b, c, d, a, words[i + 12], 20, -1926607734);
      a = __md5hh(a, b, c, d, words[i + 5], 4, -378558);
      d = __md5hh(d, a, b, c, words[i + 8], 11, -2022574463);
      c = __md5hh(c, d, a, b, words[i + 11], 16, 1839030562);
      b = __md5hh(b, c, d, a, words[i + 14], 23, -35309556);
      a = __md5hh(a, b, c, d, words[i + 1], 4, -1530992060);
      d = __md5hh(d, a, b, c, words[i + 4], 11, 1272893353);
      c = __md5hh(c, d, a, b, words[i + 7], 16, -155497632);
      b = __md5hh(b, c, d, a, words[i + 10], 23, -1094730640);
      a = __md5hh(a, b, c, d, words[i + 13], 4, 681279174);
      d = __md5hh(d, a, b, c, words[i + 0], 11, -358537222);
      c = __md5hh(c, d, a, b, words[i + 3], 16, -722521979);
      b = __md5hh(b, c, d, a, words[i + 6], 23, 76029189);
      a = __md5hh(a, b, c, d, words[i + 9], 4, -640364487);
      d = __md5hh(d, a, b, c, words[i + 12], 11, -421815835);
      c = __md5hh(c, d, a, b, words[i + 15], 16, 530742525);
      b = __md5hh(b, c, d, a, words[i + 2], 23, -995338651);
      a = __md5ii(a, b, c, d, words[i + 0], 6, -198630844);
      d = __md5ii(d, a, b, c, words[i + 7], 10, 1126891415);
      c = __md5ii(c, d, a, b, words[i + 14], 15, -1416354905);
      b = __md5ii(b, c, d, a, words[i + 5], 21, -57434055);
      a = __md5ii(a, b, c, d, words[i + 12], 6, 1700485571);
      d = __md5ii(d, a, b, c, words[i + 3], 10, -1894986606);
      c = __md5ii(c, d, a, b, words[i + 10], 15, -1051523);
      b = __md5ii(b, c, d, a, words[i + 1], 21, -2054922799);
      a = __md5ii(a, b, c, d, words[i + 8], 6, 1873313359);
      d = __md5ii(d, a, b, c, words[i + 15], 10, -30611744);
      c = __md5ii(c, d, a, b, words[i + 6], 15, -1560198380);
      b = __md5ii(b, c, d, a, words[i + 13], 21, 1309151649);
      a = __md5ii(a, b, c, d, words[i + 4], 6, -145523070);
      d = __md5ii(d, a, b, c, words[i + 11], 10, -1120210379);
      c = __md5ii(c, d, a, b, words[i + 2], 15, 718787259);
      b = __md5ii(b, c, d, a, words[i + 9], 21, -343485551);
      a = (a + oa) | 0; b = (b + ob) | 0; c = (c + oc) | 0; d = (d + od) | 0;
    }
    return toHex(a) + toHex(b) + toHex(c) + toHex(d);
  }
  function __md5cmn(q, a, b, x, s, t) { return __md5add(rotl(__md5add(__md5add(a, q), __md5add(x, t)), s), b); }
  function __md5ff(a, b, c, d, x, s, t) { return __md5cmn((b & c) | ((~b) & d), a, b, x, s, t); }
  function __md5gg(a, b, c, d, x, s, t) { return __md5cmn((b & d) | (c & (~d)), a, b, x, s, t); }
  function __md5hh(a, b, c, d, x, s, t) { return __md5cmn(b ^ c ^ d, a, b, x, s, t); }
  function __md5ii(a, b, c, d, x, s, t) { return __md5cmn(c ^ (b | (~d)), a, b, x, s, t); }
  function __md5add(a, b) { var x = (a & 0xFFFF) + (b & 0xFFFF); var y = (a >> 16) + (b >> 16) + (x >> 16); return (y << 16) | (x & 0xFFFF); }

  // ============================ SHA1（纯 JS 实现）============================
  function __sha1(str) {
    function rotl(n, s) { return (n << s) | (n >>> (32 - s)); }
    function toHex(num) {
      var s = "";
      for (var j = 7; j >= 0; j--) s += ((num >> (j * 4)) & 0x0F).toString(16);
      return s;
    }
    var msg = unescape(encodeURIComponent(str));
    var len = msg.length;
    var wordCount = (((len + 8) >> 6) + 1) * 16;
    var words = new Array(wordCount - 1);
    for (var i = 0; i < len; i++) words[i >> 2] |= msg.charCodeAt(i) << ((i % 4) * 8);
    words[i >> 2] |= 0x80 << ((i % 4) * 8);
    words[wordCount - 2] = Math.floor(len * 8 / 0x100000000);
    words[wordCount - 1] = (len * 8) & 0xFFFFFFFF;
    var h0 = 0x67452301, h1 = 0xEFCDAB89, h2 = 0x98BADCFE, h3 = 0x10325476, h4 = 0xC3D2E1F0;
    for (var i = 0; i < words.length; i += 16) {
      var w = new Array(80);
      for (var j = 0; j < 16; j++) w[j] = words[i + j];
      for (var j = 16; j < 80; j++) w[j] = rotl(w[j - 3] ^ w[j - 8] ^ w[j - 14] ^ w[j - 16], 1);
      var a = h0, b = h1, c = h2, d = h3, e = h4;
      for (var j = 0; j < 80; j++) {
        var f, k;
        if (j < 20) { f = (b & c) | ((~b) & d); k = 0x5A827999; }
        else if (j < 40) { f = b ^ c ^ d; k = 0x6ED9EBA1; }
        else if (j < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDC; }
        else { f = b ^ c ^ d; k = 0xCA62C1D6; }
        var temp = (rotl(a, 5) + f + e + k + w[j]) | 0;
        e = d; d = c; c = rotl(b, 30); b = a; a = temp;
      }
      h0 = (h0 + a) | 0; h1 = (h1 + b) | 0; h2 = (h2 + c) | 0; h3 = (h3 + d) | 0; h4 = (h4 + e) | 0;
    }
    return toHex(h0) + toHex(h1) + toHex(h2) + toHex(h3) + toHex(h4);
  }

  // ============================ SHA256（纯 JS 实现）============================
  function __sha256(str) {
    function rotr(n, s) { return (n >>> s) | (n << (32 - s)); }
    function toHex(num) {
      var s = "";
      for (var j = 7; j >= 0; j--) s += ((num >> (j * 4)) & 0x0F).toString(16);
      return s;
    }
    var K = [
      0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
      0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
      0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
      0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
      0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
      0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
      0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
      0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2
    ];
    var msg = unescape(encodeURIComponent(str));
    var len = msg.length;
    var bitLen = len * 8;
    var wordCount = (((len + 8) >> 6) + 1) * 16;
    var words = new Array(wordCount - 1);
    for (var i = 0; i < len; i++) words[i >> 2] |= msg.charCodeAt(i) << ((3 - (i % 4)) * 8);
    words[i >> 2] |= 0x80 << ((3 - (i % 4)) * 8);
    words[wordCount - 2] = Math.floor(bitLen / 0x100000000);
    words[wordCount - 1] = bitLen & 0xFFFFFFFF;
    var h0 = 0x6A09E667, h1 = 0xBB67AE85, h2 = 0x3C6EF372, h3 = 0xA54FF53A;
    var h4 = 0x510E527F, h5 = 0x9B05688C, h6 = 0x1F83D9AB, h7 = 0x5BE0CD19;
    for (var i = 0; i < words.length; i += 16) {
      var w = new Array(64);
      for (var j = 0; j < 16; j++) w[j] = words[i + j];
      for (var j = 16; j < 64; j++) {
        var s0 = rotr(w[j - 15], 7) ^ rotr(w[j - 15], 18) ^ (w[j - 15] >>> 3);
        var s1 = rotr(w[j - 2], 17) ^ rotr(w[j - 2], 19) ^ (w[j - 2] >>> 10);
        w[j] = (w[j - 16] + s0 + w[j - 7] + s1) | 0;
      }
      var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
      for (var j = 0; j < 64; j++) {
        var S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        var ch = (e & f) ^ ((~e) & g);
        var temp1 = (h + S1 + ch + K[j] + w[j]) | 0;
        var S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        var maj = (a & b) ^ (a & c) ^ (b & c);
        var temp2 = (S0 + maj) | 0;
        h = g; g = f; f = e; e = (d + temp1) | 0;
        d = c; c = b; b = a; a = (temp1 + temp2) | 0;
      }
      h0 = (h0 + a) | 0; h1 = (h1 + b) | 0; h2 = (h2 + c) | 0; h3 = (h3 + d) | 0;
      h4 = (h4 + e) | 0; h5 = (h5 + f) | 0; h6 = (h6 + g) | 0; h7 = (h7 + h) | 0;
    }
    return toHex(h0) + toHex(h1) + toHex(h2) + toHex(h3) + toHex(h4) + toHex(h5) + toHex(h6) + toHex(h7);
  }

  // ============================ java ============================
  function __argString(args) {
    return Array.prototype.map.call(args, function (a) {
      if (typeof a === "string") return a;
      try { return JSON.stringify(a); } catch (e) { return String(a); }
    }).join(" ");
  }

  var java = {
    // 日志 / 提示
    log: function () { __state.logs.push(__argString(arguments)); },
    toast: function (msg) { var s = String(msg == null ? "" : msg); __state.toasts.push(s); __state.logs.push(s); },
    longToast: function (msg) { var s = String(msg == null ? "" : msg); __state.toasts.push(s); __state.logs.push(s); },

    // 网络
    ajax: function (url, options) {
      var p = __parseUrlOptions(url, options);
      return __doXhr(p.url, p.opt);
    },
    get: function (url, headers) {
      return __doXhr(url, { method: "GET", headers: headers || {} });
    },
    post: function (url, body, headers) {
      return __doXhr(url, { method: "POST", body: body, headers: headers || {} });
    },
    put: function (url, body, headers) {
      return __doXhr(url, { method: "PUT", body: body, headers: headers || {} });
    },
    delete: function (url, headers) {
      return __doXhr(url, { method: "DELETE", headers: headers || {} });
    },
    head: function (url, headers) {
      return __doXhr(url, { method: "HEAD", headers: headers || {} });
    },
    connect: function (url) { return __connect(url); },
    newResponse: function (url) { return __connect(url); },
    getCookie: function (url) { return cookie.getCookie(url); },

    // 编码
    base64Encode: function (str) { return __b64Unicode(str); },
    base64Decode: function (str) {
      try { return __unb64Unicode(str); } catch (e) {
        try { return atob(str); } catch (e2) { return ""; }
      }
    },
    encodeBase64: function (str) { return __b64Unicode(str); },
    decodeBase64: function (str) { return this.base64Decode(str); },
    hexDecodeToString: function (hex) {
      // 书源对「明文 JSON / HTML」与「十六进制响应」都会调用本函数。
      // 仅当整串为合法、偶数长度、可解出 UTF-8 的十六进制时才解码，否则原样返回。
      var raw = String(hex == null ? "" : hex);
      var h = raw.replace(/\s+/g, "");
      if (h.length === 0 || (h.length % 2) !== 0 || /[^0-9a-fA-F]/.test(h)) return raw;
      try {
        var bytes = new Uint8Array(h.length / 2);
        for (var i = 0; i < bytes.length; i++) bytes[i] = parseInt(h.substr(i * 2, 2), 16);
        return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
      } catch (e) { return raw; }
    },
    hexEncodeToString: function (str) { return __bytesToHex(new TextEncoder().encode(str)); },
    stringToHex: function (str) { return __bytesToHex(new TextEncoder().encode(str)); },
    md5Encode: function (str) { return __md5(String(str == null ? "" : str)); },
    sha1Encode: function (str) { return __sha1(String(str == null ? "" : str)); },
    sha256Encode: function (str) { return __sha256(String(str == null ? "" : str)); },

    // AES 对称加解密（同步；对齐 legado JsExtensions）
    aesBase64DecodeToString: function (data, key, transformation, iv) {
      return __aesDecryptToString(data, key, transformation, iv);
    },
    aesBase64EncodeToString: function (text, key, transformation, iv) {
      return __aesEncryptToString(text, key, transformation, iv);
    },
    aesDecodeToString: function (data, key, transformation, iv) {
      return __aesDecryptToString(data, key, transformation, iv);
    },
    aesEncodeToString: function (text, key, transformation, iv) {
      return __aesEncryptToString(text, key, transformation, iv);
    },

    // 设备 / UA
    deviceID: function () { return __state.deviceId; },
    androidId: function () { return __state.deviceId; },
    getWebViewUA: function () { return __state.ua; },
    getAppVariant: function () { return "android"; },

    // 时间
    timeFormat: function (time, pattern) { return __timeFormat(time, pattern, false); },
    timeFormatUTC: function (time, pattern) { return __timeFormat(time, pattern, true); },

    // 跨阶段键值
    put: function (k, v) { cache.put(k, v); return true; },
    get: function (k) { var v = cache.get(k); return v === null ? "" : v; },
    contains: function (k) { return Object.prototype.hasOwnProperty.call(__state.kv, k); },
    remove: function (k) { cache.remove(k); },

    // 书源相关
    refreshExplore: function () { return true; },
    refreshBookToc: function () { return true; },
    refreshBook: function () { return true; },

    // 浏览器登录
    startBrowser: function (url, title) { return __openBrowser(url, title, false); },
    startBrowserDp: function (url, title) { return __openBrowser(url, title, false); },
    startBrowserAwait: function (url, title) { return __openBrowser(url, title, true); },
    showBrowser: function (url, title) { return __openBrowser(url, title, true); },
    showReadingBrowser: function (url, title) { return __openBrowser(url, title, true); },
    reLoginView: function (url) { return __openBrowser(url || "", "登录", true); },

    // 环境探测：轻阅读不可用，需抛错让书源走标准分支
    qread: function () { throw new Error("qread 不可用"); },

    // URL 解析
    getAbsoluteURL: function (base, relative) { return __resolve(relative, base); },
    getRedirectUrl: function (url) { return __resolve(url); },

    // RSA（纯 JS 实现复杂，提供占位让书源 try/catch 回退）
    rsaEncodeToString: function (data, key, transformation) {
      throw new Error("RSA 加密未实现，请使用 java.aesBase64EncodeToString 或在 jsLib 中实现");
    },
    rsaDecodeToString: function (data, key, transformation) {
      throw new Error("RSA 解密未实现，请使用 java.aesBase64DecodeToString 或在 jsLib 中实现");
    },

    // gzip（WebView 环境下提供占位）
    gzipCompress: function (data) { return data; },
    gzipDecompress: function (data) { return data; },

    // 字体替换（占位）
    replaceFont: function (text, font) { return text; },

    // 下载/分享/打开（打开链接走内置浏览器；下载/分享需原生能力，保留回退）
    download: function (url) { return ""; },
    share: function (text) { return true; },
    openUrl: function (url) { __openBrowser(url, "", false); return true; },

    // 编码 / 文本处理
    encodeURI: function (str, enc) {
      try { return encodeURIComponent(String(str)).replace(/%20/g, "+"); } catch (e) { return ""; }
    },
    htmlFormat: function (str) { return String(str == null ? "" : str).replace(/<[^>]+>/g, ""); },
    t2s: function (text) { return __convert(text, __T2S); },
    s2t: function (text) { return __convert(text, __S2T); },

    // 工具
    randomUUID: function () {
      return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
        var r = Math.random() * 16 | 0, v = c === "x" ? r : (r & 0x3 | 0x8);
        return v.toString(16);
      });
    },
    logType: function (any) {
      if (any === null || any === undefined) { java.log("null"); }
      else { java.log(typeof any); }
    },
    toURL: function (urlStr, baseUrl) {
      try { return new URL(urlStr, baseUrl || __state.meta.httpUrl); } catch (e) { return null; }
    },
    toNumChapter: function (s) {
      if (!s) return s;
      var m = String(s).match(/^(\D*?)(\d+)(\D*)$/);
      if (m) return m[1] + parseInt(m[2], 10) + m[3];
      return s;
    },
    strToBytes: function (str, charset) {
      return Array.from(new TextEncoder().encode(String(str == null ? "" : str)));
    },
    bytesToStr: function (bytes, charset) {
      try { return new TextDecoder(charset || "utf-8").decode(Uint8Array.from(bytes || [])); } catch (e) { return ""; }
    },

    // 脚本导入 / 文件缓存（占位，返回空让书源回退）
    importScript: function (path) { return ""; },
    cacheFile: function (urlStr, saveTime) { return ""; },
    readTxtFile: function (path, charset) { return ""; },
    deleteFile: function (path) { return true; },

    // 源信息
    getSource: function () { return source; },
    getTag: function () { return __state.meta.name; },

    // 并发请求（占位，串行执行）
    ajaxAll: function (urlList) {
      var results = [];
      for (var i = 0; i < urlList.length; i++) {
        try { results.push({ url: urlList[i], body: __doXhr(urlList[i], { method: "GET" }) }); }
        catch (e) { results.push({ url: urlList[i], body: String(e) }); }
      }
      return results;
    },
    ajaxTestAll: function (urlList, timeout) { return this.ajaxAll(urlList); },

    // WebView 渲染（占位，返回空让书源回退到普通请求）
    webView: function (html, url, js, cacheFirst) { return html || ""; },
    webViewGetSource: function (html, url, js, sourceRegex, cacheFirst, delayTime) { return ""; },
    webViewGetOverrideUrl: function (html, url, js, overrideUrlRegex, cacheFirst, delayTime) { return url || ""; },
    getVerificationCode: function (imageUrl) { return ""; },

    // 字体反爬（占位）
    queryTTF: function (data, useCache) { return null; },
    getZipStringContent: function (url, path, charset) { return ""; },
    unzipFile: function (zipPath) { return ""; },
    unArchiveFile: function (zipPath) { return ""; },

    // 对称加密：返回 encrypt/decrypt 对象（对齐 legado JsExtensions.createSymmetricCrypto）
    createSymmetricCrypto: function (transformation, key) {
      var kb = __aesKeyBytes(key);
      var mode = String(transformation || "AES").toUpperCase();
      var useCbc = mode.indexOf("CBC") >= 0;
      return {
        encrypt: function (data) {
          var text = (typeof data === "string") ? data : String(data);
          var dataBytes = __utf8ToBytes(text);
          var pad = 16 - (dataBytes.length % 16);
          var padded = new Uint8Array(dataBytes.length + pad);
          padded.set(dataBytes);
          for (var i = dataBytes.length; i < padded.length; i++) padded[i] = pad;
          var enc;
          if (useCbc) {
            enc = new aesjs.ModeOfOperation.cbc(kb, __aesIv(null)).encrypt(padded);
          } else {
            enc = new aesjs.ModeOfOperation.ecb(kb).encrypt(padded);
          }
          return Array.from(enc);
        },
        decrypt: function (bytes) {
          var data = (bytes instanceof Uint8Array) ? bytes : Uint8Array.from(bytes || []);
          var dec;
          if (useCbc) {
            dec = new aesjs.ModeOfOperation.cbc(kb, __aesIv(null)).decrypt(data);
          } else {
            dec = new aesjs.ModeOfOperation.ecb(kb).decrypt(data);
          }
          dec = __unpadPkcs7(dec);
          return __bytesToUtf8(dec);
        }
      };
    },

    // java.lang / java.net 常见静态调用
    lang: {
      Thread: { sleep: function () {} },
      System: { currentTimeMillis: function () { return Date.now(); }, nanoTime: function () { return Date.now() * 1000000; } },
      String: function (v) { return String(v); },
      Integer: { parseInt: function (v) { return parseInt(v, 10); } }
    },
    net: {
      URLEncoder: { encode: function (s) { return encodeURIComponent(String(s)).replace(/%20/g, "+"); } },
      URLDecoder: { decode: function (s) { return decodeURIComponent(String(s).replace(/\+/g, "%20")); } }
    }
  };
  globalThis.java = java;

  function __pad(n) { return n < 10 ? "0" + n : "" + n; }
  function __timeFormat(time, pattern, utc) {
    if (!time) return "";
    var d;
    if (typeof time === "number" || /^\d+$/.test(String(time))) {
      var n = Number(time);
      if (n < 1e12) n = n * 1000;
      d = new Date(n);
    } else {
      d = new Date(String(time).replace(/-/g, "/"));
    }
    if (isNaN(d.getTime())) return "";
    var p = pattern || "yyyy-MM-dd HH:mm:ss";
    var Y = utc ? d.getUTCFullYear() : d.getFullYear();
    var M = (utc ? d.getUTCMonth() : d.getMonth()) + 1;
    var D = utc ? d.getUTCDate() : d.getDate();
    var H = utc ? d.getUTCHours() : d.getHours();
    var m = utc ? d.getUTCMinutes() : d.getMinutes();
    var s = utc ? d.getUTCSeconds() : d.getSeconds();
    return p
      .replace(/yyyy/g, "" + Y)
      .replace(/yy/g, ("" + Y).slice(-2))
      .replace(/MM/g, __pad(M))
      .replace(/dd/g, __pad(D))
      .replace(/HH/g, __pad(H))
      .replace(/mm/g, __pad(m))
      .replace(/ss/g, __pad(s));
  }

  // 供原生每次求值前重置「瞬态」输出
  globalThis.__resetTransient = function () {
    __state.logs = [];
    __state.toasts = [];
    __state.hosts = [];
    __state.browser = [];
  };

  // 求值结束后汇总输出
  globalThis.__envelope = function (ret, err) {
    if (ret === undefined) {
      try { ret = globalThis.result; } catch (e) { ret = null; }
    }
    var safeRet;
    try { safeRet = (ret === undefined) ? null : ret; } catch (e) { safeRet = String(ret); }
    return JSON.stringify({
      ret: safeRet,
      variable: __state.variable,
      loginInfo: __state.loginInfo,
      loginHeader: __state.loginHeader,
      kv: __state.kv,
      cookies: __state.cookies,
      logs: __state.logs,
      toasts: __state.toasts,
      hosts: __state.hosts,
      browser: __state.browser,
      error: err ? ((err && err.stack) ? String(err.stack) : String(err)) : null
    });
  };
})();
''';
}
