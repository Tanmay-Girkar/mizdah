import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/auth_provider.dart';
import '../../../data/repositories/settings_repository.dart';

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  String? _selectedType;
  final TextEditingController _namesController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  bool _includeVideo = true;
  bool _submitting = false;

  final List<String> _abuseTypes = [
    'Spam or unwanted content',
    'Fraud, phishing and other deceptive practices',
    'Malware (distributed via link in the chat window)',
    'Harassment and hateful content',
    'Unwanted sexual content',
    'Violence and gore',
    'Child endangerment',
    'Other',
  ];

  @override
  void dispose() {
    _namesController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Submit the report. Routes through `SettingsRepository.sendFeedback`
  /// which posts to `/api/meeting/feedback` with the abuse details
  /// rolled into the feedback payload. The dedicated
  /// `/api/abuse/report` endpoint described in
  /// docs/MORE_OPTIONS_BACKEND.md is not yet live; this code will
  /// switch over once it is — the FE will keep working in the
  /// meantime through the feedback path.
  Future<void> _submit() async {
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final accent = Theme.of(context).primaryColor;

    final repo = ref.read(settingsRepositoryProvider);
    final user = ref.read(authProvider).user;
    final description =
        'Type: ${_selectedType ?? 'unspecified'}\n'
        'Reported names: ${_namesController.text}\n'
        'Include video clip: $_includeVideo\n\n'
        '${_descriptionController.text}';

    try {
      await repo.sendFeedback(
        category: 'Report abuse',
        description: description,
        userEmail: user?.email ?? 'anonymous',
      );
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Report submitted. Thank you.'),
          backgroundColor: accent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      // Surface the real error so the user (and the backend dev
      // if logs are shared) sees that the endpoint is broken,
      // instead of pretending success like the previous code did.
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not submit report: $e'),
          backgroundColor: const Color(0xFFB71C1C),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Use project-specific accent or default primary
    final accentColor = isDark ? const Color(0xFFE38E6E) : theme.primaryColor;
    final backgroundColor = isDark ? const Color(0xFF1D1B16) : theme.scaffoldBackgroundColor;
    final surfaceColor = isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03);
    final textColor = isDark ? Colors.white : Colors.black87;
    final labelColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Report abuse',
          style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.normal),
        ),
        actions: [
          TextButton(
            onPressed: _submitting ||
                    _selectedType == null ||
                    _namesController.text.isEmpty ||
                    _descriptionController.text.isEmpty
                ? null
                : _submit,
            child: _submitting
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: accentColor),
                  )
                : Text(
                    'Submit',
                    style: TextStyle(
                      color: (_selectedType == null ||
                              _namesController.text.isEmpty ||
                              _descriptionController.text.isEmpty)
                          ? labelColor
                          : accentColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: TextStyle(color: textColor, fontSize: 14, height: 1.5),
                children: [
                  const TextSpan(
                      text:
                          'Identify the people in this meeting that you want to report as abusive. Information about the meeting and participants, plus an optional short video clip, will be sent to Mizdah for review. '),
                  TextSpan(
                    text: 'Learn more about reporting abuse',
                    style: TextStyle(color: accentColor, decoration: TextDecoration.underline),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Type of abuse dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedType,
                  hint: Text('Type of abuse*', style: TextStyle(color: labelColor)),
                  isExpanded: true,
                  dropdownColor: isDark ? const Color(0xFF2D2A26) : theme.cardColor,
                  icon: Icon(Icons.arrow_drop_down, color: labelColor),
                  items: _abuseTypes.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value, style: TextStyle(color: textColor, fontSize: 16)),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => _selectedType = value),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Names field
            TextField(
              controller: _namesController,
              style: TextStyle(color: textColor),
              decoration: InputDecoration(
                labelText: 'Full names of abusers*',
                labelStyle: TextStyle(color: labelColor),
                helperText: 'Use commas to separate multiple names',
                helperStyle: TextStyle(color: labelColor, fontSize: 12),
                filled: true,
                fillColor: surfaceColor,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: accentColor),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),

            // Description field
            TextField(
              controller: _descriptionController,
              maxLines: 5,
              maxLength: 1000,
              style: TextStyle(color: textColor),
              decoration: InputDecoration(
                labelText: 'Describe the abuse*',
                labelStyle: TextStyle(color: labelColor),
                alignLabelWithHint: true,
                filled: true,
                fillColor: surfaceColor,
                counterStyle: TextStyle(color: labelColor),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: accentColor),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            // Video checkbox
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 24,
                  width: 24,
                  child: Checkbox(
                    value: _includeVideo,
                    activeColor: accentColor,
                    checkColor: Colors.white,
                    side: BorderSide(color: labelColor),
                    onChanged: (v) => setState(() => _includeVideo = v ?? false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _includeVideo = !_includeVideo),
                    child: Text(
                      'Include a brief (less than 60 seconds) video clip recorded now',
                      style: TextStyle(color: textColor, fontSize: 14),
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
