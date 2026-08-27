import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/browser_models.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import '../widgets/ai_assistant_sheet.dart';

const kHome = 'about:home';

class BrowserHome extends StatefulWidget {
  const BrowserHome({super.key});

  @override
  State<BrowserHome> createState() => _BrowserHomeState();
}

class _BrowserHomeState extends State<BrowserHome> {
  final _storage = StorageService();
  final _uuid = const Uuid();
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _homeSearchCtrl = TextEditingController();

  final List<BrowserTab> _tabs = [];
  final Map<String, WebViewController> _controllers = {};
  final Map<String, List<ConsoleLog>> _console = {};
  int _active = 0;

  List<BookmarkItem> _bookmarks = [];
  List<HistoryItem> _history = [];
  String _searchEngine = 'google';
  bool _desktopMode = false;
  bool _showConsole = false;
  double _progress = 0;
  String? _findQuery;

  static const _mobileUa =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36';
  static const _desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  static const _shortcuts = [
    _Shortcut('Google', 'https://www.google.com', Icons.search_rounded, Color(0xFF4285F4)),
    _Shortcut('Bing', 'https://www.bing.com', Icons.language_rounded, Color(0xFF008373)),
    _Shortcut('DuckDuckGo', 'https://duckduckgo.com', Icons.privacy_tip_outlined, Color(0xFFDE5833)),
    _Shortcut('百度', 'https://www.baidu.com', Icons.public_rounded, Color(0xFF2932E1)),
    _Shortcut('GitHub', 'https://github.com', Icons.code_rounded, Color(0xFF333333)),
    _Shortcut('Bilibili', 'https://www.bilibili.com', Icons.play_circle_outline, Color(0xFFFB7299)),
    _Shortcut('知乎', 'https://www.zhihu.com', Icons.forum_outlined, Color(0xFF0084FF)),
    _Shortcut('维基', 'https://zh.wikipedia.org', Icons.menu_book_rounded, Color(0xFF000000)),
  ];

