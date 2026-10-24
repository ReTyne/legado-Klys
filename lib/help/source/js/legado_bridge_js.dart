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
///   * 文件：readTxtFile / deleteFile / downloadFile（含 hex 兼容签名）/
///     importScript / cacheFile / getTxtInFolder
///   * 压缩包：getZipStringContent / get7zStringContent / getRarStringContent /
///     unzipFile / un7zFile / unrarFile / unArchiveFile（7z/rar 走 Android 原生解压）
///
/// 该脚本在每个书源的无头 WebView 创建后于「全局作用域」执行一次；
/// 书源的 jsLib / loginUrl 随后也在全局作用域执行（定义全局函数）。
///
/// 阅读/主题相关接口（java.getReadBookConfig / getThemeConfig / getThemeMode /
/// getTxtInFolder / openVideoPlayer）在 JS 侧读 `__state` 快照并回退默认值；
/// 原生需要实时数据时，可用本类的 Dart 静态助手生成 JSON 后种子注入
/// `__state.readConfig` / `__state.theme` / `__state.themeMode`。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Brightness, PlatformDispatcher;

import 'package:flutter/services.dart';

import '../../../constant/app_theme.dart';
import '../../../data/model/read_config.dart';

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
  // pako gzip 库（UMD，挂到 globalThis.pako）
  /*! pako 2.1.0 https://github.com/nodeca/pako @license (MIT AND Zlib) */
