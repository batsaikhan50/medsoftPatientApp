import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:medsoft_patient/api/time_order_dao.dart';
import 'package:medsoft_patient/login.dart';
import 'package:medsoft_patient/time_order/branch_select_widget.dart';
import 'package:medsoft_patient/time_order/time_selection_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class DropdownItem {
  final String id;
  final String name;
  final String? tenant;
  final String? logoUrl;

  final List<String>? phones;
  final String? facebook;
  final bool isAvailable;

  DropdownItem({
    required this.id,
    required this.name,
    this.tenant,
    this.logoUrl,
    this.phones,
    this.facebook,
    this.isAvailable = true,
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

  List<dynamic>? _preFetchedTimeSlots;
  bool _isLoadingTimeSlots = false;

  List<DropdownItem> _hospitals = [];
  List<DropdownItem> _branches = [];
  List<DropdownItem> _tasags = [];
  List<DropdownItem> _doctors = [];

  DropdownItem? _selectedHospital;
  DropdownItem? _selectedBranch;
  DropdownItem? _selectedTasag;
  DropdownItem? _selectedDoctor;

  bool _isLoadingHospitals = false;
  bool _isLoadingBranches = false;
  bool _isLoadingTasags = false;
  bool _isLoadingDoctors = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final shortestSide = MediaQuery.of(context).size.shortestSide;
      debugPrint('shortestSide : $shortestSide');

      const double tabletBreakpoint = 600;

      if (shortestSide < tabletBreakpoint) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    });

    _loadHospitals();
  }

  Future<void> _launchUrl(String url) async {
    if (url.startsWith('tel:')) {
      final Uri telUri = Uri.parse(url);
      if (await canLaunchUrl(telUri)) {
        await launchUrl(telUri, mode: LaunchMode.platformDefault);
      } else {
        _showWarningSnackbar('Уучлаарай, утас руу залгах боломжгүй байна.');
      }
      return;
    }

    if (url.contains('facebook.com')) {
      final pageIdOrName = url.split('/').last.split('?').first;

      debugPrint('Extracted Facebook ID/Name: $pageIdOrName');

      Uri fbUri;
      if (Platform.isIOS) {
        fbUri = Uri.parse('fb://page/$pageIdOrName');
      } else if (Platform.isAndroid) {
        fbUri = Uri.parse('fb://page/$pageIdOrName');
      } else {
        fbUri = Uri.parse(url);
      }
      debugPrint('fbUri: $fbUri');

      if (await canLaunchUrl(fbUri)) {
        await launchUrl(fbUri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    final Uri webUri = Uri.parse(url);
    if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } else {
      _showWarningSnackbar('Уучлаарай, холбоосыг нээх боломжгүй байна: $url');
      debugPrint('Could not launch $url');
    }
  }

  Future<void> _checkAvailableTimeSlots() async {
    if (_selectedHospital == null || _selectedBranch == null || _selectedTasag == null) {
      setState(() {
        _preFetchedTimeSlots = null;
        _isLoadingTimeSlots = false;
      });
      return;
    }

    setState(() {
      _isLoadingTimeSlots = true;
      _preFetchedTimeSlots = null;
    });

    final body = {
      'tenant': _selectedHospital!.tenant,
      'branchId': _selectedBranch!.id,
      'tasagId': _selectedTasag!.id,
      'employeeId': _selectedDoctor?.id,
    };

    final response = await _dao.getTimes(body);

    setState(() {
      _isLoadingTimeSlots = false;
      if (response.success && response.data is List) {
        debugPrint('success data timeSlot');
        _preFetchedTimeSlots = response.data as List;
      } else {
        debugPrint('fail data timeSlot');
        _preFetchedTimeSlots = [];
      }
    });
  }

  void _showWarningSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

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
                    logoUrl: json['logoUrl'] as String?,
                  ),
                )
                .toList();
      } else {
        _error = response.message ?? 'Эмнэлгүүдийг татаж чадсангүй.';
      }
    });
  }

  void _logOut() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    prefs.clear();
    // try {
    //   await platform.invokeMethod('stopLocationUpdates');
    // } on PlatformException catch (e) {
    //   debugPrint("Failed to stop location updates: '${e.message}'.");
    // }
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginScreen()));
    }
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
        final List<DropdownItem> loadedBranches =
            response.data!
                .map(
                  (json) => DropdownItem(
                    id: json['id'] as String,
                    name: json['name'] as String,
                    tenant: tenant,
                    logoUrl: json['imgLink'] as String?,
                    phones:
                        (json['phone'] is List)
                            ? (json['phone'] as List).map((p) => p.toString()).toList()
                            : null,
                    facebook: json['facebook'] as String?,
                    isAvailable: json['available'] as bool,
                  ),
                )
                .toList();

        loadedBranches.sort((a, b) {
          if (a.isAvailable && !b.isAvailable) return -1;
          if (!a.isAvailable && b.isAvailable) return 1;
          return a.name.compareTo(b.name);
        });

        _branches = loadedBranches;

        final availableBranches = _branches.where((b) => b.isAvailable).toList();

        if (availableBranches.length == 1) {
          final singleBranch = availableBranches.first;
          _selectedBranch = singleBranch;

          debugPrint('Auto-selected single available branch: ${singleBranch.name}');

          if (_selectedHospital?.tenant != null) {
            _loadTasags(_selectedHospital!.tenant!, singleBranch.id);
          }
        }
      } else {
        _error = response.message ?? 'Салбаруудыг татаж чадсангүй.';
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
        _error = response.message ?? 'Тасгуудыг татаж чадсангүй.';
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
        _error = response.message ?? 'Эмч нарыг татаж чадсангүй.';
      }
    });
  }

  void _clearSelections() {
    setState(() {
      _selectedHospital = null;
      _selectedBranch = null;
      _selectedTasag = null;
      _selectedDoctor = null;

      _branches = [];
      _tasags = [];
      _doctors = [];

      _preFetchedTimeSlots = null;
      _isLoadingTimeSlots = false;

      _loadHospitals();
    });
  }

  Widget _buildItemChild(DropdownItem item) {
    final bool isHospitalWithLogo =
        item.tenant != null && item.logoUrl != null && item.logoUrl!.isNotEmpty;

    // final bool isBranchWithLogo =
    //     item.tenant == null && item.logoUrl != null && item.logoUrl!.isNotEmpty;

    // final bool isBranchUnavailable = isBranchWithLogo && !item.isAvailable;

    // final bool isBranchAvailable = isBranchWithLogo && item.isAvailable;

    if (isHospitalWithLogo) {
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
    }

    return Text(item.name);
  }

  Widget _buildSelectedBranchCard(DropdownItem item, bool isEnabled, bool isSelected) {
    final bool isBranchAvailable = item.isAvailable;

    const double cardHeight = 220.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8.0),
      child: Container(
        height: cardHeight,
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Colors.blue.shade700 : Colors.grey.shade300,
            width: isSelected ? 3.0 : 1.0,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColorFiltered(
              colorFilter:
                  !isBranchAvailable
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
                        child: Icon(Icons.apartment, color: Colors.white, size: 30),
                      ),
                    ),
              ),
            ),

            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                color: Colors.black45,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),

                    Icon(
                      Icons.arrow_drop_down,
                      color: isEnabled ? Colors.white : Colors.grey.shade400,
                    ),
                  ],
                ),
              ),
            ),

            if (!isBranchAvailable)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'ҮЗЛЭГГҮЙ',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchSelectionField() {
    final bool enabled = _selectedHospital != null && !_isLoadingBranches;
    const double modalHeightMultiplier = 0.70;

    final bool isClearable = _selectedBranch != null && enabled && !_isLoadingBranches;

    final Widget fieldContent;

    if (_selectedBranch != null) {
      fieldContent = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0, left: 2.0, right: 40.0),
            child: Text(
              'Салбар',
              style: TextStyle(
                color: enabled ? Colors.grey.shade700 : Colors.grey.shade500,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          _buildSelectedBranchCard(_selectedBranch!, enabled, true),
        ],
      );
    } else {
      fieldContent = Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: enabled ? Colors.grey.shade400 : Colors.grey.shade300,
            width: 1.0,
          ),
          borderRadius: BorderRadius.circular(4.0),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _isLoadingBranches ? 'Салбар татаж байна...' : 'Салбар сонгоно уу',
              style: TextStyle(color: enabled ? Colors.black54 : Colors.grey, fontSize: 16),
            ),
            _isLoadingBranches
                ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : Icon(Icons.arrow_drop_down, color: enabled ? Colors.black54 : Colors.grey),
          ],
        ),
      );
    }

    return Stack(
      children: [
        InkWell(
          onTap:
              enabled
                  ? () async {
                    if (_branches.isEmpty) {
                      _showWarningSnackbar('Салбарууд татагдаж дуусаагүй эсвэл байхгүй байна.');
                      return;
                    }

                    final DropdownItem? selectedBranch = await showModalBottomSheet<DropdownItem>(
                      context: context,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(15.0)),
                      ),
                      backgroundColor: Colors.white,

                      builder: (context) {
                        const double listTopPadding = 55.0;

                        return Container(
                          height: MediaQuery.of(context).size.height * modalHeightMultiplier,
                          color: Colors.white,
                          child: Stack(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: listTopPadding),
                                child: BranchSelectionModal(
                                  branches: _branches,
                                  currentSelectedBranch: _selectedBranch,
                                  onBranchSelected: (branch) {
                                    Navigator.pop(context, branch);
                                  },
                                  launchUrlCallback: _launchUrl,
                                ),
                              ),
                              const Positioned(
                                top: 10,
                                left: 0,
                                right: 0,
                                child: Text(
                                  'Салбар сонгох',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.normal),
                                ),
                              ),
                              const Positioned(
                                top: 45,
                                left: 0,
                                right: 0,
                                child: Divider(height: 0),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: IconButton(
                                  icon: const Icon(Icons.close, size: 30),
                                  color: Colors.black54,
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );

                    if (selectedBranch != null) {
                      if (selectedBranch.isAvailable) {
                        _handleBranchSelection(selectedBranch);
                      } else {
                        _showWarningSnackbar(
                          '(${selectedBranch.name}) салбарыг одоогоор сонгох боломжгүй байна. Та өөр салбар сонгоно уу.',
                        );
                      }
                    }
                  }
                  : null,

          child: fieldContent,
        ),

        if (isClearable)
          Positioned(
            top: 32,
            right: 13,
            child: IconButton(
              icon: const Icon(Icons.cancel, size: 25),
              color: Colors.grey.shade400,
              onPressed: () {
                _handleBranchSelection(null);
              },
            ),
          ),
      ],
    );
  }

  /*
void _handleBranchSelection(DropdownItem branch) {
  setState(() {
    _selectedBranch = branch;
    _tasags = [];
    _selectedTasag = null;
    _doctors = [];
    _selectedDoctor = null;
  });
  if (_selectedHospital?.tenant != null) {
    _loadTasags(_selectedHospital!.tenant!, branch.id);
  }
}
*/

  void _handleBranchSelection(DropdownItem? newValue) {
    setState(() {
      _selectedBranch = newValue;

      _tasags = [];
      _selectedTasag = null;
      _doctors = [];
      _selectedDoctor = null;
    });
    if (_selectedHospital?.tenant != null && newValue != null) {
      _loadTasags(_selectedHospital!.tenant!, newValue.id);
    }
  }

  Widget _buildDropdown({
    required String labelText,
    required DropdownItem? selectedValue,
    required List<DropdownItem> items,
    required bool isLoading,
    required ValueChanged<DropdownItem?> onChanged,
    bool enabled = true,
  }) {
    final bool isClearable = selectedValue != null && enabled && !isLoading;

    Widget? clearButton;
    if (isClearable) {
      clearButton = IconButton(
        icon: const Icon(Icons.clear, size: 20),
        color: Colors.grey,
        onPressed: () {
          if (labelText == 'Эмнэлэг') {
            setState(() {
              _selectedHospital = null;
              _selectedBranch = null;
              _tasags = [];
              _selectedTasag = null;
              _doctors = [];
              _selectedDoctor = null;
            });
          }

          if (labelText == 'Тасаг') {
            setState(() {
              _selectedTasag = null;
              _doctors = [];
              _selectedDoctor = null;
            });
          }

          if (labelText == 'Эмч') {
            setState(() {
              _doctors = [];
              _selectedDoctor = null;
            });
          }
          onChanged(null);
        },
      );
    }

    return Stack(
      alignment: Alignment.centerRight,
      children: [
        DropdownButtonFormField<DropdownItem>(
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
                    : (isClearable ? const SizedBox(width: 40) : null),
          ),
          initialValue: selectedValue,

          items:
              items.map((item) {
                return DropdownMenuItem<DropdownItem>(
                  value: item,
                  enabled: true,
                  child: _buildItemChild(item),
                );
              }).toList(),

          onChanged: enabled && !isLoading ? onChanged : null,
          isExpanded: true,
          hint: Text('$labelText сонгоно уу'),
          validator: (value) => value == null ? '$labelText сонгоно уу' : null,
        ),

        if (isClearable) Positioned(right: isLoading ? 8 : 12, child: clearButton!),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isEnabled = _preFetchedTimeSlots != null && _preFetchedTimeSlots!.isNotEmpty;
    bool isDoctorSelected = _selectedDoctor != null;

    String buttonLabel = 'Цаг Сонгох';
    Color labelColor = Colors.white;

    if (_isLoadingTimeSlots) {
      buttonLabel = 'Хуваарийг шалгаж байна...';
      isEnabled = false;
    } else if (_preFetchedTimeSlots == null || _preFetchedTimeSlots!.isEmpty) {
      isEnabled = false;
      if (!isDoctorSelected) {
        buttonLabel = 'Эмч сонгоно уу';
      } else {
        buttonLabel = 'Онлайн үзлэгийн хуваарь байхгүй';
      }
      labelColor = Colors.redAccent;
    }

    final double screenWidth = MediaQuery.of(context).size.width;
    const double maxWidth = 600.0;

    final bool shouldConstrain = screenWidth > maxWidth;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: shouldConstrain ? maxWidth : double.infinity),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildDropdown(
                  labelText: 'Эмнэлэг',
                  selectedValue: _selectedHospital,
                  items: _hospitals,
                  isLoading: _isLoadingHospitals,
                  onChanged: (DropdownItem? newValue) {
                    if (newValue != null && newValue != _selectedHospital) {
                      setState(() {
                        _selectedHospital = newValue;
                        _selectedBranch = null;
                        _selectedTasag = null;
                        _selectedDoctor = null;
                      });
                      if (newValue.tenant != null) {
                        _loadBranches(newValue.tenant!);
                      }
                    }
                  },
                ),

                SizedBox(height: _selectedBranch != null ? 10 : 20),

                _buildBranchSelectionField(),
                const SizedBox(height: 20),

                _buildDropdown(
                  labelText: 'Тасаг',
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

                      _checkAvailableTimeSlots();
                    }
                  },
                  enabled: _selectedBranch != null,
                ),
                const SizedBox(height: 20),

                _buildDropdown(
                  labelText: 'Эмч',
                  selectedValue: _selectedDoctor,
                  items: _doctors,
                  isLoading: _isLoadingDoctors,
                  onChanged: (DropdownItem? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedDoctor = newValue;
                      });
                      _checkAvailableTimeSlots();
                    }
                  },
                  enabled: _selectedTasag != null,
                ),
                const SizedBox(height: 30),

                if (_error != null)
                  Text('Алдаа: $_error', style: const TextStyle(color: Colors.red)),

                if (_selectedHospital != null &&
                    _selectedBranch != null &&
                    _selectedTasag != null &&
                    !_isLoadingDoctors)
                  const Divider(),

                if (_selectedHospital != null &&
                    _selectedBranch != null &&
                    _selectedTasag != null &&
                    !_isLoadingDoctors)
                  Padding(
                    padding: const EdgeInsets.only(top: 20.0),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed:
                            isEnabled
                                ? () async {
                                  debugPrint('Redirecting to Time Selection Screen...');

                                  if (_selectedHospital?.tenant != null &&
                                      _selectedBranch != null &&
                                      _selectedTasag != null) {
                                    final bool? isSuccess = await Navigator.of(context).push<bool>(
                                      MaterialPageRoute(
                                        builder:
                                            (context) => TimeSelectionScreen(
                                              tenant: _selectedHospital!.tenant!,
                                              branchId: _selectedBranch!.id,
                                              tasagId: _selectedTasag!.id,
                                              tasagName: _selectedTasag!.name,
                                              employeeId: _selectedDoctor?.id,
                                              doctorName: _selectedDoctor?.name,
                                              timeData: _preFetchedTimeSlots!,
                                            ),
                                      ),
                                    );

                                    if (isSuccess == true) {
                                      _clearSelections();
                                    }
                                  }
                                }
                                : null,
                        icon:
                            _isLoadingTimeSlots
                                ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                                : const Icon(Icons.calendar_month, size: 24),
                        label: Text(
                          buttonLabel,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isEnabled ? Colors.white : labelColor,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),

                          backgroundColor:
                              isEnabled ? Theme.of(context).primaryColor : Colors.grey[400],
                        ),
                      ),
                    ),
                  ),

                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text('Алдаа: $_error', style: const TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);

    _animation = Tween(begin: 0.7, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: const Icon(Icons.touch_app, color: Colors.white, size: 45),
    );
  }
}
