import 'package:flutter/material.dart';

import '../models/card_filter.dart';
import '../theme.dart';

String _langLabel(LangFilter l) {
  switch (l) {
    case LangFilter.any:
      return 'Tutte';
    case LangFilter.hasIt:
      return 'Con copie IT';
    case LangFilter.hasEn:
      return 'Con copie EN';
    case LangFilter.onlyIt:
      return 'Solo IT';
    case LangFilter.onlyEn:
      return 'Solo EN';
  }
}

String _deckLabel(DeckFilter d) {
  switch (d) {
    case DeckFilter.any:
      return 'Tutte';
    case DeckFilter.inDeck:
      return 'In almeno un deck';
    case DeckFilter.notInDeck:
      return 'In nessun deck';
  }
}

/// Mostra il pannello dei filtri. Restituisce i filtri scelti (o null se chiuso).
Future<CardFilter?> showFilterSheet(
  BuildContext context,
  CardFilter current, {
  bool showDeckFilter = true,
}) {
  final f = current.copy();
  return showModalBottomSheet<CardFilter>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheet) {
          Widget title(String t) => Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 6),
                child: Text(t,
                    style: const TextStyle(
                        color: AppColors.gold,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1)),
              );

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.85,
            maxChildSize: 0.95,
            builder: (ctx, scroll) => Column(
              children: [
                Expanded(
                  child: ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    children: [
                      const Text('Filtri e ordinamento',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      title('ORDINA PER'),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final k in SortKey.values)
                            ChoiceChip(
                              label: Text(sortKeyLabel(k)),
                              selected: f.sort == k,
                              onSelected: (_) => setSheet(() {
                                f.sort = k;
                                f.ascending = k == SortKey.name;
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: true, label: Text('Crescente')),
                          ButtonSegment(value: false, label: Text('Decrescente')),
                        ],
                        selected: {f.ascending},
                        onSelectionChanged: (s) =>
                            setSheet(() => f.ascending = s.first),
                      ),
                      title('TIPO'),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final g in TypeGroup.values)
                            FilterChip(
                              label: Text(typeGroupLabel(g)),
                              selected: f.types.contains(g),
                              onSelected: (v) => setSheet(() {
                                if (v) {
                                  f.types.add(g);
                                } else {
                                  f.types.remove(g);
                                }
                              }),
                            ),
                        ],
                      ),
                      title('ATTRIBUTO'),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final e in kAttributes.entries)
                            FilterChip(
                              label: Text(e.value),
                              selected: f.attributes.contains(e.key),
                              onSelected: (v) => setSheet(() {
                                if (v) {
                                  f.attributes.add(e.key);
                                } else {
                                  f.attributes.remove(e.key);
                                }
                              }),
                            ),
                        ],
                      ),
                      title('LIVELLO / GRADO'),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (var l = 1; l <= 12; l++)
                            FilterChip(
                              label: Text('$l'),
                              selected: f.levels.contains(l),
                              onSelected: (v) => setSheet(() {
                                if (v) {
                                  f.levels.add(l);
                                } else {
                                  f.levels.remove(l);
                                }
                              }),
                            ),
                        ],
                      ),
                      title('LINGUA DELLE COPIE'),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final l in LangFilter.values)
                            ChoiceChip(
                              label: Text(_langLabel(l)),
                              selected: f.lang == l,
                              onSelected: (_) => setSheet(() => f.lang = l),
                            ),
                        ],
                      ),
                      title('DOPPIONI'),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Solo carte con più di una copia'),
                        value: f.duplicatesOnly,
                        onChanged: (v) => setSheet(() => f.duplicatesOnly = v),
                      ),
                      if (showDeckFilter) ...[
                        title('DECK'),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final d in DeckFilter.values)
                              ChoiceChip(
                                label: Text(_deckLabel(d)),
                                selected: f.deck == d,
                                onSelected: (_) => setSheet(() => f.deck = d),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setSheet(() {
                            f.clearFilters();
                            f.sort = SortKey.name;
                            f.ascending = true;
                          }),
                          child: const Text('Azzera'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(f),
                          child: const Text('Applica'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