!function(t,e){"object"==typeof exports&&"undefined"!=typeof module?e(exports):"function"==typeof define&&define.amd?define(["exports"],e):e((t="undefined"!=typeof globalThis?globalThis:t||self).pako={})}(this,(function(t){"use strict";function e(t){let e=t.length;for(;--e>=0;)t[e]=0}const a=256,i=286,n=30,s=15,r=new Uint8Array([0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0]),o=new Uint8Array([0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13]),l=new Uint8Array([0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,3,7]),h=new Uint8Array([16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15]),d=new Array(576);e(d);const _=new Array(60);e(_);const f=new Array(512);e(f);const c=new Array(256);e(c);const u=new Array(29);e(u);const w=new Array(n);function m(t,e,a,i,n){this.static_tree=t,this.extra_bits=e,this.extra_base=a,this.elems=i,this.max_length=n,this.has_stree=t&&t.length}let b,g,p;function k(t,e){this.dyn_tree=t,this.max_code=0,this.stat_desc=e}e(w);const v=t=>t<256?f[t]:f[256+(t>>>7)],y=(t,e)=>{t.pending_buf[t.pending++]=255&e,t.pending_buf[t.pending++]=e>>>8&255},x=(t,e,a)=>{t.bi_valid>16-a?(t.bi_buf|=e<<t.bi_valid&65535,y(t,t.bi_buf),t.bi_buf=e>>16-t.bi_valid,t.bi_valid+=a-16):(t.bi_buf|=e<<t.bi_valid&65535,t.bi_valid+=a)},z=(t,e,a)=>{x(t,a[2*e],a[2*e+1])},A=(t,e)=>{let a=0;do{a|=1&t,t>>>=1,a<<=1}while(--e>0);return a>>>1},E=(t,e,a)=>{const i=new Array(16);let n,r,o=0;for(n=1;n<=s;n++)o=o+a[n-1]<<1,i[n]=o;for(r=0;r<=e;r++){let e=t[2*r+1];0!==e&&(t[2*r]=A(i[e]++,e))}},R=t=>{let e;for(e=0;e<i;e++)t.dyn_ltree[2*e]=0;for(e=0;e<n;e++)t.dyn_dtree[2*e]=0;for(e=0;e<19;e++)t.bl_tree[2*e]=0;t.dyn_ltree[512]=1,t.opt_len=t.static_len=0,t.sym_next=t.matches=0},Z=t=>{t.bi_valid>8?y(t,t.bi_buf):t.bi_valid>0&&(t.pending_buf[t.pending++]=t.bi_buf),t.bi_buf=0,t.bi_valid=0},U=(t,e,a,i)=>{const n=2*e,s=2*a;return t[n]<t[s]||t[n]===t[s]&&i[e]<=i[a]},S=(t,e,a)=>{const i=t.heap[a];let n=a<<1;for(;n<=t.heap_len&&(n<t.heap_len&&U(e,t.heap[n+1],t.heap[n],t.depth)&&n++,!U(e,i,t.heap[n],t.depth));)t.heap[a]=t.heap[n],a=n,n<<=1;t.heap[a]=i},D=(t,e,i)=>{let n,s,l,h,d=0;if(0!==t.sym_next)do{n=255&t.pending_buf[t.sym_buf+d++],n+=(255&t.pending_buf[t.sym_buf+d++])<<8,s=t.pending_buf[t.sym_buf+d++],0===n?z(t,s,e):(l=c[s],z(t,l+a+1,e),h=r[l],0!==h&&(s-=u[l],x(t,s,h)),n--,l=v(n),z(t,l,i),h=o[l],0!==h&&(n-=w[l],x(t,n,h)))}while(d<t.sym_next);z(t,256,e)},T=(t,e)=>{const a=e.dyn_tree,i=e.stat_desc.static_tree,n=e.stat_desc.has_stree,r=e.stat_desc.elems;let o,l,h,d=-1;for(t.heap_len=0,t.heap_max=573,o=0;o<r;o++)0!==a[2*o]?(t.heap[++t.heap_len]=d=o,t.depth[o]=0):a[2*o+1]=0;for(;t.heap_len<2;)h=t.heap[++t.heap_len]=d<2?++d:0,a[2*h]=1,t.depth[h]=0,t.opt_len--,n&&(t.static_len-=i[2*h+1]);for(e.max_code=d,o=t.heap_len>>1;o>=1;o--)S(t,a,o);h=r;do{o=t.heap[1],t.heap[1]=t.heap[t.heap_len--],S(t,a,1),l=t.heap[1],t.heap[--t.heap_max]=o,t.heap[--t.heap_max]=l,a[2*h]=a[2*o]+a[2*l],t.depth[h]=(t.depth[o]>=t.depth[l]?t.depth[o]:t.depth[l])+1,a[2*o+1]=a[2*l+1]=h,t.heap[1]=h++,S(t,a,1)}while(t.heap_len>=2);t.heap[--t.heap_max]=t.heap[1],((t,e)=>{const a=e.dyn_tree,i=e.max_code,n=e.stat_desc.static_tree,r=e.stat_desc.has_stree,o=e.stat_desc.extra_bits,l=e.stat_desc.extra_base,h=e.stat_desc.max_length;let d,_,f,c,u,w,m=0;for(c=0;c<=s;c++)t.bl_count[c]=0;for(a[2*t.heap[t.heap_max]+1]=0,d=t.heap_max+1;d<573;d++)_=t.heap[d],c=a[2*a[2*_+1]+1]+1,c>h&&(c=h,m++),a[2*_+1]=c,_>i||(t.bl_count[c]++,u=0,_>=l&&(u=o[_-l]),w=a[2*_],t.opt_len+=w*(c+u),r&&(t.static_len+=w*(n[2*_+1]+u)));if(0!==m){do{for(c=h-1;0===t.bl_count[c];)c--;t.bl_count[c]--,t.bl_count[c+1]+=2,t.bl_count[h]--,m-=2}while(m>0);for(c=h;0!==c;c--)for(_=t.bl_count[c];0!==_;)f=t.heap[--d],f>i||(a[2*f+1]!==c&&(t.opt_len+=(c-a[2*f+1])*a[2*f],a[2*f+1]=c),_--)}})(t,e),E(a,d,t.bl_count)},O=(t,e,a)=>{let i,n,s=-1,r=e[1],o=0,l=7,h=4;for(0===r&&(l=138,h=3),e[2*(a+1)+1]=65535,i=0;i<=a;i++)n=r,r=e[2*(i+1)+1],++o<l&&n===r||(o<h?t.bl_tree[2*n]+=o:0!==n?(n!==s&&t.bl_tree[2*n]++,t.bl_tree[32]++):o<=10?t.bl_tree[34]++:t.bl_tree[36]++,o=0,s=n,0===r?(l=138,h=3):n===r?(l=6,h=3):(l=7,h=4))},I=(t,e,a)=>{let i,n,s=-1,r=e[1],o=0,l=7,h=4;for(0===r&&(l=138,h=3),i=0;i<=a;i++)if(n=r,r=e[2*(i+1)+1],!(++o<l&&n===r)){if(o<h)do{z(t,n,t.bl_tree)}while(0!=--o);else 0!==n?(n!==s&&(z(t,n,t.bl_tree),o--),z(t,16,t.bl_tree),x(t,o-3,2)):o<=10?(z(t,17,t.bl_tree),x(t,o-3,3)):(z(t,18,t.bl_tree),x(t,o-11,7));o=0,s=n,0===r?(l=138,h=3):n===r?(l=6,h=3):(l=7,h=4)}};let F=!1;const L=(t,e,a,i)=>{x(t,0+(i?1:0),3),Z(t),y(t,a),y(t,~a),a&&t.pending_buf.set(t.window.subarray(e,e+a),t.pending),t.pending+=a};var N=(t,e,i,n)=>{let s,r,o=0;t.level>0?(2===t.strm.data_type&&(t.strm.data_type=(t=>{let e,i=4093624447;for(e=0;e<=31;e++,i>>>=1)if(1&i&&0!==t.dyn_ltree[2*e])return 0;if(0!==t.dyn_ltree[18]||0!==t.dyn_ltree[20]||0!==t.dyn_ltree[26])return 1;for(e=32;e<a;e++)if(0!==t.dyn_ltree[2*e])return 1;return 0})(t)),T(t,t.l_desc),T(t,t.d_desc),o=(t=>{let e;for(O(t,t.dyn_ltree,t.l_desc.max_code),O(t,t.dyn_dtree,t.d_desc.max_code),T(t,t.bl_desc),e=18;e>=3&&0===t.bl_tree[2*h[e]+1];e--);return t.opt_len+=3*(e+1)+5+5+4,e})(t),s=t.opt_len+3+7>>>3,r=t.static_len+3+7>>>3,r<=s&&(s=r)):s=r=i+5,i+4<=s&&-1!==e?L(t,e,i,n):4===t.strategy||r===s?(x(t,2+(n?1:0),3),D(t,d,_)):(x(t,4+(n?1:0),3),((t,e,a,i)=>{let n;for(x(t,e-257,5),x(t,a-1,5),x(t,i-4,4),n=0;n<i;n++)x(t,t.bl_tree[2*h[n]+1],3);I(t,t.dyn_ltree,e-1),I(t,t.dyn_dtree,a-1)})(t,t.l_desc.max_code+1,t.d_desc.max_code+1,o+1),D(t,t.dyn_ltree,t.dyn_dtree)),R(t),n&&Z(t)},B={_tr_init:t=>{F||((()=>{let t,e,a,h,k;const v=new Array(16);for(a=0,h=0;h<28;h++)for(u[h]=a,t=0;t<1<<r[h];t++)c[a++]=h;for(c[a-1]=h,k=0,h=0;h<16;h++)for(w[h]=k,t=0;t<1<<o[h];t++)f[k++]=h;for(k>>=7;h<n;h++)for(w[h]=k<<7,t=0;t<1<<o[h]-7;t++)f[256+k++]=h;for(e=0;e<=s;e++)v[e]=0;for(t=0;t<=143;)d[2*t+1]=8,t++,v[8]++;for(;t<=255;)d[2*t+1]=9,t++,v[9]++;for(;t<=279;)d[2*t+1]=7,t++,v[7]++;for(;t<=287;)d[2*t+1]=8,t++,v[8]++;for(E(d,287,v),t=0;t<n;t++)_[2*t+1]=5,_[2*t]=A(t,5);b=new m(d,r,257,i,s),g=new m(_,o,0,n,s),p=new m(new Array(0),l,0,19,7)})(),F=!0),t.l_desc=new k(t.dyn_ltree,b),t.d_desc=new k(t.dyn_dtree,g),t.bl_desc=new k(t.bl_tree,p),t.bi_buf=0,t.bi_valid=0,R(t)},_tr_stored_block:L,_tr_flush_block:N,_tr_tally:(t,e,i)=>(t.pending_buf[t.sym_buf+t.sym_next++]=e,t.pending_buf[t.sym_buf+t.sym_next++]=e>>8,t.pending_buf[t.sym_buf+t.sym_next++]=i,0===e?t.dyn_ltree[2*i]++:(t.matches++,e--,t.dyn_ltree[2*(c[i]+a+1)]++,t.dyn_dtree[2*v(e)]++),t.sym_next===t.sym_end),_tr_align:t=>{x(t,2,3),z(t,256,d),(t=>{16===t.bi_valid?(y(t,t.bi_buf),t.bi_buf=0,t.bi_valid=0):t.bi_valid>=8&&(t.pending_buf[t.pending++]=255&t.bi_buf,t.bi_buf>>=8,t.bi_valid-=8)})(t)}};var C=(t,e,a,i)=>{let n=65535&t|0,s=t>>>16&65535|0,r=0;for(;0!==a;){r=a>2e3?2e3:a,a-=r;do{n=n+e[i++]|0,s=s+n|0}while(--r);n%=65521,s%=65521}return n|s<<16|0};const M=new Uint32Array((()=>{let t,e=[];for(var a=0;a<256;a++){t=a;for(var i=0;i<8;i++)t=1&t?3988292384^t>>>1:t>>>1;e[a]=t}return e})());var H=(t,e,a,i)=>{const n=M,s=i+a;t^=-1;for(let a=i;a<s;a++)t=t>>>8^n[255&(t^e[a])];return-1^t},j={2:"need dictionary",1:"stream end",0:"","-1":"file error","-2":"stream error","-3":"data error","-4":"insufficient memory","-5":"buffer error","-6":"incompatible version"},K={Z_NO_FLUSH:0,Z_PARTIAL_FLUSH:1,Z_SYNC_FLUSH:2,Z_FULL_FLUSH:3,Z_FINISH:4,Z_BLOCK:5,Z_TREES:6,Z_OK:0,Z_STREAM_END:1,Z_NEED_DICT:2,Z_ERRNO:-1,Z_STREAM_ERROR:-2,Z_DATA_ERROR:-3,Z_MEM_ERROR:-4,Z_BUF_ERROR:-5,Z_NO_COMPRESSION:0,Z_BEST_SPEED:1,Z_BEST_COMPRESSION:9,Z_DEFAULT_COMPRESSION:-1,Z_FILTERED:1,Z_HUFFMAN_ONLY:2,Z_RLE:3,Z_FIXED:4,Z_DEFAULT_STRATEGY:0,Z_BINARY:0,Z_TEXT:1,Z_UNKNOWN:2,Z_DEFLATED:8};const{_tr_init:P,_tr_stored_block:Y,_tr_flush_block:G,_tr_tally:X,_tr_align:W}=B,{Z_NO_FLUSH:q,Z_PARTIAL_FLUSH:J,Z_FULL_FLUSH:Q,Z_FINISH:V,Z_BLOCK:$,Z_OK:tt,Z_STREAM_END:et,Z_STREAM_ERROR:at,Z_DATA_ERROR:it,Z_BUF_ERROR:nt,Z_DEFAULT_COMPRESSION:st,Z_FILTERED:rt,Z_HUFFMAN_ONLY:ot,Z_RLE:lt,Z_FIXED:ht,Z_DEFAULT_STRATEGY:dt,Z_UNKNOWN:_t,Z_DEFLATED:ft}=K,ct=258,ut=262,wt=42,mt=113,bt=666,gt=(t,e)=>(t.msg=j[e],e),pt=t=>2*t-(t>4?9:0),kt=t=>{let e=t.length;for(;--e>=0;)t[e]=0},vt=t=>{let e,a,i,n=t.w_size;e=t.hash_size,i=e;do{a=t.head[--i],t.head[i]=a>=n?a-n:0}while(--e);e=n,i=e;do{a=t.prev[--i],t.prev[i]=a>=n?a-n:0}while(--e)};let yt=(t,e,a)=>(e<<t.hash_shift^a)&t.hash_mask;const xt=t=>{const e=t.state;let a=e.pending;a>t.avail_out&&(a=t.avail_out),0!==a&&(t.output.set(e.pending_buf.subarray(e.pending_out,e.pending_out+a),t.next_out),t.next_out+=a,e.pending_out+=a,t.total_out+=a,t.avail_out-=a,e.pending-=a,0===e.pending&&(e.pending_out=0))},zt=(t,e)=>{G(t,t.block_start>=0?t.block_start:-1,t.strstart-t.block_start,e),t.block_start=t.strstart,xt(t.strm)},At=(t,e)=>{t.pending_buf[t.pending++]=e},Et=(t,e)=>{t.pending_buf[t.pending++]=e>>>8&255,t.pending_buf[t.pending++]=255&e},Rt=(t,e,a,i)=>{let n=t.avail_in;return n>i&&(n=i),0===n?0:(t.avail_in-=n,e.set(t.input.subarray(t.next_in,t.next_in+n),a),1===t.state.wrap?t.adler=C(t.adler,e,n,a):2===t.state.wrap&&(t.adler=H(t.adler,e,n,a)),t.next_in+=n,t.total_in+=n,n)},Zt=(t,e)=>{let a,i,n=t.max_chain_length,s=t.strstart,r=t.prev_length,o=t.nice_match;const l=t.strstart>t.w_size-ut?t.strstart-(t.w_size-ut):0,h=t.window,d=t.w_mask,_=t.prev,f=t.strstart+ct;let c=h[s+r-1],u=h[s+r];t.prev_length>=t.good_match&&(n>>=2),o>t.lookahead&&(o=t.lookahead);do{if(a=e,h[a+r]===u&&h[a+r-1]===c&&h[a]===h[s]&&h[++a]===h[s+1]){s+=2,a++;do{}while(h[++s]===h[++a]&&h[++s]===h[++a]&&h[++s]===h[++a]&&h[++s]===h[++a]&&h[++s]===h[++a]&&h[++s]===h[++a]&&h[++s]===h[++a]&&h[++s]===h[++a]&&s<f);if(i=ct-(f-s),s=f-ct,i>r){if(t.match_start=e,r=i,i>=o)break;c=h[s+r-1],u=h[s+r]}}}while((e=_[e&d])>l&&0!=--n);return r<=t.lookahead?r:t.lookahead},Ut=t=>{const e=t.w_size;let a,i,n;do{if(i=t.window_size-t.lookahead-t.strstart,t.strstart>=e+(e-ut)&&(t.window.set(t.window.subarray(e,e+e-i),0),t.match_start-=e,t.strstart-=e,t.block_start-=e,t.insert>t.strstart&&(t.insert=t.strstart),vt(t),i+=e),0===t.strm.avail_in)break;if(a=Rt(t.strm,t.window,t.strstart+t.lookahead,i),t.lookahead+=a,t.lookahead+t.insert>=3)for(n=t.strstart-t.insert,t.ins_h=t.window[n],t.ins_h=yt(t,t.ins_h,t.window[n+1]);t.insert&&(t.ins_h=yt(t,t.ins_h,t.window[n+3-1]),t.prev[n&t.w_mask]=t.head[t.ins_h],t.head[t.ins_h]=n,n++,t.insert--,!(t.lookahead+t.insert<3)););}while(t.lookahead<ut&&0!==t.strm.avail_in)},St=(t,e)=>{let a,i,n,s=t.pending_buf_size-5>t.w_size?t.w_size:t.pending_buf_size-5,r=0,o=t.strm.avail_in;do{if(a=65535,n=t.bi_valid+42>>3,t.strm.avail_out<n)break;if(n=t.strm.avail_out-n,i=t.strstart-t.block_start,a>i+t.strm.avail_in&&(a=i+t.strm.avail_in),a>n&&(a=n),a<s&&(0===a&&e!==V||e===q||a!==i+t.strm.avail_in))break;r=e===V&&a===i+t.strm.avail_in?1:0,Y(t,0,0,r),t.pending_buf[t.pending-4]=a,t.pending_buf[t.pending-3]=a>>8,t.pending_buf[t.pending-2]=~a,t.pending_buf[t.pending-1]=~a>>8,xt(t.strm),i&&(i>a&&(i=a),t.strm.output.set(t.window.subarray(t.block_start,t.block_start+i),t.strm.next_out),t.strm.next_out+=i,t.strm.avail_out-=i,t.strm.total_out+=i,t.block_start+=i,a-=i),a&&(Rt(t.strm,t.strm.output,t.strm.next_out,a),t.strm.next_out+=a,t.strm.avail_out-=a,t.strm.total_out+=a)}while(0===r);return o-=t.strm.avail_in,o&&(o>=t.w_size?(t.matches=2,t.window.set(t.strm.input.subarray(t.strm.next_in-t.w_size,t.strm.next_in),0),t.strstart=t.w_size,t.insert=t.strstart):(t.window_size-t.strstart<=o&&(t.strstart-=t.w_size,t.window.set(t.window.subarray(t.w_size,t.w_size+t.strstart),0),t.matches<2&&t.matches++,t.insert>t.strstart&&(t.insert=t.strstart)),t.window.set(t.strm.input.subarray(t.strm.next_in-o,t.strm.next_in),t.strstart),t.strstart+=o,t.insert+=o>t.w_size-t.insert?t.w_size-t.insert:o),t.block_start=t.strstart),t.high_water<t.strstart&&(t.high_water=t.strstart),r?4:e!==q&&e!==V&&0===t.strm.avail_in&&t.strstart===t.block_start?2:(n=t.window_size-t.strstart,t.strm.avail_in>n&&t.block_start>=t.w_size&&(t.block_start-=t.w_size,t.strstart-=t.w_size,t.window.set(t.window.subarray(t.w_size,t.w_size+t.strstart),0),t.matches<2&&t.matches++,n+=t.w_size,t.insert>t.strstart&&(t.insert=t.strstart)),n>t.strm.avail_in&&(n=t.strm.avail_in),n&&(Rt(t.strm,t.window,t.strstart,n),t.strstart+=n,t.insert+=n>t.w_size-t.insert?t.w_size-t.insert:n),t.high_water<t.strstart&&(t.high_water=t.strstart),n=t.bi_valid+42>>3,n=t.pending_buf_size-n>65535?65535:t.pending_buf_size-n,s=n>t.w_size?t.w_size:n,i=t.strstart-t.block_start,(i>=s||(i||e===V)&&e!==q&&0===t.strm.avail_in&&i<=n)&&(a=i>n?n:i,r=e===V&&0===t.strm.avail_in&&a===i?1:0,Y(t,t.block_start,a,r),t.block_start+=a,xt(t.strm)),r?3:1)},Dt=(t,e)=>{let a,i;for(;;){if(t.lookahead<ut){if(Ut(t),t.lookahead<ut&&e===q)return 1;if(0===t.lookahead)break}if(a=0,t.lookahead>=3&&(t.ins_h=yt(t,t.ins_h,t.window[t.strstart+3-1]),a=t.prev[t.strstart&t.w_mask]=t.head[t.ins_h],t.head[t.ins_h]=t.strstart),0!==a&&t.strstart-a<=t.w_size-ut&&(t.match_length=Zt(t,a)),t.match_length>=3)if(i=X(t,t.strstart-t.match_start,t.match_length-3),t.lookahead-=t.match_length,t.match_length<=t.max_lazy_match&&t.lookahead>=3){t.match_length--;do{t.strstart++,t.ins_h=yt(t,t.ins_h,t.window[t.strstart+3-1]),a=t.prev[t.strstart&t.w_mask]=t.head[t.ins_h],t.head[t.ins_h]=t.strstart}while(0!=--t.match_length);t.strstart++}else t.strstart+=t.match_length,t.match_length=0,t.ins_h=t.window[t.strstart],t.ins_h=yt(t,t.ins_h,t.window[t.strstart+1]);else i=X(t,0,t.window[t.strstart]),t.lookahead--,t.strstart++;if(i&&(zt(t,!1),0===t.strm.avail_out))return 1}return t.insert=t.strstart<2?t.strstart:2,e===V?(zt(t,!0),0===t.strm.avail_out?3:4):t.sym_next&&(zt(t,!1),0===t.strm.avail_out)?1:2},Tt=(t,e)=>{let a,i,n;for(;;){if(t.lookahead<ut){if(Ut(t),t.lookahead<ut&&e===q)return 1;if(0===t.lookahead)break}if(a=0,t.lookahead>=3&&(t.ins_h=yt(t,t.ins_h,t.window[t.strstart+3-1]),a=t.prev[t.strstart&t.w_mask]=t.head[t.ins_h],t.head[t.ins_h]=t.strstart),t.prev_length=t.match_length,t.prev_match=t.match_start,t.match_length=2,0!==a&&t.prev_length<t.max_lazy_match&&t.strstart-a<=t.w_size-ut&&(t.match_length=Zt(t,a),t.match_length<=5&&(t.strategy===rt||3===t.match_length&&t.strstart-t.match_start>4096)&&(t.match_length=2)),t.prev_length>=3&&t.match_length<=t.prev_length){n=t.strstart+t.lookahead-3,i=X(t,t.strstart-1-t.prev_match,t.prev_length-3),t.lookahead-=t.prev_length-1,t.prev_length-=2;do{++t.strstart<=n&&(t.ins_h=yt(t,t.ins_h,t.window[t.strstart+3-1]),a=t.prev[t.strstart&t.w_mask]=t.head[t.ins_h],t.head[t.ins_h]=t.strstart)}while(0!=--t.prev_length);if(t.match_available=0,t.match_length=2,t.strstart++,i&&(zt(t,!1),0===t.strm.avail_out))return 1}else if(t.match_available){if(i=X(t,0,t.window[t.strstart-1]),i&&zt(t,!1),t.strstart++,t.lookahead--,0===t.strm.avail_out)return 1}else t.match_available=1,t.strstart++,t.lookahead--}return t.match_available&&(i=X(t,0,t.window[t.strstart-1]),t.match_available=0),t.insert=t.strstart<2?t.strstart:2,e===V?(zt(t,!0),0===t.strm.avail_out?3:4):t.sym_next&&(zt(t,!1),0===t.strm.avail_out)?1:2};function Ot(t,e,a,i,n){this.good_length=t,this.max_lazy=e,this.nice_length=a,this.max_chain=i,this.func=n}const It=[new Ot(0,0,0,0,St),new Ot(4,4,8,4,Dt),new Ot(4,5,16,8,Dt),new Ot(4,6,32,32,Dt),new Ot(4,4,16,16,Tt),new Ot(8,16,32,32,Tt),new Ot(8,16,128,128,Tt),new Ot(8,32,128,256,Tt),new Ot(32,128,258,1024,Tt),new Ot(32,258,258,4096,Tt)];function Ft(){this.strm=null,this.status=0,this.pending_buf=null,this.pending_buf_size=0,this.pending_out=0,this.pending=0,this.wrap=0,this.gzhead=null,this.gzindex=0,this.method=ft,this.last_flush=-1,this.w_size=0,this.w_bits=0,this.w_mask=0,this.window=null,this.window_size=0,this.prev=null,this.head=null,this.ins_h=0,this.hash_size=0,this.hash_bits=0,this.hash_mask=0,this.hash_shift=0,this.block_start=0,this.match_length=0,this.prev_match=0,this.match_available=0,this.strstart=0,this.match_start=0,this.lookahead=0,this.prev_length=0,this.max_chain_length=0,this.max_lazy_match=0,this.level=0,this.strategy=0,this.good_match=0,this.nice_match=0,this.dyn_ltree=new Uint16Array(1146),this.dyn_dtree=new Uint16Array(122),this.bl_tree=new Uint16Array(78),kt(this.dyn_ltree),kt(this.dyn_dtree),kt(this.bl_tree),this.l_desc=null,this.d_desc=null,this.bl_desc=null,this.bl_count=new Uint16Array(16),this.heap=new Uint16Array(573),kt(this.heap),this.heap_len=0,this.heap_max=0,this.depth=new Uint16Array(573),kt(this.depth),this.sym_buf=0,this.lit_bufsize=0,this.sym_next=0,this.sym_end=0,this.opt_len=0,this.static_len=0,this.matches=0,this.insert=0,this.bi_buf=0,this.bi_valid=0}const Lt=t=>{if(!t)return 1;const e=t.state;return!e||e.strm!==t||e.status!==wt&&57!==e.status&&69!==e.status&&73!==e.status&&91!==e.status&&103!==e.status&&e.status!==mt&&e.status!==bt?1:0},Nt=t=>{if(Lt(t))return gt(t,at);t.total_in=t.total_out=0,t.data_type=_t;const e=t.state;return e.pending=0,e.pending_out=0,e.wrap<0&&(e.wrap=-e.wrap),e.status=2===e.wrap?57:e.wrap?wt:mt,t.adler=2===e.wrap?0:1,e.last_flush=-2,P(e),tt},Bt=t=>{const e=Nt(t);var a;return e===tt&&((a=t.state).window_size=2*a.w_size,kt(a.head),a.max_lazy_match=It[a.level].max_lazy,a.good_match=It[a.level].good_length,a.nice_match=It[a.level].nice_length,a.max_chain_length=It[a.level].max_chain,a.strstart=0,a.block_start=0,a.lookahead=0,a.insert=0,a.match_length=a.prev_length=2,a.match_available=0,a.ins_h=0),e},Ct=(t,e,a,i,n,s)=>{if(!t)return at;let r=1;if(e===st&&(e=6),i<0?(r=0,i=-i):i>15&&(r=2,i-=16),n<1||n>9||a!==ft||i<8||i>15||e<0||e>9||s<0||s>ht||8===i&&1!==r)return gt(t,at);8===i&&(i=9);const o=new Ft;return t.state=o,o.strm=t,o.status=wt,o.wrap=r,o.gzhead=null,o.w_bits=i,o.w_size=1<<o.w_bits,o.w_mask=o.w_size-1,o.hash_bits=n+7,o.hash_size=1<<o.hash_bits,o.hash_mask=o.hash_size-1,o.hash_shift=~~((o.hash_bits+3-1)/3),o.window=new Uint8Array(2*o.w_size),o.head=new Uint16Array(o.hash_size),o.prev=new Uint16Array(o.w_size),o.lit_bufsize=1<<n+6,o.pending_buf_size=4*o.lit_bufsize,o.pending_buf=new Uint8Array(o.pending_buf_size),o.sym_buf=o.lit_bufsize,o.sym_end=3*(o.lit_bufsize-1),o.level=e,o.strategy=s,o.method=a,Bt(t)};var Mt={deflateInit:(t,e)=>Ct(t,e,ft,15,8,dt),deflateInit2:Ct,deflateReset:Bt,deflateResetKeep:Nt,deflateSetHeader:(t,e)=>Lt(t)||2!==t.state.wrap?at:(t.state.gzhead=e,tt),deflate:(t,e)=>{if(Lt(t)||e>$||e<0)return t?gt(t,at):at;const a=t.state;if(!t.output||0!==t.avail_in&&!t.input||a.status===bt&&e!==V)return gt(t,0===t.avail_out?nt:at);const i=a.last_flush;if(a.last_flush=e,0!==a.pending){if(xt(t),0===t.avail_out)return a.last_flush=-1,tt}else if(0===t.avail_in&&pt(e)<=pt(i)&&e!==V)return gt(t,nt);if(a.status===bt&&0!==t.avail_in)return gt(t,nt);if(a.status===wt&&0===a.wrap&&(a.status=mt),a.status===wt){let e=ft+(a.w_bits-8<<4)<<8,i=-1;if(i=a.strategy>=ot||a.level<2?0:a.level<6?1:6===a.level?2:3,e|=i<<6,0!==a.strstart&&(e|=32),e+=31-e%31,Et(a,e),0!==a.strstart&&(Et(a,t.adler>>>16),Et(a,65535&t.adler)),t.adler=1,a.status=mt,xt(t),0!==a.pending)return a.last_flush=-1,tt}if(57===a.status)if(t.adler=0,At(a,31),At(a,139),At(a,8),a.gzhead)At(a,(a.gzhead.text?1:0)+(a.gzhead.hcrc?2:0)+(a.gzhead.extra?4:0)+(a.gzhead.name?8:0)+(a.gzhead.comment?16:0)),At(a,255&a.gzhead.time),At(a,a.gzhead.time>>8&255),At(a,a.gzhead.time>>16&255),At(a,a.gzhead.time>>24&255),At(a,9===a.level?2:a.strategy>=ot||a.level<2?4:0),At(a,255&a.gzhead.os),a.gzhead.extra&&a.gzhead.extra.length&&(At(a,255&a.gzhead.extra.length),At(a,a.gzhead.extra.length>>8&255)),a.gzhead.hcrc&&(t.adler=H(t.adler,a.pending_buf,a.pending,0)),a.gzindex=0,a.status=69;else if(At(a,0),At(a,0),At(a,0),At(a,0),At(a,0),At(a,9===a.level?2:a.strategy>=ot||a.level<2?4:0),At(a,3),a.status=mt,xt(t),0!==a.pending)return a.last_flush=-1,tt;if(69===a.status){if(a.gzhead.extra){let e=a.pending,i=(65535&a.gzhead.extra.length)-a.gzindex;for(;a.pending+i>a.pending_buf_size;){let n=a.pending_buf_size-a.pending;if(a.pending_buf.set(a.gzhead.extra.subarray(a.gzindex,a.gzindex+n),a.pending),a.pending=a.pending_buf_size,a.gzhead.hcrc&&a.pending>e&&(t.adler=H(t.adler,a.pending_buf,a.pending-e,e)),a.gzindex+=n,xt(t),0!==a.pending)return a.last_flush=-1,tt;e=0,i-=n}let n=new Uint8Array(a.gzhead.extra);a.pending_buf.set(n.subarray(a.gzindex,a.gzindex+i),a.pending),a.pending+=i,a.gzhead.hcrc&&a.pending>e&&(t.adler=H(t.adler,a.pending_buf,a.pending-e,e)),a.gzindex=0}a.status=73}if(73===a.status){if(a.gzhead.name){let e,i=a.pending;do{if(a.pending===a.pending_buf_size){if(a.gzhead.hcrc&&a.pending>i&&(t.adler=H(t.adler,a.pending_buf,a.pending-i,i)),xt(t),0!==a.pending)return a.last_flush=-1,tt;i=0}e=a.gzindex<a.gzhead.name.length?255&a.gzhead.name.charCodeAt(a.gzindex++):0,At(a,e)}while(0!==e);a.gzhead.hcrc&&a.pending>i&&(t.adler=H(t.adler,a.pending_buf,a.pending-i,i)),a.gzindex=0}a.status=91}if(91===a.status){if(a.gzhead.comment){let e,i=a.pending;do{if(a.pending===a.pending_buf_size){if(a.gzhead.hcrc&&a.pending>i&&(t.adler=H(t.adler,a.pending_buf,a.pending-i,i)),xt(t),0!==a.pending)return a.last_flush=-1,tt;i=0}e=a.gzindex<a.gzhead.comment.length?255&a.gzhead.comment.charCodeAt(a.gzindex++):0,At(a,e)}while(0!==e);a.gzhead.hcrc&&a.pending>i&&(t.adler=H(t.adler,a.pending_buf,a.pending-i,i))}a.status=103}if(103===a.status){if(a.gzhead.hcrc){if(a.pending+2>a.pending_buf_size&&(xt(t),0!==a.pending))return a.last_flush=-1,tt;At(a,255&t.adler),At(a,t.adler>>8&255),t.adler=0}if(a.status=mt,xt(t),0!==a.pending)return a.last_flush=-1,tt}if(0!==t.avail_in||0!==a.lookahead||e!==q&&a.status!==bt){let i=0===a.level?St(a,e):a.strategy===ot?((t,e)=>{let a;for(;;){if(0===t.lookahead&&(Ut(t),0===t.lookahead)){if(e===q)return 1;break}if(t.match_length=0,a=X(t,0,t.window[t.strstart]),t.lookahead--,t.strstart++,a&&(zt(t,!1),0===t.strm.avail_out))return 1}return t.insert=0,e===V?(zt(t,!0),0===t.strm.avail_out?3:4):t.sym_next&&(zt(t,!1),0===t.strm.avail_out)?1:2})(a,e):a.strategy===lt?((t,e)=>{let a,i,n,s;const r=t.window;for(;;){if(t.lookahead<=ct){if(Ut(t),t.lookahead<=ct&&e===q)return 1;if(0===t.lookahead)break}if(t.match_length=0,t.lookahead>=3&&t.strstart>0&&(n=t.strstart-1,i=r[n],i===r[++n]&&i===r[++n]&&i===r[++n])){s=t.strstart+ct;do{}while(i===r[++n]&&i===r[++n]&&i===r[++n]&&i===r[++n]&&i===r[++n]&&i===r[++n]&&i===r[++n]&&i===r[++n]&&n<s);t.match_length=ct-(s-n),t.match_length>t.lookahead&&(t.match_length=t.lookahead)}if(t.match_length>=3?(a=X(t,1,t.match_length-3),t.lookahead-=t.match_length,t.strstart+=t.match_length,t.match_length=0):(a=X(t,0,t.window[t.strstart]),t.lookahead--,t.strstart++),a&&(zt(t,!1),0===t.strm.avail_out))return 1}return t.insert=0,e===V?(zt(t,!0),0===t.strm.avail_out?3:4):t.sym_next&&(zt(t,!1),0===t.strm.avail_out)?1:2})(a,e):It[a.level].func(a,e);if(3!==i&&4!==i||(a.status=bt),1===i||3===i)return 0===t.avail_out&&(a.last_flush=-1),tt;if(2===i&&(e===J?W(a):e!==$&&(Y(a,0,0,!1),e===Q&&(kt(a.head),0===a.lookahead&&(a.strstart=0,a.block_start=0,a.insert=0))),xt(t),0===t.avail_out))return a.last_flush=-1,tt}return e!==V?tt:a.wrap<=0?et:(2===a.wrap?(At(a,255&t.adler),At(a,t.adler>>8&255),At(a,t.adler>>16&255),At(a,t.adler>>24&255),At(a,255&t.total_in),At(a,t.total_in>>8&255),At(a,t.total_in>>16&255),At(a,t.total_in>>24&255)):(Et(a,t.adler>>>16),Et(a,65535&t.adler)),xt(t),a.wrap>0&&(a.wrap=-a.wrap),0!==a.pending?tt:et)},deflateEnd:t=>{if(Lt(t))return at;const e=t.state.status;return t.state=null,e===mt?gt(t,it):tt},deflateSetDictionary:(t,e)=>{let a=e.length;if(Lt(t))return at;const i=t.state,n=i.wrap;if(2===n||1===n&&i.status!==wt||i.lookahead)return at;if(1===n&&(t.adler=C(t.adler,e,a,0)),i.wrap=0,a>=i.w_size){0===n&&(kt(i.head),i.strstart=0,i.block_start=0,i.insert=0);let t=new Uint8Array(i.w_size);t.set(e.subarray(a-i.w_size,a),0),e=t,a=i.w_size}const s=t.avail_in,r=t.next_in,o=t.input;for(t.avail_in=a,t.next_in=0,t.input=e,Ut(i);i.lookahead>=3;){let t=i.strstart,e=i.lookahead-2;do{i.ins_h=yt(i,i.ins_h,i.window[t+3-1]),i.prev[t&i.w_mask]=i.head[i.ins_h],i.head[i.ins_h]=t,t++}while(--e);i.strstart=t,i.lookahead=2,Ut(i)}return i.strstart+=i.lookahead,i.block_start=i.strstart,i.insert=i.lookahead,i.lookahead=0,i.match_length=i.prev_length=2,i.match_available=0,t.next_in=r,t.input=o,t.avail_in=s,i.wrap=n,tt},deflateInfo:"pako deflate (from Nodeca project)"};const Ht=(t,e)=>Object.prototype.hasOwnProperty.call(t,e);var jt=function(t){const e=Array.prototype.slice.call(arguments,1);for(;e.length;){const a=e.shift();if(a){if("object"!=typeof a)throw new TypeError(a+"must be non-object");for(const e in a)Ht(a,e)&&(t[e]=a[e])}}return t},Kt=t=>{let e=0;for(let a=0,i=t.length;a<i;a++)e+=t[a].length;const a=new Uint8Array(e);for(let e=0,i=0,n=t.length;e<n;e++){let n=t[e];a.set(n,i),i+=n.length}return a};let Pt=!0;try{String.fromCharCode.apply(null,new Uint8Array(1))}catch(t){Pt=!1}const Yt=new Uint8Array(256);for(let t=0;t<256;t++)Yt[t]=t>=252?6:t>=248?5:t>=240?4:t>=224?3:t>=192?2:1;Yt[254]=Yt[254]=1;var Gt=t=>{if("function"==typeof TextEncoder&&TextEncoder.prototype.encode)return(new TextEncoder).encode(t);let e,a,i,n,s,r=t.length,o=0;for(n=0;n<r;n++)a=t.charCodeAt(n),55296==(64512&a)&&n+1<r&&(i=t.charCodeAt(n+1),56320==(64512&i)&&(a=65536+(a-55296<<10)+(i-56320),n++)),o+=a<128?1:a<2048?2:a<65536?3:4;for(e=new Uint8Array(o),s=0,n=0;s<o;n++)a=t.charCodeAt(n),55296==(64512&a)&&n+1<r&&(i=t.charCodeAt(n+1),56320==(64512&i)&&(a=65536+(a-55296<<10)+(i-56320),n++)),a<128?e[s++]=a:a<2048?(e[s++]=192|a>>>6,e[s++]=128|63&a):a<65536?(e[s++]=224|a>>>12,e[s++]=128|a>>>6&63,e[s++]=128|63&a):(e[s++]=240|a>>>18,e[s++]=128|a>>>12&63,e[s++]=128|a>>>6&63,e[s++]=128|63&a);return e},Xt=(t,e)=>{const a=e||t.length;if("function"==typeof TextDecoder&&TextDecoder.prototype.decode)return(new TextDecoder).decode(t.subarray(0,e));let i,n;const s=new Array(2*a);for(n=0,i=0;i<a;){let e=t[i++];if(e<128){s[n++]=e;continue}let r=Yt[e];if(r>4)s[n++]=65533,i+=r-1;else{for(e&=2===r?31:3===r?15:7;r>1&&i<a;)e=e<<6|63&t[i++],r--;r>1?s[n++]=65533:e<65536?s[n++]=e:(e-=65536,s[n++]=55296|e>>10&1023,s[n++]=56320|1023&e)}}return((t,e)=>{if(e<65534&&t.subarray&&Pt)return String.fromCharCode.apply(null,t.length===e?t:t.subarray(0,e));let a="";for(let i=0;i<e;i++)a+=String.fromCharCode(t[i]);return a})(s,n)},Wt=(t,e)=>{(e=e||t.length)>t.length&&(e=t.length);let a=e-1;for(;a>=0&&128==(192&t[a]);)a--;return a<0||0===a?e:a+Yt[t[a]]>e?a:e};var qt=function(){this.input=null,this.next_in=0,this.avail_in=0,this.total_in=0,this.output=null,this.next_out=0,this.avail_out=0,this.total_out=0,this.msg="",this.state=null,this.data_type=2,this.adler=0};const Jt=Object.prototype.toString,{Z_NO_FLUSH:Qt,Z_SYNC_FLUSH:Vt,Z_FULL_FLUSH:$t,Z_FINISH:te,Z_OK:ee,Z_STREAM_END:ae,Z_DEFAULT_COMPRESSION:ie,Z_DEFAULT_STRATEGY:ne,Z_DEFLATED:se}=K;function re(t){this.options=jt({level:ie,method:se,chunkSize:16384,windowBits:15,memLevel:8,strategy:ne},t||{});let e=this.options;e.raw&&e.windowBits>0?e.windowBits=-e.windowBits:e.gzip&&e.windowBits>0&&e.windowBits<16&&(e.windowBits+=16),this.err=0,this.msg="",this.ended=!1,this.chunks=[],this.strm=new qt,this.strm.avail_out=0;let a=Mt.deflateInit2(this.strm,e.level,e.method,e.windowBits,e.memLevel,e.strategy);if(a!==ee)throw new Error(j[a]);if(e.header&&Mt.deflateSetHeader(this.strm,e.header),e.dictionary){let t;if(t="string"==typeof e.dictionary?Gt(e.dictionary):"[object ArrayBuffer]"===Jt.call(e.dictionary)?new Uint8Array(e.dictionary):e.dictionary,a=Mt.deflateSetDictionary(this.strm,t),a!==ee)throw new Error(j[a]);this._dict_set=!0}}function oe(t,e){const a=new re(e);if(a.push(t,!0),a.err)throw a.msg||j[a.err];return a.result}re.prototype.push=function(t,e){const a=this.strm,i=this.options.chunkSize;let n,s;if(this.ended)return!1;for(s=e===~~e?e:!0===e?te:Qt,"string"==typeof t?a.input=Gt(t):"[object ArrayBuffer]"===Jt.call(t)?a.input=new Uint8Array(t):a.input=t,a.next_in=0,a.avail_in=a.input.length;;)if(0===a.avail_out&&(a.output=new Uint8Array(i),a.next_out=0,a.avail_out=i),(s===Vt||s===$t)&&a.avail_out<=6)this.onData(a.output.subarray(0,a.next_out)),a.avail_out=0;else{if(n=Mt.deflate(a,s),n===ae)return a.next_out>0&&this.onData(a.output.subarray(0,a.next_out)),n=Mt.deflateEnd(this.strm),this.onEnd(n),this.ended=!0,n===ee;if(0!==a.avail_out){if(s>0&&a.next_out>0)this.onData(a.output.subarray(0,a.next_out)),a.avail_out=0;else if(0===a.avail_in)break}else this.onData(a.output)}return!0},re.prototype.onData=function(t){this.chunks.push(t)},re.prototype.onEnd=function(t){t===ee&&(this.result=Kt(this.chunks)),this.chunks=[],this.err=t,this.msg=this.strm.msg};var le={Deflate:re,deflate:oe,deflateRaw:function(t,e){return(e=e||{}).raw=!0,oe(t,e)},gzip:function(t,e){return(e=e||{}).gzip=!0,oe(t,e)},constants:K};const he=16209;var de=function(t,e){let a,i,n,s,r,o,l,h,d,_,f,c,u,w,m,b,g,p,k,v,y,x,z,A;const E=t.state;a=t.next_in,z=t.input,i=a+(t.avail_in-5),n=t.next_out,A=t.output,s=n-(e-t.avail_out),r=n+(t.avail_out-257),o=E.dmax,l=E.wsize,h=E.whave,d=E.wnext,_=E.window,f=E.hold,c=E.bits,u=E.lencode,w=E.distcode,m=(1<<E.lenbits)-1,b=(1<<E.distbits)-1;t:do{c<15&&(f+=z[a++]<<c,c+=8,f+=z[a++]<<c,c+=8),g=u[f&m];e:for(;;){if(p=g>>>24,f>>>=p,c-=p,p=g>>>16&255,0===p)A[n++]=65535&g;else{if(!(16&p)){if(0==(64&p)){g=u[(65535&g)+(f&(1<<p)-1)];continue e}if(32&p){E.mode=16191;break t}t.msg="invalid literal/length code",E.mode=he;break t}k=65535&g,p&=15,p&&(c<p&&(f+=z[a++]<<c,c+=8),k+=f&(1<<p)-1,f>>>=p,c-=p),c<15&&(f+=z[a++]<<c,c+=8,f+=z[a++]<<c,c+=8),g=w[f&b];a:for(;;){if(p=g>>>24,f>>>=p,c-=p,p=g>>>16&255,!(16&p)){if(0==(64&p)){g=w[(65535&g)+(f&(1<<p)-1)];continue a}t.msg="invalid distance code",E.mode=he;break t}if(v=65535&g,p&=15,c<p&&(f+=z[a++]<<c,c+=8,c<p&&(f+=z[a++]<<c,c+=8)),v+=f&(1<<p)-1,v>o){t.msg="invalid distance too far back",E.mode=he;break t}if(f>>>=p,c-=p,p=n-s,v>p){if(p=v-p,p>h&&E.sane){t.msg="invalid distance too far back",E.mode=he;break t}if(y=0,x=_,0===d){if(y+=l-p,p<k){k-=p;do{A[n++]=_[y++]}while(--p);y=n-v,x=A}}else if(d<p){if(y+=l+d-p,p-=d,p<k){k-=p;do{A[n++]=_[y++]}while(--p);if(y=0,d<k){p=d,k-=p;do{A[n++]=_[y++]}while(--p);y=n-v,x=A}}}else if(y+=d-p,p<k){k-=p;do{A[n++]=_[y++]}while(--p);y=n-v,x=A}for(;k>2;)A[n++]=x[y++],A[n++]=x[y++],A[n++]=x[y++],k-=3;k&&(A[n++]=x[y++],k>1&&(A[n++]=x[y++]))}else{y=n-v;do{A[n++]=A[y++],A[n++]=A[y++],A[n++]=A[y++],k-=3}while(k>2);k&&(A[n++]=A[y++],k>1&&(A[n++]=A[y++]))}break}}break}}while(a<i&&n<r);k=c>>3,a-=k,c-=k<<3,f&=(1<<c)-1,t.next_in=a,t.next_out=n,t.avail_in=a<i?i-a+5:5-(a-i),t.avail_out=n<r?r-n+257:257-(n-r),E.hold=f,E.bits=c};const _e=15,fe=new Uint16Array([3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258,0,0]),ce=new Uint8Array([16,16,16,16,16,16,16,16,17,17,17,17,18,18,18,18,19,19,19,19,20,20,20,20,21,21,21,21,16,72,78]),ue=new Uint16Array([1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577,0,0]),we=new Uint8Array([16,16,16,16,17,17,18,18,19,19,20,20,21,21,22,22,23,23,24,24,25,25,26,26,27,27,28,28,29,29,64,64]);var me=(t,e,a,i,n,s,r,o)=>{const l=o.bits;let h,d,_,f,c,u,w=0,m=0,b=0,g=0,p=0,k=0,v=0,y=0,x=0,z=0,A=null;const E=new Uint16Array(16),R=new Uint16Array(16);let Z,U,S,D=null;for(w=0;w<=_e;w++)E[w]=0;for(m=0;m<i;m++)E[e[a+m]]++;for(p=l,g=_e;g>=1&&0===E[g];g--);if(p>g&&(p=g),0===g)return n[s++]=20971520,n[s++]=20971520,o.bits=1,0;for(b=1;b<g&&0===E[b];b++);for(p<b&&(p=b),y=1,w=1;w<=_e;w++)if(y<<=1,y-=E[w],y<0)return-1;if(y>0&&(0===t||1!==g))return-1;for(R[1]=0,w=1;w<_e;w++)R[w+1]=R[w]+E[w];for(m=0;m<i;m++)0!==e[a+m]&&(r[R[e[a+m]]++]=m);if(0===t?(A=D=r,u=20):1===t?(A=fe,D=ce,u=257):(A=ue,D=we,u=0),z=0,m=0,w=b,c=s,k=p,v=0,_=-1,x=1<<p,f=x-1,1===t&&x>852||2===t&&x>592)return 1;for(;;){Z=w-v,r[m]+1<u?(U=0,S=r[m]):r[m]>=u?(U=D[r[m]-u],S=A[r[m]-u]):(U=96,S=0),h=1<<w-v,d=1<<k,b=d;do{d-=h,n[c+(z>>v)+d]=Z<<24|U<<16|S|0}while(0!==d);for(h=1<<w-1;z&h;)h>>=1;if(0!==h?(z&=h-1,z+=h):z=0,m++,0==--E[w]){if(w===g)break;w=e[a+r[m]]}if(w>p&&(z&f)!==_){for(0===v&&(v=p),c+=b,k=w-v,y=1<<k;k+v<g&&(y-=E[k+v],!(y<=0));)k++,y<<=1;if(x+=1<<k,1===t&&x>852||2===t&&x>592)return 1;_=z&f,n[_]=p<<24|k<<16|c-s|0}}return 0!==z&&(n[c+z]=w-v<<24|64<<16|0),o.bits=p,0};const{Z_FINISH:be,Z_BLOCK:ge,Z_TREES:pe,Z_OK:ke,Z_STREAM_END:ve,Z_NEED_DICT:ye,Z_STREAM_ERROR:xe,Z_DATA_ERROR:ze,Z_MEM_ERROR:Ae,Z_BUF_ERROR:Ee,Z_DEFLATED:Re}=K,Ze=16180,Ue=16190,Se=16191,De=16192,Te=16194,Oe=16199,Ie=16200,Fe=16206,Le=16209,Ne=t=>(t>>>24&255)+(t>>>8&65280)+((65280&t)<<8)+((255&t)<<24);function Be(){this.strm=null,this.mode=0,this.last=!1,this.wrap=0,this.havedict=!1,this.flags=0,this.dmax=0,this.check=0,this.total=0,this.head=null,this.wbits=0,this.wsize=0,this.whave=0,this.wnext=0,this.window=null,this.hold=0,this.bits=0,this.length=0,this.offset=0,this.extra=0,this.lencode=null,this.distcode=null,this.lenbits=0,this.distbits=0,this.ncode=0,this.nlen=0,this.ndist=0,this.have=0,this.next=null,this.lens=new Uint16Array(320),this.work=new Uint16Array(288),this.lendyn=null,this.distdyn=null,this.sane=0,this.back=0,this.was=0}const Ce=t=>{if(!t)return 1;const e=t.state;return!e||e.strm!==t||e.mode<Ze||e.mode>16211?1:0},Me=t=>{if(Ce(t))return xe;const e=t.state;return t.total_in=t.total_out=e.total=0,t.msg="",e.wrap&&(t.adler=1&e.wrap),e.mode=Ze,e.last=0,e.havedict=0,e.flags=-1,e.dmax=32768,e.head=null,e.hold=0,e.bits=0,e.lencode=e.lendyn=new Int32Array(852),e.distcode=e.distdyn=new Int32Array(592),e.sane=1,e.back=-1,ke},He=t=>{if(Ce(t))return xe;const e=t.state;return e.wsize=0,e.whave=0,e.wnext=0,Me(t)},je=(t,e)=>{let a;if(Ce(t))return xe;const i=t.state;return e<0?(a=0,e=-e):(a=5+(e>>4),e<48&&(e&=15)),e&&(e<8||e>15)?xe:(null!==i.window&&i.wbits!==e&&(i.window=null),i.wrap=a,i.wbits=e,He(t))},Ke=(t,e)=>{if(!t)return xe;const a=new Be;t.state=a,a.strm=t,a.window=null,a.mode=Ze;const i=je(t,e);return i!==ke&&(t.state=null),i};let Pe,Ye,Ge=!0;const Xe=t=>{if(Ge){Pe=new Int32Array(512),Ye=new Int32Array(32);let e=0;for(;e<144;)t.lens[e++]=8;for(;e<256;)t.lens[e++]=9;for(;e<280;)t.lens[e++]=7;for(;e<288;)t.lens[e++]=8;for(me(1,t.lens,0,288,Pe,0,t.work,{bits:9}),e=0;e<32;)t.lens[e++]=5;me(2,t.lens,0,32,Ye,0,t.work,{bits:5}),Ge=!1}t.lencode=Pe,t.lenbits=9,t.distcode=Ye,t.distbits=5},We=(t,e,a,i)=>{let n;const s=t.state;return null===s.window&&(s.wsize=1<<s.wbits,s.wnext=0,s.whave=0,s.window=new Uint8Array(s.wsize)),i>=s.wsize?(s.window.set(e.subarray(a-s.wsize,a),0),s.wnext=0,s.whave=s.wsize):(n=s.wsize-s.wnext,n>i&&(n=i),s.window.set(e.subarray(a-i,a-i+n),s.wnext),(i-=n)?(s.window.set(e.subarray(a-i,a),0),s.wnext=i,s.whave=s.wsize):(s.wnext+=n,s.wnext===s.wsize&&(s.wnext=0),s.whave<s.wsize&&(s.whave+=n))),0};var qe={inflateReset:He,inflateReset2:je,inflateResetKeep:Me,inflateInit:t=>Ke(t,15),inflateInit2:Ke,inflate:(t,e)=>{let a,i,n,s,r,o,l,h,d,_,f,c,u,w,m,b,g,p,k,v,y,x,z=0;const A=new Uint8Array(4);let E,R;const Z=new Uint8Array([16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15]);if(Ce(t)||!t.output||!t.input&&0!==t.avail_in)return xe;a=t.state,a.mode===Se&&(a.mode=De),r=t.next_out,n=t.output,l=t.avail_out,s=t.next_in,i=t.input,o=t.avail_in,h=a.hold,d=a.bits,_=o,f=l,x=ke;t:for(;;)switch(a.mode){case Ze:if(0===a.wrap){a.mode=De;break}for(;d<16;){if(0===o)break t;o--,h+=i[s++]<<d,d+=8}if(2&a.wrap&&35615===h){0===a.wbits&&(a.wbits=15),a.check=0,A[0]=255&h,A[1]=h>>>8&255,a.check=H(a.check,A,2,0),h=0,d=0,a.mode=16181;break}if(a.head&&(a.head.done=!1),!(1&a.wrap)||(((255&h)<<8)+(h>>8))%31){t.msg="incorrect header check",a.mode=Le;break}if((15&h)!==Re){t.msg="unknown compression method",a.mode=Le;break}if(h>>>=4,d-=4,y=8+(15&h),0===a.wbits&&(a.wbits=y),y>15||y>a.wbits){t.msg="invalid window size",a.mode=Le;break}a.dmax=1<<a.wbits,a.flags=0,t.adler=a.check=1,a.mode=512&h?16189:Se,h=0,d=0;break;case 16181:for(;d<16;){if(0===o)break t;o--,h+=i[s++]<<d,d+=8}if(a.flags=h,(255&a.flags)!==Re){t.msg="unknown compression method",a.mode=Le;break}if(57344&a.flags){t.msg="unknown header flags set",a.mode=Le;break}a.head&&(a.head.text=h>>8&1),512&a.flags&&4&a.wrap&&(A[0]=255&h,A[1]=h>>>8&255,a.check=H(a.check,A,2,0)),h=0,d=0,a.mode=16182;case 16182:for(;d<32;){if(0===o)break t;o--,h+=i[s++]<<d,d+=8}a.head&&(a.head.time=h),512&a.flags&&4&a.wrap&&(A[0]=255&h,A[1]=h>>>8&255,A[2]=h>>>16&255,A[3]=h>>>24&255,a.check=H(a.check,A,4,0)),h=0,d=0,a.mode=16183;case 16183:for(;d<16;){if(0===o)break t;o--,h+=i[s++]<<d,d+=8}a.head&&(a.head.xflags=255&h,a.head.os=h>>8),512&a.flags&&4&a.wrap&&(A[0]=255&h,A[1]=h>>>8&255,a.check=H(a.check,A,2,0)),h=0,d=0,a.mode=16184;case 16184:if(1024&a.flags){for(;d<16;){if(0===o)break t;o--,h+=i[s++]<<d,d+=8}a.length=h,a.head&&(a.head.extra_len=h),512&a.flags&&4&a.wrap&&(A[0]=255&h,A[1]=h>>>8&255,a.check=H(a.check,A,2,0)),h=0,d=0}else a.head&&(a.head.extra=null);a.mode=16185;case 16185:if(1024&a.flags&&(c=a.length,c>o&&(c=o),c&&(a.head&&(y=a.head.extra_len-a.length,a.head.extra||(a.head.extra=new Uint8Array(a.head.extra_len)),a.head.extra.set(i.subarray(s,s+c),y)),512&a.flags&&4&a.wrap&&(a.check=H(a.check,i,c,s)),o-=c,s+=c,a.length-=c),a.length))break t;a.length=0,a.mode=16186;case 16186:if(2048&a.flags){if(0===o)break t;c=0;do{y=i[s+c++],a.head&&y&&a.length<65536&&(a.head.name+=String.fromCharCode(y))}while(y&&c<o);if(512&a.flags&&4&a.wrap&&(a.check=H(a.check,i,c,s)),o-=c,s+=c,y)break t}else a.head&&(a.head.name=null);a.length=0,a.mode=16187;case 16187:if(4096&a.flags){if(0===o)break t;c=0;do{y=i[s+c++],a.head&&y&&a.length<65536&&(a.head.comment+=String.fromCharCode(y))}while(y&&c<o);if(512&a.flags&&4&a.wrap&&(a.check=H(a.check,i,c,s)),o-=c,s+=c,y)break t}else a.head&&(a.head.comment=null);a.mode=16188;case 16188:if(512&a.flags){for(;d<16;){if(0===o)break t;o--,h+=i[s++]<<d,d+=8}if(4&a.wrap&&h!==(65535&a.check)){t.msg="header crc mismatch",a.mode=Le;break}h=0,d=0}a.head&&(a.head.hcrc=a.flags>>9&1,a.head.done=!0),t.adler=a.check=0,a.mode=Se;break;case 16189:for(;d<32;){if(0===o)break t;o--,h+=i[s++]<<d,d+=8}t.adler=a.check=Ne(h),h=0,d=0,a.mode=Ue;case Ue:if(0===a.havedict)return t.next_out=r,t.avail_out=l,t.next_in=s,t.avail_in=o,a.hold=h,a.bits=d,ye;t.adler=a.check=1,a.mode=Se;case Se:if(e===ge||e===pe)break t;case De:if(a.last){h>>>=7&d,d-=7&d,a.mode=Fe;break}for(;d<3;){if(0===o)break t;o--,h+=i[s++]<<d,d+=8}switch(a.last=1&h,h>>>=1,d-=1,3&h){case 0:a.mode=16193;break;case 1:if(Xe(a),a.mode=Oe,e===pe){h>>>=2,d-=2;break t}break;case 2:a.mode=16196;break;case 3:t.msg="invalid block type",a.mode=Le}h>>>=2,d-=2;break;case 16193:for(h>>>=7&d,d-=7&d;d<32;){if(0===o)break t;o--,h+=i[s++]<<d,d+=8}if((65535&h)!=(h>>>16^65535)){t.msg="invalid stored block lengths",a.mode=Le;break}if(a.length=65535&h,h=0,d=0,a.mode=Te,e===pe)break t;case Te:a.mode=16195;case 16195:if(c=a.length,c){if(c>o&&(c=o),c>l&&(c=l),0===c)break t;n.set(i.subarray(s,s+c),r),o-=c,s+=c,l-=c,r+=c,a.length-=c;break}a.mode=Se;break;case 16196:for(;d<14;){if(0===o)break t;o--,h+=i[s++]<<d,d+=8}if(a.nlen=257+(31&h),h>>>=5,d-=5,a.ndist=1+(31&h),h>>>=5,d-=5,a.ncode=4+(15&h),h>>>=4,d-=4,a.nlen>286||a.ndist>30){t.msg="too many length or distance symbols",a.mode=Le;break}a.have=0,a.mode=16197;case 16197:for(;a.have<a.ncode;){for(;d<3;){if(0===o)break t;o--,h+=i[s++]<<d,d+=8}a.lens[Z[a.have++]]=7&h,h>>>=3,d-=3}for(;a.have<19;)a.lens[Z[a.have++]]=0;if(a.lencode=a.lendyn,a.lenbits=7,E={bits:a.lenbits},x=me(0,a.lens,0,19,a.lencode,0,a.work,E),a.lenbits=E.bits,x){t.msg="invalid code lengths set",a.mode=Le;break}a.have=0,a.mode=16198;case 16198:for(;a.have<a.nlen+a.ndist;){for(;z=a.lencode[h&(1<<a.lenbits)-1],m=z>>>24,b=z>>>16&255,g=65535&z,!(m<=d);){if(0===o)break t;o--,h+=i[s++]<<d,d+=8}if(g<16)h>>>=m,d-=m,a.lens[a.have++]=g;else{if(16===g){for(R=m+2;d<R;){if(0===o)break t;o--,h+=i[s++]<<d,d+=8}if(h>>>=m,d-=m,0===a.have){t.msg="invalid bit length repeat",a.mode=Le;break}y=a.lens[a.have-1],c=3+(3&h),h>>>=2,d-=2}else if(17===g){for(R=m+3;d<R;){if(0===o)break t;o--,h+=i[s++]<<d,d+=8}h>>>=m,d-=m,y=0,c=3+(7&h),h>>>=3,d-=3}else{for(R=m+7;d<R;){if(0===o)break t;o--,h+=i[s++]<<d,d+=8}h>>>=m,d-=m,y=0,c=11+(127&h),h>>>=7,d-=7}if(a.have+c>a.nlen+a.ndist){t.msg="invalid bit length repeat",a.mode=Le;break}for(;c--;)a.lens[a.have++]=y}}if(a.mode===Le)break;if(0===a.lens[256]){t.msg="invalid code -- missing end-of-block",a.mode=Le;break}if(a.lenbits=9,E={bits:a.lenbits},x=me(1,a.lens,0,a.nlen,a.lencode,0,a.work,E),a.lenbits=E.bits,x){t.msg="invalid literal/lengths set",a.mode=Le;break}if(a.distbits=6,a.distcode=a.distdyn,E={bits:a.distbits},x=me(2,a.lens,a.nlen,a.ndist,a.distcode,0,a.work,E),a.distbits=E.bits,x){t.msg="invalid distances set",a.mode=Le;break}if(a.mode=Oe,e===pe)break t;case Oe:a.mode=Ie;case Ie:if(o>=6&&l>=258){t.next_out=r,t.avail_out=l,t.next_in=s,t.avail_in=o,a.hold=h,a.bits=d,de(t,f),r=t.next_out,n=t.output,l=t.avail_out,s=t.next_in,i=t.input,o=t.avail_in,h=a.hold,d=a.bits,a.mode===Se&&(a.back=-1);break}for(a.back=0;z=a.lencode[h&(1<<a.lenbits)-1],m=z>>>24,b=z>>>16&255,g=65535&z,!(m<=d);){if(0===o)break t;o--,h+=i[s++]<<d,d+=8}if(b&&0==(240&b)){for(p=m,k=b,v=g;z=a.lencode[v+((h&(1<<p+k)-1)>>p)],m=z>>>24,b=z>>>16&255,g=65535&z,!(p+m<=d);){if(0===o)break t;o--,h+=i[s++]<<d,d+=8}h>>>=p,d-=p,a.back+=p}if(h>>>=m,d-=m,a.back+=m,a.length=g,0===b){a.mode=16205;break}if(32&b){a.back=-1,a.mode=Se;break}if(64&b){t.msg="invalid literal/length code",a.mode=Le;break}a.extra=15&b,a.mode=16201;case 16201:if(a.extra){for(R=a.extra;d<R;){if(0===o)break t;o--,h+=i[s++]<<d,d+=8}a.length+=h&(1<<a.extra)-1,h>>>=a.extra,d-=a.extra,a.back+=a.extra}a.was=a.length,a.mode=16202;case 16202:for(;z=a.distcode[h&(1<<a.distbits)-1],m=z>>>24,b=z>>>16&255,g=65535&z,!(m<=d);){if(0===o)break t;o--,h+=i[s++]<<d,d+=8}if(0==(240&b)){for(p=m,k=b,v=g;z=a.distcode[v+((h&(1<<p+k)-1)>>p)],m=z>>>24,b=z>>>16&255,g=65535&z,!(p+m<=d);){if(0===o)break t;o--,h+=i[s++]<<d,d+=8}h>>>=p,d-=p,a.back+=p}if(h>>>=m,d-=m,a.back+=m,64&b){t.msg="invalid distance code",a.mode=Le;break}a.offset=g,a.extra=15&b,a.mode=16203;case 16203:if(a.extra){for(R=a.extra;d<R;){if(0===o)break t;o--,h+=i[s++]<<d,d+=8}a.offset+=h&(1<<a.extra)-1,h>>>=a.extra,d-=a.extra,a.back+=a.extra}if(a.offset>a.dmax){t.msg="invalid distance too far back",a.mode=Le;break}a.mode=16204;case 16204:if(0===l)break t;if(c=f-l,a.offset>c){if(c=a.offset-c,c>a.whave&&a.sane){t.msg="invalid distance too far back",a.mode=Le;break}c>a.wnext?(c-=a.wnext,u=a.wsize-c):u=a.wnext-c,c>a.length&&(c=a.length),w=a.window}else w=n,u=r-a.offset,c=a.length;c>l&&(c=l),l-=c,a.length-=c;do{n[r++]=w[u++]}while(--c);0===a.length&&(a.mode=Ie);break;case 16205:if(0===l)break t;n[r++]=a.length,l--,a.mode=Ie;break;case Fe:if(a.wrap){for(;d<32;){if(0===o)break t;o--,h|=i[s++]<<d,d+=8}if(f-=l,t.total_out+=f,a.total+=f,4&a.wrap&&f&&(t.adler=a.check=a.flags?H(a.check,n,f,r-f):C(a.check,n,f,r-f)),f=l,4&a.wrap&&(a.flags?h:Ne(h))!==a.check){t.msg="incorrect data check",a.mode=Le;break}h=0,d=0}a.mode=16207;case 16207:if(a.wrap&&a.flags){for(;d<32;){if(0===o)break t;o--,h+=i[s++]<<d,d+=8}if(4&a.wrap&&h!==(4294967295&a.total)){t.msg="incorrect length check",a.mode=Le;break}h=0,d=0}a.mode=16208;case 16208:x=ve;break t;case Le:x=ze;break t;case 16210:return Ae;default:return xe}return t.next_out=r,t.avail_out=l,t.next_in=s,t.avail_in=o,a.hold=h,a.bits=d,(a.wsize||f!==t.avail_out&&a.mode<Le&&(a.mode<Fe||e!==be))&&We(t,t.output,t.next_out,f-t.avail_out),_-=t.avail_in,f-=t.avail_out,t.total_in+=_,t.total_out+=f,a.total+=f,4&a.wrap&&f&&(t.adler=a.check=a.flags?H(a.check,n,f,t.next_out-f):C(a.check,n,f,t.next_out-f)),t.data_type=a.bits+(a.last?64:0)+(a.mode===Se?128:0)+(a.mode===Oe||a.mode===Te?256:0),(0===_&&0===f||e===be)&&x===ke&&(x=Ee),x},inflateEnd:t=>{if(Ce(t))return xe;let e=t.state;return e.window&&(e.window=null),t.state=null,ke},inflateGetHeader:(t,e)=>{if(Ce(t))return xe;const a=t.state;return 0==(2&a.wrap)?xe:(a.head=e,e.done=!1,ke)},inflateSetDictionary:(t,e)=>{const a=e.length;let i,n,s;return Ce(t)?xe:(i=t.state,0!==i.wrap&&i.mode!==Ue?xe:i.mode===Ue&&(n=1,n=C(n,e,a,0),n!==i.check)?ze:(s=We(t,e,a,a),s?(i.mode=16210,Ae):(i.havedict=1,ke)))},inflateInfo:"pako inflate (from Nodeca project)"};var Je=function(){this.text=0,this.time=0,this.xflags=0,this.os=0,this.extra=null,this.extra_len=0,this.name="",this.comment="",this.hcrc=0,this.done=!1};const Qe=Object.prototype.toString,{Z_NO_FLUSH:Ve,Z_FINISH:$e,Z_OK:ta,Z_STREAM_END:ea,Z_NEED_DICT:aa,Z_STREAM_ERROR:ia,Z_DATA_ERROR:na,Z_MEM_ERROR:sa}=K;function ra(t){this.options=jt({chunkSize:65536,windowBits:15,to:""},t||{});const e=this.options;e.raw&&e.windowBits>=0&&e.windowBits<16&&(e.windowBits=-e.windowBits,0===e.windowBits&&(e.windowBits=-15)),!(e.windowBits>=0&&e.windowBits<16)||t&&t.windowBits||(e.windowBits+=32),e.windowBits>15&&e.windowBits<48&&0==(15&e.windowBits)&&(e.windowBits|=15),this.err=0,this.msg="",this.ended=!1,this.chunks=[],this.strm=new qt,this.strm.avail_out=0;let a=qe.inflateInit2(this.strm,e.windowBits);if(a!==ta)throw new Error(j[a]);if(this.header=new Je,qe.inflateGetHeader(this.strm,this.header),e.dictionary&&("string"==typeof e.dictionary?e.dictionary=Gt(e.dictionary):"[object ArrayBuffer]"===Qe.call(e.dictionary)&&(e.dictionary=new Uint8Array(e.dictionary)),e.raw&&(a=qe.inflateSetDictionary(this.strm,e.dictionary),a!==ta)))throw new Error(j[a])}function oa(t,e){const a=new ra(e);if(a.push(t),a.err)throw a.msg||j[a.err];return a.result}ra.prototype.push=function(t,e){const a=this.strm,i=this.options.chunkSize,n=this.options.dictionary;let s,r,o;if(this.ended)return!1;for(r=e===~~e?e:!0===e?$e:Ve,"[object ArrayBuffer]"===Qe.call(t)?a.input=new Uint8Array(t):a.input=t,a.next_in=0,a.avail_in=a.input.length;;){for(0===a.avail_out&&(a.output=new Uint8Array(i),a.next_out=0,a.avail_out=i),s=qe.inflate(a,r),s===aa&&n&&(s=qe.inflateSetDictionary(a,n),s===ta?s=qe.inflate(a,r):s===na&&(s=aa));a.avail_in>0&&s===ea&&a.state.wrap>0&&0!==t[a.next_in];)qe.inflateReset(a),s=qe.inflate(a,r);switch(s){case ia:case na:case aa:case sa:return this.onEnd(s),this.ended=!0,!1}if(o=a.avail_out,a.next_out&&(0===a.avail_out||s===ea))if("string"===this.options.to){let t=Wt(a.output,a.next_out),e=a.next_out-t,n=Xt(a.output,t);a.next_out=e,a.avail_out=i-e,e&&a.output.set(a.output.subarray(t,t+e),0),this.onData(n)}else this.onData(a.output.length===a.next_out?a.output:a.output.subarray(0,a.next_out));if(s!==ta||0!==o){if(s===ea)return s=qe.inflateEnd(this.strm),this.onEnd(s),this.ended=!0,!0;if(0===a.avail_in)break}}return!0},ra.prototype.onData=function(t){this.chunks.push(t)},ra.prototype.onEnd=function(t){t===ta&&("string"===this.options.to?this.result=this.chunks.join(""):this.result=Kt(this.chunks)),this.chunks=[],this.err=t,this.msg=this.strm.msg};var la={Inflate:ra,inflate:oa,inflateRaw:function(t,e){return(e=e||{}).raw=!0,oa(t,e)},ungzip:oa,constants:K};const{Deflate:ha,deflate:da,deflateRaw:_a,gzip:fa}=le,{Inflate:ca,inflate:ua,inflateRaw:wa,ungzip:ma}=la;var ba=ha,ga=da,pa=_a,ka=fa,va=ca,ya=ua,xa=wa,za=ma,Aa=K,Ea={Deflate:ba,deflate:ga,deflateRaw:pa,gzip:ka,Inflate:va,inflate:ya,inflateRaw:xa,ungzip:za,constants:Aa};t.Deflate=ba,t.Inflate=va,t.constants=Aa,t.default=Ea,t.deflate=ga,t.deflateRaw=pa,t.gzip=ka,t.inflate=ya,t.inflateRaw=xa,t.ungzip=za,Object.defineProperty(t,"__esModule",{value:!0})}));

  // jsencrypt RSA 库（UMD，挂到 globalThis.JSEncrypt）
  /*! For license information please see jsencrypt.min.js.LICENSE.txt */
