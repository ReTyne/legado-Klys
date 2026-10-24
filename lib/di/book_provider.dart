import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:legado_md3/data/model/book.dart';
import 'package:legado_md3/data/model/book_chapter.dart';
import 'package:legado_md3/data/model/db_models.dart';
import 'package:legado_md3/data/model/read_config.dart';
import '../data/local/app_database.dart';

class BookProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  List<Book> _books = [];
  List<BookGroup> _groupMeta = [];
  bool _isLoading = false;
  // 0:详细列表 1:紧凑列表 2:三列网格 3:四列紧凑网格 4:大封面
  int _bookshelfLayout = 0;
  String _currentGroup = '全部';

  List<Book> get books => _books;
  bool get isLoading => _isLoading;
  int get bookshelfLayout => _bookshelfLayout;
  String get currentGroup => _currentGroup;

  /// 阅读进度小粒度修订号：翻页等高频保存进度时只 ++ 并通知
  /// ValueListenableBuilder 监听者（书架角标/副标题局部重建），
  /// 不再触发 notifyListeners 全量重建书架。
  final ValueNotifier<int> readingRevision = ValueNotifier<int>(0);

  /// 虚拟分组名称（按书籍属性自动计算，不属于用户自定义分组）
  static const String vGroupLocal = '本地';
  static const String vGroupAudio = '音频';
  static const String vGroupVideo = '视频';
  static const String vGroupUngrouped = '未分组';

  /// 全部虚拟分组（同时决定展示顺序）
  static const List<String> virtualGroups = [
    vGroupLocal,
    vGroupAudio,
    vGroupVideo,
    vGroupUngrouped,
  ];

  /// 是否为虚拟分组
  static bool isVirtualGroup(String group) => virtualGroups.contains(group);

  /// 书籍是否命中某虚拟分组（本地/音频/视频/未分组）
  static bool inVirtualGroup(Book book, String group) {
    switch (group) {
      case vGroupLocal:
        return book.local;
      case vGroupAudio:
        return book.type == Book.typeAudio;
      case vGroupVideo:
        return book.type == Book.typeVideo;
      case vGroupUngrouped:
        return book.group == null || book.group!.isEmpty;
      default:
        return false;
    }
  }

  /// 书籍是否属于指定分组：用户分组按 group 相等，虚拟分组按属性判定
  static bool bookInGroup(Book book, String group) {
    if (group == '全部') return true;
    if (book.group == group) return true;
    return isVirtualGroup(group) && inVirtualGroup(book, group);
  }

  /// 书架分组：合并 book_groups 元数据（排序/显隐）与书籍实际分组
  List<String> displayGroups({bool hideEmpty = false}) =>
      resolveGroups(_books, _groupMeta, hideEmpty: hideEmpty);

  /// 纯函数：由书籍与分组元数据计算展示分组（首位固定“全部”，末尾追加有书的虚拟分组）
  static List<String> resolveGroups(
    List<Book> books,
    List<BookGroup> meta, {
    bool hideEmpty = false,
  }) {
    final counts = <String, int>{};
    for (final b in books) {
      final g = b.group;
      if (g != null && g.isNotEmpty) counts[g] = (counts[g] ?? 0) + 1;
    }
    final names = <String>{...meta.map((m) => m.name), ...counts.keys};
    final byName = {for (final m in meta) m.name: m};
    final ordered = names.toList()..sort((a, b) {
        final ma = byName[a];
        final mb = byName[b];
        if (ma != null && mb != null) return ma.order.compareTo(mb.order);
        if (ma != null) return -1;
        if (mb != null) return 1;
        return a.compareTo(b);
      });
    final visible = ordered.where((n) {
      if (byName[n]?.show == 0) return false;
      if (hideEmpty && (counts[n] ?? 0) == 0) return false;
      return true;
    }).toList();
    // 追加虚拟分组：仅存在命中书籍时展示，且避免与用户分组重名
    final extraVirtual = virtualGroups.where(
        (vg) => !visible.contains(vg) && books.any((b) => inVirtualGroup(b, vg)));
    return ['全部', ...visible, ...extraVirtual];
  }

  /// 兼容旧引用
  List<String> get groups => displayGroups();

  int bookCountOf(String group) => group == '全部'
      ? _books.length
      : _books.where((b) => bookInGroup(b, group)).length;

  List<Book> get filteredBooks {
    if (_currentGroup == '全部') return _books;
    return _books.where((b) => bookInGroup(b, _currentGroup)).toList();
  }

  Future<void> loadBooks() async {
    _isLoading = true;
    notifyListeners();
    _books = await _db.getAllBooks();
    _groupMeta = await _db.getBookGroups();
    // 当前分组若已被隐藏/删除，回退到全部
    if (_currentGroup != '全部' && !displayGroups().contains(_currentGroup)) {
      _currentGroup = '全部';
    }
    _isLoading = false;
    notifyListeners();
  }

  /// 读取本地持久化的视图偏好（布局、当前分组）
  Future<void> loadViewPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    var layout = prefs.getInt('bs_layout');
    layout ??= _migrateLayout(prefs);
    _bookshelfLayout = layout;
    final cg = prefs.getString('bs_currentGroup');
    if (cg != null && cg.isNotEmpty) _currentGroup = cg;
    notifyListeners();
  }

  int _migrateLayout(SharedPreferences prefs) {
    final mode = prefs.getInt('bs_layoutMode') ?? 0;
    if (mode == 1) return (prefs.getInt('bs_gridStyle') ?? 0) == 1 ? 3 : 2;
    return 0;
  }

  Future<void> addBook(Book book) async {
    await _db.insertBook(book);
    await loadBooks();
  }

  Future<void> updateBook(Book book) async {
    await _db.updateBook(book);
    final index = _books.indexWhere((b) => b.name == book.name && b.author == book.author);
    if (index != -1) {
      _books[index] = book;
      notifyListeners();
    }
  }

  Future<void> removeBook(String name, String author) async {
    await _db.deleteBook(name, author);
    await loadBooks();
  }

  Future<void> setBookshelfLayout(int layout) async {
    _bookshelfLayout = layout;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('bs_layout', layout);
  }

  Future<void> setCurrentGroup(String group) async {
    _currentGroup = group;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bs_currentGroup', group);
  }

  /// 测试用：直接注入书籍与分组元数据，绕过数据库
  @visibleForTesting
  void debugSeed(List<Book> books, {List<BookGroup> groupMeta = const []}) {
    _books = books;
    _groupMeta = groupMeta;
    notifyListeners();
  }

  Book? findBook(String name, String author) {
    try {
      return _books.firstWhere((b) => b.name == name && b.author == author);
    } catch (_) {
      return null;
    }
  }

  // 章节相关
  Future<List<BookChapter>> getChapters(Book book) async {
    return _db.getChapters(book.name, book.author);
  }

  Future<void> saveChapters(Book book, List<BookChapter> chapters) async {
    await _db.saveChapters(book.name, book.author, chapters);
  }

  Future<void> saveReadingProgress(Book book, int chapterIndex, int pos) async {
    book.durChapterIndex = chapterIndex;
    book.durChapterPos = pos;
    book.durChapterTime = DateTime.now().millisecondsSinceEpoch;
    // 同步内存列表对应项（保持同一引用语义），但不 notifyListeners：
    // 翻页保存进度属高频操作，全量通知会导致整书架重排。
    final index =
        _books.indexWhere((b) => b.name == book.name && b.author == book.author);
    if (index != -1) {
      _books[index] = book;
    }
    await _db.updateBook(book);
    readingRevision.value++;
  }

  @override
  void dispose() {
    readingRevision.dispose();
    super.dispose();
  }
}

