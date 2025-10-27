import 'package:flutter/material.dart';
import 'package:medsoft_patient/api/time_order_dao.dart';
import 'package:intl/intl.dart';

// --- Date Comparison Extension ---
// Used to compare DateTime objects without worrying about time component.
extension DateOnlyCompare on DateTime {
  bool isSameDay(DateTime other) {
    return year == other.year && month == other.month && day == other.day;
  }

  bool isSameMonth(DateTime other) {
    return year == other.year && month == other.month;
  }

  // Normalizes the date to start of the day for clean comparison
  DateTime toNormalizedDate() {
    return DateTime(year, month, day);
  }
}
// -----------------------------------

// Data structure for Time Slot
class TimeSlot {
  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final String date;
  final bool isAvailable;

  TimeSlot({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.date,
    required this.isAvailable,
  });

  @override
  String toString() =>
      '${DateFormat('HH:mm').format(startTime)} - ${DateFormat('HH:mm').format(endTime)}';
}

class TimeSelectionScreen extends StatefulWidget {
  final String tenant;
  final String branchId;
  final String tasagId;
  final String employeeId;
  final String doctorName; // For display

  const TimeSelectionScreen({
    super.key,
    required this.tenant,
    required this.branchId,
    required this.tasagId,
    required this.employeeId,
    required this.doctorName,
  });

  @override
  State<TimeSelectionScreen> createState() => _TimeSelectionScreenState();
}

class _TimeSelectionScreenState extends State<TimeSelectionScreen> {
  final TimeOrderDAO _dao = TimeOrderDAO();

  List<TimeSlot> _timeSlots = [];
  bool _isLoading = false;
  String? _error;
  TimeSlot? _selectedTimeSlot;

  // Calendar State
  DateTime _currentMonth = DateTime.now().toNormalizedDate();
  DateTime _selectedDate = DateTime.now().toNormalizedDate();

  // Stores API dates with slots in "YYYY.MM.DD" format
  Set<String> _targetDates = {};

  // Grouped list of ALL time slots by date for display
  Map<String, List<TimeSlot>> _groupedTimeSlots = {};

  @override
  void initState() {
    super.initState();
    _loadTimeSlots();
  }

  // Helper function to format date string consistently for API keys
  String _formatDateToApi(DateTime date) {
    return DateFormat('yyyy.MM.dd').format(date);
  }

  // Helper function to format date string for status display
  String _formatDateToDisplay(DateTime date) {
    return DateFormat('yyyy оны M сарын d').format(date);
  }

  // --- Calendar Control Methods ---
  void _goToPrevMonth() {
    final now = DateTime.now().toNormalizedDate();
    final prevMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1).toNormalizedDate();

    // Do not allow navigating to a month before the current month
    if (prevMonth.isBefore(DateTime(now.year, now.month, 1))) {
      return;
    }