!function(t,e){"object"==typeof exports&&"object"==typeof module?module.exports=e():"function"==typeof define&&define.amd?define([],e):"object"==typeof exports?exports.JSEncrypt=e():t.JSEncrypt=e()}(window,(()=>(()=>{var t={155:t=>{var e,i,r=t.exports={};function n(){throw new Error("setTimeout has not been defined")}function s(){throw new Error("clearTimeout has not been defined")}function o(t){if(e===setTimeout)return setTimeout(t,0);if((e===n||!e)&&setTimeout)return e=setTimeout,setTimeout(t,0);try{return e(t,0)}catch(i){try{return e.call(null,t,0)}catch(i){return e.call(this,t,0)}}}!function(){try{e="function"==typeof setTimeout?setTimeout:n}catch(t){e=n}try{i="function"==typeof clearTimeout?clearTimeout:s}catch(t){i=s}}();var h,a=[],u=!1,c=-1;function f(){u&&h&&(u=!1,h.length?a=h.concat(a):c=-1,a.length&&l())}function l(){if(!u){var t=o(f);u=!0;for(var e=a.length;e;){for(h=a,a=[];++c<e;)h&&h[c].run();c=-1,e=a.length}h=null,u=!1,function(t){if(i===clearTimeout)return clearTimeout(t);if((i===s||!i)&&clearTimeout)return i=clearTimeout,clearTimeout(t);try{return i(t)}catch(e){try{return i.call(null,t)}catch(e){return i.call(this,t)}}}(t)}}function p(t,e){this.fun=t,this.array=e}function g(){}r.nextTick=function(t){var e=new Array(arguments.length-1);if(arguments.length>1)for(var i=1;i<arguments.length;i++)e[i-1]=arguments[i];a.push(new p(t,e)),1!==a.length||u||o(l)},p.prototype.run=function(){this.fun.apply(null,this.array)},r.title="browser",r.browser=!0,r.env={},r.argv=[],r.version="",r.versions={},r.on=g,r.addListener=g,r.once=g,r.off=g,r.removeListener=g,r.removeAllListeners=g,r.emit=g,r.prependListener=g,r.prependOnceListener=g,r.listeners=function(t){return[]},r.binding=function(t){throw new Error("process.binding is not supported")},r.cwd=function(){return"/"},r.chdir=function(t){throw new Error("process.chdir is not supported")},r.umask=function(){return 0}}},e={};function i(r){var n=e[r];if(void 0!==n)return n.exports;var s=e[r]={exports:{}};return t[r](s,s.exports,i),s.exports}i.d=(t,e)=>{for(var r in e)i.o(e,r)&&!i.o(t,r)&&Object.defineProperty(t,r,{enumerable:!0,get:e[r]})},i.o=(t,e)=>Object.prototype.hasOwnProperty.call(t,e);var r={};return(()=>{"use strict";i.d(r,{default:()=>ct});var t="0123456789abcdefghijklmnopqrstuvwxyz";function e(e){return t.charAt(e)}function n(t,e){return t&e}function s(t,e){return t|e}function o(t,e){return t^e}function h(t,e){return t&~e}function a(t){if(0==t)return-1;var e=0;return 0==(65535&t)&&(t>>=16,e+=16),0==(255&t)&&(t>>=8,e+=8),0==(15&t)&&(t>>=4,e+=4),0==(3&t)&&(t>>=2,e+=2),0==(1&t)&&++e,e}function u(t){for(var e=0;0!=t;)t&=t-1,++e;return e}var c,f="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",l="=";function p(t){var e,i,r="";for(e=0;e+3<=t.length;e+=3)i=parseInt(t.substring(e,e+3),16),r+=f.charAt(i>>6)+f.charAt(63&i);for(e+1==t.length?(i=parseInt(t.substring(e,e+1),16),r+=f.charAt(i<<2)):e+2==t.length&&(i=parseInt(t.substring(e,e+2),16),r+=f.charAt(i>>2)+f.charAt((3&i)<<4));(3&r.length)>0;)r+=l;return r}function g(t){var i,r="",n=0,s=0;for(i=0;i<t.length&&t.charAt(i)!=l;++i){var o=f.indexOf(t.charAt(i));o<0||(0==n?(r+=e(o>>2),s=3&o,n=1):1==n?(r+=e(s<<2|o>>4),s=15&o,n=2):2==n?(r+=e(s),r+=e(o>>2),s=3&o,n=3):(r+=e(s<<2|o>>4),r+=e(15&o),n=0))}return 1==n&&(r+=e(s<<2)),r}var d,v={decode:function(t){var e;if(void 0===d){var i="= \f\n\r\t \u2028\u2029";for(d=Object.create(null),e=0;e<64;++e)d["ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".charAt(e)]=e;for(d["-"]=62,d._=63,e=0;e<i.length;++e)d[i.charAt(e)]=-1}var r=[],n=0,s=0;for(e=0;e<t.length;++e){var o=t.charAt(e);if("="==o)break;if(-1!=(o=d[o])){if(void 0===o)throw new Error("Illegal character at offset "+e);n|=o,++s>=4?(r[r.length]=n>>16,r[r.length]=n>>8&255,r[r.length]=255&n,n=0,s=0):n<<=6}}switch(s){case 1:throw new Error("Base64 encoding incomplete: at least 2 bits missing");case 2:r[r.length]=n>>10;break;case 3:r[r.length]=n>>16,r[r.length]=n>>8&255}return r},re:/-----BEGIN [^-]+-----([A-Za-z0-9+\/=\s]+)-----END [^-]+-----|begin-base64[^\n]+\n([A-Za-z0-9+\/=\s]+)====/,unarmor:function(t){var e=v.re.exec(t);if(e)if(e[1])t=e[1];else{if(!e[2])throw new Error("RegExp out of sync");t=e[2]}return v.decode(t)}},m=1e13,y=function(){function t(t){this.buf=[+t||0]}return t.prototype.mulAdd=function(t,e){var i,r,n=this.buf,s=n.length;for(i=0;i<s;++i)(r=n[i]*t+e)<m?e=0:r-=(e=0|r/m)*m,n[i]=r;e>0&&(n[i]=e)},t.prototype.sub=function(t){var e,i,r=this.buf,n=r.length;for(e=0;e<n;++e)(i=r[e]-t)<0?(i+=m,t=1):t=0,r[e]=i;for(;0===r[r.length-1];)r.pop()},t.prototype.toString=function(t){if(10!=(t||10))throw new Error("only base 10 is supported");for(var e=this.buf,i=e[e.length-1].toString(),r=e.length-2;r>=0;--r)i+=(m+e[r]).toString().substring(1);return i},t.prototype.valueOf=function(){for(var t=this.buf,e=0,i=t.length-1;i>=0;--i)e=e*m+t[i];return e},t.prototype.simplify=function(){var t=this.buf;return 1==t.length?t[0]:this},t}(),b="…",T=/^(\d\d)(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])([01]\d|2[0-3])(?:([0-5]\d)(?:([0-5]\d)(?:[.,](\d{1,3}))?)?)?(Z|[-+](?:[0]\d|1[0-2])([0-5]\d)?)?$/,S=/^(\d\d\d\d)(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])([01]\d|2[0-3])(?:([0-5]\d)(?:([0-5]\d)(?:[.,](\d{1,3}))?)?)?(Z|[-+](?:[0]\d|1[0-2])([0-5]\d)?)?$/;function E(t,e){return t.length>e&&(t=t.substring(0,e)+b),t}var w,D=function(){function t(e,i){this.hexDigits="0123456789ABCDEF",e instanceof t?(this.enc=e.enc,this.pos=e.pos):(this.enc=e,this.pos=i)}return t.prototype.get=function(t){if(void 0===t&&(t=this.pos++),t>=this.enc.length)throw new Error("Requesting byte offset ".concat(t," on a stream of length ").concat(this.enc.length));return"string"==typeof this.enc?this.enc.charCodeAt(t):this.enc[t]},t.prototype.hexByte=function(t){return this.hexDigits.charAt(t>>4&15)+this.hexDigits.charAt(15&t)},t.prototype.hexDump=function(t,e,i){for(var r="",n=t;n<e;++n)if(r+=this.hexByte(this.get(n)),!0!==i)switch(15&n){case 7:r+="  ";break;case 15:r+="\n";break;default:r+=" "}return r},t.prototype.isASCII=function(t,e){for(var i=t;i<e;++i){var r=this.get(i);if(r<32||r>176)return!1}return!0},t.prototype.parseStringISO=function(t,e){for(var i="",r=t;r<e;++r)i+=String.fromCharCode(this.get(r));return i},t.prototype.parseStringUTF=function(t,e){for(var i="",r=t;r<e;){var n=this.get(r++);i+=n<128?String.fromCharCode(n):n>191&&n<224?String.fromCharCode((31&n)<<6|63&this.get(r++)):String.fromCharCode((15&n)<<12|(63&this.get(r++))<<6|63&this.get(r++))}return i},t.prototype.parseStringBMP=function(t,e){for(var i,r,n="",s=t;s<e;)i=this.get(s++),r=this.get(s++),n+=String.fromCharCode(i<<8|r);return n},t.prototype.parseTime=function(t,e,i){var r=this.parseStringISO(t,e),n=(i?T:S).exec(r);return n?(i&&(n[1]=+n[1],n[1]+=+n[1]<70?2e3:1900),r=n[1]+"-"+n[2]+"-"+n[3]+" "+n[4],n[5]&&(r+=":"+n[5],n[6]&&(r+=":"+n[6],n[7]&&(r+="."+n[7]))),n[8]&&(r+=" UTC","Z"!=n[8]&&(r+=n[8],n[9]&&(r+=":"+n[9]))),r):"Unrecognized time: "+r},t.prototype.parseInteger=function(t,e){for(var i,r=this.get(t),n=r>127,s=n?255:0,o="";r==s&&++t<e;)r=this.get(t);if(0==(i=e-t))return n?-1:0;if(i>4){for(o=r,i<<=3;0==(128&(+o^s));)o=+o<<1,--i;o="("+i+" bit)\n"}n&&(r-=256);for(var h=new y(r),a=t+1;a<e;++a)h.mulAdd(256,this.get(a));return o+h.toString()},t.prototype.parseBitString=function(t,e,i){for(var r=this.get(t),n="("+((e-t-1<<3)-r)+" bit)\n",s="",o=t+1;o<e;++o){for(var h=this.get(o),a=o==e-1?r:0,u=7;u>=a;--u)s+=h>>u&1?"1":"0";if(s.length>i)return n+E(s,i)}return n+s},t.prototype.parseOctetString=function(t,e,i){if(this.isASCII(t,e))return E(this.parseStringISO(t,e),i);var r=e-t,n="("+r+" byte)\n";r>(i/=2)&&(e=t+i);for(var s=t;s<e;++s)n+=this.hexByte(this.get(s));return r>i&&(n+=b),n},t.prototype.parseOID=function(t,e,i){for(var r="",n=new y,s=0,o=t;o<e;++o){var h=this.get(o);if(n.mulAdd(128,127&h),s+=7,!(128&h)){if(""===r)if((n=n.simplify())instanceof y)n.sub(80),r="2."+n.toString();else{var a=n<80?n<40?0:1:2;r=a+"."+(n-40*a)}else r+="."+n.toString();if(r.length>i)return E(r,i);n=new y,s=0}}return s>0&&(r+=".incomplete"),r},t}(),x=function(){function t(t,e,i,r,n){if(!(r instanceof R))throw new Error("Invalid tag value.");this.stream=t,this.header=e,this.length=i,this.tag=r,this.sub=n}return t.prototype.typeName=function(){switch(this.tag.tagClass){case 0:switch(this.tag.tagNumber){case 0:return"EOC";case 1:return"BOOLEAN";case 2:return"INTEGER";case 3:return"BIT_STRING";case 4:return"OCTET_STRING";case 5:return"NULL";case 6:return"OBJECT_IDENTIFIER";case 7:return"ObjectDescriptor";case 8:return"EXTERNAL";case 9:return"REAL";case 10:return"ENUMERATED";case 11:return"EMBEDDED_PDV";case 12:return"UTF8String";case 16:return"SEQUENCE";case 17:return"SET";case 18:return"NumericString";case 19:return"PrintableString";case 20:return"TeletexString";case 21:return"VideotexString";case 22:return"IA5String";case 23:return"UTCTime";case 24:return"GeneralizedTime";case 25:return"GraphicString";case 26:return"VisibleString";case 27:return"GeneralString";case 28:return"UniversalString";case 30:return"BMPString"}return"Universal_"+this.tag.tagNumber.toString();case 1:return"Application_"+this.tag.tagNumber.toString();case 2:return"["+this.tag.tagNumber.toString()+"]";case 3:return"Private_"+this.tag.tagNumber.toString()}},t.prototype.content=function(t){if(void 0===this.tag)return null;void 0===t&&(t=1/0);var e=this.posContent(),i=Math.abs(this.length);if(!this.tag.isUniversal())return null!==this.sub?"("+this.sub.length+" elem)":this.stream.parseOctetString(e,e+i,t);switch(this.tag.tagNumber){case 1:return 0===this.stream.get(e)?"false":"true";case 2:return this.stream.parseInteger(e,e+i);case 3:return this.sub?"("+this.sub.length+" elem)":this.stream.parseBitString(e,e+i,t);case 4:return this.sub?"("+this.sub.length+" elem)":this.stream.parseOctetString(e,e+i,t);case 6:return this.stream.parseOID(e,e+i,t);case 16:case 17:return null!==this.sub?"("+this.sub.length+" elem)":"(no elem)";case 12:return E(this.stream.parseStringUTF(e,e+i),t);case 18:case 19:case 20:case 21:case 22:case 26:return E(this.stream.parseStringISO(e,e+i),t);case 30:return E(this.stream.parseStringBMP(e,e+i),t);case 23:case 24:return this.stream.parseTime(e,e+i,23==this.tag.tagNumber)}return null},t.prototype.toString=function(){return this.typeName()+"@"+this.stream.pos+"[header:"+this.header+",length:"+this.length+",sub:"+(null===this.sub?"null":this.sub.length)+"]"},t.prototype.toPrettyString=function(t){void 0===t&&(t="");var e=t+this.typeName()+" @"+this.stream.pos;if(this.length>=0&&(e+="+"),e+=this.length,this.tag.tagConstructed?e+=" (constructed)":!this.tag.isUniversal()||3!=this.tag.tagNumber&&4!=this.tag.tagNumber||null===this.sub||(e+=" (encapsulates)"),e+="\n",null!==this.sub){t+="  ";for(var i=0,r=this.sub.length;i<r;++i)e+=this.sub[i].toPrettyString(t)}return e},t.prototype.posStart=function(){return this.stream.pos},t.prototype.posContent=function(){return this.stream.pos+this.header},t.prototype.posEnd=function(){return this.stream.pos+this.header+Math.abs(this.length)},t.prototype.toHexString=function(){return this.stream.hexDump(this.posStart(),this.posEnd(),!0)},t.decodeLength=function(t){var e=t.get(),i=127&e;if(i==e)return i;if(i>6)throw new Error("Length over 48 bits not supported at position "+(t.pos-1));if(0===i)return null;e=0;for(var r=0;r<i;++r)e=256*e+t.get();return e},t.prototype.getHexStringValue=function(){var t=this.toHexString(),e=2*this.header,i=2*this.length;return t.substr(e,i)},t.decode=function(e){var i;i=e instanceof D?e:new D(e,0);var r=new D(i),n=new R(i),s=t.decodeLength(i),o=i.pos,h=o-r.pos,a=null,u=function(){var e=[];if(null!==s){for(var r=o+s;i.pos<r;)e[e.length]=t.decode(i);if(i.pos!=r)throw new Error("Content size is not correct for container starting at offset "+o)}else try{for(;;){var n=t.decode(i);if(n.tag.isEOC())break;e[e.length]=n}s=o-i.pos}catch(t){throw new Error("Exception while decoding undefined length content: "+t)}return e};if(n.tagConstructed)a=u();else if(n.isUniversal()&&(3==n.tagNumber||4==n.tagNumber))try{if(3==n.tagNumber&&0!=i.get())throw new Error("BIT STRINGs with unused bits cannot encapsulate.");a=u();for(var c=0;c<a.length;++c)if(a[c].tag.isEOC())throw new Error("EOC is not supposed to be actual content.")}catch(t){a=null}if(null===a){if(null===s)throw new Error("We can't skip over an invalid tag with undefined length at offset "+o);i.pos=o+Math.abs(s)}return new t(r,h,s,n,a)},t}(),R=function(){function t(t){var e=t.get();if(this.tagClass=e>>6,this.tagConstructed=0!=(32&e),this.tagNumber=31&e,31==this.tagNumber){var i=new y;do{e=t.get(),i.mulAdd(128,127&e)}while(128&e);this.tagNumber=i.simplify()}}return t.prototype.isUniversal=function(){return 0===this.tagClass},t.prototype.isEOC=function(){return 0===this.tagClass&&0===this.tagNumber},t}(),B=[2,3,5,7,11,13,17,19,23,29,31,37,41,43,47,53,59,61,67,71,73,79,83,89,97,101,103,107,109,113,127,131,137,139,149,151,157,163,167,173,179,181,191,193,197,199,211,223,227,229,233,239,241,251,257,263,269,271,277,281,283,293,307,311,313,317,331,337,347,349,353,359,367,373,379,383,389,397,401,409,419,421,431,433,439,443,449,457,461,463,467,479,487,491,499,503,509,521,523,541,547,557,563,569,571,577,587,593,599,601,607,613,617,619,631,641,643,647,653,659,661,673,677,683,691,701,709,719,727,733,739,743,751,757,761,769,773,787,797,809,811,821,823,827,829,839,853,857,859,863,877,881,883,887,907,911,919,929,937,941,947,953,967,971,977,983,991,997],O=(1<<26)/B[B.length-1],A=function(){function t(t,e,i){null!=t&&("number"==typeof t?this.fromNumber(t,e,i):null==e&&"string"!=typeof t?this.fromString(t,256):this.fromString(t,e))}return t.prototype.toString=function(t){if(this.s<0)return"-"+this.negate().toString(t);var i;if(16==t)i=4;else if(8==t)i=3;else if(2==t)i=1;else if(32==t)i=5;else{if(4!=t)return this.toRadix(t);i=2}var r,n=(1<<i)-1,s=!1,o="",h=this.t,a=this.DB-h*this.DB%i;if(h-- >0)for(a<this.DB&&(r=this[h]>>a)>0&&(s=!0,o=e(r));h>=0;)a<i?(r=(this[h]&(1<<a)-1)<<i-a,r|=this[--h]>>(a+=this.DB-i)):(r=this[h]>>(a-=i)&n,a<=0&&(a+=this.DB,--h)),r>0&&(s=!0),s&&(o+=e(r));return s?o:"0"},t.prototype.negate=function(){var e=M();return t.ZERO.subTo(this,e),e},t.prototype.abs=function(){return this.s<0?this.negate():this},t.prototype.compareTo=function(t){var e=this.s-t.s;if(0!=e)return e;var i=this.t;if(0!=(e=i-t.t))return this.s<0?-e:e;for(;--i>=0;)if(0!=(e=this[i]-t[i]))return e;return 0},t.prototype.bitLength=function(){return this.t<=0?0:this.DB*(this.t-1)+K(this[this.t-1]^this.s&this.DM)},t.prototype.mod=function(e){var i=M();return this.abs().divRemTo(e,null,i),this.s<0&&i.compareTo(t.ZERO)>0&&e.subTo(i,i),i},t.prototype.modPowInt=function(t,e){var i;return i=t<256||e.isEven()?new I(e):new N(e),this.exp(t,i)},t.prototype.clone=function(){var t=M();return this.copyTo(t),t},t.prototype.intValue=function(){if(this.s<0){if(1==this.t)return this[0]-this.DV;if(0==this.t)return-1}else{if(1==this.t)return this[0];if(0==this.t)return 0}return(this[1]&(1<<32-this.DB)-1)<<this.DB|this[0]},t.prototype.byteValue=function(){return 0==this.t?this.s:this[0]<<24>>24},t.prototype.shortValue=function(){return 0==this.t?this.s:this[0]<<16>>16},t.prototype.signum=function(){return this.s<0?-1:this.t<=0||1==this.t&&this[0]<=0?0:1},t.prototype.toByteArray=function(){var t=this.t,e=[];e[0]=this.s;var i,r=this.DB-t*this.DB%8,n=0;if(t-- >0)for(r<this.DB&&(i=this[t]>>r)!=(this.s&this.DM)>>r&&(e[n++]=i|this.s<<this.DB-r);t>=0;)r<8?(i=(this[t]&(1<<r)-1)<<8-r,i|=this[--t]>>(r+=this.DB-8)):(i=this[t]>>(r-=8)&255,r<=0&&(r+=this.DB,--t)),0!=(128&i)&&(i|=-256),0==n&&(128&this.s)!=(128&i)&&++n,(n>0||i!=this.s)&&(e[n++]=i);return e},t.prototype.equals=function(t){return 0==this.compareTo(t)},t.prototype.min=function(t){return this.compareTo(t)<0?this:t},t.prototype.max=function(t){return this.compareTo(t)>0?this:t},t.prototype.and=function(t){var e=M();return this.bitwiseTo(t,n,e),e},t.prototype.or=function(t){var e=M();return this.bitwiseTo(t,s,e),e},t.prototype.xor=function(t){var e=M();return this.bitwiseTo(t,o,e),e},t.prototype.andNot=function(t){var e=M();return this.bitwiseTo(t,h,e),e},t.prototype.not=function(){for(var t=M(),e=0;e<this.t;++e)t[e]=this.DM&~this[e];return t.t=this.t,t.s=~this.s,t},t.prototype.shiftLeft=function(t){var e=M();return t<0?this.rShiftTo(-t,e):this.lShiftTo(t,e),e},t.prototype.shiftRight=function(t){var e=M();return t<0?this.lShiftTo(-t,e):this.rShiftTo(t,e),e},t.prototype.getLowestSetBit=function(){for(var t=0;t<this.t;++t)if(0!=this[t])return t*this.DB+a(this[t]);return this.s<0?this.t*this.DB:-1},t.prototype.bitCount=function(){for(var t=0,e=this.s&this.DM,i=0;i<this.t;++i)t+=u(this[i]^e);return t},t.prototype.testBit=function(t){var e=Math.floor(t/this.DB);return e>=this.t?0!=this.s:0!=(this[e]&1<<t%this.DB)},t.prototype.setBit=function(t){return this.changeBit(t,s)},t.prototype.clearBit=function(t){return this.changeBit(t,h)},t.prototype.flipBit=function(t){return this.changeBit(t,o)},t.prototype.add=function(t){var e=M();return this.addTo(t,e),e},t.prototype.subtract=function(t){var e=M();return this.subTo(t,e),e},t.prototype.multiply=function(t){var e=M();return this.multiplyTo(t,e),e},t.prototype.divide=function(t){var e=M();return this.divRemTo(t,e,null),e},t.prototype.remainder=function(t){var e=M();return this.divRemTo(t,null,e),e},t.prototype.divideAndRemainder=function(t){var e=M(),i=M();return this.divRemTo(t,e,i),[e,i]},t.prototype.modPow=function(t,e){var i,r,n=t.bitLength(),s=U(1);if(n<=0)return s;i=n<18?1:n<48?3:n<144?4:n<768?5:6,r=n<8?new I(e):e.isEven()?new P(e):new N(e);var o=[],h=3,a=i-1,u=(1<<i)-1;if(o[1]=r.convert(this),i>1){var c=M();for(r.sqrTo(o[1],c);h<=u;)o[h]=M(),r.mulTo(c,o[h-2],o[h]),h+=2}var f,l,p=t.t-1,g=!0,d=M();for(n=K(t[p])-1;p>=0;){for(n>=a?f=t[p]>>n-a&u:(f=(t[p]&(1<<n+1)-1)<<a-n,p>0&&(f|=t[p-1]>>this.DB+n-a)),h=i;0==(1&f);)f>>=1,--h;if((n-=h)<0&&(n+=this.DB,--p),g)o[f].copyTo(s),g=!1;else{for(;h>1;)r.sqrTo(s,d),r.sqrTo(d,s),h-=2;h>0?r.sqrTo(s,d):(l=s,s=d,d=l),r.mulTo(d,o[f],s)}for(;p>=0&&0==(t[p]&1<<n);)r.sqrTo(s,d),l=s,s=d,d=l,--n<0&&(n=this.DB-1,--p)}return r.revert(s)},t.prototype.modInverse=function(e){var i=e.isEven();if(this.isEven()&&i||0==e.signum())return t.ZERO;for(var r=e.clone(),n=this.clone(),s=U(1),o=U(0),h=U(0),a=U(1);0!=r.signum();){for(;r.isEven();)r.rShiftTo(1,r),i?(s.isEven()&&o.isEven()||(s.addTo(this,s),o.subTo(e,o)),s.rShiftTo(1,s)):o.isEven()||o.subTo(e,o),o.rShiftTo(1,o);for(;n.isEven();)n.rShiftTo(1,n),i?(h.isEven()&&a.isEven()||(h.addTo(this,h),a.subTo(e,a)),h.rShiftTo(1,h)):a.isEven()||a.subTo(e,a),a.rShiftTo(1,a);r.compareTo(n)>=0?(r.subTo(n,r),i&&s.subTo(h,s),o.subTo(a,o)):(n.subTo(r,n),i&&h.subTo(s,h),a.subTo(o,a))}return 0!=n.compareTo(t.ONE)?t.ZERO:a.compareTo(e)>=0?a.subtract(e):a.signum()<0?(a.addTo(e,a),a.signum()<0?a.add(e):a):a},t.prototype.pow=function(t){return this.exp(t,new V)},t.prototype.gcd=function(t){var e=this.s<0?this.negate():this.clone(),i=t.s<0?t.negate():t.clone();if(e.compareTo(i)<0){var r=e;e=i,i=r}var n=e.getLowestSetBit(),s=i.getLowestSetBit();if(s<0)return e;for(n<s&&(s=n),s>0&&(e.rShiftTo(s,e),i.rShiftTo(s,i));e.signum()>0;)(n=e.getLowestSetBit())>0&&e.rShiftTo(n,e),(n=i.getLowestSetBit())>0&&i.rShiftTo(n,i),e.compareTo(i)>=0?(e.subTo(i,e),e.rShiftTo(1,e)):(i.subTo(e,i),i.rShiftTo(1,i));return s>0&&i.lShiftTo(s,i),i},t.prototype.isProbablePrime=function(t){var e,i=this.abs();if(1==i.t&&i[0]<=B[B.length-1]){for(e=0;e<B.length;++e)if(i[0]==B[e])return!0;return!1}if(i.isEven())return!1;for(e=1;e<B.length;){for(var r=B[e],n=e+1;n<B.length&&r<O;)r*=B[n++];for(r=i.modInt(r);e<n;)if(r%B[e++]==0)return!1}return i.millerRabin(t)},t.prototype.copyTo=function(t){for(var e=this.t-1;e>=0;--e)t[e]=this[e];t.t=this.t,t.s=this.s},t.prototype.fromInt=function(t){this.t=1,this.s=t<0?-1:0,t>0?this[0]=t:t<-1?this[0]=t+this.DV:this.t=0},t.prototype.fromString=function(e,i){var r;if(16==i)r=4;else if(8==i)r=3;else if(256==i)r=8;else if(2==i)r=1;else if(32==i)r=5;else{if(4!=i)return void this.fromRadix(e,i);r=2}this.t=0,this.s=0;for(var n=e.length,s=!1,o=0;--n>=0;){var h=8==r?255&+e[n]:F(e,n);h<0?"-"==e.charAt(n)&&(s=!0):(s=!1,0==o?this[this.t++]=h:o+r>this.DB?(this[this.t-1]|=(h&(1<<this.DB-o)-1)<<o,this[this.t++]=h>>this.DB-o):this[this.t-1]|=h<<o,(o+=r)>=this.DB&&(o-=this.DB))}8==r&&0!=(128&+e[0])&&(this.s=-1,o>0&&(this[this.t-1]|=(1<<this.DB-o)-1<<o)),this.clamp(),s&&t.ZERO.subTo(this,this)},t.prototype.clamp=function(){for(var t=this.s&this.DM;this.t>0&&this[this.t-1]==t;)--this.t},t.prototype.dlShiftTo=function(t,e){var i;for(i=this.t-1;i>=0;--i)e[i+t]=this[i];for(i=t-1;i>=0;--i)e[i]=0;e.t=this.t+t,e.s=this.s},t.prototype.drShiftTo=function(t,e){for(var i=t;i<this.t;++i)e[i-t]=this[i];e.t=Math.max(this.t-t,0),e.s=this.s},t.prototype.lShiftTo=function(t,e){for(var i=t%this.DB,r=this.DB-i,n=(1<<r)-1,s=Math.floor(t/this.DB),o=this.s<<i&this.DM,h=this.t-1;h>=0;--h)e[h+s+1]=this[h]>>r|o,o=(this[h]&n)<<i;for(h=s-1;h>=0;--h)e[h]=0;e[s]=o,e.t=this.t+s+1,e.s=this.s,e.clamp()},t.prototype.rShiftTo=function(t,e){e.s=this.s;var i=Math.floor(t/this.DB);if(i>=this.t)e.t=0;else{var r=t%this.DB,n=this.DB-r,s=(1<<r)-1;e[0]=this[i]>>r;for(var o=i+1;o<this.t;++o)e[o-i-1]|=(this[o]&s)<<n,e[o-i]=this[o]>>r;r>0&&(e[this.t-i-1]|=(this.s&s)<<n),e.t=this.t-i,e.clamp()}},t.prototype.subTo=function(t,e){for(var i=0,r=0,n=Math.min(t.t,this.t);i<n;)r+=this[i]-t[i],e[i++]=r&this.DM,r>>=this.DB;if(t.t<this.t){for(r-=t.s;i<this.t;)r+=this[i],e[i++]=r&this.DM,r>>=this.DB;r+=this.s}else{for(r+=this.s;i<t.t;)r-=t[i],e[i++]=r&this.DM,r>>=this.DB;r-=t.s}e.s=r<0?-1:0,r<-1?e[i++]=this.DV+r:r>0&&(e[i++]=r),e.t=i,e.clamp()},t.prototype.multiplyTo=function(e,i){var r=this.abs(),n=e.abs(),s=r.t;for(i.t=s+n.t;--s>=0;)i[s]=0;for(s=0;s<n.t;++s)i[s+r.t]=r.am(0,n[s],i,s,0,r.t);i.s=0,i.clamp(),this.s!=e.s&&t.ZERO.subTo(i,i)},t.prototype.squareTo=function(t){for(var e=this.abs(),i=t.t=2*e.t;--i>=0;)t[i]=0;for(i=0;i<e.t-1;++i){var r=e.am(i,e[i],t,2*i,0,1);(t[i+e.t]+=e.am(i+1,2*e[i],t,2*i+1,r,e.t-i-1))>=e.DV&&(t[i+e.t]-=e.DV,t[i+e.t+1]=1)}t.t>0&&(t[t.t-1]+=e.am(i,e[i],t,2*i,0,1)),t.s=0,t.clamp()},t.prototype.divRemTo=function(e,i,r){var n=e.abs();if(!(n.t<=0)){var s=this.abs();if(s.t<n.t)return null!=i&&i.fromInt(0),void(null!=r&&this.copyTo(r));null==r&&(r=M());var o=M(),h=this.s,a=e.s,u=this.DB-K(n[n.t-1]);u>0?(n.lShiftTo(u,o),s.lShiftTo(u,r)):(n.copyTo(o),s.copyTo(r));var c=o.t,f=o[c-1];if(0!=f){var l=f*(1<<this.F1)+(c>1?o[c-2]>>this.F2:0),p=this.FV/l,g=(1<<this.F1)/l,d=1<<this.F2,v=r.t,m=v-c,y=null==i?M():i;for(o.dlShiftTo(m,y),r.compareTo(y)>=0&&(r[r.t++]=1,r.subTo(y,r)),t.ONE.dlShiftTo(c,y),y.subTo(o,o);o.t<c;)o[o.t++]=0;for(;--m>=0;){var b=r[--v]==f?this.DM:Math.floor(r[v]*p+(r[v-1]+d)*g);if((r[v]+=o.am(0,b,r,m,0,c))<b)for(o.dlShiftTo(m,y),r.subTo(y,r);r[v]<--b;)r.subTo(y,r)}null!=i&&(r.drShiftTo(c,i),h!=a&&t.ZERO.subTo(i,i)),r.t=c,r.clamp(),u>0&&r.rShiftTo(u,r),h<0&&t.ZERO.subTo(r,r)}}},t.prototype.invDigit=function(){if(this.t<1)return 0;var t=this[0];if(0==(1&t))return 0;var e=3&t;return(e=(e=(e=(e=e*(2-(15&t)*e)&15)*(2-(255&t)*e)&255)*(2-((65535&t)*e&65535))&65535)*(2-t*e%this.DV)%this.DV)>0?this.DV-e:-e},t.prototype.isEven=function(){return 0==(this.t>0?1&this[0]:this.s)},t.prototype.exp=function(e,i){if(e>4294967295||e<1)return t.ONE;var r=M(),n=M(),s=i.convert(this),o=K(e)-1;for(s.copyTo(r);--o>=0;)if(i.sqrTo(r,n),(e&1<<o)>0)i.mulTo(n,s,r);else{var h=r;r=n,n=h}return i.revert(r)},t.prototype.chunkSize=function(t){return Math.floor(Math.LN2*this.DB/Math.log(t))},t.prototype.toRadix=function(t){if(null==t&&(t=10),0==this.signum()||t<2||t>36)return"0";var e=this.chunkSize(t),i=Math.pow(t,e),r=U(i),n=M(),s=M(),o="";for(this.divRemTo(r,n,s);n.signum()>0;)o=(i+s.intValue()).toString(t).substr(1)+o,n.divRemTo(r,n,s);return s.intValue().toString(t)+o},t.prototype.fromRadix=function(e,i){this.fromInt(0),null==i&&(i=10);for(var r=this.chunkSize(i),n=Math.pow(i,r),s=!1,o=0,h=0,a=0;a<e.length;++a){var u=F(e,a);u<0?"-"==e.charAt(a)&&0==this.signum()&&(s=!0):(h=i*h+u,++o>=r&&(this.dMultiply(n),this.dAddOffset(h,0),o=0,h=0))}o>0&&(this.dMultiply(Math.pow(i,o)),this.dAddOffset(h,0)),s&&t.ZERO.subTo(this,this)},t.prototype.fromNumber=function(e,i,r){if("number"==typeof i)if(e<2)this.fromInt(1);else for(this.fromNumber(e,r),this.testBit(e-1)||this.bitwiseTo(t.ONE.shiftLeft(e-1),s,this),this.isEven()&&this.dAddOffset(1,0);!this.isProbablePrime(i);)this.dAddOffset(2,0),this.bitLength()>e&&this.subTo(t.ONE.shiftLeft(e-1),this);else{var n=[],o=7&e;n.length=1+(e>>3),i.nextBytes(n),o>0?n[0]&=(1<<o)-1:n[0]=0,this.fromString(n,256)}},t.prototype.bitwiseTo=function(t,e,i){var r,n,s=Math.min(t.t,this.t);for(r=0;r<s;++r)i[r]=e(this[r],t[r]);if(t.t<this.t){for(n=t.s&this.DM,r=s;r<this.t;++r)i[r]=e(this[r],n);i.t=this.t}else{for(n=this.s&this.DM,r=s;r<t.t;++r)i[r]=e(n,t[r]);i.t=t.t}i.s=e(this.s,t.s),i.clamp()},t.prototype.changeBit=function(e,i){var r=t.ONE.shiftLeft(e);return this.bitwiseTo(r,i,r),r},t.prototype.addTo=function(t,e){for(var i=0,r=0,n=Math.min(t.t,this.t);i<n;)r+=this[i]+t[i],e[i++]=r&this.DM,r>>=this.DB;if(t.t<this.t){for(r+=t.s;i<this.t;)r+=this[i],e[i++]=r&this.DM,r>>=this.DB;r+=this.s}else{for(r+=this.s;i<t.t;)r+=t[i],e[i++]=r&this.DM,r>>=this.DB;r+=t.s}e.s=r<0?-1:0,r>0?e[i++]=r:r<-1&&(e[i++]=this.DV+r),e.t=i,e.clamp()},t.prototype.dMultiply=function(t){this[this.t]=this.am(0,t-1,this,0,0,this.t),++this.t,this.clamp()},t.prototype.dAddOffset=function(t,e){if(0!=t){for(;this.t<=e;)this[this.t++]=0;for(this[e]+=t;this[e]>=this.DV;)this[e]-=this.DV,++e>=this.t&&(this[this.t++]=0),++this[e]}},t.prototype.multiplyLowerTo=function(t,e,i){var r=Math.min(this.t+t.t,e);for(i.s=0,i.t=r;r>0;)i[--r]=0;for(var n=i.t-this.t;r<n;++r)i[r+this.t]=this.am(0,t[r],i,r,0,this.t);for(n=Math.min(t.t,e);r<n;++r)this.am(0,t[r],i,r,0,e-r);i.clamp()},t.prototype.multiplyUpperTo=function(t,e,i){--e;var r=i.t=this.t+t.t-e;for(i.s=0;--r>=0;)i[r]=0;for(r=Math.max(e-this.t,0);r<t.t;++r)i[this.t+r-e]=this.am(e-r,t[r],i,0,0,this.t+r-e);i.clamp(),i.drShiftTo(1,i)},t.prototype.modInt=function(t){if(t<=0)return 0;var e=this.DV%t,i=this.s<0?t-1:0;if(this.t>0)if(0==e)i=this[0]%t;else for(var r=this.t-1;r>=0;--r)i=(e*i+this[r])%t;return i},t.prototype.millerRabin=function(e){var i=this.subtract(t.ONE),r=i.getLowestSetBit();if(r<=0)return!1;var n=i.shiftRight(r);(e=e+1>>1)>B.length&&(e=B.length);for(var s=M(),o=0;o<e;++o){s.fromInt(B[Math.floor(Math.random()*B.length)]);var h=s.modPow(n,this);if(0!=h.compareTo(t.ONE)&&0!=h.compareTo(i)){for(var a=1;a++<r&&0!=h.compareTo(i);)if(0==(h=h.modPowInt(2,this)).compareTo(t.ONE))return!1;if(0!=h.compareTo(i))return!1}}return!0},t.prototype.square=function(){var t=M();return this.squareTo(t),t},t.prototype.gcda=function(t,e){var i=this.s<0?this.negate():this.clone(),r=t.s<0?t.negate():t.clone();if(i.compareTo(r)<0){var n=i;i=r,r=n}var s=i.getLowestSetBit(),o=r.getLowestSetBit();if(o<0)e(i);else{s<o&&(o=s),o>0&&(i.rShiftTo(o,i),r.rShiftTo(o,r));var h=function(){(s=i.getLowestSetBit())>0&&i.rShiftTo(s,i),(s=r.getLowestSetBit())>0&&r.rShiftTo(s,r),i.compareTo(r)>=0?(i.subTo(r,i),i.rShiftTo(1,i)):(r.subTo(i,r),r.rShiftTo(1,r)),i.signum()>0?setTimeout(h,0):(o>0&&r.lShiftTo(o,r),setTimeout((function(){e(r)}),0))};setTimeout(h,10)}},t.prototype.fromNumberAsync=function(e,i,r,n){if("number"==typeof i)if(e<2)this.fromInt(1);else{this.fromNumber(e,r),this.testBit(e-1)||this.bitwiseTo(t.ONE.shiftLeft(e-1),s,this),this.isEven()&&this.dAddOffset(1,0);var o=this,h=function(){o.dAddOffset(2,0),o.bitLength()>e&&o.subTo(t.ONE.shiftLeft(e-1),o),o.isProbablePrime(i)?setTimeout((function(){n()}),0):setTimeout(h,0)};setTimeout(h,0)}else{var a=[],u=7&e;a.length=1+(e>>3),i.nextBytes(a),u>0?a[0]&=(1<<u)-1:a[0]=0,this.fromString(a,256)}},t}(),V=function(){function t(){}return t.prototype.convert=function(t){return t},t.prototype.revert=function(t){return t},t.prototype.mulTo=function(t,e,i){t.multiplyTo(e,i)},t.prototype.sqrTo=function(t,e){t.squareTo(e)},t}(),I=function(){function t(t){this.m=t}return t.prototype.convert=function(t){return t.s<0||t.compareTo(this.m)>=0?t.mod(this.m):t},t.prototype.revert=function(t){return t},t.prototype.reduce=function(t){t.divRemTo(this.m,null,t)},t.prototype.mulTo=function(t,e,i){t.multiplyTo(e,i),this.reduce(i)},t.prototype.sqrTo=function(t,e){t.squareTo(e),this.reduce(e)},t}(),N=function(){function t(t){this.m=t,this.mp=t.invDigit(),this.mpl=32767&this.mp,this.mph=this.mp>>15,this.um=(1<<t.DB-15)-1,this.mt2=2*t.t}return t.prototype.convert=function(t){var e=M();return t.abs().dlShiftTo(this.m.t,e),e.divRemTo(this.m,null,e),t.s<0&&e.compareTo(A.ZERO)>0&&this.m.subTo(e,e),e},t.prototype.revert=function(t){var e=M();return t.copyTo(e),this.reduce(e),e},t.prototype.reduce=function(t){for(;t.t<=this.mt2;)t[t.t++]=0;for(var e=0;e<this.m.t;++e){var i=32767&t[e],r=i*this.mpl+((i*this.mph+(t[e]>>15)*this.mpl&this.um)<<15)&t.DM;for(t[i=e+this.m.t]+=this.m.am(0,r,t,e,0,this.m.t);t[i]>=t.DV;)t[i]-=t.DV,t[++i]++}t.clamp(),t.drShiftTo(this.m.t,t),t.compareTo(this.m)>=0&&t.subTo(this.m,t)},t.prototype.mulTo=function(t,e,i){t.multiplyTo(e,i),this.reduce(i)},t.prototype.sqrTo=function(t,e){t.squareTo(e),this.reduce(e)},t}(),P=function(){function t(t){this.m=t,this.r2=M(),this.q3=M(),A.ONE.dlShiftTo(2*t.t,this.r2),this.mu=this.r2.divide(t)}return t.prototype.convert=function(t){if(t.s<0||t.t>2*this.m.t)return t.mod(this.m);if(t.compareTo(this.m)<0)return t;var e=M();return t.copyTo(e),this.reduce(e),e},t.prototype.revert=function(t){return t},t.prototype.reduce=function(t){for(t.drShiftTo(this.m.t-1,this.r2),t.t>this.m.t+1&&(t.t=this.m.t+1,t.clamp()),this.mu.multiplyUpperTo(this.r2,this.m.t+1,this.q3),this.m.multiplyLowerTo(this.q3,this.m.t+1,this.r2);t.compareTo(this.r2)<0;)t.dAddOffset(1,this.m.t+1);for(t.subTo(this.r2,t);t.compareTo(this.m)>=0;)t.subTo(this.m,t)},t.prototype.mulTo=function(t,e,i){t.multiplyTo(e,i),this.reduce(i)},t.prototype.sqrTo=function(t,e){t.squareTo(e),this.reduce(e)},t}();function M(){return new A(null)}function L(t,e){return new A(t,e)}var j="undefined"!=typeof navigator;j&&"Microsoft Internet Explorer"==navigator.appName?(A.prototype.am=function(t,e,i,r,n,s){for(var o=32767&e,h=e>>15;--s>=0;){var a=32767&this[t],u=this[t++]>>15,c=h*a+u*o;n=((a=o*a+((32767&c)<<15)+i[r]+(1073741823&n))>>>30)+(c>>>15)+h*u+(n>>>30),i[r++]=1073741823&a}return n},w=30):j&&"Netscape"!=navigator.appName?(A.prototype.am=function(t,e,i,r,n,s){for(;--s>=0;){var o=e*this[t++]+i[r]+n;n=Math.floor(o/67108864),i[r++]=67108863&o}return n},w=26):(A.prototype.am=function(t,e,i,r,n,s){for(var o=16383&e,h=e>>14;--s>=0;){var a=16383&this[t],u=this[t++]>>14,c=h*a+u*o;n=((a=o*a+((16383&c)<<14)+i[r]+n)>>28)+(c>>14)+h*u,i[r++]=268435455&a}return n},w=28),A.prototype.DB=w,A.prototype.DM=(1<<w)-1,A.prototype.DV=1<<w,A.prototype.FV=Math.pow(2,52),A.prototype.F1=52-w,A.prototype.F2=2*w-52;var q,H,C=[];for(q="0".charCodeAt(0),H=0;H<=9;++H)C[q++]=H;for(q="a".charCodeAt(0),H=10;H<36;++H)C[q++]=H;for(q="A".charCodeAt(0),H=10;H<36;++H)C[q++]=H;function F(t,e){var i=C[t.charCodeAt(e)];return null==i?-1:i}function U(t){var e=M();return e.fromInt(t),e}function K(t){var e,i=1;return 0!=(e=t>>>16)&&(t=e,i+=16),0!=(e=t>>8)&&(t=e,i+=8),0!=(e=t>>4)&&(t=e,i+=4),0!=(e=t>>2)&&(t=e,i+=2),0!=(e=t>>1)&&(t=e,i+=1),i}A.ZERO=U(0),A.ONE=U(1);var k,_,z=function(){function t(){this.i=0,this.j=0,this.S=[]}return t.prototype.init=function(t){var e,i,r;for(e=0;e<256;++e)this.S[e]=e;for(i=0,e=0;e<256;++e)i=i+this.S[e]+t[e%t.length]&255,r=this.S[e],this.S[e]=this.S[i],this.S[i]=r;this.i=0,this.j=0},t.prototype.next=function(){var t;return this.i=this.i+1&255,this.j=this.j+this.S[this.i]&255,t=this.S[this.i],this.S[this.i]=this.S[this.j],this.S[this.j]=t,this.S[t+this.S[this.i]&255]},t}(),Z=256,G=null;if(null==G){G=[],_=0;var $=void 0;if("undefined"!=typeof window&&window.crypto&&window.crypto.getRandomValues){var Y=new Uint32Array(256);for(window.crypto.getRandomValues(Y),$=0;$<Y.length;++$)G[_++]=255&Y[$]}var J=0,X=function(t){if((J=J||0)>=256||_>=Z)window.removeEventListener?window.removeEventListener("mousemove",X,!1):window.detachEvent&&window.detachEvent("onmousemove",X);else try{var e=t.x+t.y;G[_++]=255&e,J+=1}catch(t){}};"undefined"!=typeof window&&(window.addEventListener?window.addEventListener("mousemove",X,!1):window.attachEvent&&window.attachEvent("onmousemove",X))}function Q(){if(null==k){for(k=new z;_<Z;){var t=Math.floor(65536*Math.random());G[_++]=255&t}for(k.init(G),_=0;_<G.length;++_)G[_]=0;_=0}return k.next()}var W=function(){function t(){}return t.prototype.nextBytes=function(t){for(var e=0;e<t.length;++e)t[e]=Q()},t}(),tt=function(){function t(){this.n=null,this.e=0,this.d=null,this.p=null,this.q=null,this.dmp1=null,this.dmq1=null,this.coeff=null}return t.prototype.doPublic=function(t){return t.modPowInt(this.e,this.n)},t.prototype.doPrivate=function(t){if(null==this.p||null==this.q)return t.modPow(this.d,this.n);for(var e=t.mod(this.p).modPow(this.dmp1,this.p),i=t.mod(this.q).modPow(this.dmq1,this.q);e.compareTo(i)<0;)e=e.add(this.p);return e.subtract(i).multiply(this.coeff).mod(this.p).multiply(this.q).add(i)},t.prototype.setPublic=function(t,e){null!=t&&null!=e&&t.length>0&&e.length>0?(this.n=L(t,16),this.e=parseInt(e,16)):console.error("Invalid RSA public key")},t.prototype.encrypt=function(t){var e=this.n.bitLength()+7>>3,i=function(t,e){if(e<t.length+11)return console.error("Message too long for RSA"),null;for(var i=[],r=t.length-1;r>=0&&e>0;){var n=t.charCodeAt(r--);n<128?i[--e]=n:n>127&&n<2048?(i[--e]=63&n|128,i[--e]=n>>6|192):(i[--e]=63&n|128,i[--e]=n>>6&63|128,i[--e]=n>>12|224)}i[--e]=0;for(var s=new W,o=[];e>2;){for(o[0]=0;0==o[0];)s.nextBytes(o);i[--e]=o[0]}return i[--e]=2,i[--e]=0,new A(i)}(t,e);if(null==i)return null;var r=this.doPublic(i);if(null==r)return null;for(var n=r.toString(16),s=n.length,o=0;o<2*e-s;o++)n="0"+n;return n},t.prototype.setPrivate=function(t,e,i){null!=t&&null!=e&&t.length>0&&e.length>0?(this.n=L(t,16),this.e=parseInt(e,16),this.d=L(i,16)):console.error("Invalid RSA private key")},t.prototype.setPrivateEx=function(t,e,i,r,n,s,o,h){null!=t&&null!=e&&t.length>0&&e.length>0?(this.n=L(t,16),this.e=parseInt(e,16),this.d=L(i,16),this.p=L(r,16),this.q=L(n,16),this.dmp1=L(s,16),this.dmq1=L(o,16),this.coeff=L(h,16)):console.error("Invalid RSA private key")},t.prototype.generate=function(t,e){var i=new W,r=t>>1;this.e=parseInt(e,16);for(var n=new A(e,16);;){for(;this.p=new A(t-r,1,i),0!=this.p.subtract(A.ONE).gcd(n).compareTo(A.ONE)||!this.p.isProbablePrime(10););for(;this.q=new A(r,1,i),0!=this.q.subtract(A.ONE).gcd(n).compareTo(A.ONE)||!this.q.isProbablePrime(10););if(this.p.compareTo(this.q)<=0){var s=this.p;this.p=this.q,this.q=s}var o=this.p.subtract(A.ONE),h=this.q.subtract(A.ONE),a=o.multiply(h);if(0==a.gcd(n).compareTo(A.ONE)){this.n=this.p.multiply(this.q),this.d=n.modInverse(a),this.dmp1=this.d.mod(o),this.dmq1=this.d.mod(h),this.coeff=this.q.modInverse(this.p);break}}},t.prototype.decrypt=function(t){var e=L(t,16),i=this.doPrivate(e);return null==i?null:function(t,e){for(var i=t.toByteArray(),r=0;r<i.length&&0==i[r];)++r;if(i.length-r!=e-1||2!=i[r])return null;for(++r;0!=i[r];)if(++r>=i.length)return null;for(var n="";++r<i.length;){var s=255&i[r];s<128?n+=String.fromCharCode(s):s>191&&s<224?(n+=String.fromCharCode((31&s)<<6|63&i[r+1]),++r):(n+=String.fromCharCode((15&s)<<12|(63&i[r+1])<<6|63&i[r+2]),r+=2)}return n}(i,this.n.bitLength()+7>>3)},t.prototype.generateAsync=function(t,e,i){var r=new W,n=t>>1;this.e=parseInt(e,16);var s=new A(e,16),o=this,h=function(){var e=function(){if(o.p.compareTo(o.q)<=0){var t=o.p;o.p=o.q,o.q=t}var e=o.p.subtract(A.ONE),r=o.q.subtract(A.ONE),n=e.multiply(r);0==n.gcd(s).compareTo(A.ONE)?(o.n=o.p.multiply(o.q),o.d=s.modInverse(n),o.dmp1=o.d.mod(e),o.dmq1=o.d.mod(r),o.coeff=o.q.modInverse(o.p),setTimeout((function(){i()}),0)):setTimeout(h,0)},a=function(){o.q=M(),o.q.fromNumberAsync(n,1,r,(function(){o.q.subtract(A.ONE).gcda(s,(function(t){0==t.compareTo(A.ONE)&&o.q.isProbablePrime(10)?setTimeout(e,0):setTimeout(a,0)}))}))},u=function(){o.p=M(),o.p.fromNumberAsync(t-n,1,r,(function(){o.p.subtract(A.ONE).gcda(s,(function(t){0==t.compareTo(A.ONE)&&o.p.isProbablePrime(10)?setTimeout(a,0):setTimeout(u,0)}))}))};setTimeout(u,0)};setTimeout(h,0)},t.prototype.sign=function(t,e,i){var r=function(t,e){if(e<t.length+22)return console.error("Message too long for RSA"),null;for(var i=e-t.length-6,r="",n=0;n<i;n+=2)r+="ff";return L("0001"+r+"00"+t,16)}((et[i]||"")+e(t).toString(),this.n.bitLength()/4);if(null==r)return null;var n=this.doPrivate(r);if(null==n)return null;var s=n.toString(16);return 0==(1&s.length)?s:"0"+s},t.prototype.verify=function(t,e,i){var r=L(e,16),n=this.doPublic(r);return null==n?null:function(t){for(var e in et)if(et.hasOwnProperty(e)){var i=et[e],r=i.length;if(t.substr(0,r)==i)return t.substr(r)}return t}(n.toString(16).replace(/^1f+00/,""))==i(t).toString()},t}(),et={md2:"3020300c06082a864886f70d020205000410",md5:"3020300c06082a864886f70d020505000410",sha1:"3021300906052b0e03021a05000414",sha224:"302d300d06096086480165030402040500041c",sha256:"3031300d060960864801650304020105000420",sha384:"3041300d060960864801650304020205000430",sha512:"3051300d060960864801650304020305000440",ripemd160:"3021300906052b2403020105000414"},it={};it.lang={extend:function(t,e,i){if(!e||!t)throw new Error("YAHOO.lang.extend failed, please check that all dependencies are included.");var r=function(){};if(r.prototype=e.prototype,t.prototype=new r,t.prototype.constructor=t,t.superclass=e.prototype,e.prototype.constructor==Object.prototype.constructor&&(e.prototype.constructor=e),i){var n;for(n in i)t.prototype[n]=i[n];var s=function(){},o=["toString","valueOf"];try{/MSIE/.test(navigator.userAgent)&&(s=function(t,e){for(n=0;n<o.length;n+=1){var i=o[n],r=e[i];"function"==typeof r&&r!=Object.prototype[i]&&(t[i]=r)}})}catch(t){}s(t.prototype,i)}}};var rt={};void 0!==rt.asn1&&rt.asn1||(rt.asn1={}),rt.asn1.ASN1Util=new function(){this.integerToByteHex=function(t){var e=t.toString(16);return e.length%2==1&&(e="0"+e),e},this.bigIntToMinTwosComplementsHex=function(t){var e=t.toString(16);if("-"!=e.substr(0,1))e.length%2==1?e="0"+e:e.match(/^[0-7]/)||(e="00"+e);else{var i=e.substr(1).length;i%2==1?i+=1:e.match(/^[0-7]/)||(i+=2);for(var r="",n=0;n<i;n++)r+="f";e=new A(r,16).xor(t).add(A.ONE).toString(16).replace(/^-/,"")}return e},this.getPEMStringFromHex=function(t,e){return hextopem(t,e)},this.newObject=function(t){var e=rt.asn1,i=e.DERBoolean,r=e.DERInteger,n=e.DERBitString,s=e.DEROctetString,o=e.DERNull,h=e.DERObjectIdentifier,a=e.DEREnumerated,u=e.DERUTF8String,c=e.DERNumericString,f=e.DERPrintableString,l=e.DERTeletexString,p=e.DERIA5String,g=e.DERUTCTime,d=e.DERGeneralizedTime,v=e.DERSequence,m=e.DERSet,y=e.DERTaggedObject,b=e.ASN1Util.newObject,T=Object.keys(t);if(1!=T.length)throw"key of param shall be only one.";var S=T[0];if(-1==":bool:int:bitstr:octstr:null:oid:enum:utf8str:numstr:prnstr:telstr:ia5str:utctime:gentime:seq:set:tag:".indexOf(":"+S+":"))throw"undefined key: "+S;if("bool"==S)return new i(t[S]);if("int"==S)return new r(t[S]);if("bitstr"==S)return new n(t[S]);if("octstr"==S)return new s(t[S]);if("null"==S)return new o(t[S]);if("oid"==S)return new h(t[S]);if("enum"==S)return new a(t[S]);if("utf8str"==S)return new u(t[S]);if("numstr"==S)return new c(t[S]);if("prnstr"==S)return new f(t[S]);if("telstr"==S)return new l(t[S]);if("ia5str"==S)return new p(t[S]);if("utctime"==S)return new g(t[S]);if("gentime"==S)return new d(t[S]);if("seq"==S){for(var E=t[S],w=[],D=0;D<E.length;D++){var x=b(E[D]);w.push(x)}return new v({array:w})}if("set"==S){for(E=t[S],w=[],D=0;D<E.length;D++)x=b(E[D]),w.push(x);return new m({array:w})}if("tag"==S){var R=t[S];if("[object Array]"===Object.prototype.toString.call(R)&&3==R.length){var B=b(R[2]);return new y({tag:R[0],explicit:R[1],obj:B})}var O={};if(void 0!==R.explicit&&(O.explicit=R.explicit),void 0!==R.tag&&(O.tag=R.tag),void 0===R.obj)throw"obj shall be specified for 'tag'.";return O.obj=b(R.obj),new y(O)}},this.jsonToASN1HEX=function(t){return this.newObject(t).getEncodedHex()}},rt.asn1.ASN1Util.oidHexToInt=function(t){for(var e="",i=parseInt(t.substr(0,2),16),r=(e=Math.floor(i/40)+"."+i%40,""),n=2;n<t.length;n+=2){var s=("00000000"+parseInt(t.substr(n,2),16).toString(2)).slice(-8);r+=s.substr(1,7),"0"==s.substr(0,1)&&(e=e+"."+new A(r,2).toString(10),r="")}return e},rt.asn1.ASN1Util.oidIntToHex=function(t){var e=function(t){var e=t.toString(16);return 1==e.length&&(e="0"+e),e},i=function(t){var i="",r=new A(t,10).toString(2),n=7-r.length%7;7==n&&(n=0);for(var s="",o=0;o<n;o++)s+="0";for(r=s+r,o=0;o<r.length-1;o+=7){var h=r.substr(o,7);o!=r.length-7&&(h="1"+h),i+=e(parseInt(h,2))}return i};if(!t.match(/^[0-9.]+$/))throw"malformed oid string: "+t;var r="",n=t.split("."),s=40*parseInt(n[0])+parseInt(n[1]);r+=e(s),n.splice(0,2);for(var o=0;o<n.length;o++)r+=i(n[o]);return r},rt.asn1.ASN1Object=function(){this.getLengthHexFromValue=function(){if(void 0===this.hV||null==this.hV)throw"this.hV is null or undefined.";if(this.hV.length%2==1)throw"value hex must be even length: n="+"".length+",v="+this.hV;var t=this.hV.length/2,e=t.toString(16);if(e.length%2==1&&(e="0"+e),t<128)return e;var i=e.length/2;if(i>15)throw"ASN.1 length too long to represent by 8x: n = "+t.toString(16);return(128+i).toString(16)+e},this.getEncodedHex=function(){return(null==this.hTLV||this.isModified)&&(this.hV=this.getFreshValueHex(),this.hL=this.getLengthHexFromValue(),this.hTLV=this.hT+this.hL+this.hV,this.isModified=!1),this.hTLV},this.getValueHex=function(){return this.getEncodedHex(),this.hV},this.getFreshValueHex=function(){return""}},rt.asn1.DERAbstractString=function(t){rt.asn1.DERAbstractString.superclass.constructor.call(this),this.getString=function(){return this.s},this.setString=function(t){this.hTLV=null,this.isModified=!0,this.s=t,this.hV=stohex(this.s)},this.setStringHex=function(t){this.hTLV=null,this.isModified=!0,this.s=null,this.hV=t},this.getFreshValueHex=function(){return this.hV},void 0!==t&&("string"==typeof t?this.setString(t):void 0!==t.str?this.setString(t.str):void 0!==t.hex&&this.setStringHex(t.hex))},it.lang.extend(rt.asn1.DERAbstractString,rt.asn1.ASN1Object),rt.asn1.DERAbstractTime=function(t){rt.asn1.DERAbstractTime.superclass.constructor.call(this),this.localDateToUTC=function(t){return utc=t.getTime()+6e4*t.getTimezoneOffset(),new Date(utc)},this.formatDate=function(t,e,i){var r=this.zeroPadding,n=this.localDateToUTC(t),s=String(n.getFullYear());"utc"==e&&(s=s.substr(2,2));var o=s+r(String(n.getMonth()+1),2)+r(String(n.getDate()),2)+r(String(n.getHours()),2)+r(String(n.getMinutes()),2)+r(String(n.getSeconds()),2);if(!0===i){var h=n.getMilliseconds();if(0!=h){var a=r(String(h),3);o=o+"."+(a=a.replace(/[0]+$/,""))}}return o+"Z"},this.zeroPadding=function(t,e){return t.length>=e?t:new Array(e-t.length+1).join("0")+t},this.getString=function(){return this.s},this.setString=function(t){this.hTLV=null,this.isModified=!0,this.s=t,this.hV=stohex(t)},this.setByDateValue=function(t,e,i,r,n,s){var o=new Date(Date.UTC(t,e-1,i,r,n,s,0));this.setByDate(o)},this.getFreshValueHex=function(){return this.hV}},it.lang.extend(rt.asn1.DERAbstractTime,rt.asn1.ASN1Object),rt.asn1.DERAbstractStructured=function(t){rt.asn1.DERAbstractString.superclass.constructor.call(this),this.setByASN1ObjectArray=function(t){this.hTLV=null,this.isModified=!0,this.asn1Array=t},this.appendASN1Object=function(t){this.hTLV=null,this.isModified=!0,this.asn1Array.push(t)},this.asn1Array=new Array,void 0!==t&&void 0!==t.array&&(this.asn1Array=t.array)},it.lang.extend(rt.asn1.DERAbstractStructured,rt.asn1.ASN1Object),rt.asn1.DERBoolean=function(){rt.asn1.DERBoolean.superclass.constructor.call(this),this.hT="01",this.hTLV="0101ff"},it.lang.extend(rt.asn1.DERBoolean,rt.asn1.ASN1Object),rt.asn1.DERInteger=function(t){rt.asn1.DERInteger.superclass.constructor.call(this),this.hT="02",this.setByBigInteger=function(t){this.hTLV=null,this.isModified=!0,this.hV=rt.asn1.ASN1Util.bigIntToMinTwosComplementsHex(t)},this.setByInteger=function(t){var e=new A(String(t),10);this.setByBigInteger(e)},this.setValueHex=function(t){this.hV=t},this.getFreshValueHex=function(){return this.hV},void 0!==t&&(void 0!==t.bigint?this.setByBigInteger(t.bigint):void 0!==t.int?this.setByInteger(t.int):"number"==typeof t?this.setByInteger(t):void 0!==t.hex&&this.setValueHex(t.hex))},it.lang.extend(rt.asn1.DERInteger,rt.asn1.ASN1Object),rt.asn1.DERBitString=function(t){if(void 0!==t&&void 0!==t.obj){var e=rt.asn1.ASN1Util.newObject(t.obj);t.hex="00"+e.getEncodedHex()}rt.asn1.DERBitString.superclass.constructor.call(this),this.hT="03",this.setHexValueIncludingUnusedBits=function(t){this.hTLV=null,this.isModified=!0,this.hV=t},this.setUnusedBitsAndHexValue=function(t,e){if(t<0||7<t)throw"unused bits shall be from 0 to 7: u = "+t;var i="0"+t;this.hTLV=null,this.isModified=!0,this.hV=i+e},this.setByBinaryString=function(t){var e=8-(t=t.replace(/0+$/,"")).length%8;8==e&&(e=0);for(var i=0;i<=e;i++)t+="0";var r="";for(i=0;i<t.length-1;i+=8){var n=t.substr(i,8),s=parseInt(n,2).toString(16);1==s.length&&(s="0"+s),r+=s}this.hTLV=null,this.isModified=!0,this.hV="0"+e+r},this.setByBooleanArray=function(t){for(var e="",i=0;i<t.length;i++)1==t[i]?e+="1":e+="0";this.setByBinaryString(e)},this.newFalseArray=function(t){for(var e=new Array(t),i=0;i<t;i++)e[i]=!1;return e},this.getFreshValueHex=function(){return this.hV},void 0!==t&&("string"==typeof t&&t.toLowerCase().match(/^[0-9a-f]+$/)?this.setHexValueIncludingUnusedBits(t):void 0!==t.hex?this.setHexValueIncludingUnusedBits(t.hex):void 0!==t.bin?this.setByBinaryString(t.bin):void 0!==t.array&&this.setByBooleanArray(t.array))},it.lang.extend(rt.asn1.DERBitString,rt.asn1.ASN1Object),rt.asn1.DEROctetString=function(t){if(void 0!==t&&void 0!==t.obj){var e=rt.asn1.ASN1Util.newObject(t.obj);t.hex=e.getEncodedHex()}rt.asn1.DEROctetString.superclass.constructor.call(this,t),this.hT="04"},it.lang.extend(rt.asn1.DEROctetString,rt.asn1.DERAbstractString),rt.asn1.DERNull=function(){rt.asn1.DERNull.superclass.constructor.call(this),this.hT="05",this.hTLV="0500"},it.lang.extend(rt.asn1.DERNull,rt.asn1.ASN1Object),rt.asn1.DERObjectIdentifier=function(t){var e=function(t){var e=t.toString(16);return 1==e.length&&(e="0"+e),e},i=function(t){var i="",r=new A(t,10).toString(2),n=7-r.length%7;7==n&&(n=0);for(var s="",o=0;o<n;o++)s+="0";for(r=s+r,o=0;o<r.length-1;o+=7){var h=r.substr(o,7);o!=r.length-7&&(h="1"+h),i+=e(parseInt(h,2))}return i};rt.asn1.DERObjectIdentifier.superclass.constructor.call(this),this.hT="06",this.setValueHex=function(t){this.hTLV=null,this.isModified=!0,this.s=null,this.hV=t},this.setValueOidString=function(t){if(!t.match(/^[0-9.]+$/))throw"malformed oid string: "+t;var r="",n=t.split("."),s=40*parseInt(n[0])+parseInt(n[1]);r+=e(s),n.splice(0,2);for(var o=0;o<n.length;o++)r+=i(n[o]);this.hTLV=null,this.isModified=!0,this.s=null,this.hV=r},this.setValueName=function(t){var e=rt.asn1.x509.OID.name2oid(t);if(""===e)throw"DERObjectIdentifier oidName undefined: "+t;this.setValueOidString(e)},this.getFreshValueHex=function(){return this.hV},void 0!==t&&("string"==typeof t?t.match(/^[0-2].[0-9.]+$/)?this.setValueOidString(t):this.setValueName(t):void 0!==t.oid?this.setValueOidString(t.oid):void 0!==t.hex?this.setValueHex(t.hex):void 0!==t.name&&this.setValueName(t.name))},it.lang.extend(rt.asn1.DERObjectIdentifier,rt.asn1.ASN1Object),rt.asn1.DEREnumerated=function(t){rt.asn1.DEREnumerated.superclass.constructor.call(this),this.hT="0a",this.setByBigInteger=function(t){this.hTLV=null,this.isModified=!0,this.hV=rt.asn1.ASN1Util.bigIntToMinTwosComplementsHex(t)},this.setByInteger=function(t){var e=new A(String(t),10);this.setByBigInteger(e)},this.setValueHex=function(t){this.hV=t},this.getFreshValueHex=function(){return this.hV},void 0!==t&&(void 0!==t.int?this.setByInteger(t.int):"number"==typeof t?this.setByInteger(t):void 0!==t.hex&&this.setValueHex(t.hex))},it.lang.extend(rt.asn1.DEREnumerated,rt.asn1.ASN1Object),rt.asn1.DERUTF8String=function(t){rt.asn1.DERUTF8String.superclass.constructor.call(this,t),this.hT="0c"},it.lang.extend(rt.asn1.DERUTF8String,rt.asn1.DERAbstractString),rt.asn1.DERNumericString=function(t){rt.asn1.DERNumericString.superclass.constructor.call(this,t),this.hT="12"},it.lang.extend(rt.asn1.DERNumericString,rt.asn1.DERAbstractString),rt.asn1.DERPrintableString=function(t){rt.asn1.DERPrintableString.superclass.constructor.call(this,t),this.hT="13"},it.lang.extend(rt.asn1.DERPrintableString,rt.asn1.DERAbstractString),rt.asn1.DERTeletexString=function(t){rt.asn1.DERTeletexString.superclass.constructor.call(this,t),this.hT="14"},it.lang.extend(rt.asn1.DERTeletexString,rt.asn1.DERAbstractString),rt.asn1.DERIA5String=function(t){rt.asn1.DERIA5String.superclass.constructor.call(this,t),this.hT="16"},it.lang.extend(rt.asn1.DERIA5String,rt.asn1.DERAbstractString),rt.asn1.DERUTCTime=function(t){rt.asn1.DERUTCTime.superclass.constructor.call(this,t),this.hT="17",this.setByDate=function(t){this.hTLV=null,this.isModified=!0,this.date=t,this.s=this.formatDate(this.date,"utc"),this.hV=stohex(this.s)},this.getFreshValueHex=function(){return void 0===this.date&&void 0===this.s&&(this.date=new Date,this.s=this.formatDate(this.date,"utc"),this.hV=stohex(this.s)),this.hV},void 0!==t&&(void 0!==t.str?this.setString(t.str):"string"==typeof t&&t.match(/^[0-9]{12}Z$/)?this.setString(t):void 0!==t.hex?this.setStringHex(t.hex):void 0!==t.date&&this.setByDate(t.date))},it.lang.extend(rt.asn1.DERUTCTime,rt.asn1.DERAbstractTime),rt.asn1.DERGeneralizedTime=function(t){rt.asn1.DERGeneralizedTime.superclass.constructor.call(this,t),this.hT="18",this.withMillis=!1,this.setByDate=function(t){this.hTLV=null,this.isModified=!0,this.date=t,this.s=this.formatDate(this.date,"gen",this.withMillis),this.hV=stohex(this.s)},this.getFreshValueHex=function(){return void 0===this.date&&void 0===this.s&&(this.date=new Date,this.s=this.formatDate(this.date,"gen",this.withMillis),this.hV=stohex(this.s)),this.hV},void 0!==t&&(void 0!==t.str?this.setString(t.str):"string"==typeof t&&t.match(/^[0-9]{14}Z$/)?this.setString(t):void 0!==t.hex?this.setStringHex(t.hex):void 0!==t.date&&this.setByDate(t.date),!0===t.millis&&(this.withMillis=!0))},it.lang.extend(rt.asn1.DERGeneralizedTime,rt.asn1.DERAbstractTime),rt.asn1.DERSequence=function(t){rt.asn1.DERSequence.superclass.constructor.call(this,t),this.hT="30",this.getFreshValueHex=function(){for(var t="",e=0;e<this.asn1Array.length;e++)t+=this.asn1Array[e].getEncodedHex();return this.hV=t,this.hV}},it.lang.extend(rt.asn1.DERSequence,rt.asn1.DERAbstractStructured),rt.asn1.DERSet=function(t){rt.asn1.DERSet.superclass.constructor.call(this,t),this.hT="31",this.sortFlag=!0,this.getFreshValueHex=function(){for(var t=new Array,e=0;e<this.asn1Array.length;e++){var i=this.asn1Array[e];t.push(i.getEncodedHex())}return 1==this.sortFlag&&t.sort(),this.hV=t.join(""),this.hV},void 0!==t&&void 0!==t.sortflag&&0==t.sortflag&&(this.sortFlag=!1)},it.lang.extend(rt.asn1.DERSet,rt.asn1.DERAbstractStructured),rt.asn1.DERTaggedObject=function(t){rt.asn1.DERTaggedObject.superclass.constructor.call(this),this.hT="a0",this.hV="",this.isExplicit=!0,this.asn1Object=null,this.setASN1Object=function(t,e,i){this.hT=e,this.isExplicit=t,this.asn1Object=i,this.isExplicit?(this.hV=this.asn1Object.getEncodedHex(),this.hTLV=null,this.isModified=!0):(this.hV=null,this.hTLV=i.getEncodedHex(),this.hTLV=this.hTLV.replace(/^../,e),this.isModified=!1)},this.getFreshValueHex=function(){return this.hV},void 0!==t&&(void 0!==t.tag&&(this.hT=t.tag),void 0!==t.explicit&&(this.isExplicit=t.explicit),void 0!==t.obj&&(this.asn1Object=t.obj,this.setASN1Object(this.isExplicit,this.hT,this.asn1Object)))},it.lang.extend(rt.asn1.DERTaggedObject,rt.asn1.ASN1Object);var nt,st,ot=(nt=function(t,e){return nt=Object.setPrototypeOf||{__proto__:[]}instanceof Array&&function(t,e){t.__proto__=e}||function(t,e){for(var i in e)Object.prototype.hasOwnProperty.call(e,i)&&(t[i]=e[i])},nt(t,e)},function(t,e){if("function"!=typeof e&&null!==e)throw new TypeError("Class extends value "+String(e)+" is not a constructor or null");function i(){this.constructor=t}nt(t,e),t.prototype=null===e?Object.create(e):(i.prototype=e.prototype,new i)}),ht=function(t){function e(i){var r=t.call(this)||this;return i&&("string"==typeof i?r.parseKey(i):(e.hasPrivateKeyProperty(i)||e.hasPublicKeyProperty(i))&&r.parsePropertiesFrom(i)),r}return ot(e,t),e.prototype.parseKey=function(t){try{var e=0,i=0,r=/^\s*(?:[0-9A-Fa-f][0-9A-Fa-f]\s*)+$/.test(t)?function(t){var e;if(void 0===c){var i="0123456789ABCDEF",r=" \f\n\r\t \u2028\u2029";for(c={},e=0;e<16;++e)c[i.charAt(e)]=e;for(i=i.toLowerCase(),e=10;e<16;++e)c[i.charAt(e)]=e;for(e=0;e<r.length;++e)c[r.charAt(e)]=-1}var n=[],s=0,o=0;for(e=0;e<t.length;++e){var h=t.charAt(e);if("="==h)break;if(-1!=(h=c[h])){if(void 0===h)throw new Error("Illegal character at offset "+e);s|=h,++o>=2?(n[n.length]=s,s=0,o=0):s<<=4}}if(o)throw new Error("Hex encoding incomplete: 4 bits missing");return n}(t):v.unarmor(t),n=x.decode(r);if(3===n.sub.length&&(n=n.sub[2].sub[0]),9===n.sub.length){e=n.sub[1].getHexStringValue(),this.n=L(e,16),i=n.sub[2].getHexStringValue(),this.e=parseInt(i,16);var s=n.sub[3].getHexStringValue();this.d=L(s,16);var o=n.sub[4].getHexStringValue();this.p=L(o,16);var h=n.sub[5].getHexStringValue();this.q=L(h,16);var a=n.sub[6].getHexStringValue();this.dmp1=L(a,16);var u=n.sub[7].getHexStringValue();this.dmq1=L(u,16);var f=n.sub[8].getHexStringValue();this.coeff=L(f,16)}else{if(2!==n.sub.length)return!1;if(n.sub[0].sub){var l=n.sub[1].sub[0];e=l.sub[0].getHexStringValue(),this.n=L(e,16),i=l.sub[1].getHexStringValue(),this.e=parseInt(i,16)}else e=n.sub[0].getHexStringValue(),this.n=L(e,16),i=n.sub[1].getHexStringValue(),this.e=parseInt(i,16)}return!0}catch(t){return!1}},e.prototype.getPrivateBaseKey=function(){var t={array:[new rt.asn1.DERInteger({int:0}),new rt.asn1.DERInteger({bigint:this.n}),new rt.asn1.DERInteger({int:this.e}),new rt.asn1.DERInteger({bigint:this.d}),new rt.asn1.DERInteger({bigint:this.p}),new rt.asn1.DERInteger({bigint:this.q}),new rt.asn1.DERInteger({bigint:this.dmp1}),new rt.asn1.DERInteger({bigint:this.dmq1}),new rt.asn1.DERInteger({bigint:this.coeff})]};return new rt.asn1.DERSequence(t).getEncodedHex()},e.prototype.getPrivateBaseKeyB64=function(){return p(this.getPrivateBaseKey())},e.prototype.getPublicBaseKey=function(){var t=new rt.asn1.DERSequence({array:[new rt.asn1.DERObjectIdentifier({oid:"1.2.840.113549.1.1.1"}),new rt.asn1.DERNull]}),e=new rt.asn1.DERSequence({array:[new rt.asn1.DERInteger({bigint:this.n}),new rt.asn1.DERInteger({int:this.e})]}),i=new rt.asn1.DERBitString({hex:"00"+e.getEncodedHex()});return new rt.asn1.DERSequence({array:[t,i]}).getEncodedHex()},e.prototype.getPublicBaseKeyB64=function(){return p(this.getPublicBaseKey())},e.wordwrap=function(t,e){if(!t)return t;var i="(.{1,"+(e=e||64)+"})( +|$\n?)|(.{1,"+e+"})";return t.match(RegExp(i,"g")).join("\n")},e.prototype.getPrivateKey=function(){var t="-----BEGIN RSA PRIVATE KEY-----\n";return(t+=e.wordwrap(this.getPrivateBaseKeyB64())+"\n")+"-----END RSA PRIVATE KEY-----"},e.prototype.getPublicKey=function(){var t="-----BEGIN PUBLIC KEY-----\n";return(t+=e.wordwrap(this.getPublicBaseKeyB64())+"\n")+"-----END PUBLIC KEY-----"},e.hasPublicKeyProperty=function(t){return(t=t||{}).hasOwnProperty("n")&&t.hasOwnProperty("e")},e.hasPrivateKeyProperty=function(t){return(t=t||{}).hasOwnProperty("n")&&t.hasOwnProperty("e")&&t.hasOwnProperty("d")&&t.hasOwnProperty("p")&&t.hasOwnProperty("q")&&t.hasOwnProperty("dmp1")&&t.hasOwnProperty("dmq1")&&t.hasOwnProperty("coeff")},e.prototype.parsePropertiesFrom=function(t){this.n=t.n,this.e=t.e,t.hasOwnProperty("d")&&(this.d=t.d,this.p=t.p,this.q=t.q,this.dmp1=t.dmp1,this.dmq1=t.dmq1,this.coeff=t.coeff)},e}(tt),at=i(155),ut=void 0!==at?null===(st=at.env)||void 0===st?void 0:"3.3.2":void 0;const ct=function(){function t(t){void 0===t&&(t={}),t=t||{},this.default_key_size=t.default_key_size?parseInt(t.default_key_size,10):1024,this.default_public_exponent=t.default_public_exponent||"010001",this.log=t.log||!1,this.key=null}return t.prototype.setKey=function(t){this.log&&this.key&&console.warn("A key was already set, overriding existing."),this.key=new ht(t)},t.prototype.setPrivateKey=function(t){this.setKey(t)},t.prototype.setPublicKey=function(t){this.setKey(t)},t.prototype.decrypt=function(t){try{return this.getKey().decrypt(g(t))}catch(t){return!1}},t.prototype.encrypt=function(t){try{return p(this.getKey().encrypt(t))}catch(t){return!1}},t.prototype.sign=function(t,e,i){try{return p(this.getKey().sign(t,e,i))}catch(t){return!1}},t.prototype.verify=function(t,e,i){try{return this.getKey().verify(t,g(e),i)}catch(t){return!1}},t.prototype.getKey=function(t){if(!this.key){if(this.key=new ht,t&&"[object Function]"==={}.toString.call(t))return void this.key.generateAsync(this.default_key_size,this.default_public_exponent,t);this.key.generate(this.default_key_size,this.default_public_exponent)}return this.key},t.prototype.getPrivateKey=function(){return this.getKey().getPrivateKey()},t.prototype.getPrivateKeyB64=function(){return this.getKey().getPrivateBaseKeyB64()},t.prototype.getPublicKey=function(){return this.getKey().getPublicKey()},t.prototype.getPublicKeyB64=function(){return this.getKey().getPublicBaseKeyB64()},t.version=ut,t}()})(),r.default})()));

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

  // RSA：把书源的 key 转成 PEM（兼容 "n,e" hex 与已有 PEM）
  function __hexToBytes(hex) {
    var s = String(hex || "").replace(/[^0-9A-Fa-f]/g, "");
    if (s.length % 2) s = "0" + s;
    var bytes = [];
    for (var i = 0; i < s.length; i += 2) bytes.push(parseInt(s.substr(i, 2), 16));
    return bytes;
  }
  function __derLength(len) {
    if (len < 128) return [len];
    var out = [], l = len, tmp = [];
    while (l > 0) { tmp.unshift(l & 0xFF); l >>= 8; }
    out.push(0x80 | tmp.length);
    return out.concat(tmp);
  }
  function __der(tag, content) { return [tag].concat(__derLength(content.length), content); }
  function __intBytes(bytes) {
    var b = bytes.slice();
    while (b.length > 1 && b[0] === 0) b.shift();
    if (b[0] & 0x80) b.unshift(0);
    return b;
  }
  function __nEToPem(key) {
    var parts = String(key).split(",");
    var n = __hexToBytes(parts[0] || "");
    var e = __hexToBytes(parts[1] || "010001");
    var inner = __der(0x02, __intBytes(n)).concat(__der(0x02, __intBytes(e)));
    var seq = __der(0x30, inner);
    var bitStr = [0].concat(seq);
    var algId = __der(0x30, [0x06, 9, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01].concat(__der(0x05, [])));
    var spki = __der(0x30, algId.concat(__der(0x03, bitStr)));
    var b64 = btoa(String.fromCharCode.apply(null, spki));
    var pem = "";
    for (var i = 0; i < b64.length; i += 64) pem += b64.substr(i, 64) + "\n";
    return "-----BEGIN PUBLIC KEY-----\n" + pem + "-----END PUBLIC KEY-----";
  }
  function __normalizePem(key) {
    var k = String(key || "").trim();
    if (k.indexOf("BEGIN") >= 0) return k;
    if (k.indexOf(",") >= 0) return __nEToPem(k);
    return k;
  }
  // book/chapter 对象包装：补齐 legado 原版 BookBean/ChapterBean 的 JS 方法
  // （大灰狼等书源直接调用 book.getVariable / book.setUseReplaceRule / book.readConfig.useReplaceRule）
  globalThis.__wrapBook = function (b) {
    if (!b || typeof b !== "object") return b;
    if (typeof b.getVariable !== "function") {
      b.getVariable = function (key) {
        if (key === undefined || key === null || key === "") return this.variable || "";
        try {
          var o = JSON.parse(this.variable || "{}");
          var v = o[key];
          return v === undefined ? "" : (typeof v === "string" ? v : JSON.stringify(v));
        } catch (e) { return ""; }
      };
      b.setVariable = function (v) { this.variable = (typeof v === "string") ? v : JSON.stringify(v); return true; };
      b.setUseReplaceRule = function (v) {
        this.useReplaceRule = !!v;
        if (!this.readConfig || typeof this.readConfig !== "object") this.readConfig = {};
        this.readConfig.useReplaceRule = !!v;
        return true;
      };
      b.getUseReplaceRule = function () {
        return !!(this.readConfig && this.readConfig.useReplaceRule) || !!this.useReplaceRule;
      };
      b.getName = function () { return this.name || ""; };
      b.getAuthor = function () { return this.author || ""; };
      b.getBookUrl = function () { return this.bookUrl || ""; };
      b.getOrigin = function () { return this.origin || ""; };
      b.getDurChapterIndex = function () { return this.durChapterIndex || 0; };
      b.getDurChapterPos = function () { return this.durChapterPos || 0; };
      b.getDurChapterTitle = function () { return this.durChapterTitle || ""; };
      b.getTotalChapterNum = function () { return this.totalChapterNum || 0; };
      b.getCoverUrl = function () { return this.customCoverUrl || this.coverUrl || ""; };
      b.getCustomCoverUrl = function () { return this.customCoverUrl || ""; };
      b.getIntro = function () { return this.intro || ""; };
      b.getKind = function () { return this.kind || ""; };
      b.getLastChapter = function () { return this.lastChapter || ""; };
      b.getTag = function () { return this.tag || ""; };
      b.getGroup = function () { return this.group || ""; };
      b.getVariableComment = function () { return this.variableComment || ""; };
      if (!b.readConfig || typeof b.readConfig !== "object") b.readConfig = {};
    }
    return b;
  };
  globalThis.__wrapChapter = function (c) {
    if (!c || typeof c !== "object") return c;
    if (typeof c.getChapterUrl !== "function") {
      c.getChapterUrl = function () { return this.url || ""; };
      c.getTitle = function () { return this.title || ""; };
      c.getIndex = function () { return this.index || 0; };
      c.getBookUrl = function () { return this.bookUrl || ""; };
      c.getIsVip = function () { return !!this.isVip; };
      c.getIsPay = function () { return !!this.isPay; };
      c.getIsVolume = function () { return !!this.isVolume; };
      c.getResourceUrl = function () { return this.resourceUrl || ""; };
    }
    return c;
  };

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
  // 验证码结果回传（人工输入界面提交/取消时由 Dart 调用）
  globalThis.__resolveVerification = function (id, code) {
    if (__pendings[id]) { var r = __pendings[id]; delete __pendings[id]; r(String(code == null ? "" : code)); }
  };

  // ============================ MD5（纯 JS 实现）============================
  function __md5(str) {
    return __bsToHex(__md5bs(__bsFromUtf8(str)));
  }

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

  // ============================ 字节级哈希 / HMAC ============================
  // 对齐 legado JsEncodeUtils 的 digestHex / digestBase64Str / HMacHex / HMacBase64。
  // 书源 JS 的 java.xxx() 是同步调用，不能用异步的 WebCrypto，故这里用纯 JS 实现。
  function __bsFromUtf8(s) {
    return __bytesToStr(new TextEncoder().encode(String(s == null ? "" : s)));
  }
  function __bytesToStr(bytes) {
    var s = "";
    for (var i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i] & 0xFF);
    return s;
  }
  function __bsToHex(bs) {
    var s = "";
    for (var i = 0; i < bs.length; i++) s += ("0" + (bs.charCodeAt(i) & 0xFF).toString(16)).slice(-2);
    return s;
  }
  function __le32(n) {
    return String.fromCharCode(n & 0xFF, (n >>> 8) & 0xFF, (n >>> 16) & 0xFF, (n >>> 24) & 0xFF);
  }
  function __be32(n) {
    return String.fromCharCode((n >>> 24) & 0xFF, (n >>> 16) & 0xFF, (n >>> 8) & 0xFF, n & 0xFF);
  }
  // MD5 字节级实现：msg 为字节串（每字符 0-255），返回 little-endian 字节串。
  // 循环式标准实现（RFC 1321），按 512-bit 块逐块做 64 轮。
  function __md5bs(msg) {
    var len = msg.length;
    var wordCount = (((len + 8) >> 6) + 1) * 16;
    var M = new Array(wordCount);
    for (var i = 0; i < wordCount; i++) M[i] = 0;
    for (var i = 0; i < len; i++) M[i >> 2] |= msg.charCodeAt(i) << ((i % 4) * 8);
    M[len >> 2] |= 0x80 << ((len % 4) * 8);
    M[wordCount - 2] = len * 8;
    var K = [0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,0x6b901122,0xfd987193,0xa679438e,0x49b40821,0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391];
    var S = [7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21];
    var a = 0x67452301, b = 0xefcdab89, c = 0x98badcfe, d = 0x10325476;
    for (var off = 0; off < wordCount; off += 16) {
      var A = a, B = b, C = c, D = d;
      for (var i = 0; i < 64; i++) {
        var f, g;
        if (i < 16) { f = (B & C) | ((~B) & D); g = i; }
        else if (i < 32) { f = (B & D) | (C & (~D)); g = (5 * i + 1) % 16; }
        else if (i < 48) { f = B ^ C ^ D; g = (3 * i + 5) % 16; }
        else { f = C ^ (B | (~D)); g = (7 * i) % 16; }
        f = (f + A + K[i] + M[off + g]) | 0;
        var tmp = (B + ((f << S[i]) | (f >>> (32 - S[i])))) | 0;
        var ob = B, oc = C, od = D;
        A = od; B = tmp; C = ob; D = oc;
      }
      a = (a + A) | 0; b = (b + B) | 0; c = (c + C) | 0; d = (d + D) | 0;
    }
    return __le32(a) + __le32(b) + __le32(c) + __le32(d);
  }
  // SHA-1 字节级实现：msg 为字节串，返回 big-endian 字节串。
  function __sha1bs(msg) {
    var len = msg.length;
    var bitLen = len * 8;
    var wordCount = (((len + 8) >> 6) + 1) * 16;
    var words = new Array(wordCount);
    for (var i = 0; i < wordCount; i++) words[i] = 0;
    for (var i = 0; i < len; i++) words[i >> 2] |= msg.charCodeAt(i) << ((3 - (i % 4)) * 8);
    words[len >> 2] |= 0x80 << ((3 - (len % 4)) * 8);
    words[wordCount - 2] = Math.floor(bitLen / 0x100000000);
    words[wordCount - 1] = bitLen & 0xFFFFFFFF;
    function rotl(n, s) { return (n << s) | (n >>> (32 - s)); }
    var h0 = 0x67452301, h1 = 0xEFCDAB89, h2 = 0x98BADCFE, h3 = 0x10325476, h4 = 0xC3D2E1F0;
    for (var i = 0; i < wordCount; i += 16) {
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
    return __be32(h0) + __be32(h1) + __be32(h2) + __be32(h3) + __be32(h4);
  }
  // SHA-256 字节级实现：msg 为字节串，返回 big-endian 字节串。
  function __sha256bs(msg) {
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
    var len = msg.length;
    var bitLen = len * 8;
    var wordCount = (((len + 8) >> 6) + 1) * 16;
    var words = new Array(wordCount);
    for (var i = 0; i < wordCount; i++) words[i] = 0;
    for (var i = 0; i < len; i++) words[i >> 2] |= msg.charCodeAt(i) << ((3 - (i % 4)) * 8);
    words[len >> 2] |= 0x80 << ((3 - (len % 4)) * 8);
    words[wordCount - 2] = Math.floor(bitLen / 0x100000000);
    words[wordCount - 1] = bitLen & 0xFFFFFFFF;
    function rotr(n, s) { return (n >>> s) | (n << (32 - s)); }
    var h0 = 0x6A09E667, h1 = 0xBB67AE85, h2 = 0x3C6EF372, h3 = 0xA54FF53A;
    var h4 = 0x510E527F, h5 = 0x9B05688C, h6 = 0x1F83D9AB, h7 = 0x5BE0CD19;
    for (var i = 0; i < wordCount; i += 16) {
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
    return __be32(h0) + __be32(h1) + __be32(h2) + __be32(h3) + __be32(h4) + __be32(h5) + __be32(h6) + __be32(h7);
  }
  function __digestBs(data, algorithm) {
    var a = String(algorithm || "MD5").toUpperCase().replace(/[-_]/g, "");
    var msg = __bsFromUtf8(data);
    if (a === "SHA1") return __sha1bs(msg);
    if (a === "SHA256") return __sha256bs(msg);
    return __md5bs(msg);
  }
  function __hmacBs(data, algorithm, key) {
    var a = String(algorithm || "MD5").toUpperCase().replace(/[-_]/g, "");
    var fn = a === "SHA1" ? __sha1bs : (a === "SHA256" ? __sha256bs : __md5bs);
    var k = __bsFromUtf8(key);
    if (k.length > 64) k = fn(k);
    var ikey = "", okey = "";
    for (var i = 0; i < 64; i++) {
      var kc = i < k.length ? k.charCodeAt(i) : 0;
      ikey += String.fromCharCode(kc ^ 0x36);
      okey += String.fromCharCode(kc ^ 0x5c);
    }
    return fn(okey + fn(ikey + __bsFromUtf8(data)));
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
    base64DecodeToByteArray: function (str) {
      try { return Array.from(__b64ToBytes(String(str == null ? "" : str))); } catch (e) { return []; }
    },
    hexDecodeToByteArray: function (hex) {
      try { return Array.from(__hexToBytes(String(hex == null ? "" : hex))); } catch (e) { return []; }
    },
    md5Encode: function (str) { return __md5(String(str == null ? "" : str)); },
    md5Encode16: function (str) { return __md5(String(str == null ? "" : str)).substring(8, 24); },
    sha1Encode: function (str) { return __sha1(String(str == null ? "" : str)); },
    sha256Encode: function (str) { return __sha256(String(str == null ? "" : str)); },
    // 摘要：java.digestHex(str, "MD5"|"SHA-1"|"SHA-256") / digestBase64Str
    digestHex: function (data, algorithm) { return __bsToHex(__digestBs(data, algorithm)); },
    digestBase64Str: function (data, algorithm) { return btoa(__digestBs(data, algorithm)); },
    // HMAC：java.HMacHex(data, algorithm, key) / HMacBase64(data, algorithm, key)
    HMacHex: function (data, algorithm, key) { return __bsToHex(__hmacBs(data, algorithm, key)); },
    HMacBase64: function (data, algorithm, key) { return btoa(__hmacBs(data, algorithm, key)); },

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
      try {
        var crypt = new JSEncrypt();
        crypt.setPublicKey(__normalizePem(key));
        return crypt.encrypt(String(data == null ? "" : data)) || "";
      } catch (e) { return ""; }
    },
    rsaDecodeToString: function (data, key, transformation) {
      try {
        var crypt = new JSEncrypt();
        crypt.setPrivateKey(__normalizePem(key));
        return crypt.decrypt(String(data == null ? "" : data)) || "";
      } catch (e) { return ""; }
    },

    // gzip（WebView 环境下提供占位）
    gzipCompress: function (data) {
      try {
        var bytes = (typeof data === "string") ? new TextEncoder().encode(data) : data;
        var gz = pako.gzip(bytes);
        return btoa(String.fromCharCode.apply(null, gz));
      } catch (e) { return data; }
    },
    gzipDecompress: function (data) {
      try {
        var bytes;
        if (typeof data === "string") {
          var s = data.trim();
          if (/^[0-9A-Za-z+/=]+$/.test(s) && s.length % 4 === 0) {
            var bin = atob(s); bytes = Uint8Array.from(bin, function (c) { return c.charCodeAt(0); });
          } else {
            bytes = new TextEncoder().encode(s);
          }
        } else { bytes = data; }
        var out = pako.ungzip(bytes);
        return new TextDecoder("utf-8").decode(out);
      } catch (e) { return data; }
    },

    // 字体替换（占位）
    replaceFont: function (text, font) {
      try {
        var map = (typeof font === "string") ? JSON.parse(font) : font;
        if (!map) return text;
        var s = String(text == null ? "" : text);
        var out = "";
        for (var i = 0; i < s.length; i++) {
          var c = s[i];
          out += (map[c] !== undefined && map[c] !== null) ? map[c] : c;
        }
        return out;
      } catch (e) { return text; }
    },

    // 下载/分享/打开（走 legado:// 内部协议，原生拦截实现）
    download: function (url) {
      try { return __doXhr("legado://download?url=" + encodeURIComponent(url), { method: "GET" }); }
      catch (e) { return ""; }
    },
    share: function (text) {
      try { return __doXhr("legado://share", { method: "POST", body: String(text == null ? "" : text) }); }
      catch (e) { return false; }
    },
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

    // 脚本导入 / 文件缓存（走 legado://file 内部协议，原生文件系统实现）
    importScript: function (path) {
      try { return __doXhr("legado://file?op=read&path=" + encodeURIComponent(path), { method: "GET" }); }
      catch (e) { return ""; }
    },
    cacheFile: function (urlStr, saveTime) {
      try { return __doXhr("legado://file?op=cache&url=" + encodeURIComponent(urlStr), { method: "GET" }); }
      catch (e) { return ""; }
    },
    readTxtFile: function (path, charset) {
      try { return __doXhr("legado://file?op=read&path=" + encodeURIComponent(path), { method: "GET" }); }
      catch (e) { return ""; }
    },
    deleteFile: function (path) {
      try { __doXhr("legado://file?op=delete&path=" + encodeURIComponent(path), { method: "GET" }); return true; }
      catch (e) { return false; }
    },
    // 下载文件到缓存目录，返回相对路径（对齐 legado-E JsExtensions.downloadFile）。
    // 兼容旧签名 downloadFile(hexContent, url)：第二参存在且首参为合法 hex 时按 hex 写入。
    downloadFile: function (url, url2) {
      try {
        if (url2 != null) {
          var hex = String(url == null ? "" : url);
          if (hex.length > 0 && hex.length % 2 === 0 && /^[0-9a-fA-F]+$/.test(hex)) {
            return __doXhr("legado://file?op=writehex&url=" + encodeURIComponent(url2) + "&hex=" + encodeURIComponent(hex), { method: "GET" });
          }
        }
        return __doXhr("legado://file?op=download&url=" + encodeURIComponent(url), { method: "GET" });
      } catch (e) { return ""; }
    },

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

    // WebView 渲染：走 legado://webview 内部协议，用第二个无头 WebView 加载并等 JS 渲染后取源码
    webView: function (html, url, js, cacheFirst) {
      try {
        var target = url || "";
        if (!target) return html || "";
        var rendered = __doXhr("legado://webview?url=" + encodeURIComponent(target), { method: "GET" });
        return rendered || html || "";
      } catch (e) { return html || ""; }
    },
    webViewGetSource: function (html, url, js, sourceRegex, cacheFirst, delayTime) {
      try {
        var target = url || "";
        if (!target) return "";
        return __doXhr("legado://webview?url=" + encodeURIComponent(target), { method: "GET" });
      } catch (e) { return ""; }
    },
    webViewGetOverrideUrl: function (html, url, js, overrideUrlRegex, cacheFirst, delayTime) { return url || ""; },
    // 验证码识别：弹出人工输入界面（对齐 E SourceVerificationHelp.getVerificationResult），
    // 返回 Promise，用户提交后 resolve 输入的字符；未提交/取消 resolve 空串。
    getVerificationCode: function (imageUrl) {
      return new Promise(function (resolve) {
        var id = "v" + Date.now() + Math.floor(Math.random() * 10000);
        __pendings[id] = resolve;
        try {
          if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            window.flutter_inappwebview.callHandler("legadoVerification", JSON.stringify({
              id: id, imageUrl: String(imageUrl == null ? "" : imageUrl)
            }));
          } else {
            delete __pendings[id]; resolve("");
          }
        } catch (e) { delete __pendings[id]; resolve(""); }
        // 5 分钟无输入自动按空处理，避免 Promise 永久挂起
        setTimeout(function () {
          if (__pendings[id]) { delete __pendings[id]; resolve(""); }
        }, 300000);
      });
    },

    // 字体反爬（占位）
    queryTTF: function (data, useCache) {
      try {
        var b64 = String(data == null ? "" : data);
        // data 为 http 链接时先下载字体文件
        if (/^https?:\/\//i.test(b64)) {
          var bytes = __doXhr(b64, { method: "GET" }, "arraybuffer");
          var bin = new Uint8Array(bytes);
          var binStr = "";
          for (var i = 0; i < bin.length; i++) binStr += String.fromCharCode(bin[i]);
          b64 = btoa(binStr);
        }
        if (!b64) return null;
        var resp = __doXhr("legado://ttf", { method: "POST", body: b64 });
        return JSON.parse(resp);
      } catch (e) { return null; }
    },
    getZipStringContent: function (url, path, charset) {
      try {
        return __doXhr("legado://zip?url=" + encodeURIComponent(url) + "&path=" + encodeURIComponent(path || ""), { method: "GET" });
      } catch (e) { return ""; }
    },
    get7zStringContent: function (url, path, charset) {
      try {
        return __doXhr("legado://zip?kind=7z&url=" + encodeURIComponent(url) + "&path=" + encodeURIComponent(path || ""), { method: "GET" });
      } catch (e) { return ""; }
    },
    getRarStringContent: function (url, path, charset) {
      try {
        return __doXhr("legado://zip?kind=rar&url=" + encodeURIComponent(url) + "&path=" + encodeURIComponent(path || ""), { method: "GET" });
      } catch (e) { return ""; }
    },
    unzipFile: function (zipPath) {
      try {
        // 整包解压到 legado_files/unzip/<md5(名)>，返回相对目录（对齐 E：后续配 getTxtInFolder 使用）
        return __doXhr("legado://zip?op=unarchive&url=" + encodeURIComponent(zipPath), { method: "GET" });
      } catch (e) { return ""; }
    },
    unArchiveFile: function (zipPath) { return this.unzipFile(zipPath); },
    // 7z/rar 整包解压：Android 端走原生 libarchive 兼容实现（commons-compress/junrar），
    // 其余平台抛错让书源 try/catch 走回退分支。
    un7zFile: function (path) {
      try {
        return __doXhr("legado://zip?kind=7z&op=unarchive&url=" + encodeURIComponent(path), { method: "GET" });
      } catch (e) { throw new Error("un7zFile 失败: " + e); }
    },
    unrarFile: function (path) {
      try {
        return __doXhr("legado://zip?kind=rar&op=unarchive&url=" + encodeURIComponent(path), { method: "GET" });
      } catch (e) { throw new Error("unrarFile 失败: " + e); }
    },

    // ===== 阅读/主题/媒体接口（对齐 legado-E JsExtensions）=====
    // 无头 WebView 内无法直接读取 App 状态，原生在求值前种子注入
    // __state.readConfig / __state.theme / __state.themeMode；
    // 未注入时回退到与 lib/data/model/read_config.dart、lib/constant/app_theme.dart 一致的默认值。
    getReadBookConfig: function () {
      try {
        var rc = __state.readConfig;
        if (!rc || typeof rc !== "object") {
          rc = {
            textSize: 20, textColor: (0xFF333333 | 0), fontFamily: "", fontWeight: 400,
            textAlign: 2, lineSpacing: 2, paragraphSpacing: 1,
            paddingLeft: 16, paddingRight: 16, paddingTop: 8, paddingBottom: 8,
            bgColor: (0xFFFFF8E1 | 0), pageAnim: 0, chineseConverter: 0
          };
        }
        return JSON.stringify(rc);
      } catch (e) { return ""; }
    },
    getThemeConfig: function () {
      try {
        var t = __state.theme;
        if (!t || typeof t !== "object") {
          var dark = false;
          try { dark = !!(window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches); } catch (e2) {}
          t = {
            isDark: dark, themeMode: dark ? 2 : 1,
            seedColor: (0xFF3F5A72 | 0), fontFamily: "", fontScale: 1.0,
            dynamicColor: false, amoled: false, eink: false, foregroundOpacity: 0.18
          };
        }
        return JSON.stringify(t);
      } catch (e) { return ""; }
    },
    getThemeMode: function () {
      // 0: 跟随系统 1: 浅色 2: 深色（与 prefs theme_mode 存储一致）
      var m = __state.themeMode;
      if (m === 0 || m === 1 || m === 2) return m;
      return 0;
    },
    getReadBookConfigMap: function () {
      try { return JSON.parse(java.getReadBookConfig()); } catch (e) { return {}; }
    },
    getThemeConfigMap: function () {
      try { return JSON.parse(java.getThemeConfig()); } catch (e) { return {}; }
    },
    getTxtInFolder: function (path) {
      // 列目录内 .txt 文件；原生 legado://file 暂无 list 能力（未知 op 返回 400），
      // 失败返回 [] 让书源走回退分支，不抛异常。
      try {
        var resp = __doXhr("legado://file?op=list&path=" + encodeURIComponent(path || ""), { method: "GET" });
        var arr = JSON.parse(resp);
        return Array.isArray(arr) ? arr : [];
      } catch (e) { return []; }
    },
    openVideoPlayer: function (url, title) {
      // 原生 legado/video 播放通道待实现（MethodChannel('legado/video') Kotlin 侧未接），
      // 当前经 legado://video 内部协议转交；失败静默返回 false。
      try {
        __doXhr("legado://video?url=" + encodeURIComponent(url || "") + "&title=" + encodeURIComponent(title || ""), { method: "GET" });
        return true;
      } catch (e) { return false; }
    },

    // 对称加密：对齐 legado JsExtensions.createSymmetricCrypto(transformation, key, iv)
    // 返回 {encrypt, encryptBase64, encryptHex, decrypt, decryptStr}
    createSymmetricCrypto: function (transformation, key, iv) {
      var kb = __aesKeyBytes(key);
      var ivb = __aesIv(iv);
      var mode = String(transformation || "AES").toUpperCase();
      var useCbc = mode.indexOf("CBC") >= 0;
      function encryptBytes(data) {
        var text = (typeof data === "string") ? data : String(data);
        var dataBytes = __utf8ToBytes(text);
        var pad = 16 - (dataBytes.length % 16);
        var padded = new Uint8Array(dataBytes.length + pad);
        padded.set(dataBytes);
        for (var i = dataBytes.length; i < padded.length; i++) padded[i] = pad;
        if (useCbc) {
          return new aesjs.ModeOfOperation.cbc(kb, ivb).encrypt(padded);
        }
        return new aesjs.ModeOfOperation.ecb(kb).encrypt(padded);
      }
      function decryptBytes(bytes) {
        var data = (bytes instanceof Uint8Array) ? bytes : Uint8Array.from(bytes || []);
        var dec;
        if (useCbc) {
          dec = new aesjs.ModeOfOperation.cbc(kb, ivb).decrypt(data);
        } else {
          dec = new aesjs.ModeOfOperation.ecb(kb).decrypt(data);
        }
        return __unpadPkcs7(dec);
      }
      function bytesToB64(b) {
        var s = "";
        for (var i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
        return btoa(s);
      }
      return {
        encrypt: function (data) { return Array.from(encryptBytes(data)); },
        encryptBase64: function (data) { return bytesToB64(encryptBytes(data)); },
        encryptHex: function (data) { return __bytesToHex(encryptBytes(data)); },
        decrypt: function (bytes) { return Array.from(decryptBytes(bytes)); },
        decryptStr: function (str) {
          var s = String(str == null ? "" : str);
          var bytes;
          if (/^[0-9a-fA-F]+$/.test(s) && s.length % 2 === 0) {
            bytes = __hexToBytes(s);
          } else {
            bytes = __b64ToBytes(s);
          }
          return __bytesToUtf8(decryptBytes(bytes));
        }
      };
    },

    // 非对称加密：对齐 legado JsExtensions.createAsymmetricCrypto(transformation)
    // 返回 {setPublicKey, setPrivateKey, encrypt, encryptBase64, decrypt, decryptStr}
    createAsymmetricCrypto: function (transformation) {
      var pubKey = "", priKey = "";
      return {
        setPublicKey: function (key) { pubKey = __normalizePem(key); return this; },
        setPrivateKey: function (key) { priKey = __normalizePem(key); return this; },
        encrypt: function (data) {
          try {
            var crypt = new JSEncrypt();
            crypt.setPublicKey(pubKey);
            return crypt.encrypt(String(data == null ? "" : data)) || "";
          } catch (e) { return ""; }
        },
        encryptBase64: function (data) { return this.encrypt(data); },
        decrypt: function (data) {
          try {
            var crypt = new JSEncrypt();
            crypt.setPrivateKey(priKey);
            return crypt.decrypt(String(data == null ? "" : data)) || "";
          } catch (e) { return ""; }
        },
        decryptStr: function (data) { return this.decrypt(data); }
      };
    },

    // 签名：对齐 legado JsExtensions.createSign(algorithm)
    // 返回 {setPublicKey, setPrivateKey, sign, signHex}
    createSign: function (algorithm) {
      var pubKey = "", priKey = "";
      return {
        setPublicKey: function (key) { pubKey = __normalizePem(key); return this; },
        setPrivateKey: function (key) { priKey = __normalizePem(key); return this; },
        sign: function (data) {
          try {
            var crypt = new JSEncrypt();
            crypt.setPrivateKey(priKey);
            return crypt.sign(String(data == null ? "" : data), function (s) { return s; }, "sha256") || "";
          } catch (e) { return ""; }
        },
        signHex: function (data) {
          try {
            var crypt = new JSEncrypt();
            crypt.setPrivateKey(priKey);
            return crypt.sign(String(data == null ? "" : data), function (s) { return s; }, "sha256") || "";
          } catch (e) { return ""; }
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

  /// 尝试打开原生视频播放器（对齐 legado-E 视频播放入口）。
  ///
  /// 走 MethodChannel('legado/video') 的 invokeMethod('open', ...)；
  /// Kotlin 侧暂未实现该 channel，调用失败时静默返回 false（不抛异常），
  /// 由调用方决定回退（如使用内置 video_player_screen）。
  static Future<bool> openVideoPlayer(String url, String title) async {
    if (url.trim().isEmpty) return false;
    try {
      await const MethodChannel('legado/video')
          .invokeMethod('open', {'url': url, 'title': title});
      return true;
    } catch (e) {
      // 原生通道未实现 / 调用异常：容错降级
      return false;
    }
  }

  /// 列出 [path] 目录下的 .txt 文件（返回绝对路径，按名称排序）。
  /// 目录不存在 / 无权限 / IO 异常时返回空列表，不抛异常。
  static List<String> txtFilesInFolder(String path) {
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) return const [];
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.txt'))
          .map((f) => f.path)
          .toList()
        ..sort();
      return files;
    } catch (e) {
      return const [];
    }
  }

  /// ReadConfig 关键字段 JSON（对齐 JS 桥 java.getReadBookConfig 的返回结构）。
  static String readConfigJson(ReadConfig config) {
    return jsonEncode({
      'textSize': config.textSize,
      'textColor': config.textColor,
      'fontFamily': config.fontFamily ?? '',
      'fontWeight': config.fontWeight,
      'textAlign': config.textAlign,
      'lineSpacing': config.lineSpacing,
      'paragraphSpacing': config.paragraphSpacing,
      'paddingLeft': config.paddingLeft,
      'paddingRight': config.paddingRight,
      'paddingTop': config.paddingTop,
      'paddingBottom': config.paddingBottom,
      'bgColor': config.bgColor,
      'pageAnim': config.pageAnim,
      'chineseConverter': config.chineseConverter,
    });
  }

  /// 主题配置 JSON（对齐 JS 桥 java.getThemeConfig 的返回结构）。
  static String themeConfigJson(AppTheme theme) {
    final modeIndex = theme.themeMode.index;
    var isDark = modeIndex == 2;
    if (modeIndex == 0) {
      isDark = PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    }
    return jsonEncode({
      'isDark': isDark,
      'themeMode': modeIndex,
      'seedColor': theme.seedColor.value,
      'fontFamily': theme.fontFamily,
      'fontScale': theme.fontScale,
      'dynamicColor': theme.dynamicColor,
      'amoled': theme.amoled,
      'eink': theme.eink,
      'foregroundOpacity': theme.foregroundOpacity,
    });
  }

  /// 主题模式索引：0 跟随系统 / 1 浅色 / 2 深色（与 prefs theme_mode 存储一致）。
  static int themeModeIndex(AppTheme theme) => theme.themeMode.index;
}
