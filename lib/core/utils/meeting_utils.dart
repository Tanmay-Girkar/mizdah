import 'dart:math';

class MeetingUtils {
  /// Generates a random 9-digit meeting code in the format 'xxx-xxxx-xx' or similar
  /// as requested by the Mizdah Integration Guide.
  static String generateMeetingCode() {
    final random = Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz';
    return List.generate(10, (index) => chars[random.nextInt(chars.length)]).join();
  }

  /// Extracts a meeting code from a URL or returns the code if it's already a code.
  static String extractCode(String input) {
    if (input.isEmpty) return '';
    
    // Split by '/' and take the last non-empty segment to handle various URL formats
    final segments = input.split('/');
    final code = segments.lastWhere((s) => s.isNotEmpty, orElse: () => input);
    
    return code.trim().toLowerCase();
  }

  /// Generates a proper Mizdah meeting link
  static String generateMeetingLink(String code) {
    final cleanCode = extractCode(code);
    return 'https://mizdah.ogoul.cloud/meeting/$cleanCode';
  }

  /// Generates a Google Calendar TEMPLATE URL for scheduling.
  static String generateCalendarUrl(String code) {
    final baseUrl = 'https://calendar.google.com/calendar/render';
    final title = Uri.encodeComponent('Mizdah Meeting');
    final details = Uri.encodeComponent('Join with Mizdah: https://mizdah.com/meeting/$code');
    return '$baseUrl?action=TEMPLATE&text=$title&details=$details';
  }
}
