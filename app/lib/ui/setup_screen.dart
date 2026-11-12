import 'package:flutter/material.dart';

import '../data/hub_api.dart';

/// First run (or "Change Mac"): where is the hub?
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.makeApi, required this.onConnected, this.initialUrl});

  final HubApi Function(String url) makeApi;
  final void Function(String url) onConnected;
  final String? initialUrl;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final _url = TextEditingController(text: widget.initialUrl ?? 'https://');
  bool _checking = false;
  String? _error;

  Future<void> _connect() async {
    var url = _url.text.trim();
    if (!url.startsWith('http')) url = 'https://$url';
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final api = widget.makeApi(url);
    final ok = await api.ping();
    api.close();
    if (!mounted) return;
    setState(() => _checking = false);
    if (ok) {
      widget.onConnected(url);
    } else {
      setState(() => _error = "Couldn't reach the hub there. Is Tailscale on, and is the hub running on your Mac?");
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 32),
            Text('Voice bridge', style: t.headlineMedium),
            const SizedBox(height: 8),
            Text(
              "Talk to Claude Code on your Mac. Enter the address the Mac's hub is served at "
              '(run "tailscale serve --bg 8765" there to get it).',
              style: t.bodyLarge,
            ),
            const SizedBox(height: 24),
            TextField(
              key: const Key('hubUrl'),
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _connect(),
              decoration: InputDecoration(
                labelText: 'Mac address',
                hintText: 'https://your-mac.tailnet.ts.net',
                errorText: _error,
                errorMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('connect'),
              onPressed: _checking ? null : _connect,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _checking
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}
