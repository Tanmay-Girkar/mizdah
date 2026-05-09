// ════════════════════════════════════════════════════════════════════
//  Scheduling Riverpod provider
// ════════════════════════════════════════════════════════════════════
//  UI consumes `calendarSchedulingServiceProvider`; never construct
//  the service directly. The provider is a singleton — the service
//  is stateless.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'calendar_scheduling_service.dart';

final calendarSchedulingServiceProvider =
    Provider<CalendarSchedulingService>((ref) {
  return const CalendarSchedulingService();
});
