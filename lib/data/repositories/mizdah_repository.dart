import '../models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class MizdahRepository {
  Future<List<Contact>> getContacts();
  Future<List<Meeting>> getMeetings();
  Future<List<CallHistory>> getCallHistory();
  Future<Meeting> createMeeting(String title, DateTime dateTime);
  Future<Meeting?> getMeetingByCode(String code);
}

class MockMizdahRepository implements MizdahRepository {
  @override
  Future<List<Contact>> getContacts() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return [
      Contact(id: '1', name: 'Zohaib Ali', email: 'zohaib@example.com'),
      Contact(id: '2', name: 'Ayesha Khan', email: 'ayesha@example.com'),
      Contact(id: '3', name: 'Mustafa Omen', email: 'mustafa@example.com'),
    ];
  }

  @override
  Future<List<Meeting>> getMeetings() async {
    return [];
  }

  @override
  Future<List<CallHistory>> getCallHistory() async {
    await Future.delayed(const Duration(milliseconds: 800));
    return [
      CallHistory(
        id: '1',
        title: 'Project Sync',
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        duration: const Duration(minutes: 45),
        isMissed: false,
      ),
      CallHistory(
        id: '2',
        title: 'UI Review',
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
        duration: const Duration(minutes: 30),
        isMissed: false,
      ),
      CallHistory(
        id: '3',
        title: 'Interview',
        timestamp: DateTime.now().subtract(const Duration(days: 2)),
        duration: const Duration(minutes: 15),
        isMissed: true,
      ),
    ];
  }

  @override
  Future<Meeting> createMeeting(String title, DateTime dateTime) async {
    return Meeting(
      id: 'mock-123',
      title: title,
      code: 'abc-defg-hij',
      dateTime: dateTime,
      participants: ['host-1'],
    );
  }

  @override
  Future<Meeting?> getMeetingByCode(String code) async {
    if (code.toLowerCase() == 'abc-defg-hij') {
      return Meeting(
        id: 'mock-123',
        title: 'Mock Meeting',
        code: 'abc-defg-hij',
        dateTime: DateTime.now(),
        participants: ['host-1'],
      );
    }
    return null;
  }
}

final mizdahRepositoryProvider = Provider<MizdahRepository>((ref) {
  return MockMizdahRepository();
});