    setState(() {
      _currentMonth = prevMonth;
    });
  }

  void _goToNextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1).toNormalizedDate();
    });
  }

  void _onDaySelected(DateTime day) {
    final normalizedDay = day.toNormalizedDate();
    final now = DateTime.now().toNormalizedDate();

    // 1. Check if the day is in the past
    if (normalizedDay.isBefore(now)) {
      return;
    }

    setState(() {
      _selectedDate = normalizedDay;
      _selectedTimeSlot = null; // Clear selection on date change
    });
  }
  // -----------------------------------

  Future<void> _loadTimeSlots() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _timeSlots = [];
      _groupedTimeSlots = {};
      _targetDates = {};
    });

    final body = {
      'tenant': widget.tenant,
      'branchId': widget.branchId,
      'tasagId': widget.tasagId,
      'employeeId': widget.employeeId,
    };

    final response = await _dao.getTimes(body);

    setState(() {
      _isLoading = false;
      if (response.success && response.data != null) {
        final List<TimeSlot> loadedSlots = [];

        // 1. Iterate over the list of Date objects
        for (var dateData in response.data!) {
          final String dateString = dateData['targetDate'] as String;
          final List<dynamic> timesList = dateData['times'] as List<dynamic>;

          // Add this date to the set of dates that have slots
          _targetDates.add(dateString);

          // 2. Iterate over the nested list of Time objects
          for (var timeData in timesList) {
            final String timeString = timeData['time'] as String;
            bool isAvailable = timeData['available'] as bool;

            // --- TESTING OVERRIDE: Simulate unavailable slots ---
            if (timeString == '09:00' || timeString == '14:00' || timeString == '10:30') {
              isAvailable = false; // Force certain times to be unavailable for testing
            }
            // ---------------------------------------------------

            // 3. Combine date and time to create the full DateTime object
            final String dateTimeStartString =
                '${dateString.replaceAll('.', '-')}'
                ' ${timeString}';

            try {
              final DateTime startTime = DateTime.parse(dateTimeStartString);
              // Assuming each slot is 15 minutes
              final DateTime endTime = startTime.add(const Duration(minutes: 15));

              final String slotId = '$dateTimeStartString-${widget.employeeId}';

              loadedSlots.add(
                TimeSlot(
                  id: slotId,
                  startTime: startTime,
                  endTime: endTime,
                  date: dateString,
                  isAvailable: isAvailable, // Retain availability status
                ),
              );
            } catch (e) {
              debugPrint('Error parsing date/time for slot: $dateTimeStartString. Error: $e');
            }
          }
        }

        _timeSlots = loadedSlots;

        // Group the slots by date
        for (var slot in _timeSlots) {
          _groupedTimeSlots.putIfAbsent(slot.date, () => []).add(slot);
        }

        // Set initial selected date to the first target day if available, otherwise today
        final todayApiFormat = _formatDateToApi(DateTime.now());
        if (_targetDates.contains(todayApiFormat)) {
          _selectedDate = DateTime.now().toNormalizedDate();
        } else if (_targetDates.isNotEmpty) {
          final sortedDates = _targetDates.toList()..sort();
          final earliestDateString = sortedDates.first;
          final parsedDate =
              DateFormat(
                'yyyy.MM.dd',
              ).parse(earliestDateString.replaceAll('.', '-')).toNormalizedDate();
          if (parsedDate.isAfter(DateTime.now().toNormalizedDate())) {
            _selectedDate = parsedDate;
          }
        }
        _currentMonth = _selectedDate;
      } else {
        _error = response.message ?? 'Failed to load available times.';
      }
    });
  }

  Widget _buildCalendar() {
    final now = DateTime.now().toNormalizedDate();
    final firstDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);

    // Dart's DateTime.weekday: 1=Mon, 7=Sun. We want 0 for empty space before Monday.
    final leadingEmptyDays = firstDayOfMonth.weekday == 7 ? 6 : firstDayOfMonth.weekday - 1;

    final List<Widget> dayWidgets = [];

    // 1. Add leading empty cells
    for (int i = 0; i < leadingEmptyDays; i++) {
      dayWidgets.add(const SizedBox.shrink());
    }

    // 2. Add day numbers
    for (int i = 1; i <= lastDayOfMonth.day; i++) {
      final day = DateTime(_currentMonth.year, _currentMonth.month, i).toNormalizedDate();
      final isPast = day.isBefore(now);
      final isSelected = day.isSameDay(_selectedDate);
      final hasSlots = _targetDates.contains(_formatDateToApi(day));

      // Determine the color and clickability
      Color color = Colors.transparent;
      Color textColor = isPast ? Colors.grey.shade400 : Colors.black87;

      if (isSelected) {
        color = Colors.blue.shade500;
        textColor = Colors.white;
      } else if (hasSlots && !isPast) {
        // Highlight days that have available slots
        color = Colors.green.shade100;
      }

      // Day button widget
      dayWidgets.add(
        GestureDetector(
          onTap: isPast ? null : () => _onDaySelected(day),
          // User asked for a subtle color change when disabled/past day is clicked,
          // but since `isPast` days are disabled (`onTap: null`), we'll apply a hover-like visual change on the container.
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    isSelected
                        ? Colors.blue.shade700
                        : (isPast ? Colors.grey.shade300 : Colors.transparent),
                width: isSelected ? 2 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              i.toString(),
              style: TextStyle(
                color: textColor,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                decoration: isPast ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ),
      );
    }

    const List<String> weekDays = [
      'Да',
      'Мя',
      'Лха',
      'Пү',
      'Ба',
      'Бя',
      'Ня',
    ]; // Mon, Tue, Wed, Thu, Fri, Sat, Sun

    return Column(
      children: [
        // Month and Navigation Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios),
                onPressed: _currentMonth.isSameMonth(now) ? null : _goToPrevMonth,
                color: _currentMonth.isSameMonth(now) ? Colors.grey : Colors.blue,
              ),

              Builder(
                builder: (context) {
                  final formattedDate = DateFormat('MMMM yyyy', 'mn').format(_currentMonth);
                  // Inline capitalization of the first letter
                  final capitalizedText =
                      formattedDate.isNotEmpty
                          ? formattedDate.substring(0, 1).toUpperCase() + formattedDate.substring(1)
                          : formattedDate;

                  return Text(
                    capitalizedText,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.normal),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios),
                onPressed: _goToNextMonth,
                color: Colors.blue,
              ),
            ],
          ),
        ),

        // Weekday labels
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children:
              weekDays
                  .map(
                    (day) => Center(
                      child: Text(
                        day,
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                      ),
                    ),
                  )
                  .toList(),
        ),

        // Days Grid
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 5.0,
          crossAxisSpacing: 5.0,
          childAspectRatio: 1.0, // Ensure square cells for days
          children: dayWidgets,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Status message logic
    final selectedDateApiFormat = _formatDateToApi(_selectedDate);
    final bool isTargetDay = _targetDates.contains(selectedDateApiFormat);

    String statusMessage;
    TextStyle statusStyle;

    // Check if the selected date is in the past
    final bool isPast = _selectedDate.isBefore(DateTime.now().toNormalizedDate());

    if (isPast) {
      statusMessage = 'Өнгөрсөн өдөр сонгох боломжгүй.';
      statusStyle = const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold);
    } else if (isTargetDay) {
      statusMessage = 'Боломжит цагуудаас сонгоно уу';
      statusStyle = const TextStyle(color: Colors.green, fontWeight: FontWeight.bold);
    } else {
      statusMessage =
          '${_formatDateToDisplay(_selectedDate)} нд сул цаггүй байна. Та өөр өдөр сонгоно уу';
      statusStyle = const TextStyle(color: Colors.red, fontWeight: FontWeight.bold);
    }

    // Filter slots for the selected date (All slots, including unavailable ones)
    final selectedSlots = _groupedTimeSlots[_formatDateToApi(_selectedDate)] ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Өдөр, цаг сонгох'),
        backgroundColor: const Color(0xFF00CCCC),
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Error: $_error', style: const TextStyle(color: Colors.red)),
                ),
              )
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Text(
                    //   'Available Times for Dr. ${widget.doctorName}',
                    //   style: Theme.of(context).textTheme.headlineSmall,
                    // ),
                    // const SizedBox(height: 16),

                    // 1. Calendar
                    _buildCalendar(),
                    const Divider(height: 24),

                    // 2. Status Text
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(statusMessage, style: statusStyle),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 3. Time Slot Grid (3 column)
                    if (isTargetDay && selectedSlots.isNotEmpty && !isPast)
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 2.5, // Adjust size ratio for chips
                        ),
                        itemCount: selectedSlots.length,
                        itemBuilder: (context, index) {
                          final slot = selectedSlots[index];
                          final bool enabled = slot.isAvailable;
                          final isSelected = _selectedTimeSlot?.id == slot.id;

                          return ActionChip(
                            label: Text(
                              DateFormat('HH:mm').format(slot.startTime), // Show only start time
                              style: TextStyle(
                                color:
                                    enabled
                                        ? (isSelected ? Colors.white : Colors.black87)
                                        : Colors.grey.shade600,
                                fontWeight: FontWeight.bold,
                                decoration: enabled ? null : TextDecoration.lineThrough,
                              ),
                            ),
                            backgroundColor:
                                enabled
                                    ? (isSelected ? Colors.blue.shade500 : Colors.grey.shade200)
                                    : Colors.grey.shade400, // Distinct gray for disabled slots
                            onPressed:
                                enabled
                                    ? () {
                                      setState(() {
                                        _selectedTimeSlot = isSelected ? null : slot;
                                      });
                                    }
                                    : null, // Disabled when not available
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side:
                                  isSelected
                                      ? BorderSide(color: Colors.blue.shade700, width: 2)
                                      : BorderSide.none,
                            ),
                          );
                        },
                      )
                    else if (_timeSlots.isEmpty && !_isLoading)
                      Center(child: Text('No available times found for Dr. ${widget.doctorName}')),

                    // 4. Confirm Button
                    const SizedBox(height: 30),
                    ElevatedButton(
                      onPressed:
                          _selectedTimeSlot != null
                              ? () {
                                // Handle the final appointment booking logic here
                                debugPrint('Selected Time Slot: ${_selectedTimeSlot!}');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Time Slot Selected: ${_selectedTimeSlot.toString()}',
                                    ),
                                  ),
                                );
                              }
                              : null,
                      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                      child: const Text('Confirm Time Slot'),
                    ),
                  ],
                ),
              ),
    );
  }
}
