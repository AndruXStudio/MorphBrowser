import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/browser_models.dart';
import '../services/storage_service.dart';

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

  final List<BrowserTab> _tabs = [];
  final Map<String, WebViewController> _controllers = {};
  final Map<String, List<ConsoleLog>> _console = {};
  int _active = 0;

  List<BookmarkItem> _bookmarks = [];
  List<HistoryItem> _history = [];
  String _homeUrl = 'https://www.google.com';
  String _searchEngine = 'google';
  bool _desktopMode = false;
  bool _showConsole = false;
  double _progress = 0;
  String? _findQuery;

  static const _mobileUa =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36';
  static const _desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  BrowserTab get tab => _tabs[_active];
  WebViewController? get ctrl => _controllers[tab.id];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _homeUrl = await _storage.loadHomeUrl();
    _searchEngine = await _storage.loadSearchEngine();
    _bookmarks = await _storage.loadBookmarks();
    _history = await _storage.loadHistory();
    _newTab(incognito: false, initialUrl: _homeUrl);
    if (mounted) setState(() {});
  }

  String _searchUrl(String q) {
    final t = q.trim();
    if (t.isEmpty) return _homeUrl;
    final looksUrl = t.contains('.') && !t.contains(' ') ||
        t.startsWith('http://') ||
        t.startsWith('https://');
    if (looksUrl) {
      if (t.startsWith('http')) return t;
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
    final t = BrowserTab(
      id: id,
      url: initialUrl ?? _homeUrl,
      isIncognito: incognito,
      title: incognito ? '无痕标签' : '新标签页',
    );
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
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
              _tabs[i].url = url;
              if (_active == i) _searchCtrl.text = url;
            });
          },
          onPageFinished: (url) async {
            final i = _tabs.indexWhere((e) => e.id == id);
            if (i < 0) return;
            final title = await _controllers[id]?.getTitle() ?? url;
            final back = await _controllers[id]?.canGoBack() ?? false;
            final fwd = await _controllers[id]?.canGoForward() ?? false;
            setState(() {
              _tabs[i].isLoading = false;
              _tabs[i].url = url;
              _tabs[i].title = title.isEmpty ? url : title;
              _tabs[i].canGoBack = back;
              _tabs[i].canGoForward = fwd;
              if (_active == i) {
                _searchCtrl.text = url;
                _progress = 0;
              }
            });
            if (!_tabs[i].isIncognito) {
              _addHistory(title.isEmpty ? url : title, url);
            }
            await _injectConsoleHook(id);
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
      )
      ..loadRequest(Uri.parse(t.url));

    _controllers[id] = c;
    _console[id] = [];
    setState(() {
      _tabs.add(t);
      _active = _tabs.length - 1;
      _searchCtrl.text = t.url;
    });
  }

  Future<void> _injectConsoleHook(String id) async {
    const js = r'''
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
''';
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
    _history.insert(
      0,
      HistoryItem(id: _uuid.v4(), title: title, url: url),
    );
    await _storage.saveHistory(_history);
  }

  void _closeTab(int index) {
    if (_tabs.length == 1) {
      final old = _tabs[0];
      _controllers.remove(old.id)?.clearLocalStorage();
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
      _searchCtrl.text = _tabs[_active].url;
    });
  }

  Future<void> _go(String input) async {
    final url = _searchUrl(input);
    await ctrl?.loadRequest(Uri.parse(url));
    setState(() {
      tab.url = url;
      _searchCtrl.text = url;
    });
    _searchFocus.unfocus();
  }

  Future<void> _toggleBookmark() async {
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
                    _showConsole
                        ? Icons.terminal_rounded
                        : Icons.terminal_outlined,
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
                    await ctrl?.reload();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share_rounded),
                  title: const Text('分享'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Share.share(tab.url, subject: tab.title);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('复制链接'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(text: tab.url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制链接')),
                    );
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
                              : Icons.public_rounded,
                        ),
                        title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(t.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _closeTab(i);
                            if (_tabs.isEmpty) {
                              Navigator.pop(ctx);
                            } else {
                              (ctx as Element).markNeedsBuild();
                              setState(() {});
                            }
                          },
                        ),
                        onTap: () {
                          setState(() {
                            _active = i;
                            _searchCtrl.text = _tabs[i].url;
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
                title: const Text('主页地址'),
                subtitle: Text(_homeUrl),
                onTap: () async {
                  final c = TextEditingController(text: _homeUrl);
                  final v = await showDialog<String>(
                    context: ctx,
                    builder: (d) => AlertDialog(
                      title: const Text('主页'),
                      content: TextField(controller: c),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(d),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(d, c.text),
                          child: const Text('保存'),
                        ),
                      ],
                    ),
                  );
                  if (v != null && v.trim().isNotEmpty) {
                    _homeUrl = _searchUrl(v.trim());
                    await _storage.saveHomeUrl(_homeUrl);
                    setState(() {});
                  }
                },
              ),
              ListTile(
                title: const Text('搜索引擎'),
                subtitle: Text(_searchEngine),
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
              const ListTile(
                title: Text('Morph Browser'),
                subtitle: Text('Material 3 · 标签 · 无痕 · 收藏 · 历史 · 控制台 · 源码'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
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
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  MorphScaleIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: '后退',
                    onPressed: tab.canGoBack ? () => ctrl?.goBack() : null,
                  ),
                  MorphScaleIconButton(
                    icon: Icons.arrow_forward_rounded,
                    tooltip: '前进',
                    onPressed: tab.canGoForward ? () => ctrl?.goForward() : null,
                  ),
                  MorphScaleIconButton(
                    icon: tab.isLoading
                        ? Icons.close_rounded
                        : Icons.refresh_rounded,
                    tooltip: tab.isLoading ? '停止' : '刷新',
                    onPressed: () {
                      if (tab.isLoading) {
                        ctrl?.loadRequest(Uri.parse('about:blank'));
                      } else {
                        ctrl?.reload();
                      }
                    },
                  ),
                  Expanded(
                    child: SearchBar(
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      hintText: tab.isIncognito ? '无痕搜索或输入网址' : '搜索或输入网址',
                      leading: Icon(
                        tab.isIncognito
                            ? Icons.visibility_off_rounded
                            : Icons.search_rounded,
                        size: 20,
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
                        IconButton(
                          icon: Icon(
                            bookmarked
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 20,
                            color: bookmarked ? cs.primary : null,
                          ),
                          onPressed: _toggleBookmark,
                        ),
                      ],
                      onChanged: (_) => setState(() {}),
                      onSubmitted: _go,
                      elevation: const WidgetStatePropertyAll(0),
                      backgroundColor:
                          WidgetStatePropertyAll(cs.surfaceContainerHighest),
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 8),
                      ),
                      constraints: const BoxConstraints(
                        minHeight: 48,
                        maxHeight: 48,
                      ),
                    ),
                  ),
                  MorphScaleIconButton(
                    icon: Icons.tab_rounded,
                    tooltip: '标签',
                    onPressed: _openTabsSheet,
                  ),
                  Badge(
                    isLabelVisible: _tabs.length > 1,
                    label: Text('${_tabs.length}'),
                    child: MorphScaleIconButton(
                      icon: Icons.more_vert_rounded,
                      tooltip: '菜单',
                      onPressed: _openMenu,
                    ),
                  ),
                ],
              ),
            ),
            if (_progress > 0 && _progress < 1)
              LinearProgressIndicator(value: _progress, minHeight: 2),
            // WebView
            Expanded(
              child: Stack(
                children: [
                  IndexedStack(
                    index: _active,
                    children: [
                      for (final t in _tabs)
                        WebViewWidget(controller: _controllers[t.id]!),
                    ],
                  ),
                  if (tab.isIncognito)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Chip(
                        avatar: const Icon(Icons.visibility_off, size: 16),
                        label: const Text('无痕'),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: cs.secondaryContainer,
                      ),
                    ),
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
              _go(_homeUrl);
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
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '主页',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmarks_outlined),
            selectedIcon: Icon(Icons.bookmarks_rounded),
            label: '收藏',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: '新建',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history_rounded),
            label: '历史',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_rounded),
            selectedIcon: Icon(Icons.menu_open_rounded),
            label: '菜单',
          ),
        ],
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
                ? const Center(child: Text('暂无日志（console.log 会显示在这里）'))
                : ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (_, i) {
                      final l = logs[i];
                      Color? c;
                      if (l.level == 'error') c = cs.error;
                      if (l.level == 'warn') c = cs.tertiary;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 2,
                        ),
                        child: Text(
                          '[${l.level}] ${l.message}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: c,
                          ),
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

/// Scale-tap icon button (Material icons; morph feel without hard dependency).
class MorphScaleIconButton extends StatefulWidget {
  const MorphScaleIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  State<MorphScaleIconButton> createState() => _MorphScaleIconButtonState();
}

class _MorphScaleIconButtonState extends State<MorphScaleIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    lowerBound: 0.85,
    upperBound: 1,
    value: 1,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _c,
      child: IconButton(
        tooltip: widget.tooltip,
        onPressed: widget.onPressed == null
            ? null
            : () async {
                await _c.reverse();
                await _c.forward();
                widget.onPressed!();
              },
        icon: Icon(widget.icon),
      ),
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
                  key: ValueKey('${e.url}-$i'),
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
                    subtitle:
                        Text(e.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
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
