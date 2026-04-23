import 'dart:core';

void main() {
  final title = 'Mizdah Meeting';
  final description = 'Join with Mizdah: https://mizdah-front.ogoul.cloud/meeting/abc\nMeeting Code: abc';
  final location = 'https://mizdah-front.ogoul.cloud/meeting/abc';
  final startTime = DateTime.now().add(Duration(hours: 1));
  final endTime = startTime.add(Duration(hours: 1));
  
  final startStr = startTime.toUtc().toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first + 'Z';
  final endStr = endTime.toUtc().toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first + 'Z';

  final url = "https://www.google.com/calendar/render?action=TEMPLATE"
      "&text=${Uri.encodeComponent(title)}"
      "&details=${Uri.encodeComponent(description)}"
      "&location=${Uri.encodeComponent(location)}"
      "&dates=$startStr/$endStr";
      
  print(url);
}
