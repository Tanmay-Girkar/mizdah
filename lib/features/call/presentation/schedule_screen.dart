import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/repositories/scheduling_repository.dart';
import '../../auth/auth_provider.dart';
import '../../../core/theme/theme_provider.dart';

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  DateTime _startDate = DateTime.now();
  TimeOfDay _startTime = TimeOfDay.now();
  DateTime _endDate = DateTime.now().add(const Duration(hours: 1));
  TimeOfDay _endTime = TimeOfDay.fromDateTime(
    DateTime.now().add(const Duration(hours: 1)),
  );
  bool _allDay = false;

  String _repeatOption = 'Does not repeat';
  Color _selectedColor = MizdahTheme.primaryBlue;

  final List<String> _repeatOptions = [
    'Does not repeat',
    'Every day',
    'Every week',
    'Every month',
    'Every year'
  ];

  final List<Color> _availableColors = [
    MizdahTheme.primaryBlue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
  ];

  final Map<Color, String> _colorNames = {
    MizdahTheme.primaryBlue: 'Default color',
    Colors.red: 'Tomato',
    Colors.green: 'Basil',
    Colors.orange: 'Tangerine',
    Colors.purple: 'Grape',
    Colors.teal: 'Peacock',
  };

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
          // Auto adjust end date if it is before start date
          if (_endDate.isBefore(_startDate)) {
            _endDate = _startDate;
          }
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

  Future<void> _showRepeatDialog() async {
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Repeat'),
          contentPadding: const EdgeInsets.only(top: 12.0, bottom: 12.0),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _repeatOptions.map((option) {
              return ListTile(
                title: Text(option),
                leading: Radio<String>(
                  value: option,
                  groupValue: _repeatOption,
                  onChanged: (String? value) {
                    Navigator.of(context).pop(value);
                  },
                ),
                onTap: () {
                  Navigator.of(context).pop(option);
                },
              );
            }).toList(),
          ),
        );
      },
    );

    if (result != null) {
      setState(() {
        _repeatOption = result;
      });
    }
  }

  Future<void> _showColorDialog() async {
    final Color? result = await showDialog<Color>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Event color'),
          contentPadding: const EdgeInsets.only(top: 12.0, bottom: 12.0),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _availableColors.map((color) {
              return ListTile(
                leading: Icon(Icons.circle, color: color),
                title: Text(_colorNames[color] ?? 'Color'),
                trailing: _selectedColor == color ? const Icon(Icons.check) : null,
                onTap: () {
                  Navigator.of(context).pop(color);
                },
              );
            }).toList(),
          ),
        );
      },
    );

    if (result != null) {
      setState(() {
        _selectedColor = result;
      });
    }
  }

  Future<void> _saveMeeting() async {
    final title = _titleController.text.trim().isEmpty ? 'Untitled Meeting' : _titleController.text.trim();
    final scheduledDate = DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
      _startTime.hour,
      _startTime.minute,
    );
    
    // Real scheduling API Logic
    final user = ref.read(authProvider).user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Not logged in')),
      );
      return;
    }

    try {
      final repository = ref.read(schedulingRepositoryProvider);
      
      var recurrence = 'none';
      if (_repeatOption == 'Every day') recurrence = 'daily';
      if (_repeatOption == 'Every week') recurrence = 'weekly';
      if (_repeatOption == 'Every month') recurrence = 'monthly';
      if (_repeatOption == 'Every year') recurrence = 'yearly';

      final endDateTime = DateTime(
        _endDate.year,
        _endDate.month,
        _endDate.day,
        _endTime.hour,
        _endTime.minute,
      );

      await repository.scheduleMeeting(
        hostId: user.id,
        title: title,
        startTime: scheduledDate,
        endTime: endDateTime,
        recurrence: recurrence,
        timezone: DateTime.now().timeZoneName,
      );

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Meeting scheduled successfully')),
      );

      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
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
            onPressed: _saveMeeting,
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
              if (!context.mounted) return;
              if (!_allDay) await _selectTime(context, true);
            },
          ),
          ListTile(
            title: Text(DateFormat('EEE, MMM d, y').format(_endDate)),
            trailing: _allDay ? null : Text(_endTime.format(context)),
            onTap: () async {
              await _selectDate(context, false);
              if (!context.mounted) return;
              if (!_allDay) await _selectTime(context, false);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.loop),
            title: Text(_repeatOption),
            onTap: _showRepeatDialog,
          ),
          ListTile(
            leading: Icon(Icons.circle, color: _selectedColor),
            title: Text(_colorNames[_selectedColor] ?? 'Default color'),
            onTap: _showColorDialog,
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 12.0, right: 32.0),
                  child: Icon(Icons.description_outlined, color: Colors.grey),
                ),
                Expanded(
                  child: TextField(
                    controller: _descriptionController,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      hintText: 'Add description',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
