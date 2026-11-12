import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../logic/bridge_cubit.dart';
import '../logic/bridge_state.dart';
import '../logic/target.dart';
import 'home_screen.dart';
import 'theme.dart';

/// Bottom bar: who you're replying to, a text box, and Hold to talk.
class TalkBar extends StatefulWidget {
  const TalkBar({super.key, required this.target});

  final Target? target;

  @override
  State<TalkBar> createState() => _TalkBarState();
}

class _TalkBarState extends State<TalkBar> {
  final _text = TextEditingController();
  bool _released = false; // finger lifted, waiting for the final transcript
  Timer? _finalTimer;
  bool _sending = false;

  Future<void> _send() async {
    if (_sending || _text.text.trim().isEmpty) return;
    final text = _text.text;
    setState(() => _sending = true);
    await run(context, () async {
      final msg = await context.read<BridgeCubit>().send(text);
      _text.clear();
      return msg;
    });
    if (mounted) setState(() => _sending = false);
  }

  bool _holding = false;

  Future<void> _down() async {
    HapticFeedback.mediumImpact();
    _holding = true;
    _released = false;
    _finalTimer?.cancel();
    _text.clear();
    final cubit = context.read<BridgeCubit>();
    final ok = await cubit.startListening((words, isFinal) {
      if (!mounted) return;
      _text.text = words;
      _text.selection = TextSelection.collapsed(offset: words.length);
      if (isFinal && _released) _finish();
    });
    // Let go while listening was still starting (the first time, the
    // microphone permission popup cancels the touch): stop instead of
    // listening on with nobody holding the button.
    if (ok && !_holding) {
      await cubit.stopListening();
      return;
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Voice input needs the microphone. Allow it in Android settings.'),
        backgroundColor: Palette.bad,
      ));
    }
  }

  Future<void> _up() async {
    HapticFeedback.lightImpact();
    _holding = false;
    _released = true;
    await context.read<BridgeCubit>().stopListening();
    // The final transcript usually lands right after stop; don't wait forever.
    _finalTimer = Timer(const Duration(milliseconds: 1500), _finish);
  }

  void _finish() {
    if (!_released) return;
    _released = false;
    _finalTimer?.cancel();
    if (context.read<BridgeCubit>().state.autoSend) _send();
  }

  @override
  void dispose() {
    _finalTimer?.cancel();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BlocBuilder<BridgeCubit, BridgeState>(
      builder: (context, s) {
        final t = widget.target;
        final line = switch (t) {
          null => const TextSpan(text: 'No one to reply to yet'),
          AnswerTarget(:final qid) => TextSpan(children: [
              const TextSpan(text: 'Answering '),
              TextSpan(text: s.labelOf(s.question(qid)?.sid), style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600)),
              TextSpan(text: ': ${s.question(qid)?.text ?? ''}'),
            ]),
          InstructTarget(:final sid) => TextSpan(children: [
              const TextSpan(text: 'Message to '),
              TextSpan(text: s.labelOf(sid), style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600)),
            ]),
        };
        return Material(
          color: scheme.surface,
          child: Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant))),
            padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.of(context).viewPadding.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text.rich(line,
                  key: const Key('target'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: TextField(
                    key: const Key('input'),
                    controller: _text,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Type a reply',
                      isDense: true,
                      filled: true,
                      fillColor: scheme.surfaceContainer,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('send'),
                  onPressed: _sending ? null : _send,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(64, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Send'),
                ),
              ]),
              const SizedBox(height: 8),
              Listener(
                key: const Key('talk'),
                onPointerDown: (_) => _down(),
                onPointerUp: (_) => _up(),
                onPointerCancel: (_) => _up(),
                child: AnimatedScale(
                  scale: s.listening ? 0.98 : 1,
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: s.listening ? Palette.bad : scheme.primary,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(s.listening ? Icons.graphic_eq_rounded : Icons.mic_rounded, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        s.listening ? 'Listening… release to ${s.autoSend ? 'send' : 'stop'}' : 'Hold to talk',
                        style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}
