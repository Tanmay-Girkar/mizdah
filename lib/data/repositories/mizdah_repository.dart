import '../models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class MizdahRepository {
  Future<List<Contact>> getContacts();
  Future<List<Meeting>> getMeetings();
  Future<List<CallHistory>> getCallHistory();
  Future<Meeting> createMeeting(String title, DateTime dateTime);
}

class MockMizdahRepository implements MizdahRepository {
  @override
  Future<List<Contact>> getContacts() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return [
      Contact(id: '1', name: 'Zohaib Ali', email: 'zohaib@example.com'),
      Contact(id: '2', name: 'Ayesha Khan', email: 'ayesha@example.com'),
      Contact(id: '3', name: 'Hamza Sheikh', email: 'hamza@example.com'),
      Contact(id: '4', name: 'Sana Fatima', email: 'sana@example.com'),
    ];
  }

  @override
  Future<List<Meeting>> getMeetings() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return [];
  }

  @override
  Future<List<CallHistory>> getCallHistory() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return [
      CallHistory(
        id: 'h1',
        title: 'Project Sync',
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        duration: const Duration(minutes: 45),
        isMissed: false,
      ),
      CallHistory(
        id: 'h2',
        title: 'Design Review',
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
        duration: const Duration(minutes: 30),
        isMissed: true,
      ),
    ];
  }

  @override
  Future<Meeting> createMeeting(String title, DateTime dateTime) async {
    await Future.delayed(const Duration(milliseconds: 800));
    return Meeting(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      dateTime: dateTime,
      code: 'vpm-mwrh-fjc',
      participants: [],
    );
  }
}

final mizdahRepositoryProvider = Provider<MizdahRepository>((ref) {
  return MockMizdahRepository();
});
