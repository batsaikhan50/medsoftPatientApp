import 'package:flutter/material.dart';
import 'package:medsoft_patient/api/time_order_dao.dart';
import 'package:intl/intl.dart';
import 'package:marquee/marquee.dart';

// --- Огноо харьцуулах өргөтгөл ---
// DateTime обьектуудыг цагийн бүрэлдэхүүн хэсэггүйгээр харьцуулах.
extension DateOnlyCompare on DateTime {
  bool isSameDay(DateTime other) {
    return year == other.year && month == other.month && day == other.day;
  }

  bool isSameMonth(DateTime other) {
    return year == other.year && month == other.month;
  }

  // Харьцуулалт хийхэд зориулж огноог өдрийн эхлэлээр хэвийн болгох
  DateTime toNormalizedDate() {
    return DateTime(year, month, day);
  }
}
// -----------------------------------

// Цагийн Слот-ын өгөгдлийн бүтэц
class TimeSlot {
  final String id;
  final DateTime startTime;
  // final DateTime endTime;
  final String date;
  final bool isAvailable;

  TimeSlot({
    required this.id,
    required this.startTime,
    // required this.endTime,
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
  final String tasagName; // Харуулах зорилгоор
  final String? employeeId;
  final String? doctorName; // Харуулах зорилгоор
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

  // Хуанлийн төлөв
  DateTime _currentMonth = DateTime.now().toNormalizedDate();
  DateTime _selectedDate = DateTime.now().toNormalizedDate();

  // API түлхүүрүүдэд "YYYY.MM.DD" форматаар слотуудтай огноог хадгална
  Set<String> _targetDates = {};

  // Бүх цагийн слотуудыг огноогоор нь бүлэглэсэн жагсаалт
  Map<String, List<TimeSlot>> _groupedTimeSlots = {};

  @override
  void initState() {
    super.initState();
    // Call the new processing function with the data passed from the widget
    _processTimeSlots(widget.timeData);
  }

  // API түлхүүрүүдэд зориулж огнооны мөрийг тогтмол форматлах туслах функц
  String _formatDateToApi(DateTime date) {
    return DateFormat('yyyy.MM.dd').format(date);
  }

  // Төлөвийг харуулах зорилгоор огнооны мөрийг форматлах туслах функц
  String _formatDateToDisplay(DateTime date) {
    return DateFormat('yyyy оны M сарын d').format(date);
  }

  // --- Хуанлийн удирдлагын аргууд ---
  void _goToPrevMonth() {
    final now = DateTime.now().toNormalizedDate();
    final prevMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1).toNormalizedDate();

    // Одоогийн сараас өмнөх сар руу шилжихийг хориглох
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

    // 1. Тухайн өдөр өнгөрсөн эсэхийг шалгах
    if (normalizedDay.isBefore(now)) {
      return;
    }

    setState(() {
      _selectedDate = normalizedDay;
      _selectedTimeSlot = null; // Огноо солигдоход сонголтыг цэвэрлэх
    });
  }

  // -----------------------------------
  void _processTimeSlots(List<dynamic> data) {
    setState(() {
      _isLoading = false; // Set loading to false immediately as data is present
      _error = null;
      _timeSlots = [];
      _groupedTimeSlots = {};
      _targetDates = {};
    });

    final List<TimeSlot> loadedSlots = [];

    // 1. Огнооны обьектуудын жагсаалтаар давтах
    for (var dateData in data) {
      // Use the passed-in 'data' list
      final String dateString = dateData['targetDate'] as String;
      final List<dynamic> timesList = dateData['times'] as List<dynamic>;

      // Слоттой огноог нэмэх
      _targetDates.add(dateString);

      // 2. Цагийн обьектуудын жагсаалтаар давтах
      for (var timeData in timesList) {
        final String timeString = timeData['time'] as String;
        bool isAvailable = timeData['available'] as bool;

        // --- ТУРШИЛТЫН ҮНЭЛГЭЭ: Боломжгүй слотуудыг симуляц хийх ---
        if (timeString == '09:00' || timeString == '14:00' || timeString == '10:30') {
          isAvailable = false; // Туршилтанд зориулж зарим цагийг боломжгүй болгох
        }
        // ---------------------------------------------------

        // 3. Огноо ба цагийг нэгтгэж бүрэн DateTime обьект үүсгэх
        final String dateTimeStartString =
            '${dateString.replaceAll('.', '-')}'
            ' $timeString';

        try {
          final DateTime startTime = DateTime.parse(dateTimeStartString);
          // Слот бүрийг 15 минут гэж үзэх
          // final DateTime endTime = startTime.add(const Duration(minutes: 15));

          final String slotId = '$dateTimeStartString-${widget.employeeId}';

          loadedSlots.add(
            TimeSlot(
              id: slotId,
              startTime: startTime,
              // endTime: endTime,
              date: dateString,
              isAvailable: isAvailable, // Боломжит байдлын төлөвийг хадгалах
            ),
          );
        } catch (e) {
          debugPrint('Слот-ын огноо/цагийг задлахад алдаа гарлаа: $dateTimeStartString. Алдаа: $e');
        }
      }
    }

    _timeSlots = loadedSlots;

    // Слотуудыг огноогоор нь бүлэглэх
    for (var slot in _timeSlots) {
      _groupedTimeSlots.putIfAbsent(slot.date, () => []).add(slot);
    }

    // Хэрэв боломжтой бол сонгосон огноог эхний зорилтот өдөр, үгүй бол өнөөдрөөр тохируулах
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

    // Dart's DateTime.weekday: 1=Mon, 7=Sun. Даваа гаригаас өмнөх хоосон зайг 0 болгох.
    final leadingEmptyDays = firstDayOfMonth.weekday == 7 ? 6 : firstDayOfMonth.weekday - 1;

    final List<Widget> dayWidgets = [];

    // 1. Эхний хоосон нүднүүдийг нэмэх
    for (int i = 0; i < leadingEmptyDays; i++) {
      dayWidgets.add(const SizedBox.shrink());
    }

    // 2. Өдөрүүдийн дугаарыг нэмэх
    for (int i = 1; i <= lastDayOfMonth.day; i++) {
      final day = DateTime(_currentMonth.year, _currentMonth.month, i).toNormalizedDate();
      final isPast = day.isBefore(now);
      final isSelected = day.isSameDay(_selectedDate);
      final hasSlots = _targetDates.contains(_formatDateToApi(day));

      // Өнгө ба дарж болох эсэхийг тодорхойлох
      Color color = Colors.transparent;
      Color textColor = isPast ? Colors.grey.shade400 : Colors.black87;

      if (isSelected) {
        color = Colors.blue.shade500;
        textColor = Colors.white;
      } else if (hasSlots && !isPast) {
        // Боломжит слотуудтай өдрүүдийг тодруулах
        color = Colors.green.shade100;
      }

      // Өдрийн товчлуур
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

    const List<String> weekDays = [
      'Да',
      'Мя',
      'Лха',
      'Пү',
      'Ба',
      'Бя',
      'Ня',
    ]; // Да, Мя, Лха, Пү, Ба, Бя, Ня

    return Column(
      children: [
        // Сар ба навигацийн толгой
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
                  // Эхний үсгийг томруулах
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

        // Ажлын өдөрүүдийн шошго
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

        // Өдөрүүдийн сүлжээ
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 5.0,
          crossAxisSpacing: 5.0,
          childAspectRatio: 1.0, // Дөрвөлжин нүд
          children: dayWidgets,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Төлөвийн мэдээллийн логик
    final selectedDateApiFormat = _formatDateToApi(_selectedDate);
    final bool isTargetDay = _targetDates.contains(selectedDateApiFormat);

    String statusMessage;
    TextStyle statusStyle;

    // Сонгосон огноо өнгөрсөн эсэхийг шалгах
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

    // Сонгосон өдрийн слотуудыг шүүх (Боломжгүй слотуудыг оруулан)
    final selectedSlots = _groupedTimeSlots[_formatDateToApi(_selectedDate)] ?? [];
    // Энэ функц нь одоо ганц форматлагдсан мөрийн оронд өгөгдлийн жагсаалтыг буцаана.
    Map<String, String?> getTitleDetails() {
      return {'tasag': widget.tasagName, 'doctor': widget.doctorName};
    }

    Widget buildTitleWidget(BuildContext context) {
      final details = getTitleDetails();
      final tasag = details['tasag'];
      final doctor = details['doctor'];

      // Эмчийг харуулах эсэхийг тодорхойлох
      final bool showDoctor = doctor != null && doctor.isNotEmpty;

      return Column(
        // ЧУХАЛ: Бүх баганын агуулгыг зүүн талд зэрэгцүүлэх, гэхдээ доорх нөхцөлтөөр давуу эрх олгоно
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, // Босоо зайг хамгийн багаар авах
        children: [
          // 1. Үндсэн гарчиг (Төвлөрсөн)
          SizedBox(
            // Боломжит гарчгийн зайг дүүргэхийн тулд double.infinity-г ашиглах
            width: double.infinity,
            child: Padding(
              // Хүрээний ирмэг эсвэл боломжит дүрс тэмдэгтэй мөргөлдөхөөс сэргийлж баруун талд зай авах
              padding: const EdgeInsets.only(right: 35.0),
              child: const Text(
                'Цаг сонгох', // Үндсэн гарчиг
                textAlign: TextAlign.center, // Боломжит зай дотор текстийг төвлөрүүлэх
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
              ),
            ),
          ),

          const SizedBox(height: 4), // Жижиг тусгаарлагч
          // 2. Тасаг ба Эмчийн дэлгэрэнгүй мэдээлэл (Нөхцөлт зэрэгцүүлэлт)
          showDoctor
              ? Text(
                // Хэрэв эмч байгаа бол зүүн талд зэрэгцүүлэх
                'Тасаг: $tasag | Эмч: $doctor',
                style: const TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 14, // Дэлгэрэнгүй мэдээллийн мөрийн жижиг үсгийн хэмжээ
                  color: Colors.white70, // Хоёрдогч мэдээллийн хувьд бага зэрэг бүдэг өнгө
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
              : SizedBox(
                // Хэрэв эмч байхгүй бол төвлөрүүлэхийн тулд SizedBox ашиглах
                width: double.infinity,
                child: Padding(
                  // Үндсэн гарчигтай ижил баруун зайг ашиглах
                  padding: const EdgeInsets.only(right: 35.0),
                  child: Text(
                    'Тасаг: $tasag',
                    textAlign: TextAlign.center, // Тасгийн нэрийг төвлөрүүлэх
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
    // ... _TimeSelectionScreenState-ийн build метод дотор:

    // ...

    // final String titleText = getAppBarTitle();
    return Scaffold(
      appBar: AppBar(
        // 💥 Энд тусгай виджетийг ашиглах 💥
        title: buildTitleWidget(context),

        // Агуулга өөрчлөгдөхөд үсрэхээс сэргийлж тогтмол өндрийг тохируулах
        toolbarHeight: 80,

        // Гарчгийг AppBar-ын өндөр дотор босоо чиглэлд төвлөрүүлэхийг баталгаажуулах
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Хуанли
                    _buildCalendar(),
                    const Divider(height: 24),

                    // 2. Төлөвийн текст
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(statusMessage, style: statusStyle),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 3. Цагийн Слот-ын сүлжээ (3 багана)
                    if (isTargetDay && selectedSlots.isNotEmpty && !isPast)
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 5,
                          crossAxisSpacing: 0,
                          childAspectRatio: 2.5, // Чипний хэмжээний харьцааг тохируулах
                        ),
                        itemCount: selectedSlots.length,
                        itemBuilder: (context, index) {
                          final slot = selectedSlots[index];
                          final bool enabled = slot.isAvailable;
                          final isSelected = _selectedTimeSlot?.id == slot.id;

                          return ActionChip(
                            label: Text(
                              DateFormat(
                                'HH:mm',
                              ).format(slot.startTime), // Зөвхөн эхлэх цагийг харуулах
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
                                    : Colors
                                        .grey
                                        .shade400, // Боломжгүй слотуудад зориулсан ялгаатай саарал өнгө
                            onPressed:
                                enabled
                                    ? () {
                                      setState(() {
                                        _selectedTimeSlot = isSelected ? null : slot;
                                      });
                                    }
                                    : null, // Боломжгүй бол disable хийх
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

                    // 4. Баталгаажуулах товчлуур
                    // const SizedBox(height: 10),
                    // time_selection_screen.dart (Confirmation Button Widget)
                    // time_selection_screen.dart (Confirmation Button Widget onPressed)
                    ElevatedButton(
                      onPressed:
                          _selectedTimeSlot != null && !_isConfirming
                              ? () async {
                                setState(() {
                                  _isConfirming = true;
                                });

                                // 1. Prepare the API body (same as before)
                                final body = {
                                  "tenant": widget.tenant,
                                  "branchId": widget.branchId,
                                  "tasagId": widget.tasagId,
                                  "employeeId": widget.employeeId,
                                  "targetDate": _formatDateToApi(_selectedTimeSlot!.startTime),
                                  "targetTime": DateFormat(
                                    'HH:mm',
                                  ).format(_selectedTimeSlot!.startTime),
                                };

                                // 2. Call the API
                                final response = await _dao.confirmOrder(body);

                                // Update loading state immediately after API call
                                setState(() {
                                  _isConfirming = false;
                                });

                                if (mounted) {
                                  // 3. Show SnackBar based on success/failure
                                  if (response.success) {
                                    // SUCCESS Logic: Show SnackBar, then pop (and pass true)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Цаг амжилттай захиалагдлаа.',
                                        ), // Order successfully confirmed
                                        backgroundColor: Colors.green,
                                      ),
                                    );

                                    // 4. Pop the screen ONLY on success
                                    Navigator.of(context).pop(true);
                                  } else {
                                    // FAILURE Logic: Show SnackBar, DO NOT POP (remain on screen)
                                    final errorMessage =
                                        response.message ??
                                        'Цаг баталгаажуулахад алдаа гарлаа. Дахин оролдоно уу.';
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(errorMessage),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                    // We do not pop here, so the user can try again or select a different slot.
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
                ),
              ),
    );
  }
}
