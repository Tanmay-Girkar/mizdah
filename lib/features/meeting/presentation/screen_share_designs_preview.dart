import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme_provider.dart';

/// Standalone preview for the Google-Meet-style screen-share UX.
/// Pure UI — no provider, no socket, no real screen capture. Lets you
/// see exactly how the in-app chrome behaves before / during / after
/// a presentation. Reachable at `/screen-share-designs`.
///
/// What's in here:
///   - MeetingMode { normal, presenting }
///   - PresentOptionsModal       (Entire Screen / Window / Tab — UI-only)
///   - PresentingBanner          (top of screen during share)
///   - _SpotlightLayout          (shared content full-bleed)
///   - _FloatingSelfView         (camera PIP)
///   - _NormalGridLayout         (placeholder grid for the non-share state)
///
/// All transitions go through AnimatedSwitcher with cross-fade so the
/// surrounding chrome (top bar, controls) never flickers.
class ScreenShareDesignsPreviewScreen extends StatefulWidget {
  const ScreenShareDesignsPreviewScreen({super.key});

  @override
  State<ScreenShareDesignsPreviewScreen> createState() =>
      _ScreenShareDesignsPreviewScreenState();
}

enum MeetingMode { normal, presenting }

class _ScreenShareDesignsPreviewScreenState
    extends State<ScreenShareDesignsPreviewScreen> {
  MeetingMode _mode = MeetingMode.normal;

  Future<void> _onPresent() async {
    final source = await showModalBottomSheet<PresentSource>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const PresentOptionsModal(),
    );
    if (source == null) return;
    // In production this is where you'd call:
    //   navigator.mediaDevices.getDisplayMedia({...})
    // For the preview we just flip mode.
    if (mounted) setState(() => _mode = MeetingMode.presenting);
  }

  void _stopPresenting() {
    setState(() => _mode = MeetingMode.normal);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F172A), Color(0xFF020617)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              // Body — cross-fade between normal grid and spotlight.
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: _mode == MeetingMode.presenting
                      ? const KeyedSubtree(
                          key: ValueKey('present'),
                          child: _SpotlightLayout(),
                        )
                      : const KeyedSubtree(
                          key: ValueKey('normal'),
                          child: _NormalGridLayout(),
                        ),
                ),
              ),

              // Top bar — persistent
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _StubTopBar(onBack: () => context.pop()),
              ),

              // Presenting banner — only when sharing, slides in/out
              Positioned(
                top: 64,
                left: 16,
                right: 16,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, anim) => SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, -0.4),
                      end: Offset.zero,
                    ).animate(anim),
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: _mode == MeetingMode.presenting
                      ? PresentingBanner(
                          key: const ValueKey('banner'),
                          onStop: _stopPresenting,
                        )
                      : const SizedBox.shrink(key: ValueKey('banner-empty')),
                ),
              ),

              // Self-view PIP — bottom right above the controls.
              // While presenting it gets a subtle "ME" tag to make it
              // obvious which tile is the camera vs the screen.
              Positioned(
                bottom: 96,
                right: 14,
                child: FloatingSelfView(
                  isPresenting: _mode == MeetingMode.presenting,
                ),
              ),

              // Bottom controls
              Align(
                alignment: Alignment.bottomCenter,
                child: _StubControls(
                  isPresenting: _mode == MeetingMode.presenting,
                  onPresent: _onPresent,
                  onStop: _stopPresenting,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PresentOptionsModal — UI-only hint sheet (real source picker is OS-level)
// ---------------------------------------------------------------------------

enum PresentSource { entireScreen, window, tab }

class PresentOptionsModal extends StatelessWidget {
  const PresentOptionsModal({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1F26),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Row(
                children: [
                  Icon(Icons.present_to_all_rounded,
                      color: MizdahTheme.primaryBlue, size: 22),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Choose what to share',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(50, 0, 16, 12),
              child: Text(
                'Your system will ask you what to share next.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
            _OptionRow(
              icon: Icons.desktop_windows_rounded,
              title: 'Entire screen',
              subtitle: 'Everything on your display',
              onTap: () => Navigator.pop(context, PresentSource.entireScreen),
            ),
            _OptionRow(
              icon: Icons.web_asset_rounded,
              title: 'A window',
              subtitle: 'A specific app window',
              onTap: () => Navigator.pop(context, PresentSource.window),
            ),
            _OptionRow(
              icon: Icons.tab_rounded,
              title: 'A Chrome tab',
              subtitle: 'Best for video & motion',
              onTap: () => Navigator.pop(context, PresentSource.tab),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _OptionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white30, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PresentingBanner — Google-Meet-style "You are presenting" pill
// ---------------------------------------------------------------------------

class PresentingBanner extends StatelessWidget {
  final VoidCallback onStop;
  const PresentingBanner({super.key, required this.onStop});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A73E8).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.present_to_all_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'You are presenting',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onStop,
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1A73E8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Stop',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// FloatingSelfView — small camera tile that hovers in the corner
// ---------------------------------------------------------------------------

class FloatingSelfView extends StatelessWidget {
  final bool isPresenting;
  const FloatingSelfView({super.key, required this.isPresenting});

  @override
  Widget build(BuildContext context) {
    final width = isPresenting ? 110.0 : 120.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      width: width,
      height: width * 1.4,
      decoration: BoxDecoration(
        color: const Color(0xFF1F232B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFF455A64),
                  shape: BoxShape.circle,
                ),
                child: const Text(
                  'Y',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isPresenting ? 'You · ME' : 'You',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Spotlight layout — shared screen full-bleed, optional thumbnails strip
// ---------------------------------------------------------------------------

class _SpotlightLayout extends StatelessWidget {
  const _SpotlightLayout();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 64, 12, 96),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                color: const Color(0xFF202124),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: MizdahTheme.primaryBlue.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.present_to_all_rounded,
                              size: 56,
                              color: MizdahTheme.primaryBlue,
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'You are presenting your screen',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Other participants see what you share',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // "Sharing your screen" chip top-left of the spotlight
                    Positioned(
                      left: 12,
                      top: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cast_connected_rounded,
                                color: Colors.white, size: 14),
                            SizedBox(width: 6),
                            Text(
                              'Sharing your screen',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Optional thumbnail strip — shows other participants while
          // presenting (3 placeholders here).
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => SizedBox(
                width: 100,
                child: _MiniTile(name: ['Alex', 'Beth', 'Cy'][i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTile extends StatelessWidget {
  final String name;
  const _MiniTile({required this.name});

  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xFFE53935),
      const Color(0xFF1E88E5),
      const Color(0xFF43A047),
    ];
    final color = colors[name.codeUnitAt(0) % 3];
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: const Color(0xFF1F232B),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Text(
                  name[0],
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Positioned(
              left: 6,
              bottom: 6,
              child: Text(
                name,
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Normal grid layout — placeholder for the non-presenting state
// ---------------------------------------------------------------------------

class _NormalGridLayout extends StatelessWidget {
  const _NormalGridLayout();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 64, 12, 96),
      child: GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.8,
        children: const [
          _MiniTile(name: 'Alex'),
          _MiniTile(name: 'Beth'),
          _MiniTile(name: 'Cy'),
          _MiniTile(name: 'Dana'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stub chrome (top bar + bottom controls) so the preview looks complete
// ---------------------------------------------------------------------------

class _StubTopBar extends StatelessWidget {
  final VoidCallback onBack;
  const _StubTopBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock, color: Color(0xFF1A73E8), size: 12),
                SizedBox(width: 6),
                Text('demo-share-ui',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    )),
                SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_down,
                    color: Colors.white54, size: 16),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _StubControls extends StatelessWidget {
  final bool isPresenting;
  final VoidCallback onPresent;
  final VoidCallback onStop;
  const _StubControls({
    required this.isPresenting,
    required this.onPresent,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const _CtlBtn(icon: Icons.videocam_rounded),
              const _CtlBtn(icon: Icons.mic_rounded),
              // The Present button — turns red while sharing.
              _PresentBtn(
                isPresenting: isPresenting,
                onTap: isPresenting ? onStop : onPresent,
              ),
              const _CtlBtn(icon: Icons.more_vert_rounded),
              const _CtlBtn(
                  icon: Icons.call_end_rounded, bg: Color(0xFFE53935)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CtlBtn extends StatelessWidget {
  final IconData icon;
  final Color? bg;
  const _CtlBtn({required this.icon, this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg ?? Colors.white.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }
}

class _PresentBtn extends StatelessWidget {
  final bool isPresenting;
  final VoidCallback onTap;
  const _PresentBtn({required this.isPresenting, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isPresenting ? 'Stop presenting' : 'Present your screen',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isPresenting
                ? const Color(0xFFE53935)
                : Colors.white.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isPresenting
                ? Icons.stop_screen_share_rounded
                : Icons.present_to_all_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
