import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:medsoft_patient/api/time_order_dao.dart';

extension DateOnlyCompare on DateTime {
  bool isSameDay(DateTime other) {
    return year == other.year && month == other.month && day == other.day;
  }

  bool isSameMonth(DateTime other) {
    return year == other.year && month == other.month;
  }

  DateTime toNormalizedDate() {
    return DateTime(year, month, day);
  }
}

class TimeSlot {
  final String id;
  final DateTime startTime;

  final String date;
  final bool isAvailable;

  TimeSlot({
    required this.id,
    required this.startTime,

    required this.date,
    required this.isAvailable,
  });

  @override
  String toString() => DateFormat('HH:mm').format(startTime);
}

class TimeSelectionScreen extends StatefulWidget {
  final String tenant;
  final String branchId;
  final String tasagId;
  final String tasagName;
  final String? employeeId;
  final String? doctorName;
  final List<dynamic> timeData;

  const TimeSelectionScreen({
    super.key,
    required this.tenant,
    required this.branchId,
    required this.tasagId,
    required this.tasagName,
    this.employeeId,
    this.doctorName,
    required this.timeData,
  });

  @override
  State<TimeSelectionScreen> createState() => _TimeSelectionScreenState();
}

class _TimeSelectionScreenState extends State<TimeSelectionScreen> {
  final TimeOrderDAO _dao = TimeOrderDAO();
  bool _isConfirming = false;

  List<TimeSlot> _timeSlots = [];
  bool _isLoading = false;
  String? _error;
  TimeSlot? _selectedTimeSlot;

  DateTime _currentMonth = DateTime.now().toNormalizedDate();
  DateTime _selectedDate = DateTime.now().toNormalizedDate();

  Set<String> _targetDates = {};

  Map<String, List<TimeSlot>> _groupedTimeSlots = {};

  @override
  void initState() {
    super.initState();

    _processTimeSlots(widget.timeData);
  }

  String _formatDateToApi(DateTime date) {
    return DateFormat('yyyy.MM.dd').format(date);
  }

  String _formatDateToDisplay(DateTime date) {
    return DateFormat('yyyy оны M сарын d').format(date);
  }

  void _goToPrevMonth() {
    final now = DateTime.now().toNormalizedDate();
    final prevMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1).toNormalizedDate();

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

    if (normalizedDay.isBefore(now)) {
      return;
    }

