import 'package:flutter/material.dart';

/// Modal dialog shown to the presenter when another participant
/// asks for remote control of their screen. Matches the visual
/// language of the user-supplied screenshot:
///   - centered cursor medallion at the top
///   - bold "Remote Control Request" headline
///   - body line naming the requester
///   - "Deny" (red) text button + "Grant" (blue) filled button
class RemoteControlRequestDialog extends StatelessWidget {
  final String requesterName;
  final VoidCallback onDeny;
  final VoidCallback onGrant;
  const RemoteControlRequestDialog({
    super.key,
    required this.requesterName,
    required this.onDeny,
    required this.onGrant,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String requesterName,
  }) {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: RemoteControlRequestDialog(
          requesterName: requesterName,
          onDeny: () => Navigator.pop(ctx, false),
          onGrant: () => Navigator.pop(ctx, true),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Container(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
        decoration: BoxDecoration(
          color: const Color(0xFF1F242C),
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
            // Cursor medallion
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF1A73E8).withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.near_me_rounded,
                color: Color(0xFF1A73E8),
                size: 32,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Remote Control Request',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                  children: [
                    TextSpan(
                      text: requesterName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const TextSpan(
                      text:
                          ' wants to control your screen. They will be able to move your mouse and type.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: onDeny,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Deny',
                      style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: onGrant,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1A73E8),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Grant',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
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
