import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/ai_service.dart';
import '../services/settings_service.dart';

class AiAssistantSheet extends StatefulWidget {
  const AiAssistantSheet({
    super.key,
    required this.controller,
    required this.pageUrl,
    required this.pageTitle,
    required this.settings,
  });

  final WebViewController? controller;
  final String pageUrl;
  final String pageTitle;
  final SettingsService settings;

  @override
  State<AiAssistantSheet> createState() => _AiAssistantSheetState();
}

class _AiAssistantSheetState extends State<AiAssistantSheet> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  bool _busy = false;
  String? _lastJs;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<String> _pageContext() async {
    final c = widget.controller;
    if (c == null) return '(无页面)';
    try {
      final text = await c.runJavaScriptReturningResult(
        r'''(function(){
          var t=document.body?document.body.innerText:"";
          t=t.replace(/\s+/g," ").trim();
          if(t.length>6000)t=t.substring(0,6000);
          var links=[].slice.call(document.querySelectorAll("a[href]")).slice(0,30).map(function(a){return a.innerText.trim().slice(0,40)+"| "+a.href;});
          var inputs=[].slice.call(document.querySelectorAll("input,textarea,select,button")).slice(0,40).map(function(el){
            return (el.tagName+"#"+(el.id||"")+"."+(el.className||"").toString().split(" ")[0]+" name="+(el.name||"")+" type="+(el.type||"")+" ph="+(el.placeholder||"")).slice(0,120);
          });
          return JSON.stringify({text:t,links:links,controls:inputs});
        })()''',
      );
      var s = text.toString();
      if (s.startsWith('"') && s.endsWith('"')) {
        s = s.substring(1, s.length - 1).replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
      }
      return s;
    } catch (e) {
      return '(无法读取页面: $e)';
    }
  }

  Future<void> _send() async {
    final q = _input.text.trim();
    if (q.isEmpty || _busy) return;
    setState(() {
      _msgs.add(_Msg(role: 'user', text: q));
      _busy = true;
      _input.clear();
    });
    try {
      final ctx = await _pageContext();
      final ai = AiService(
        baseUrl: widget.settings.aiBaseUrl,
        model: widget.settings.aiModel,
      );
      const system = '''你是浏览器内的本地 AI 办公助手。根据用户指令和当前网页内容，帮助完成填表、总结、提取信息、导航建议等。
若需要操作页面，在回复末尾附加且仅附加一个 JSON 代码块，格式：
```json
{"js":"要在页面执行的javascript单行或多行代码"}
```
js 应安全、简短。不要解释 JSON。若无需操作页面则不要输出 JSON。
用简洁中文回复。''';
      final user = '''当前页面标题: ${widget.pageTitle}
URL: ${widget.pageUrl}
页面摘要与控件:
$ctx

用户需求: $q''';
      final reply = await ai.chat(system: system, user: user);
      String? js;
      final m = RegExp(r'```json\s*([\s\S]*?)```').firstMatch(reply);
      if (m != null) {
        try {
          final j = jsonDecode(m.group(1)!.trim()) as Map<String, dynamic>;
          js = j['js'] as String?;
        } catch (_) {}
      }
      var show = reply;
      if (m != null) {
        show = reply.replaceAll(m.group(0)!, '').trim();
      }
      setState(() {
        _msgs.add(_Msg(role: 'ai', text: show.isEmpty ? '(已生成操作脚本)' : show));
        _lastJs = js;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _msgs.add(_Msg(
          role: 'ai',
          text: '连接本地 AI 失败。\n请确认：\n1. 本机或局域网已运行 Ollama / 兼容服务\n2. 设置里的地址正确（手机访问电脑请用电脑局域网 IP，并允许防火墙）\n\n错误: $e',
        ));
        _busy = false;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _runJs() async {
    final js = _lastJs;
    final c = widget.controller;
    if (js == null || c == null) return;
    try {
      await c.runJavaScript(js);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已在页面执行操作')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('执行失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (_, sc) {
        return Material(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(Icons.auto_awesome, color: cs.primary),
                title: const Text('AI 办公助手'),
                subtitle: Text(
                  '${widget.settings.aiModel} · ${widget.settings.aiBaseUrl}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: sc,
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final m in _msgs)
                      Align(
                        alignment: m.role == 'user'
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.85,
                          ),
                          decoration: BoxDecoration(
                            color: m.role == 'user'
                                ? cs.primaryContainer
                                : cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(m.text),
                        ),
                      ),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (_lastJs != null && !_busy)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: FilledButton.tonalIcon(
                          onPressed: _runJs,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('在页面执行 AI 建议的操作'),
                        ),
                      ),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: '例如：总结本页 / 帮我勾选同意并继续',
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _busy ? null : _send,
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(14),
                        ),
                        child: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Msg {
  _Msg({required this.role, required this.text});
  final String role;
  final String text;
}
