import 'package:flutter/material.dart';
import 'package:medsoft_patient/api/time_order_dao.dart';
import 'package:intl/intl.dart'; 

// Data structure for Time Slot
class TimeSlot {
  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final String date;
  final bool isAvailable; // ADDED: Status of the slot

  TimeSlot({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.date,
    required this.isAvailable, // ADDED
  });

  @override
  String toString() => '${DateFormat('HH:mm').format(startTime)} - ${DateFormat('HH:mm').format(endTime)}';
}

class TimeSelectionScreen extends StatefulWidget {
  final String tenant;
  final String branchId;
  final String tasagId;
  final String employeeId; // UPDATED: Consistent name for API payload
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

  // Grouped list of time slots by date for better display
  Map<String, List<TimeSlot>> _groupedTimeSlots = {};

  @override
  void initState() {
    super.initState();
    _loadTimeSlots();
  }

  Future<void> _loadTimeSlots() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _timeSlots = [];
      _groupedTimeSlots = {};
    });

    // Construct the body for the getTimes POST request
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
          final String dateString = dateData['targetDate'] as String; // e.g., "2025.10.25"
          final List<dynamic> timesList = dateData['times'] as List<dynamic>;

          // 2. Iterate over the nested list of Time objects
          for (var timeData in timesList) {
            final String timeString = timeData['time'] as String; // e.g., "08:00"
            bool isAvailable = timeData['available'] as bool;
            
            // --- TESTING OVERRIDE: Simulate unavailable slots ---
            if (timeString == '09:00' || timeString == '14:00' || timeString == '10:30') {
              isAvailable = false; // Force certain times to be unavailable for testing
              debugPrint('TESTING: Slot at $timeString on $dateString marked UNABLE.');
            }
            // ---------------------------------------------------

            // 3. Combine date and time to create the full DateTime object
            // Replace '.' with '-' for the date part: "2025-10-25 08:00"
            final String dateTimeStartString = 
                '${dateString.replaceAll('.', '-')}'
                ' ${timeString}';
            
            try {
              final DateTime startTime = DateTime.parse(dateTimeStartString);
              // Assuming each slot is 15 minutes
              final DateTime endTime = startTime.add(const Duration(minutes: 15)); 
              
              // Using the full datetime string as a temporary ID.
              final String slotId = '$dateTimeStartString-${widget.employeeId}'; 

              loadedSlots.add(
                TimeSlot(
                  id: slotId,
                  startTime: startTime,
                  endTime: endTime,
                  date: dateString,
                  isAvailable: isAvailable, // Now passing the status
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
        
      } else {
        _error = response.message ?? 'Failed to load available times.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Appointment Time'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text('Error: $_error', style: const TextStyle(color: Colors.red)),
                  ),
                )
              : _timeSlots.isEmpty
                  ? Center(child: Text('No available times found for Dr. ${widget.doctorName}'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Available Times for Dr. ${widget.doctorName}',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 16),
                          ..._groupedTimeSlots.keys.map((date) {
                            final slots = _groupedTimeSlots[date]!;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                                  child: Text(
                                    DateFormat('EEEE, MMM d, yyyy').format(slots.first.startTime),
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: slots.map((slot) {
                                    final isSelected = _selectedTimeSlot?.id == slot.id;
                                    final bool enabled = slot.isAvailable;

                                    return ChoiceChip(
                                      label: Text(
                                        '${DateFormat('HH:mm').format(slot.startTime)} - ${DateFormat('HH:mm').format(slot.endTime)}',
                                      ),
                                      // Only select if it is available and currently selected
                                      selected: isSelected && enabled, 
                                      
                                      // Disable selection (onSelected = null) if not available
                                      onSelected: enabled
                                          ? (selected) {
                                              setState(() {
                                                // If we select a slot, ensure it is set. If we deselect, clear it.
                                                _selectedTimeSlot = selected ? slot : null;
                                              });
                                            }
                                          : null, // This makes the chip unclickable
                                      
                                      // Styling for available vs. unavailable
                                      selectedColor: Colors.blue.shade100,
                                      // Use a gray background for unavailable slots
                                      backgroundColor: enabled ? Colors.grey.shade100 : Colors.grey.shade200, 
                                      
                                      labelStyle: TextStyle(
                                        color: enabled
                                            ? (isSelected ? Colors.blue.shade900 : Colors.black87)
                                            : Colors.grey.shade600, // Gray text for unavailable
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        // Optional: Add a subtle line through for visual confirmation
                                        decoration: enabled ? null : TextDecoration.lineThrough, 
                                      ),
                                    );
                                  }).toList(),
                                ),
                                const Divider(height: 30),
                              ],
                            );
                          }).toList(),
                          
                          const SizedBox(height: 30),
                          ElevatedButton(
                            onPressed: _selectedTimeSlot != null
                                ? () {
                                    // Handle the final appointment booking logic here
                                    debugPrint('Selected Time Slot: ${_selectedTimeSlot!}');
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Time Slot Selected: ${_selectedTimeSlot.toString()}')),
                                    );
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                            ),
                            child: const Text('Confirm Time Slot'),
                          ),
                        ],
                      ),
                    ),
    );
  }
}