    setState(() {
      _selectedDate = normalizedDay;
      _selectedTimeSlot = null;
    });
  }

  void _processTimeSlots(List<dynamic> data) {
    setState(() {
      _isLoading = false;
      _error = null;
      _timeSlots = [];
      _groupedTimeSlots = {};
      _targetDates = {};
    });

    final List<TimeSlot> loadedSlots = [];

    for (var dateData in data) {
      final String dateString = dateData['targetDate'] as String;
      final List<dynamic> timesList = dateData['times'] as List<dynamic>;

      _targetDates.add(dateString);

      for (var timeData in timesList) {
        final String timeString = timeData['time'] as String;
        bool isAvailable = timeData['available'] as bool;

        if (timeString == '09:00' || timeString == '14:00' || timeString == '10:30') {
          isAvailable = false;
        }

        final String dateTimeStartString =
            '${dateString.replaceAll('.', '-')}'
            ' $timeString';

        try {
          final DateTime startTime = DateTime.parse(dateTimeStartString);

          final String slotId = '$dateTimeStartString-${widget.employeeId}';

          loadedSlots.add(
            TimeSlot(id: slotId, startTime: startTime, date: dateString, isAvailable: isAvailable),
          );
        } catch (e) {
          debugPrint('Слот-ын огноо/цагийг задлахад алдаа гарлаа: $dateTimeStartString. Алдаа: $e');
        }
      }
    }

    _timeSlots = loadedSlots;

    for (var slot in _timeSlots) {
      _groupedTimeSlots.putIfAbsent(slot.date, () => []).add(slot);
    }

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
  }

  Widget _buildCalendar() {
    final now = DateTime.now().toNormalizedDate();
    final firstDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);

    final leadingEmptyDays = firstDayOfMonth.weekday == 7 ? 6 : firstDayOfMonth.weekday - 1;

    final List<Widget> dayWidgets = [];

    for (int i = 0; i < leadingEmptyDays; i++) {
      dayWidgets.add(const SizedBox.shrink());
    }

    for (int i = 1; i <= lastDayOfMonth.day; i++) {
      final day = DateTime(_currentMonth.year, _currentMonth.month, i).toNormalizedDate();
      final isPast = day.isBefore(now);
      final isSelected = day.isSameDay(_selectedDate);
      final hasSlots = _targetDates.contains(_formatDateToApi(day));

      Color color = Colors.transparent;
      Color textColor = isPast ? Colors.grey.shade400 : Colors.black87;

      if (isSelected) {
        color = Colors.blue.shade500;
        textColor = Colors.white;
      } else if (hasSlots && !isPast) {
        color = Colors.green.shade100;
      }

      dayWidgets.add(
        GestureDetector(
          onTap: isPast ? null : () => _onDaySelected(day),
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

    const List<String> weekDays = ['Да', 'Мя', 'Лха', 'Пү', 'Ба', 'Бя', 'Ня'];

    return Column(
      children: [
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

        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 5.0,
          crossAxisSpacing: 5.0,
          childAspectRatio: 1.0,
          children: dayWidgets,
        ),
      ],
    );
  }

  Widget _buildBodyContent(
    List<TimeSlot> selectedSlots,
    bool isTargetDay,
    bool isPast,
    String statusMessage,
    TextStyle statusStyle,
    BuildContext context,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCalendar(),
        const Divider(height: 24),

        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(statusMessage, style: statusStyle),
          ),
        ),
        const SizedBox(height: 16),

        if (isTargetDay && selectedSlots.isNotEmpty && !isPast)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 5,
              crossAxisSpacing: 0,
              childAspectRatio: 2.5,
            ),
            itemCount: selectedSlots.length,
            itemBuilder: (context, index) {
              final slot = selectedSlots[index];
              final bool enabled = slot.isAvailable;
              final isSelected = _selectedTimeSlot?.id == slot.id;

              return ActionChip(
                label: Text(
                  DateFormat('HH:mm').format(slot.startTime),
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
                        : Colors.grey.shade400,
                onPressed:
                    enabled
                        ? () {
                          setState(() {
                            _selectedTimeSlot = isSelected ? null : slot;
                          });
                        }
                        : null,
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
          Center(child: Text('Сонгосон эмчид боломжит цаг олдсонгүй')),

        ElevatedButton(
          onPressed:
              _selectedTimeSlot != null && !_isConfirming
                  ? () async {
                    setState(() {
                      _isConfirming = true;
                    });

                    final body = {
                      "tenant": widget.tenant,
                      "branchId": widget.branchId,
                      "tasagId": widget.tasagId,
                      "employeeId": widget.employeeId,
                      "targetDate": _formatDateToApi(_selectedTimeSlot!.startTime),
                      "targetTime": DateFormat('HH:mm').format(_selectedTimeSlot!.startTime),
                    };

                    final response = await _dao.confirmOrder(body);

                    setState(() {
                      _isConfirming = false;
                    });

                    if (mounted) {
                      if (response.success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Цаг амжилттай захиалагдлаа.'),
                            backgroundColor: Colors.green,
                          ),
                        );

                        Navigator.of(context).pop(true);
                      } else {
                        final errorMessage =
                            response.message ??
                            'Цаг баталгаажуулахад алдаа гарлаа. Дахин оролдоно уу.';
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
                        );
                      }
                    }
                  }
                  : null,
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          child:
              _isConfirming
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
                  : const Text('Баталгаажуулах'),
        ),

        const SizedBox(height: 250),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedDateApiFormat = _formatDateToApi(_selectedDate);
    final bool isTargetDay = _targetDates.contains(selectedDateApiFormat);

    String statusMessage;
    TextStyle statusStyle;

    final bool isPast = _selectedDate.isBefore(DateTime.now().toNormalizedDate());

    if (isPast) {
      statusMessage = 'Өнгөрсөн өдөр сонгох боломжгүй.';
      statusStyle = const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold);
    } else if (isTargetDay) {
      statusMessage = 'Боломжит цагуудаас сонгоно уу';
      statusStyle = const TextStyle(color: Colors.green, fontWeight: FontWeight.bold);
    } else {
      statusMessage =
          '${_formatDateToDisplay(_selectedDate)} нд сул цаггүй байна. Та өөр өдөр сонгоно уу.';
      statusStyle = const TextStyle(color: Colors.red, fontWeight: FontWeight.bold);
    }

    final selectedSlots = _groupedTimeSlots[_formatDateToApi(_selectedDate)] ?? [];

    Map<String, String?> getTitleDetails() {
      return {'tasag': widget.tasagName, 'doctor': widget.doctorName};
    }

    Widget buildTitleWidget(BuildContext context) {
      final details = getTitleDetails();
      final tasag = details['tasag'];
      final doctor = details['doctor'];

      final bool showDoctor = doctor != null && doctor.isNotEmpty;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.only(right: 35.0),
              child: const Text(
                'Цаг сонгох',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
              ),
            ),
          ),

          const SizedBox(height: 4),

          showDoctor
              ? Text(
                'Тасаг: $tasag | Эмч: $doctor',
                style: const TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 14,
                  color: Colors.white70,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
              : SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.only(right: 35.0),
                  child: Text(
                    'Тасаг: $tasag',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.normal,
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
        ],
      );
    }

    final double screenWidth = MediaQuery.of(context).size.width;
    const double kTabletBreakpoint = 600.0;

    return Scaffold(
      appBar: AppBar(
        title: buildTitleWidget(context),
        toolbarHeight: 80,
        centerTitle: true,
        backgroundColor: const Color(0xFF00CCCC),
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Алдаа: $_error', style: const TextStyle(color: Colors.red)),
                ),
              )
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child:
                      screenWidth > kTabletBreakpoint
                          ? ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: kTabletBreakpoint),
                            child: _buildBodyContent(
                              selectedSlots,
                              isTargetDay,
                              isPast,
                              statusMessage,
                              statusStyle,
                              context,
                            ),
                          )
                          : _buildBodyContent(
                            selectedSlots,
                            isTargetDay,
                            isPast,
                            statusMessage,
                            statusStyle,
                            context,
                          ),
                ),
              ),
    );
  }
}
