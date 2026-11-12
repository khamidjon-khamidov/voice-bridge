import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../logic/bridge_cubit.dart';
import '../logic/bridge_state.dart';

const languages = [('en-US', 'English'), ('ru-RU', 'Русский'), ('uz-UZ', 'Oʻzbekcha')];

Future<void> showSettings(BuildContext context, {required VoidCallback onChangeMac}) {
  final cubit = context.read<BridgeCubit>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, scroll) => _Settings(scroll: scroll, onChangeMac: onChangeMac),
      ),
    ),
  );
}

class _Settings extends StatelessWidget {
  const _Settings({required this.scroll, required this.onChangeMac});

  final ScrollController scroll;
  final VoidCallback onChangeMac;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<BridgeCubit>();
    final scheme = Theme.of(context).colorScheme;
    return BlocBuilder<BridgeCubit, BridgeState>(
      builder: (context, s) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          _h(context, "Claude's voice", 'Tap one to hear it.'),
          for (final v in s.voices)
            _Option(
              key: Key('voice-${v.id}'),
              title: v.name.split(' · ').first,
              subtitle: v.name.contains(' · ') ? v.name.split(' · ').last : null,
              selected: s.voice == v.id,
              onTap: () => cubit.setVoice(v.id),
            ),
          _h(context, 'I speak in'),
          for (final (id, name) in languages)
            _Option(key: Key('lang-$id'), title: name, selected: s.lang == id, onTap: () => cubit.setLang(id)),
          _h(context, 'Talking'),
          _Toggle(
            title: 'Send as soon as I let go',
            value: s.autoSend,
            onChanged: cubit.setAutoSend,
          ),
          _Toggle(
            title: 'Keep listening with the screen off',
            subtitle: 'Shows a small permanent notification while on',
            value: s.keepListening,
            onChanged: cubit.setKeepListening,
          ),
          _h(context, 'Mac'),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              onChangeMac();
            },
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text('Change Mac address', style: TextStyle(color: scheme.primary)),
          ),
        ],
      ),
    );
  }

  Widget _h(BuildContext context, String title, [String? hint]) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  )),
          if (hint != null)
            Text(hint, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      );
}

class _Option extends StatelessWidget {
  const _Option({super.key, required this.title, this.subtitle, required this.selected, required this.onTap});

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
      ),
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        minTileHeight: 56,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: selected ? Icon(Icons.check_rounded, color: scheme.primary) : null,
        onTap: onTap,
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.title, this.subtitle, required this.value, required this.onChanged});

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 6),
        child: SwitchListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle!),
          value: value,
          onChanged: onChanged,
        ),
      );
}
