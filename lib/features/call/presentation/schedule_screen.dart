import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final _titleController = TextEditingController();
  DateTime _startDate = DateTime.now();
  TimeOfDay _startTime = TimeOfDay.now();
  DateTime _endDate = DateTime.now().add(const Duration(hours: 1));
  TimeOfDay _endTime = TimeOfDay.fromDateTime(
    DateTime.now().add(const Duration(hours: 1)),
  );
  bool _allDay = false;

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _selectTime(BuildContext context, bool isStart) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: const Text('New meeting'),
        actions: [
          TextButton(
            onPressed: () {
              // Save meeting logic
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Meeting scheduled')),
              );
              context.pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _titleController,
              style: Theme.of(context).textTheme.headlineSmall,
              decoration: const InputDecoration(
                hintText: 'Add title',
                border: InputBorder.none,
              ),
            ),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('All-day'),
            value: _allDay,
            onChanged: (val) => setState(() => _allDay = val),
            secondary: const Icon(Icons.access_time),
          ),
          ListTile(
            title: Text(DateFormat('EEE, MMM d, y').format(_startDate)),
            trailing: _allDay ? null : Text(_startTime.format(context)),
            onTap: () async {
              await _selectDate(context, true);
              if (!mounted) return;
              if (!_allDay) await _selectTime(context, true);
            },
          ),
          ListTile(
            title: Text(DateFormat('EEE, MMM d, y').format(_endDate)),
            trailing: _allDay ? null : Text(_endTime.format(context)),
            onTap: () async {
              await _selectDate(context, false);
              if (!mounted) return;
              if (!_allDay) await _selectTime(context, false);
            },
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.loop),
            title: Text('Does not repeat'),
            onTap: null,
          ),
          const ListTile(
            leading: Icon(Icons.circle, color: Colors.blue),
            title: Text('Default color'),
            onTap: null,
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.description_outlined),
            title: Text('Add description'),
            onTap: null,
          ),
        ],
      ),
    );
  }
}
