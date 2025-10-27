import 'package:flutter/material.dart';
import 'package:medsoft_patient/api/time_order_dao.dart';
import 'package:medsoft_patient/time_order/time_selection_screen.dart'; // Assuming this is the correct path

// Data structure to hold the list item data (name and ID/tenant)
class DropdownItem {
  final String id;
  final String name;
  final String? tenant; // Only for Hospitals
  final String? logoUrl; // UPDATED: Now also used for Branch imgLink

  // NEW fields for Branch details
  final List<String>? phones;
  final String? facebook;
  final bool isAvailable; // ADDED: To track availability status

  DropdownItem({
    required this.id,
    required this.name,
    this.tenant,
    this.logoUrl,
    this.phones,
    this.facebook,
    this.isAvailable =
        true, // Default to true if not specified (e.g., for Tasags/Doctors/Hospitals where 'available' isn't explicitly checked)
  });

  @override
  String toString() => name;
}

class TimeOrderScreen extends StatefulWidget {
  const TimeOrderScreen({super.key});

  @override
  State<TimeOrderScreen> createState() => _TimeOrderScreenState();
}

class _TimeOrderScreenState extends State<TimeOrderScreen> {
  final TimeOrderDAO _dao = TimeOrderDAO();

  // State for fetched data
  List<DropdownItem> _hospitals = [];
  List<DropdownItem> _branches = [];
  List<DropdownItem> _tasags = [];
  List<DropdownItem> _doctors = [];

  // State for selected values
  DropdownItem? _selectedHospital;
  DropdownItem? _selectedBranch;
  DropdownItem? _selectedTasag;
  DropdownItem? _selectedDoctor;