  BrowserTab get tab => _tabs[_active];
  WebViewController? get ctrl => _controllers[tab.id];
  bool get isStartPage => tab.url == kHome || tab.url.startsWith('about:');

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _searchEngine = await _storage.loadSearchEngine();
    try {
      final s = context.read<SettingsService>();
      if (s.ready) _searchEngine = s.searchEngine;
    } catch (_) {}
    _bookmarks = await _storage.loadBookmarks();
    _history = await _storage.loadHistory();
    _newTab(incognito: false);
    if (mounted) setState(() {});
  }

  String _normalizeUrl(String input) {
    var t = input.trim();
    if (t.isEmpty) return kHome;
    if (t == kHome || t.startsWith('about:')) return t;

    final looksUrl = (!t.contains(' ') && t.contains('.')) ||
        t.startsWith('http://') ||
        t.startsWith('https://');

    if (looksUrl) {
      if (t.startsWith('https://')) return t;
      if (t.startsWith('http://')) return 'https://${t.substring(7)}';
      return 'https://$t';
    }

    final enc = Uri.encodeComponent(t);
    switch (_searchEngine) {
      case 'bing':
        return 'https://www.bing.com/search?q=$enc';
      case 'duck':
        return 'https://duckduckgo.com/?q=$enc';
      case 'baidu':
        return 'https://www.baidu.com/s?wd=$enc';
      default:
        return 'https://www.google.com/search?q=$enc';
    }
  }

  void _newTab({bool incognito = false, String? initialUrl}) {
    final id = _uuid.v4();
    final start = initialUrl ?? kHome;
    final t = BrowserTab(
      id: id,
      url: start,
      isIncognito: incognito,
      title: incognito ? '无痕标签' : '新标签页',
    );

    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setUserAgent(_desktopMode ? _desktopUa : _mobileUa)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (_tabs.isEmpty || _tabs[_active].id != id) return;
            setState(() => _progress = p / 100.0);
          },
          onPageStarted: (url) {
            final i = _tabs.indexWhere((e) => e.id == id);
            if (i < 0) return;
            setState(() {
              _tabs[i].isLoading = true;
              if (!url.startsWith('about:')) {
                _tabs[i].url = url;
                if (_active == i) _searchCtrl.text = url;
              }
            });
          },
          onPageFinished: (url) async {
            final i = _tabs.indexWhere((e) => e.id == id);
            if (i < 0) return;
            String title = url;
            try {
              title = await _controllers[id]?.getTitle() ?? url;
            } catch (_) {}
            final back = await _controllers[id]?.canGoBack() ?? false;
            final fwd = await _controllers[id]?.canGoForward() ?? false;
            setState(() {
              _tabs[i].isLoading = false;
              if (!url.startsWith('about:')) {
                _tabs[i].url = url;
                _tabs[i].title =
                    (title.isEmpty || title == 'about:blank') ? url : title;
                if (_active == i) {
                  _searchCtrl.text = url;
                  _progress = 0;
                }
              } else {
                _tabs[i].title = _tabs[i].isIncognito ? '无痕标签' : '新标签页';
              }
              _tabs[i].canGoBack = back;
              _tabs[i].canGoForward = fwd;
            });
            if (!_tabs[i].isIncognito &&
                !url.startsWith('about:') &&
                url.isNotEmpty) {
              _addHistory(_tabs[i].title, url);
            }
            await _injectConsoleHook(id);
            await _applyZoomTo(id);
          },
          onWebResourceError: (err) {
            _pushConsole(id, 'error', err.description);
          },
        ),
      )
      ..addJavaScriptChannel(
        'MorphConsole',
        onMessageReceived: (msg) {
          try {
            final data = jsonDecode(msg.message) as Map<String, dynamic>;
            _pushConsole(
              id,
              data['level'] as String? ?? 'log',
              data['message'] as String? ?? msg.message,
            );
          } catch (_) {
            _pushConsole(id, 'log', msg.message);
          }
        },
      );

    if (start != kHome && !start.startsWith('about:')) {
      c.loadRequest(Uri.parse(start));
    }

    _controllers[id] = c;
    _console[id] = [];
    setState(() {
      _tabs.add(t);
      _active = _tabs.length - 1;
      _searchCtrl.text = start == kHome ? '' : start;
      _homeSearchCtrl.clear();
    });
  }

  Future<void> _injectConsoleHook(String id) async {
    const js = r"""
(function(){
  if(window.__morphConsole) return;
  window.__morphConsole=1;
  function send(level,args){
    try{
      var m=[];
      for(var i=0;i<args.length;i++){
        try{m.push(typeof args[i]==='object'?JSON.stringify(args[i]):String(args[i]));}
        catch(e){m.push(String(args[i]));}
      }
      MorphConsole.postMessage(JSON.stringify({level:level,message:m.join(' ')}));
    }catch(e){}
  }
  var l=console.log,w=console.warn,e=console.error,i=console.info;
  console.log=function(){send('log',arguments);return l.apply(console,arguments);};
  console.warn=function(){send('warn',arguments);return w.apply(console,arguments);};
  console.error=function(){send('error',arguments);return e.apply(console,arguments);};
  console.info=function(){send('info',arguments);return i.apply(console,arguments);};
})();
""";
    try {
      await _controllers[id]?.runJavaScript(js);
    } catch (_) {}
  }

  void _pushConsole(String id, String level, String message) {
    final list = _console.putIfAbsent(id, () => []);
    list.insert(0, ConsoleLog(level: level, message: message));
    if (list.length > 200) list.removeLast();
    if (mounted && _showConsole && tab.id == id) setState(() {});
  }

  Future<void> _addHistory(String title, String url) async {
    _history.removeWhere((h) => h.url == url);
    _history.insert(
      0,
      HistoryItem(id: _uuid.v4(), title: title, url: url),
    );
    await _storage.saveHistory(_history);
  }

  void _closeTab(int index) {
    if (_tabs.length == 1) {
      final old = _tabs[0];
      _controllers.remove(old.id);
      _console.remove(old.id);
      _tabs.clear();
      _newTab();
      return;
    }
    final id = _tabs[index].id;
    _controllers.remove(id);
    _console.remove(id);
    setState(() {
      _tabs.removeAt(index);
      if (_active >= _tabs.length) _active = _tabs.length - 1;
      if (_active < 0) _active = 0;
      final u = _tabs[_active].url;
      _searchCtrl.text = u == kHome ? '' : u;
    });
  }

  Future<void> _go(String input) async {
    final url = _normalizeUrl(input);
    if (url == kHome) {
      setState(() {
        tab.url = kHome;
        tab.title = tab.isIncognito ? '无痕标签' : '新标签页';
        _searchCtrl.text = '';
        _progress = 0;
      });
      return;
    }
    setState(() {
      tab.url = url;
      _searchCtrl.text = url;
    });
    await ctrl?.loadRequest(Uri.parse(url));
    _searchFocus.unfocus();
  }

  Future<void> _toggleBookmark() async {
    if (isStartPage) return;
    final url = tab.url;
    final exists = _bookmarks.any((b) => b.url == url);
    if (exists) {
      _bookmarks.removeWhere((b) => b.url == url);
    } else {
      _bookmarks.insert(
        0,
        BookmarkItem(id: _uuid.v4(), title: tab.title, url: url),
      );
    }
    await _storage.saveBookmarks(_bookmarks);
    setState(() {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(exists ? '已取消收藏' : '已加入收藏')),
    );
  }

  Future<void> _viewSource() async {
    if (isStartPage) return;
    final html = await ctrl?.runJavaScriptReturningResult(
          'document.documentElement.outerHTML',
        ) ??
        '';
    var source = html.toString();
    if (source.startsWith('"') && source.endsWith('"')) {
      source = source
          .substring(1, source.length - 1)
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\"', '"')
          .replaceAll(r'\\', r'\');
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SourceScreen(title: tab.title, source: source),
      ),
    );
  }

  Future<void> _findInPage() async {
    if (isStartPage) return;
    final q = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController(text: _findQuery ?? '');
        return AlertDialog(
          title: const Text('页内查找'),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '输入关键词',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('查找'),
            ),
          ],
        );
      },
    );
    if (q == null || q.isEmpty) return;
    _findQuery = q;
    final js =
        "window.find(${jsonEncode(q)}, false, false, true, false, false, false)";
    await ctrl?.runJavaScript(js);
  }


  Future<void> _applyZoomTo(String id) async {
    try {
      final z = context.read<SettingsService>().pageZoom;
      await _controllers[id]?.runJavaScript(
        "document.documentElement.style.zoom='${z}';",
      );
    } catch (_) {}
  }

  Future<void> _applyZoomAll() async {
    final z = context.read<SettingsService>().pageZoom;
    for (final id in _controllers.keys) {
      try {
        await _controllers[id]?.runJavaScript(
          "document.documentElement.style.zoom='${z}';",
        );
      } catch (_) {}
    }
  }

  void _openAi() {
    if (isStartPage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先打开一个网页再使用 AI 助手')),
      );
      return;
    }
    final s = context.read<SettingsService>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiAssistantSheet(
        controller: ctrl,
        pageUrl: tab.url,
        pageTitle: tab.title,
        settings: s,
      ),
    );
  }

  void _openZoom() {
    final s = context.read<SettingsService>();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder: (ctx, setS) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('页面缩放', style: Theme.of(ctx).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    Text('${(s.pageZoom * 100).round()}%'),
                    Slider(
                      value: s.pageZoom,
                      min: 0.5,
                      max: 2.5,
                      divisions: 20,
                      label: '${(s.pageZoom * 100).round()}%',
                      onChanged: (v) async {
                        await s.setZoom(v);
                        setS(() {});
                        await _applyZoomAll();
                      },
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final z in [0.75, 1.0, 1.25, 1.5, 2.0])
                          ActionChip(
                            label: Text('${(z * 100).round()}%'),
                            onPressed: () async {
                              await s.setZoom(z);
                              setS(() {});
                              await _applyZoomAll();
                            },
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _openMenu() {
    final isBookmarked = _bookmarks.any((b) => b.url == tab.url);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(
                    isBookmarked ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: isBookmarked ? cs.primary : null,
                  ),
                  title: Text(isBookmarked ? '取消收藏' : '收藏此页'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleBookmark();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.bookmarks_outlined),
                  title: const Text('收藏夹'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openBookmarks();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: const Text('历史记录'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openHistory();
                  },
                ),
                ListTile(
                  leading: Icon(
                    tab.isIncognito
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                  title: Text(tab.isIncognito ? '当前为无痕' : '新建无痕标签'),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (!tab.isIncognito) _newTab(incognito: true);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.tab_rounded),
                  title: Text('标签页 (${_tabs.length})'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openTabsSheet();
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.code_rounded),
                  title: const Text('查看网页源代码'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _viewSource();
                  },
                ),
                ListTile(
                  leading: Icon(
                    _showConsole ? Icons.terminal_rounded : Icons.terminal_outlined,
                  ),
                  title: Text(_showConsole ? '隐藏控制台' : '显示控制台'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _showConsole = !_showConsole);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.search_rounded),
                  title: const Text('页内查找'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _findInPage();
                  },
                ),
                ListTile(
                  leading: Icon(
                    _desktopMode
                        ? Icons.computer_rounded
                        : Icons.phone_android_rounded,
                  ),
                  title: Text(_desktopMode ? '切换为手机版' : '切换为桌面版'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    setState(() => _desktopMode = !_desktopMode);
                    await ctrl?.setUserAgent(
                      _desktopMode ? _desktopUa : _mobileUa,
                    );
                    if (!isStartPage) await ctrl?.reload();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share_rounded),
                  title: const Text('分享'),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (!isStartPage) Share.share(tab.url, subject: tab.title);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('复制链接'),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (!isStartPage) {
                      Clipboard.setData(ClipboardData(text: tab.url));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制链接')),
                      );
                    }
                  },
                ),
                
                ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: const Text('AI 办公助手'),
                  subtitle: const Text('连接本地 Ollama / 兼容接口'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openAi();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.zoom_in_rounded),
                  title: const Text('页面缩放'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openZoom();
                  },
                ),
                ListTile(
                  leading: Icon(
                    Theme.of(context).brightness == Brightness.dark
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                  ),
                  title: const Text('浅色 / 深色 / 跟随系统'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openThemePicker();
                  },
                ),
ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('设置'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openSettings();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openTabsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (_, sc) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text('标签页', style: Theme.of(ctx).textTheme.titleLarge),
                      const Spacer(),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _newTab();
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('新建'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _newTab(incognito: true);
                        },
                        icon: const Icon(Icons.visibility_off),
                        label: const Text('无痕'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: sc,
                    itemCount: _tabs.length,
                    itemBuilder: (_, i) {
                      final t = _tabs[i];
                      final selected = i == _active;
                      return ListTile(
                        selected: selected,
                        leading: Icon(
                          t.isIncognito
                              ? Icons.visibility_off_rounded
                              : (t.url == kHome
                                  ? Icons.home_rounded
                                  : Icons.public_rounded),
                        ),
                        title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          t.url == kHome ? '起始页' : t.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _closeTab(i);
                            setState(() {});
                          },
                        ),
                        onTap: () {
                          setState(() {
                            _active = i;
                            final u = _tabs[i].url;
                            _searchCtrl.text = u == kHome ? '' : u;
                          });
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openBookmarks() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ListScreen(
          title: '收藏夹',
          empty: '还没有收藏',
          items: _bookmarks
              .map((b) => _ListEntry(title: b.title, subtitle: b.url, url: b.url))
              .toList(),
          onOpen: (url) {
            Navigator.pop(context);
            _go(url);
          },
          onDelete: (i) async {
            _bookmarks.removeAt(i);
            await _storage.saveBookmarks(_bookmarks);
            setState(() {});
          },
        ),
      ),
    );
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ListScreen(
          title: '历史记录',
          empty: '暂无历史',
          items: _history
              .map((h) => _ListEntry(title: h.title, subtitle: h.url, url: h.url))
              .toList(),
          onOpen: (url) {
            Navigator.pop(context);
            _go(url);
          },
          onDelete: (i) async {
            _history.removeAt(i);
            await _storage.saveHistory(_history);
            setState(() {});
          },
          trailingAction: TextButton(
            onPressed: () async {
              _history.clear();
              await _storage.saveHistory(_history);
              setState(() {});
              if (mounted) Navigator.pop(context);
            },
            child: const Text('清空'),
          ),
        ),
      ),
    );
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('搜索引擎'),
                subtitle: Text(_engineLabel(_searchEngine)),
                onTap: () async {
                  final v = await showModalBottomSheet<String>(
                    context: ctx,
                    builder: (d) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final e in [
                            ('google', 'Google'),
                            ('bing', 'Bing'),
                            ('duck', 'DuckDuckGo'),
                            ('baidu', '百度'),
                          ])
                            ListTile(
                              title: Text(e.$2),
                              selected: _searchEngine == e.$1,
                              onTap: () => Navigator.pop(d, e.$1),
                            ),
                        ],
                      ),
                    ),
                  );
                  if (v != null) {
                    _searchEngine = v;
                    await _storage.saveSearchEngine(v);
                    setState(() {});
                  }
                },
              ),
              ListTile(
                title: const Text('本地 AI 地址'),
                subtitle: Text(context.read<SettingsService>().aiBaseUrl),
                onTap: () async {
                  final s = context.read<SettingsService>();
                  final c = TextEditingController(text: s.aiBaseUrl);
                  final v = await showDialog<String>(
                    context: ctx,
                    builder: (d) => AlertDialog(
                      title: const Text('AI Base URL'),
                      content: TextField(
                        controller: c,
                        decoration: const InputDecoration(
                          hintText: 'http://192.168.1.x:11434',
                        ),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消')),
                        FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('保存')),
                      ],
                    ),
                  );
                  if (v != null && v.trim().isNotEmpty) await s.setAiBase(v.trim());
                },
              ),
              ListTile(
                title: const Text('AI 模型名'),
                subtitle: Text(context.read<SettingsService>().aiModel),
                onTap: () async {
                  final s = context.read<SettingsService>();
                  final c = TextEditingController(text: s.aiModel);
                  final v = await showDialog<String>(
                    context: ctx,
                    builder: (d) => AlertDialog(
                      title: const Text('模型'),
                      content: TextField(controller: c, decoration: const InputDecoration(hintText: 'llama3.2')),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消')),
                        FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('保存')),
                      ],
                    ),
                  );
                  if (v != null && v.trim().isNotEmpty) await s.setAiModel(v.trim());
                },
              ),
              const ListTile(
                title: Text('Morph Browser'),
                subtitle: Text('起始页 · AI · 缩放 · 主题 · 标签 · 无痕 · 收藏 · 历史'),
              ),
            ],
          ),
        );
      },
    );
  }

  String _engineLabel(String id) {
    switch (id) {
      case 'bing':
        return 'Bing';
      case 'duck':
        return 'DuckDuckGo';
      case 'baidu':
        return '百度';
      default:
        return 'Google';
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _homeSearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_tabs.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final bookmarked = _bookmarks.any((b) => b.url == tab.url);

    return Scaffold(
      floatingActionButton: isStartPage
          ? null
          : FloatingActionButton.extended(
              onPressed: _openAi,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('AI'),
            ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(
                children: [
                  _IconBtn(
                    icon: Icons.arrow_back_rounded,
                    tooltip: '后退',
                    onPressed: !isStartPage && tab.canGoBack ? () => ctrl?.goBack() : null,
                  ),
                  _IconBtn(
                    icon: Icons.arrow_forward_rounded,
                    tooltip: '前进',
                    onPressed: !isStartPage && tab.canGoForward ? () => ctrl?.goForward() : null,
                  ),
                  _IconBtn(
                    icon: tab.isLoading ? Icons.close_rounded : Icons.refresh_rounded,
                    tooltip: tab.isLoading ? '停止' : '刷新',
                    onPressed: isStartPage
                        ? null
                        : () {
                            if (tab.isLoading) {
                              ctrl?.loadRequest(Uri.parse('about:blank'));
                            } else {
                              ctrl?.reload();
                            }
                          },
                  ),
                  const Spacer(),
                  if (tab.isIncognito)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Chip(
                        avatar: const Icon(Icons.visibility_off, size: 14),
                        label: const Text('无痕', style: TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        backgroundColor: cs.secondaryContainer,
                      ),
                    ),
                  _IconBtn(icon: Icons.tab_rounded, tooltip: '标签 ${_tabs.length}', onPressed: _openTabsSheet),
                  _IconBtn(icon: Icons.more_vert_rounded, tooltip: '菜单', onPressed: _openMenu),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: SearchBar(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                hintText: isStartPage
                    ? (tab.isIncognito ? '无痕搜索或输入网址' : '搜索或输入网址')
                    : null,
                leading: Icon(
                  tab.isIncognito ? Icons.visibility_off_rounded : Icons.search_rounded,
                  size: 22,
                ),
                trailing: [
                  if (_searchCtrl.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 20),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {});
                      },
                    ),
                  if (!isStartPage)
                    IconButton(
                      icon: Icon(
                        bookmarked ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 22,
                        color: bookmarked ? cs.primary : null,
                      ),
                      onPressed: _toggleBookmark,
                    ),
                ],
                onChanged: (_) => setState(() {}),
                onSubmitted: _go,
                elevation: const WidgetStatePropertyAll(0),
                backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHighest),
                padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
                constraints: const BoxConstraints(minHeight: 52, maxHeight: 52),
              ),
            ),
            if (_progress > 0 && _progress < 1 && !isStartPage)
              LinearProgressIndicator(value: _progress, minHeight: 2),
            Expanded(
              child: isStartPage
                  ? _buildStartPage(cs)
                  : IndexedStack(
                      index: _active,
                      children: [
                        for (final t in _tabs)
                          (t.url == kHome || t.url.startsWith('about:'))
                              ? const SizedBox.shrink()
                              : WebViewWidget(controller: _controllers[t.id]!),
                      ],
                    ),
            ),
            if (_showConsole) _buildConsole(cs),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 64,
        selectedIndex: 0,
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              _go(kHome);
            case 1:
              _openBookmarks();
            case 2:
              _newTab();
            case 3:
              _openHistory();
            case 4:
              _openMenu();
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: '主页'),
          NavigationDestination(icon: Icon(Icons.bookmarks_outlined), selectedIcon: Icon(Icons.bookmarks_rounded), label: '收藏'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), selectedIcon: Icon(Icons.add_circle), label: '新建'),
          NavigationDestination(icon: Icon(Icons.history), selectedIcon: Icon(Icons.history_rounded), label: '历史'),
          NavigationDestination(icon: Icon(Icons.menu_rounded), selectedIcon: Icon(Icons.menu_open_rounded), label: '菜单'),
        ],
      ),
    );
  }

  Widget _buildStartPage(ColorScheme cs) {
    final recent = _history.take(6).toList();
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 28),
            Text(
              tab.isIncognito ? '无痕模式' : 'Morph',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: tab.isIncognito ? cs.tertiary : cs.primary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              tab.isIncognito ? '浏览记录不会被保存' : '搜索或输入网址',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            SearchBar(
              controller: _homeSearchCtrl,
              hintText: '搜索 ${_engineLabel(_searchEngine)} 或输入网址',
              leading: const Icon(Icons.search_rounded),
              trailing: [
                if (_homeSearchCtrl.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () {
                      _homeSearchCtrl.clear();
                      setState(() {});
                    },
                  ),
              ],
              onChanged: (_) => setState(() {}),
              onSubmitted: (v) {
                _homeSearchCtrl.clear();
                _go(v);
              },
              elevation: const WidgetStatePropertyAll(1),
              padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
              constraints: const BoxConstraints(minHeight: 56, maxHeight: 56),
            ),
            const SizedBox(height: 32),
            Text('快捷方式', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.85,
              children: [
                for (final s in _shortcuts)
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _go(s.url),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: s.color.withValues(alpha: 0.15),
                          child: Icon(s.icon, color: s.color, size: 26),
                        ),
                        const SizedBox(height: 8),
                        Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium),
                      ],
                    ),
                  ),
              ],
            ),
            if (recent.isNotEmpty && !tab.isIncognito) ...[
              const SizedBox(height: 28),
              Row(
                children: [
                  Text('最近访问', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
                  const Spacer(),
                  TextButton(onPressed: _openHistory, child: const Text('全部')),
                ],
              ),
              for (final h in recent)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: cs.surfaceContainerHighest,
                    child: const Icon(Icons.public, size: 18),
                  ),
                  title: Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(h.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => _go(h.url),
                ),
            ],
            if (_bookmarks.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('收藏', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
                  const Spacer(),
                  TextButton(onPressed: _openBookmarks, child: const Text('全部')),
                ],
              ),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _bookmarks.length.clamp(0, 12),
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final b = _bookmarks[i];
                    return ActionChip(
                      avatar: const Icon(Icons.star_rounded, size: 16),
                      label: Text(b.title, maxLines: 1),
                      onPressed: () => _go(b.url),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConsole(ColorScheme cs) {
    final logs = _console[tab.id] ?? [];
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            title: const Text('控制台'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () {
                    _console[tab.id]?.clear();
                    setState(() {});
                  },
                  child: const Text('清空'),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _showConsole = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: logs.isEmpty
                ? const Center(child: Text('暂无日志'))
                : ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (_, i) {
                      final l = logs[i];
                      Color? c;
                      if (l.level == 'error') c = cs.error;
                      if (l.level == 'warn') c = cs.tertiary;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        child: Text(
                          '[${l.level}] ${l.message}',
                          style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: c),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Shortcut {
  const _Shortcut(this.label, this.url, this.icon, this.color);
  final String label;
  final String url;
  final IconData icon;
  final Color color;
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, this.onPressed, this.tooltip});
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ListEntry {
  _ListEntry({required this.title, required this.subtitle, required this.url});
  final String title;
  final String subtitle;
  final String url;
}

class _ListScreen extends StatefulWidget {
  const _ListScreen({
    required this.title,
    required this.empty,
    required this.items,
    required this.onOpen,
    required this.onDelete,
    this.trailingAction,
  });

  final String title;
  final String empty;
  final List<_ListEntry> items;
  final void Function(String url) onOpen;
  final Future<void> Function(int index) onDelete;
  final Widget? trailingAction;

  @override
  State<_ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<_ListScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [if (widget.trailingAction != null) widget.trailingAction!],
      ),
      body: widget.items.isEmpty
          ? Center(child: Text(widget.empty))
          : ListView.builder(
              itemCount: widget.items.length,
              itemBuilder: (_, i) {
                final e = widget.items[i];
                return Dismissible(
                  key: ValueKey('${e.url}-$i-${widget.items.length}'),
                  background: Container(
                    color: Theme.of(context).colorScheme.errorContainer,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child: const Icon(Icons.delete_outline),
                  ),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) async {
                    await widget.onDelete(i);
                    setState(() {});
                  },
                  child: ListTile(
                    leading: const Icon(Icons.public),
                    title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(e.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => widget.onOpen(e.url),
                  ),
                );
              },
            ),
    );
  }
}

class _SourceScreen extends StatelessWidget {
  const _SourceScreen({required this.title, required this.source});
  final String title;
  final String source;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('源代码 · $title', maxLines: 1),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: source));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制源代码')),
              );
            },
          ),
        ],
      ),
      body: SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Text(
            source.isEmpty ? '(无法获取源代码)' : source,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ),
    );
  }
}
