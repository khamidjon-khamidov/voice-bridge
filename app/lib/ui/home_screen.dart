import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/hub_api.dart';
import '../data/models.dart';
import '../logic/bridge_cubit.dart';
import '../logic/bridge_state.dart';
import '../logic/target.dart';
import 'settings_sheet.dart';
import 'talk_bar.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onChangeMac});

  final VoidCallback onChangeMac;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {})); // "5m ago"
  }

  @override
  // "inactive" is a dialog or the notification shade over the app: still on screen.
  void didChangeAppLifecycleState(AppLifecycleState s) => context
      .read<BridgeCubit>()
      .setForeground(s == AppLifecycleState.resumed || s == AppLifecycleState.inactive);

  @override
  void dispose() {
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BridgeCubit, BridgeState>(
      builder: (context, s) {
        final cubit = context.read<BridgeCubit>();
        final target = s.target;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: Row(children: [
              _Dot(on: s.connected),
              const SizedBox(width: 8),
              const Text('Voice bridge'),
            ]),
            actions: [
              TextButton(
                key: const Key('statusAll'),
                onPressed: () => run(context, () => cubit.status()),
                child: const Text('Status: all'),
              ),
              IconButton(
                key: const Key('sound'),
                tooltip: s.soundOn ? 'Mute' : 'Unmute',
                icon: Icon(s.soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded),
                onPressed: () => cubit.setSound(!s.soundOn),
              ),
              IconButton(
                key: const Key('settings'),
                tooltip: 'Settings',
                icon: const Icon(Icons.tune_rounded),
                onPressed: () => showSettings(context, onChangeMac: widget.onChangeMac),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              if (s.questions.isNotEmpty) ...[
                const _Heading('Waiting for you'),
                for (final q in s.questions)
                  _QuestionCard(
                    question: q,
                    label: s.labelOf(q.sid),
                    selected: target == AnswerTarget(q.qid),
                    onTap: () => cubit.pick(AnswerTarget(q.qid)),
                  ),
              ],
              const _Heading('Sessions'),
              if (s.sessions.isEmpty)
                const _Empty('No Claude sessions yet. Start claude on your Mac.')
              else
                for (final session in s.sessions)
                  SessionCard(session: session, selected: target == InstructTarget(session.id)),
              const _Heading('Recent'),
              if (s.feed.isEmpty)
                const _Empty('Nothing yet.')
              else
                for (final m in s.feed.reversed.take(60)) _FeedTile(m),
            ],
          ),
          bottomNavigationBar: TalkBar(target: target),
        );
      },
    );
  }
}

/// Runs a hub action and shows how it went.
Future<void> run(BuildContext context, Future<String> Function() action) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final msg = await action();
    if (msg.isNotEmpty) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }
  } on HubError catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Palette.bad));
  }
}

String ago(double ts) {
  final s = DateTime.now().millisecondsSinceEpoch / 1000 - ts;
  if (s < 60) return 'just now';
  if (s < 3600) return '${s ~/ 60}m ago';
  return '${s ~/ 3600}h ago';
}

String clock(double ts) {
  final d = DateTime.fromMillisecondsSinceEpoch((ts * 1000).round());
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _Dot extends StatelessWidget {
  const _Dot({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) => Semantics(
        label: on ? 'Connected' : 'Not connected',
        child: Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: on ? Palette.good : Palette.bad, shape: BoxShape.circle),
        ),
      );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
              ),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(4),
        child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.question, required this.label, required this.selected, required this.onTap});

  final Question question;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      key: Key('q-${question.qid}'),
      color: dark ? const Color(0xFF2A2216) : const Color(0xFFFFF6E6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? Theme.of(context).colorScheme.primary : (dark ? const Color(0xFF7A5A20) : const Color(0xFFF0C777)),
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$label · ${ago(question.ts)}',
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(question.text, style: const TextStyle(fontSize: 17)),
          ]),
        ),
      ),
    );
  }
}

class SessionCard extends StatelessWidget {
  const SessionCard({super.key, required this.session, required this.selected});

  final Session session;
  final bool selected;

  Future<void> _rename(BuildContext context) async {
    final cubit = context.read<BridgeCubit>();
    final ctrl = TextEditingController(text: session.label);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Name this session'),
        content: TextField(controller: ctrl, autofocus: true, onSubmitted: (v) => Navigator.pop(c, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty && context.mounted) {
      await run(context, () => cubit.rename(session.id, name.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<BridgeCubit>();
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 13);
    final color = Palette.stateColor(session.state);
    return Opacity(
      opacity: session.ended ? 0.55 : 1,
      child: Card(
        key: Key('s-${session.id}'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: InkWell(
                  onTap: () => _rename(context),
                  child: Text(session.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(99)),
                child: Text(Palette.stateText(session.state), style: TextStyle(color: color, fontSize: 12)),
              ),
            ]),
            if (session.last.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(session.last, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14)),
            ],
            if (session.phoneWaitingUntil != null) ...[
              const SizedBox(height: 4),
              Text('Listening for your instructions until ${clock(session.phoneWaitingUntil!)}', style: muted),
            ],
            if (session.queued > 0) ...[
              const SizedBox(height: 4),
              Text('${session.queued} message(s) queued', style: muted),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (session.ended)
                OutlinedButton(onPressed: () => run(context, () => cubit.forget(session.id)), child: const Text('Remove'))
              else ...[
                OutlinedButton(
                  key: Key('status-${session.id}'),
                  onPressed: () => run(context, () => cubit.status(session.id)),
                  child: const Text('Status'),
                ),
                OutlinedButton(
                  key: Key('msg-${session.id}'),
                  onPressed: () => cubit.pick(InstructTarget(session.id)),
                  child: const Text('Message'),
                ),
                FilterChip(
                  key: Key('phone-${session.id}'),
                  label: const Text('Phone mode'),
                  selected: session.phoneMode,
                  onSelected: (on) => run(context, () => cubit.setPhoneMode(session.id, on)),
                ),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}

class _FeedTile extends StatelessWidget {
  const _FeedTile(this.m);
  final HubMessage m;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = m.fromUser
        ? scheme.primary
        : m.kind == 'system'
            ? scheme.onSurfaceVariant
            : scheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${m.label.isEmpty ? 'hub' : m.label} · ${clock(m.ts)} · ${m.fromUser ? 'you' : m.kind}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        Text(m.text,
            style: TextStyle(
              color: color,
              fontWeight: m.kind == 'question' ? FontWeight.w600 : FontWeight.normal,
            )),
      ]),
    );
  }
}