  // Loading state
  bool _isLoadingHospitals = false;
  bool _isLoadingBranches = false;
  bool _isLoadingTasags = false;
  bool _isLoadingDoctors = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHospitals();
  }

  // Placeholder function for launching URLs (e.g., phone calls or Facebook links)
  void _launchUrl(String url) {
    // NOTE: In a real Flutter application, you would use 'package:url_launcher'
    // and call: await launchUrl(Uri.parse(url));
    debugPrint('Attempting to launch URL/Phone: $url');
  }

  void _showWarningDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Branch Unavailable'),
          content: Text(message),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
          ],
        );
      },
    );
  }

  // --- Data Loading Functions ---
  Future<void> _loadHospitals() async {
    setState(() {
      _isLoadingHospitals = true;
      _error = null;
    });
    final response = await _dao.getAllHospitals();
    setState(() {
      _isLoadingHospitals = false;
      if (response.success && response.data != null) {
        _hospitals =
            response.data!
                .map(
                  (json) => DropdownItem(
                    id: json['id'] as String,
                    name: json['name'] as String,
                    tenant: json['tenant'] as String,
                    logoUrl: json['logoUrl'] as String?, // UPDATED: Parse logoUrl
                  ),
                )
                .toList();
      } else {
        _error = response.message ?? 'Failed to load hospitals.';
      }
    });
  }

  Future<void> _loadBranches(String tenant) async {
    setState(() {
      _isLoadingBranches = true;
      _branches = [];
      _selectedBranch = null;
      _tasags = [];
      _selectedTasag = null;
      _doctors = [];
      _selectedDoctor = null;
      _error = null;
    });

    final response = await _dao.getBranches(tenant);

    setState(() {
      _isLoadingBranches = false;
      if (response.success && response.data != null) {
        _branches =
            response.data!
                .map(
                  (json) => DropdownItem(
                    id: json['id'] as String,
                    name: json['name'] as String,
                    logoUrl: json['imgLink'] as String?,
                    phones:
                        (json['phone'] is List)
                            ? (json['phone'] as List).map((p) => p.toString()).toList()
                            : null,
                    facebook: json['facebook'] as String?,
                    isAvailable: json['available'] as bool, // CHANGED: Map 'available'
                  ),
                )
                .toList();

        // NEW: Sort the branches to place available ones first
        _branches.sort((a, b) {
          // Sorting: True (available) comes before False (unavailable).
          // We use -1 to put the available branches first in the list.
          if (a.isAvailable && !b.isAvailable) return -1;
          if (!a.isAvailable && b.isAvailable) return 1;
          // If both are same availability, sort alphabetically by name
          return a.name.compareTo(b.name);
        });
      } else {
        _error = response.message ?? 'Failed to load branches.';
      }
    });
  }

  Future<void> _loadTasags(String tenant, String branchId) async {
    setState(() {
      _isLoadingTasags = true;
      _tasags = [];
      _selectedTasag = null;
      _doctors = [];
      _selectedDoctor = null;
      _error = null;
    });

    final response = await _dao.getTasags(tenant, branchId);

    setState(() {
      _isLoadingTasags = false;
      if (response.success && response.data != null) {
        _tasags =
            response.data!
                .map((json) => DropdownItem(id: json['id'] as String, name: json['name'] as String))
                .toList();
        debugPrint('Loaded tasags: $_tasags');
      } else {
        _error = response.message ?? 'Failed to load departments.';
      }
    });
  }

  Future<void> _loadDoctors(String tenant, String branchId, String tasagId) async {
    setState(() {
      _isLoadingDoctors = true;
      _doctors = [];
      _selectedDoctor = null;
      _error = null;
    });

    final response = await _dao.getDoctors(tenant, branchId, tasagId);

    setState(() {
      _isLoadingDoctors = false;
      if (response.success && response.data != null) {
        _doctors =
            response.data!
                .map((json) => DropdownItem(id: json['id'] as String, name: json['name'] as String))
                .toList();
      } else {
        _error = response.message ?? 'Failed to load doctors.';
      }
    });
  }

  // --- Widget Builders ---
  Widget _buildItemChild(DropdownItem item) {
    // Determine if it's a Hospital (has tenant and logoUrl)
    final bool isHospitalWithLogo =
        item.tenant != null && item.logoUrl != null && item.logoUrl!.isNotEmpty;

    // Determine if it's a Branch (no tenant, but has logoUrl)
    final bool isBranchWithLogo =
        item.tenant == null && item.logoUrl != null && item.logoUrl!.isNotEmpty;

    // Determine if the branch is unavailable
    final bool isBranchUnavailable = isBranchWithLogo && !item.isAvailable;

    // Determine if the branch is available
    final bool isBranchAvailable = isBranchWithLogo && item.isAvailable;

    if (isHospitalWithLogo) {
      // 1. HOSPITAL LAYOUT: Logo next to the name (standard, compact)
      return Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4.0),
              child: Image.network(
                item.logoUrl!,
                fit: BoxFit.cover,
                errorBuilder:
                    (context, error, stackTrace) =>
                        const Icon(Icons.local_hospital, color: Colors.grey, size: 24),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(child: Text(item.name, overflow: TextOverflow.ellipsis)),
        ],
      );
    } else if (isBranchWithLogo) {
      // 2. BRANCH LAYOUT: Image Banner with Overlayed Name (used for menu item options)
      const double bannerHeight = 220.0;

      return Opacity(
        // Opacity handles the grayed-out effect
        opacity: isBranchUnavailable ? 0.8 : 1.0,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: Container(
            height: bannerHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Full-width Image (Banner)
                ColorFiltered(
                  // B&W filter applied if unavailable
                  colorFilter:
                      isBranchUnavailable
                          ? const ColorFilter.matrix(<double>[
                            0.2126,
                            0.7152,
                            0.0722,
                            0,
                            0,
                            0.2126,
                            0.7152,
                            0.0722,
                            0,
                            0,
                            0.2126,
                            0.7152,
                            0.0722,
                            0,
                            0,
                            0,
                            0,
                            0,
                            1,
                            0,
                          ])
                          : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
                  child: Image.network(
                    item.logoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (context, error, stackTrace) => Container(
                          color: Colors.grey[400],
                          child: const Center(
                            child: Icon(Icons.apartment, color: Colors.white, size: 40),
                          ),
                        ),
                  ),
                ),

                // 2. Overlayed Text Container (at the bottom)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                    color: Colors.black38,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Branch Name
                        Text(
                          item.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 4),

                        // NEW STRUCTURE: Phones and Facebook links
                        if ((item.phones != null && item.phones!.isNotEmpty) ||
                            (item.facebook != null && item.facebook!.isNotEmpty))
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // A. Phones (Using Wrap for multiple lines)
                              if (item.phones != null && item.phones!.isNotEmpty)
                                Wrap(
                                  spacing: 8.0,
                                  runSpacing: 4.0,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    const Icon(Icons.phone, color: Colors.white70, size: 14),
                                    ...item.phones!
                                        .map(
                                          (phone) => InkWell(
                                            // Disabled for unavailable branches
                                            onTap:
                                                isBranchUnavailable
                                                    ? null
                                                    : () => _launchUrl('tel:$phone'),
                                            child: Text(
                                              phone,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                decoration:
                                                    isBranchUnavailable
                                                        ? TextDecoration.none
                                                        : TextDecoration.underline,
                                                decorationColor: Colors.white,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ],
                                ),

                              if ((item.phones != null && item.phones!.isNotEmpty) &&
                                  (item.facebook != null && item.facebook!.isNotEmpty))
                                const SizedBox(height: 8),

                              // B. Facebook (Pushed to the bottom-right using a Row)
                              if (item.facebook != null && item.facebook!.isNotEmpty)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    InkWell(
                                      // Disabled for unavailable branches
                                      onTap:
                                          isBranchUnavailable
                                              ? null
                                              : () => _launchUrl(item.facebook!),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.facebook, color: Colors.blueAccent, size: 14),
                                          SizedBox(width: 4),
                                          Text(
                                            'Facebook Page',
                                            style: TextStyle(
                                              color: Colors.blueAccent,
                                              fontSize: 14,
                                              decoration: TextDecoration.underline,
                                              decorationColor: Colors.blueAccent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),

                // 3. UNAVAILABLE CAPTION (Mongolian Text)
                if (isBranchUnavailable)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'ОНЛАЙН ҮЗЛЭГИЙН ХУВААРЬ БАЙХГҮЙ',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),

                // 4. CLICKABLE INDICATOR (Pulsing Animation)
                if (isBranchAvailable)
                  const Positioned(top: 50, right: 50, child: PulsingClickIndicator()),
              ],
            ),
          ),
        ),
      );
    }

    // 3. DEFAULT LAYOUT: Just the name (for Tasags, Doctors, and items without logo)
    return Text(item.name);
  }

  Widget _buildDropdown({
    required String labelText,
    required DropdownItem? selectedValue,
    required List<DropdownItem> items,
    required bool isLoading,
    required ValueChanged<DropdownItem?> onChanged,
    bool enabled = true,
  }) {
    final bool isBranchDropdown = labelText == 'Branch';

    return DropdownButtonFormField<DropdownItem>(
      decoration: InputDecoration(
        labelText: labelText,
        border: const OutlineInputBorder(),
        suffixIcon:
            isLoading
                ? const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
                : null,
      ),
      value: selectedValue,

      selectedItemBuilder:
          isBranchDropdown
              ? (context) {
                return items.map((item) {
                  // When selected, display only the name as simple text
                  return Text(
                    item.name,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  );
                }).toList();
              }
              : null,

      items:
          items.map((item) {
            final bool isUnavailableBranch = isBranchDropdown && !item.isAvailable; // NEW Check

            return DropdownMenuItem<DropdownItem>(
              value: item,
              child: _buildItemChild(item),
              // NEW: We disable the item if it's an unavailable branch.
              enabled: !isUnavailableBranch,
            );
          }).toList(),

      onChanged:
          enabled && !isLoading
              ? (DropdownItem? newValue) {
                if (isBranchDropdown && newValue != null && !newValue.isAvailable) {
                  // NEW: Show warning for unavailable branch selection
                  _showWarningDialog(
                    'You cannot choose this branch (${newValue.name}) as it is currently unavailable. Please select another available branch.',
                  );
                  // Do NOT call onChanged to keep the previous selection or null
                  return;
                }
                // Proceed with normal selection for all other cases
                onChanged(newValue);
              }
              : null,
      isExpanded: true,
      hint: Text('Select $labelText'),
      validator: (value) => value == null ? 'Please select a $labelText' : null,
    );
  }
  // NOTE: The _showBranchGridDialog function has been removed as requested.

  @override
  Widget build(BuildContext context) {
    // Determine if the branch selection is enabled
    final isBranchSelectorEnabled = _selectedHospital != null && !_isLoadingBranches;

    return Scaffold(
      // appBar: AppBar(title: const Text('Time Order')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 1. Hospital Dropdown (getAllHospitals)
            _buildDropdown(
              labelText: 'Hospital',
              selectedValue: _selectedHospital,
              items: _hospitals,
              isLoading: _isLoadingHospitals,
              onChanged: (DropdownItem? newValue) {
                if (newValue != null && newValue != _selectedHospital) {
                  setState(() {
                    _selectedHospital = newValue;
                    _selectedBranch = null; // Clear branch when hospital changes
                    _selectedTasag = null;
                    _selectedDoctor = null;
                  });
                  if (newValue.tenant != null) {
                    _loadBranches(newValue.tenant!);
                  }
                }
              },
            ),
            const SizedBox(height: 20),

            // 2. Branch Dropdown (getBranches) - Reverted to standard dropdown
            _buildDropdown(
              labelText: 'Branch',
              selectedValue: _selectedBranch,
              items: _branches,
              isLoading: _isLoadingBranches,
              onChanged: (DropdownItem? newValue) {
                if (newValue != null && newValue != _selectedBranch) {
                  setState(() {
                    _selectedBranch = newValue;
                    // Reset dependents upon new branch selection
                    _tasags = [];
                    _selectedTasag = null;
                    _doctors = [];
                    _selectedDoctor = null;
                  });
                  if (_selectedHospital?.tenant != null) {
                    // Only load tasags if a hospital is selected
                    _loadTasags(_selectedHospital!.tenant!, newValue.id);
                  }
                }
              },
              enabled: _selectedHospital != null, // Enable only after hospital is selected
            ),
            const SizedBox(height: 20),

            // 3. Department (Tasag) Dropdown (getTasags)
            _buildDropdown(
              labelText: 'Department (Tasag)',
              selectedValue: _selectedTasag,
              items: _tasags,
              isLoading: _isLoadingTasags,
              onChanged: (DropdownItem? newValue) {
                if (newValue != null && newValue != _selectedTasag) {
                  setState(() {
                    _selectedTasag = newValue;
                  });
                  if (_selectedHospital?.tenant != null && _selectedBranch != null) {
                    _loadDoctors(_selectedHospital!.tenant!, _selectedBranch!.id, newValue.id);
                  }
                }
              },
              enabled: _selectedBranch != null,
            ),
            const SizedBox(height: 20),

            // 4. Doctor Dropdown (getDoctors)
            _buildDropdown(
              labelText: 'Doctor',
              selectedValue: _selectedDoctor,
              items: _doctors,
              isLoading: _isLoadingDoctors,
              onChanged: (DropdownItem? newValue) {
                if (newValue != null) {
                  setState(() {
                    _selectedDoctor = newValue;
                  });

                  // NEW: Navigate to TimeSelectionScreen

                  if (_selectedHospital?.tenant != null &&
                      _selectedBranch != null &&
                      _selectedTasag != null) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder:
                            (context) => TimeSelectionScreen(
                              tenant: _selectedHospital!.tenant!,
                              branchId: _selectedBranch!.id,
                              tasagId: _selectedTasag!.id,
                              employeeId: newValue.id,
                              doctorName: newValue.name, // Pass the name for display
                            ),
                      ),
                    );
                  }
                }
              },
              enabled: _selectedTasag != null,
            ),
            const SizedBox(height: 30),

            if (_error != null) Text('Error: $_error', style: const TextStyle(color: Colors.red)),

            // Example of usage: Display selected values
            const Divider(),
            const Text('Selected Order Details:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              'Hospital: ${_selectedHospital?.name ?? 'N/A'} (Tenant: ${_selectedHospital?.tenant ?? 'N/A'})',
            ),
            Text('Branch: ${_selectedBranch?.name ?? 'N/A'}'),
            Text('Department (Tasag): ${_selectedTasag?.name ?? 'N/A'}'),
            Text('Doctor: ${_selectedDoctor?.name ?? 'N/A'}'),
          ],
        ),
      ),
    );
  }
}

// Helper widget for the animated click indicator
class PulsingClickIndicator extends StatefulWidget {
  const PulsingClickIndicator({super.key});

  @override
  State<PulsingClickIndicator> createState() => _PulsingClickIndicatorState();
}

class _PulsingClickIndicatorState extends State<PulsingClickIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600), // Cycle duration
    )..repeat(reverse: true); // Repeat the animation, reversing direction

    // MODIFIED: Change Tween to animate the scale factor (zoom effect)
    // Starts at 80% (0.8) of the original size and zooms out to 100% (1.0).
    _animation = Tween(begin: 0.7, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // MODIFIED: Use ScaleTransition instead of FadeTransition
    return ScaleTransition(
      scale: _animation,
      child: const Icon(Icons.touch_app, color: Colors.white, size: 45),
    );
  }
}