class ReadProvider extends ChangeNotifier {
  ReadConfig _config = ReadConfig();
  bool _showMenu = false;
  double _brightness = 1.0; // 默认不压暗屏幕
  bool _loaded = false;

  static const String _prefKey = 'read_config_json';

  ReadConfig get config => _config;
  bool get showMenu => _showMenu;
  double get brightness => _brightness;

  /// 从 SharedPreferences 加载阅读配置（应用启动时调用一次）
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefKey);
      if (json != null && json.isNotEmpty) {
        _config = ReadConfig.fromJsonString(json);
      }
      _brightness = prefs.getDouble('read_brightness') ?? 1.0;
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, _config.toJsonString());
    } catch (_) {}
  }

  void setConfig(ReadConfig config) {
    _config = config;
    _persist();
    notifyListeners();
  }

  void updateConfig(void Function(ReadConfig) updater) {
    updater(_config);
    _persist();
    notifyListeners();
  }

  void toggleMenu() {
    _showMenu = !_showMenu;
    notifyListeners();
  }

  void hideMenu() {
    _showMenu = false;
    notifyListeners();
  }

  void setBrightness(double value) {
    _brightness = value;
    SharedPreferences.getInstance().then((p) => p.setDouble('read_brightness', value));
    notifyListeners();
  }

  void setTextSize(int size) {
    _config.textSize = size;
    _persist();
    notifyListeners();
  }

  void setBgColor(int color) {
    _config.bgColor = color;
    _persist();
    notifyListeners();
  }

  void setTextColor(int color) {
    _config.textColor = color;
    _persist();
    notifyListeners();
  }

  void setPageAnim(int anim) {
    _config.pageAnim = anim;
    _persist();
    notifyListeners();
  }

  void setLineSpacing(int spacing) {
    _config.lineSpacing = spacing;
    _persist();
    notifyListeners();
  }
}
