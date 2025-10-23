import 'package:flutter/material.dart';
import 'package:medsoft_patient/api/time_order_dao.dart'; // Assuming this is the correct path

// Data structure to hold the list item data (name and ID/tenant)
class DropdownItem {
  final String id;
  final String name;
  final String? tenant; // Only for Hospitals
  final String? logoUrl; // NEW: Added logo URL for hospitals

  DropdownItem({
    required this.id,
    required this.name,
    this.tenant,
    this.logoUrl,
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
        _hospitals = response.data!
            .map((json) => DropdownItem(
                  id: json['id'] as String,
                  name: json['name'] as String,
                  tenant: json['tenant'] as String,
                  logoUrl: json['logoUrl'] as String?, // UPDATED: Parse logoUrl
                ))
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
                .map((json) => DropdownItem(id: json['id'] as String, name: json['name'] as String))
                .toList();
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
    if (item.logoUrl != null && item.logoUrl!.isNotEmpty) {
      // For Hospitals, show logo and name
      return Row(
        children: [
          // Constrain the network image size
          SizedBox(
            width: 24,
            height: 24,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4.0),
              child: Image.network(
                item.logoUrl!,
                fit: BoxFit.cover,
                // Fallback widget if the image fails to load
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.local_hospital,
                  color: Colors.grey,
                  size: 24,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Flexible ensures the Text widget doesn't cause overflow
          Flexible(child: Text(item.name, overflow: TextOverflow.ellipsis)),
        ],
      );
    }
    // For Branches, Departments, and Doctors, just show the name
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
    return DropdownButtonFormField<DropdownItem>(
      decoration: InputDecoration(
        labelText: labelText,
        border: const OutlineInputBorder(),
        suffixIcon: isLoading
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
      items: items.map((item) {
        return DropdownMenuItem<DropdownItem>(
          value: item,
          child: _buildItemChild(item), // UPDATED: Use the new helper
        );
      }).toList(),
      onChanged: enabled && !isLoading ? onChanged : null,
      isExpanded: true,
      hint: Text('Select $labelText'),
      validator: (value) => value == null ? 'Please select a $labelText' : null,
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  });
                  if (newValue.tenant != null) {
                    _loadBranches(newValue.tenant!);
                  }
                }
              },
            ),
            const SizedBox(height: 20),

            // 2. Branch Dropdown (getBranches)
            _buildDropdown(
              labelText: 'Branch',
              selectedValue: _selectedBranch,
              items: _branches,
              isLoading: _isLoadingBranches,
              onChanged: (DropdownItem? newValue) {
                if (newValue != null && newValue != _selectedBranch) {
                  setState(() {
                    _selectedBranch = newValue;
                  });
                  if (_selectedHospital?.tenant != null) {
                    _loadTasags(_selectedHospital!.tenant!, newValue.id);
                  }
                }
              },
              enabled: _selectedHospital != null,
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
                  // Here you would typically load times (getTimes)
                  // but this is excluded as per the request.
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
