# 00 · Shared architecture

Build this **first**. Every later feature drops in as one provider line + one row widget — without these helpers each setting would be ~30 lines of boilerplate.

## Files to create / extend

```
lib/features/settings/
├── meeting_layout_provider.dart       (existing — contains layout/maxTiles/hideNoVideo)
├── meeting_preferences_provider.dart  (NEW — generic helpers + 22 prefs)
└── presentation/
    └── meeting_preferences_screen.dart (existing — extend with new sections)
```

## Why split providers across two files?

`meeting_layout_provider.dart` already exists and is depended on by the meeting room widget (it reads `layout` and `maxTiles` to render the grid). Adding 22 more notifiers to that file would bloat it and tangle "settings UI" concerns with "in-meeting rendering" concerns.

The new file `meeting_preferences_provider.dart` holds settings that are **only** consumed by the preferences screen for now. When the backend later integrates one of them (e.g. background blur uploads to an ML server), it's clear which provider is where.

## Generic notifiers (4 helpers)

Each helper handles loading from `SharedPreferences` on construction and writing on every `set(...)`. The pattern matches the existing `MeetingLayoutNotifier` so reviewers can pattern-match.

### `_BoolPref`
- Stores under string key, default value supplied at construction.
- `set(bool)` writes back; no-op when value matches current state.

### `_IntPref`
- Same, with `min` / `max` clamping on every read and write.
- Used for: touch-up appearance slider (0–100), max tiles slider (4–49 — already exists).

### `_StringPref`
- Same. Used for free-form values like caption language code.

### `_EnumPref<T extends Enum>`
- Persists the enum's `.name`; rehydrates by matching against a `List<T>` of allowed values.
- Falls back to current state on unknown saved values (safe across renames).
- Used for: noise suppression (3-state), video quality (3-state), background effect (3-state), self preview (3-state), caption size (3-state), default meeting type (2-state).

Provider declarations using these helpers are one line each:

```
// Boolean toggle
final muteOnJoinProvider = StateNotifierProvider<_BoolPref, bool>(
  (ref) => _BoolPref('mizdah_mute_on_join_v1', false));

// Enum picker
final noiseSuppressionProvider =
    StateNotifierProvider<_EnumPref<NoiseSuppression>, NoiseSuppression>(
  (ref) => _EnumPref(
    'mizdah_noise_suppression_v1',
    NoiseSuppression.standard,
    NoiseSuppression.values,
  ),
);
```

## Reusable row widgets (4 types)

Add these **private** widgets to `meeting_preferences_screen.dart` once. Each subsequent feature reuses the matching row.

### `_SwitchRow` (boolean)
Layout: `[icon tile] [label + sublabel] [Switch.adaptive]`. Whole row tappable; tapping toggles. Uses `MizdahTokens.iconTileBg(context)` for the icon background — adaptive light/dark.

Used by: any feature with `_BoolPref`.

### `_SegmentedRow` (2–4 mutually exclusive options)
Layout: `[icon tile] [label + sublabel]` on top row, full-width segmented control with sliding gradient pill below. Animated `AnimatedPositioned` for the pill, 220 ms `easeOutCubic`.

Used by: noise suppression, video quality, background, self preview, caption size, default meeting type.

### `_SliderRow` (int with range)
Layout: `[icon tile] [label + sublabel] [value pill]` top row, slider underneath. The value pill (e.g. "47") sits to the right of the label so users see current value without dragging. Slider uses `MizdahTokens.primary` for the active track + thumb.

Used by: touch-up appearance, max tiles (already exists in a custom form — could be migrated).

### `_PickerRow` (long lists)
Layout: `[icon tile] [label] [current value] [chevron]`. Tapping opens a modal bottom sheet with a scrollable list and a check mark on the active item.

Used by: caption language. Could later cover ringtone, default reaction emoji, etc.

## Section wrapper

A `_Section` widget already exists for the layout-section pattern. Reuse it: `[gradient title label] + [list of cards]`. Each section group is a `_Section(title: 'Audio', children: [...])`.

## Persistence key naming

All keys follow `mizdah_<feature_name>_v1`. The `_v1` suffix lets you ship a v2 (e.g. enum gains a new case) without colliding with old saved values — bump to `_v2` and ignore the v1 key.

## Backend hand-off plan (later)

When the backend gains a `/api/me/preferences` endpoint, only the `set(...)` method on each notifier needs to change:

```
Future<void> set(bool value) async {
  state = value;
  await SharedPreferences.getInstance().then((p) => p.setBool(_key, value));
  await api.updatePreference(_key, value); // <— new line
}
```

That's it. UI doesn't change, screen doesn't change, persistence still works offline.

## Testing surface

Each feature's notifier is trivially unit-testable:

```
test('muteOnJoin persists across reloads', () async {
  SharedPreferences.setMockInitialValues({'mizdah_mute_on_join_v1': true});
  final container = ProviderContainer();
  await Future.microtask(() {});  // let _load run
  expect(container.read(muteOnJoinProvider), true);
});
```

No backend required — keeps the CI green.

## Complexity estimate for this milestone

- Providers file: ~250 lines (mostly the 4 helper classes + ~22 one-line provider declarations + 6 enum extensions).
- Row widgets: ~250 lines (~60 lines per widget).
- Section wiring per feature: ~6 lines.

**Total:** about ~500 lines of new code for the architecture, then ~6 lines per feature added. Build this first and the rest is incremental.
