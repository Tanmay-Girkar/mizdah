import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
            onPressed: _selectedType == null || _namesController.text.isEmpty || _descriptionController.text.isEmpty
                ? null
                : () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Report submitted successfully'),
                        backgroundColor: accentColor,
                      ),
                    );
                  },
            child: Text(
              'Submit',
              style: TextStyle(
                color: (_selectedType == null || _namesController.text.isEmpty || _descriptionController.text.isEmpty)
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
