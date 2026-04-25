import 'package:flutter/material.dart';

/// "Choose what to share" dialog modeled on the Chrome screen-share
/// picker that meet.google.com surfaces. The dialog itself is UI
/// only — the actual capture is started by the caller (which calls
/// getDisplayMedia, and the OS shows its own native picker on
/// mobile platforms).
///
/// Returns the chosen [PresentSource] when the user taps Share, or
/// `null` if they cancel.
enum PresentSource { entireScreen, window, chromeTab }

class PresentSourcePicker extends StatefulWidget {
  /// Hostname shown in the title (e.g. `mizdah.com`). Defaults to a
  /// generic label.
  final String origin;
  const PresentSourcePicker({super.key, this.origin = 'mizdah.com'});

  @override
  State<PresentSourcePicker> createState() => _PresentSourcePickerState();

  /// Convenience: show the dialog modally and await the user's
  /// choice. Returns null on cancel.
  static Future<PresentSource?> show(
    BuildContext context, {
    String origin = 'mizdah.com',
  }) {
    return showDialog<PresentSource>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        child: PresentSourcePicker(origin: origin),
      ),
    );
  }
}

class _PresentSourcePickerState extends State<PresentSourcePicker> {
  static const List<_TabSpec> _tabs = [
    _TabSpec(PresentSource.chromeTab, 'Chrome tab', Icons.tab_rounded),
    _TabSpec(PresentSource.window, 'Window', Icons.web_asset_rounded),
    _TabSpec(
        PresentSource.entireScreen, 'Entire screen', Icons.desktop_windows_rounded),
  ];

  int _tabIndex = 2; // Default: Entire screen (matches Chrome's default)
  bool _selected = false;
  bool _shareSystemAudio = false;

  PresentSource get _currentSource => _tabs[_tabIndex].source;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            _buildTabs(),
            const Divider(height: 1, color: Colors.white12),
            Flexible(child: _buildBody()),
            const Divider(height: 1, color: Colors.white12),
            _buildAudioToggle(),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  // ----- header (title + subtitle) ----------------------------------

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose what to share with ${widget.origin}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'The site will be able to see the contents of your screen',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ----- tabs --------------------------------------------------------

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: List.generate(_tabs.length, (i) {
          final selected = i == _tabIndex;
          return Expanded(
            child: InkWell(
              onTap: () => setState(() {
                _tabIndex = i;
                _selected = false;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: selected
                          ? const Color(0xFF8AB4F8)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  _tabs[i].label,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF8AB4F8)
                        : Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ----- body (preview area) ----------------------------------------

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPreview(),
          const SizedBox(height: 12),
          Text(
            _tabs[_tabIndex].label,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final spec = _tabs[_tabIndex];
    return GestureDetector(
      onTap: () => setState(() => _selected = true),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 220,
        width: 320,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _selected ? const Color(0xFF8AB4F8) : Colors.transparent,
            width: 3,
          ),
          boxShadow: _selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF8AB4F8).withValues(alpha: 0.3),
                    blurRadius: 16,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Faux thumbnail — gradient + icon. On web the browser
              // would render an actual screenshot here; we stand in
              // with a styled placeholder so the dialog still
              // communicates intent.
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3A3D45), Color(0xFF1A1D23)],
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(spec.icon,
                        color: Colors.white.withValues(alpha: 0.5), size: 56),
                    const SizedBox(height: 8),
                    Text(
                      spec.label,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----- audio toggle row -------------------------------------------

  Widget _buildAudioToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.volume_up_rounded,
              color: Colors.white60, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Also share system audio',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          Switch(
            value: _shareSystemAudio,
            activeThumbColor: const Color(0xFF8AB4F8),
            onChanged: (v) => setState(() => _shareSystemAudio = v),
          ),
        ],
      ),
    );
  }

  // ----- footer (Cancel / Share) ------------------------------------

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              shape: const StadiumBorder(),
              side: const BorderSide(color: Color(0xFF8AB4F8)),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Color(0xFF8AB4F8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: _selected
                ? () => Navigator.of(context).pop(_currentSource)
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8AB4F8),
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.10),
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              shape: const StadiumBorder(),
            ),
            child: Text(
              'Share',
              style: TextStyle(
                color: _selected ? const Color(0xFF202124) : Colors.white38,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabSpec {
  final PresentSource source;
  final String label;
  final IconData icon;
  const _TabSpec(this.source, this.label, this.icon);
}
