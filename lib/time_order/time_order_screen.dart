import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:medsoft_patient/api/time_order_dao.dart';
import 'package:medsoft_patient/time_order/branch_select_widget.dart';
import 'package:medsoft_patient/time_order/time_selection_screen.dart'; // Assuming this is the correct path
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;

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

  // New state for pre-fetched time slots
  List<dynamic>? _preFetchedTimeSlots;
  bool _isLoadingTimeSlots = false;

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
  // Placeholder function for launching URLs (e.g., phone calls or Facebook links)
  Future<void> _launchUrl(String url) async {
    // 1. Handle Tel Links (and other non-HTTP schemes) immediately
    if (url.startsWith('tel:')) {
      final Uri telUri = Uri.parse(url);
      if (await canLaunchUrl(telUri)) {
        await launchUrl(telUri, mode: LaunchMode.platformDefault);
      } else {
        _showWarningSnackbar('Уучлаарай, утас руу залгах боломжгүй байна.');
      }
      return;
    }

    // 2. Handle Facebook Links with Deep Linking (using platform-specific schemes)
    if (url.contains('facebook.com')) {
      // Get the page name or ID from the URL (e.g., "mitpc.medsoft" from the example)
      // This is a simple way, but assumes the URL format is clean: https://www.facebook.com/PAGE_ID_OR_NAME
      final pageIdOrName = url.split('/').last.split('?').first;
      // For "https://www.facebook.com/mitpc.medsoft", this should result in "mitpc.medsoft"

      debugPrint('Extracted Facebook ID/Name: $pageIdOrName'); // NEW: Add this check

      // Define the deep link schemes
      Uri fbUri;
      if (Platform.isIOS) {
        // iOS scheme: fb://profile/<ID> or fb://page/<ID>
        // We try the page scheme, which works for profiles/pages:
        fbUri = Uri.parse('fb://page/$pageIdOrName'); // NOTE: Using fb://page/
      } else if (Platform.isAndroid) {
        // Android scheme
        fbUri = Uri.parse('fb://page/$pageIdOrName');
      } else {
        // Use the standard web URL as a safe fallback for unsupported platforms
        fbUri = Uri.parse(url);
      }
      debugPrint('fbUri: $fbUri');
      // Try to launch the deep link first
      if (await canLaunchUrl(fbUri)) {
        await launchUrl(fbUri, mode: LaunchMode.externalApplication);
        return; // Success, stop here
      }
      // If deep link failed (Facebook app not installed), fall through to web launch below
    }

    // 3. General Web Fallback (for failed deep links or other HTTP/HTTPS URLs)
    final Uri webUri = Uri.parse(url);
    if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication); // This opens Safari/Chrome
    } else {
      _showWarningSnackbar('Уучлаарай, холбоосыг нээх боломжгүй байна: $url');
      debugPrint('Could not launch $url');
    }
  }

  // time_order_screen.dart (inside _TimeOrderScreenState)

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
      'employeeId': _selectedDoctor?.id, // Use selected doctor if available
    };

    final response = await _dao.getTimes(body);

    setState(() {
      _isLoadingTimeSlots = false;
      if (response.success && response.data is List) {
        _preFetchedTimeSlots = response.data as List;
      } else {
        _preFetchedTimeSlots = []; // Treat failure or non-list data as no slots
      }
    });
  }

  // RENAMED and MODIFIED: Changed from AlertDialog to a SnackBar for the warning,
  // which is a standard, less intrusive way to show temporary, immediate feedback
  // near the top of the screen (as requested near "Appbar").
  void _showWarningSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating, // Floating behavior is less intrusive
        duration: const Duration(seconds: 4), // Show for a few seconds
      ),
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
        _error = response.message ?? 'Эмнэлгүүдийг татаж чадсангүй.';
      }
    });
  }

  Future<void> _loadBranches(String tenant) async {
    // 1. Initial State Reset
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

    // 2. Fetch Data
    final response = await _dao.getBranches(tenant);

    // 3. Process Data and Update State
    setState(() {
      _isLoadingBranches = false;

      if (response.success && response.data != null) {
        // Map JSON to DropdownItem list
        final List<DropdownItem> loadedBranches =
            response.data!
                .map(
                  (json) => DropdownItem(
                    id: json['id'] as String,
                    name: json['name'] as String,
                    tenant: tenant, // Ensure tenant is carried over for subsequent calls
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

        // Sort the branches to place available ones first
        loadedBranches.sort((a, b) {
          if (a.isAvailable && !b.isAvailable) return -1;
          if (!a.isAvailable && b.isAvailable) return 1;
          return a.name.compareTo(b.name);
        });

        _branches = loadedBranches;

        // 4. --- AUTO-SELECTION LOGIC ---
        final availableBranches = _branches.where((b) => b.isAvailable).toList();

        if (availableBranches.length == 1) {
          final singleBranch = availableBranches.first;
          _selectedBranch = singleBranch;

          debugPrint('Auto-selected single available branch: ${singleBranch.name}');

          // CRITICAL: Load the next dependent data immediately
          // Note: _selectedHospital is used here, assuming it's correctly set.
          if (_selectedHospital?.tenant != null) {
            _loadTasags(_selectedHospital!.tenant!, singleBranch.id);
          }
        }
        // -------------------------------
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

      // Clear related fetched lists/statuses too
      _branches = [];
      _tasags = [];
      _doctors = [];

      // Clear pre-fetched time slots and status
      _preFetchedTimeSlots = null;
      _isLoadingTimeSlots = false;

      // If you need to reload the initial data (e.g., hospitals)
      _loadHospitals();
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
    }
    // else if (isBranchWithLogo) {
    //   // 2. BRANCH LAYOUT: Image Banner with Overlayed Name (used for menu item options)
    //   const double bannerHeight = 220.0;

    //   return Opacity(
    //     // Opacity handles the grayed-out effect
    //     opacity: isBranchUnavailable ? 0.8 : 1.0,
    //     child: ClipRRect(
    //       borderRadius: BorderRadius.circular(8.0),
    //       child: Container(
    //         height: bannerHeight,
    //         width: double.infinity,
    //         decoration: BoxDecoration(
    //           border: Border.all(color: Colors.grey.shade300),
    //           borderRadius: BorderRadius.circular(8.0),
    //         ),
    //         child: Stack(
    //           fit: StackFit.expand,
    //           children: [
    //             // 1. Full-width Image (Banner)
    //             ColorFiltered(
    //               // B&W filter applied if unavailable
    //               colorFilter:
    //                   isBranchUnavailable
    //                       ? const ColorFilter.matrix(<double>[
    //                         0.2126,
    //                         0.7152,
    //                         0.0722,
    //                         0,
    //                         0,
    //                         0.2126,
    //                         0.7152,
    //                         0.0722,
    //                         0,
    //                         0,
    //                         0.2126,
    //                         0.7152,
    //                         0.0722,
    //                         0,
    //                         0,
    //                         0,
    //                         0,
    //                         0,
    //                         1,
    //                         0,
    //                       ])
    //                       : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
    //               child: Image.network(
    //                 item.logoUrl!,
    //                 fit: BoxFit.cover,
    //                 errorBuilder:
    //                     (context, error, stackTrace) => Container(
    //                       color: Colors.grey[400],
    //                       child: const Center(
    //                         child: Icon(Icons.apartment, color: Colors.white, size: 40),
    //                       ),
    //                     ),
    //               ),
    //             ),

    //             // 2. Overlayed Text Container (at the bottom)
    //             Positioned(
    //               bottom: 0,
    //               left: 0,
    //               right: 0,
    //               child: Container(
    //                 padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
    //                 color: Colors.black38,
    //                 child: Column(
    //                   crossAxisAlignment: CrossAxisAlignment.start,
    //                   mainAxisSize: MainAxisSize.min,
    //                   children: [
    //                     // Branch Name
    //                     Text(
    //                       item.name,
    //                       style: const TextStyle(
    //                         color: Colors.white,
    //                         fontWeight: FontWeight.bold,
    //                         fontSize: 16,
    //                       ),
    //                       overflow: TextOverflow.ellipsis,
    //                       maxLines: 1,
    //                     ),
    //                     const SizedBox(height: 4),

    //                     // NEW STRUCTURE: Phones and Facebook links
    //                     if ((item.phones != null && item.phones!.isNotEmpty) ||
    //                         (item.facebook != null && item.facebook!.isNotEmpty))
    //                       Column(
    //                         crossAxisAlignment: CrossAxisAlignment.start,
    //                         children: [
    //                           // A. Phones (Using Wrap for multiple lines)
    //                           if (item.phones != null && item.phones!.isNotEmpty)
    //                             Wrap(
    //                               spacing: 8.0,
    //                               runSpacing: 4.0,
    //                               crossAxisAlignment: WrapCrossAlignment.center,
    //                               children: [
    //                                 const Icon(Icons.phone, color: Colors.white70, size: 14),
    //                                 ...item.phones!.map(
    //                                   (phone) => InkWell(
    //                                     // Disabled for unavailable branches
    //                                     onTap:
    //                                         isBranchUnavailable
    //                                             ? null
    //                                             : () => _launchUrl('tel:$phone'),
    //                                     child: Text(
    //                                       phone,
    //                                       style: TextStyle(
    //                                         color: Colors.white,
    //                                         fontSize: 14,
    //                                         decoration:
    //                                             isBranchUnavailable
    //                                                 ? TextDecoration.none
    //                                                 : TextDecoration.underline,
    //                                         decorationColor: Colors.white,
    //                                       ),
    //                                     ),
    //                                   ),
    //                                 ),
    //                               ],
    //                             ),

    //                           if ((item.phones != null && item.phones!.isNotEmpty) &&
    //                               (item.facebook != null && item.facebook!.isNotEmpty))
    //                             const SizedBox(height: 8),

    //                           // B. Facebook (Pushed to the bottom-right using a Row)
    //                           if (item.facebook != null && item.facebook!.isNotEmpty)
    //                             Row(
    //                               mainAxisAlignment: MainAxisAlignment.end,
    //                               children: [
    //                                 InkWell(
    //                                   // Disabled for unavailable branches
    //                                   onTap:
    //                                       isBranchUnavailable
    //                                           ? null
    //                                           : () => _launchUrl(item.facebook!),
    //                                   child: Row(
    //                                     mainAxisSize: MainAxisSize.min,
    //                                     children: [
    //                                       Icon(
    //                                         Icons.facebook,
    //                                         color:
    //                                             isBranchAvailable
    //                                                 ? Colors.blueAccent
    //                                                 : Colors.white,
    //                                         size: 14,
    //                                       ),
    //                                       const SizedBox(width: 4),
    //                                       Text(
    //                                         // TRANSLATED
    //                                         'Facebook Page',
    //                                         style: TextStyle(
    //                                           color:
    //                                               isBranchAvailable
    //                                                   ? Colors.blueAccent
    //                                                   : Colors.white,
    //                                           fontSize: 14,
    //                                           decoration: TextDecoration.underline,
    //                                           decorationColor:
    //                                               isBranchAvailable
    //                                                   ? Colors.blueAccent
    //                                                   : Colors.white,
    //                                         ),
    //                                       ),
    //                                     ],
    //                                   ),
    //                                 ),
    //                               ],
    //                             ),
    //                         ],
    //                       ),
    //                   ],
    //                 ),
    //               ),
    //             ),

    //             // 3. UNAVAILABLE CAPTION (Mongolian Text)
    //             if (isBranchUnavailable)
    //               Positioned(
    //                 top: 8,
    //                 right: 8,
    //                 child: Container(
    //                   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    //                   decoration: BoxDecoration(
    //                     color: Colors.red.shade700,
    //                     borderRadius: BorderRadius.circular(4),
    //                   ),
    //                   child: const Text(
    //                     'ОНЛАЙН ҮЗЛЭГИЙН ХУВААРЬ БАЙХГҮЙ',
    //                     style: TextStyle(
    //                       color: Colors.white,
    //                       fontWeight: FontWeight.bold,
    //                       fontSize: 12,
    //                     ),
    //                   ),
    //                 ),
    //               ),

    //             // 4. CLICKABLE INDICATOR (Pulsing Animation)
    //             if (isBranchAvailable)
    //               const Positioned(top: 50, right: 50, child: PulsingClickIndicator()),
    //           ],
    //         ),
    //       ),
    //     ),
    //   );
    // }

    // 3. DEFAULT LAYOUT: Just the name (for Tasags, Doctors, and items without logo)
    return Text(item.name);
  }
  // Inside _TimeOrderScreenState:
  // Inside _TimeOrderScreenState:
  // Inside _TimeOrderScreenState
  // Inside _TimeOrderScreenState in time_order_screen.dart

  Widget _buildSelectedBranchCard(DropdownItem item, bool isEnabled, bool isSelected) {
    // Replicate the styling from BranchSelectionModal's _buildItemChild
    final bool isBranchAvailable = item.isAvailable;

    // Define a smaller banner height for the form field
    const double cardHeight = 220.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8.0),
      child: Container(
        height: cardHeight,
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(
            // Use the selection color for the form field border
            color: isSelected ? Colors.blue.shade700 : Colors.grey.shade300,
            width: isSelected ? 3.0 : 1.0,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Full-width Image (Banner)
            ColorFiltered(
              // Use the opacity/color filter if the branch is unavailable
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
                        child: Icon(Icons.apartment, color: Colors.white, size: 30), // Smaller icon
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
                color: Colors.black45, // Slightly darker overlay
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Branch Name
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
                    // Dropdown Indicator
                    Icon(
                      Icons.arrow_drop_down,
                      color: isEnabled ? Colors.white : Colors.grey.shade400,
                    ),
                  ],
                ),
              ),
            ),

            // 3. UNAVAILABLE CAPTION (Optional, simplified for field)
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
                    'ҮЗЛЭГГҮЙ', // Simplified text
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

    // Determine if the clear button should be visible (only when a branch is selected)
    final bool isClearable = _selectedBranch != null && enabled && !_isLoadingBranches;

    // --- START: CUSTOM FIELD WIDGET LOGIC (remains mostly the same) ---
    final Widget fieldContent;

    if (_selectedBranch != null) {
      // If a branch is selected, show the card view with a label
      fieldContent = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // NEW: Label Text "Салбар"
          Padding(
            // Adjust padding to accommodate the clear button overlay if needed
            padding: const EdgeInsets.only(
              bottom: 4.0,
              left: 2.0,
              right: 40.0,
            ), // Added right padding
            child: Text(
              'Салбар',
              style: TextStyle(
                color: enabled ? Colors.grey.shade700 : Colors.grey.shade500,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          // The full-height branch card (no changes needed here)
          _buildSelectedBranchCard(_selectedBranch!, enabled, true),
        ],
      );
    } else {
      // If no branch is selected, or loading, show a standard placeholder box
      fieldContent = Container(
        // ... (Placeholder box remains unchanged)
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
    // --- END: CUSTOM FIELD WIDGET ---

    // 1. Wrap the entire InkWell in a Stack
    return Stack(
      children: [
        // 2. The main Interactive Content (InkWell)
        InkWell(
          onTap:
              enabled
                  ? () async {
                    // ... (Your existing showModalBottomSheet logic) ...
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
                        // ... (Modal builder logic)
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

                    // Handle the result
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
          // Use the content determined above
          child: fieldContent,
        ),

        // 3. The Clear Button (Positioned over the top right corner)
        if (isClearable)
          Positioned(
            top: 32, // Position it right at the top
            right: 13, // Position it far to the right
            child: IconButton(
              icon: const Icon(Icons.cancel, size: 25),
              color: Colors.grey.shade400, // Use a noticeable color
              onPressed: () {
                // Call the handler logic to clear the branch selection
                _handleBranchSelection(null);
              },
            ),
          ),
      ],
    );
  }

  // NOTE: Ensure you have a helper function like _handleBranchSelection
  // in your _TimeOrderScreenState to set the state and load next data:
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
  // NEW: Extract the branch selection logic for reuse
  void _handleBranchSelection(DropdownItem? newValue) {
    setState(() {
      _selectedBranch = newValue;
      // Reset dependents upon new branch selection
      _tasags = [];
      _selectedTasag = null;
      _doctors = [];
      _selectedDoctor = null;
    });
    if (_selectedHospital?.tenant != null && newValue != null) {
      // Only load tasags if a hospital is selected
      _loadTasags(_selectedHospital!.tenant!, newValue.id);
    }
  }
  // Inside _TimeOrderScreenState:

  // Inside your TimeOrderScreenState (time_order_screen.dart)

  Widget _buildDropdown({
    required String labelText,
    required DropdownItem? selectedValue,
    required List<DropdownItem> items,
    required bool isLoading,
    required ValueChanged<DropdownItem?> onChanged,
    bool enabled = true,
  }) {
    // Determine if the clear button should be visible and enabled
    final bool isClearable = selectedValue != null && enabled && !isLoading;

    // The custom clear button widget
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

    // To place the button on top of the field, we wrap it in a Stack
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        // 1. The main Dropdown Field
        DropdownButtonFormField<DropdownItem>(
          decoration: InputDecoration(
            labelText: labelText,
            border: const OutlineInputBorder(),
            // Use a custom suffix if loading, otherwise, leave it null for the clear button to occupy the space
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
                    : (isClearable
                        ? const SizedBox(width: 40)
                        : null), // Add padding/placeholder if clearable
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

        // 2. The Clear Button (positioned on top)
        if (isClearable)
          Positioned(
            // Adjust this position based on your InputDecoration's padding
            // This places it to the left of the default dropdown arrow/icon
            right: isLoading ? 8 : 12,
            child: clearButton!,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isEnabled = _preFetchedTimeSlots != null && _preFetchedTimeSlots!.isNotEmpty;
    bool isDoctorSelected = _selectedDoctor != null;

    String buttonLabel = 'Цаг Сонгох';
    Color labelColor = Colors.white; // Default color

    if (_isLoadingTimeSlots) {
      buttonLabel = 'Хуваарийг шалгаж байна...'; // Checking Schedule...
      isEnabled = false;
    } else if (_preFetchedTimeSlots == null || _preFetchedTimeSlots!.isEmpty) {
      isEnabled = false;
      if (!isDoctorSelected) {
        buttonLabel = 'Эмч сонгоно уу'; // Select a Doctor
      } else {
        buttonLabel = 'Онлайн үзлэгийн хуваарь байхгүй'; // No Online Appointment Schedule
      }
      labelColor = Colors.redAccent; // Visually indicate no slots
    }

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 1. Hospital Dropdown (getAllHospitals)
            _buildDropdown(
              labelText: 'Эмнэлэг',
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

            SizedBox(height: _selectedBranch != null ? 10 : 20),

            // 2. Branch Dropdown (getBranches)

            // _buildDropdown(
            //   labelText: 'Салбар',
            //   selectedValue: _selectedBranch,
            //   items: _branches,
            //   isLoading: _isLoadingBranches,
            //   onChanged: (DropdownItem? newValue) {
            //     if (newValue != null && newValue != _selectedBranch) {
            //       setState(() {
            //         _selectedBranch = newValue;
            //         // Reset dependents upon new branch selection
            //         _tasags = [];
            //         _selectedTasag = null;
            //         _doctors = [];
            //         _selectedDoctor = null;
            //       });
            //       if (_selectedHospital?.tenant != null) {
            //         // Only load tasags if a hospital is selected
            //         _loadTasags(_selectedHospital!.tenant!, newValue.id);
            //       }
            //     }
            //   },
            //   enabled: _selectedHospital != null, // Enable only after hospital is selected
            // ),
            _buildBranchSelectionField(),
            const SizedBox(height: 20),

            // 3. Department (Tasag) Dropdown (getTasags)
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
                }
              },
              enabled: _selectedBranch != null,
            ),
            const SizedBox(height: 20),

            // 4. Doctor Dropdown (getDoctors)
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

                  // NEW: Navigate to TimeSelectionScreen

                  // if (_selectedHospital?.tenant != null &&
                  //     _selectedBranch != null &&
                  //     _selectedTasag != null) {
                  //   Navigator.of(context).push(
                  //     MaterialPageRoute(
                  //       builder:
                  //           (context) => TimeSelectionScreen(
                  //             tenant: _selectedHospital!.tenant!,
                  //             branchId: _selectedBranch!.id,
                  //             tasagId: _selectedTasag!.id,
                  //             employeeId: newValue.id,
                  //             doctorName: newValue.name, // Pass the name for display
                  //           ),
                  //     ),
                  //   );
                  // }
                }
              },
              enabled: _selectedTasag != null,
            ),
            const SizedBox(height: 30),

            if (_error != null)
              Text('Алдаа: $_error', style: const TextStyle(color: Colors.red)), // TRANSLATED
            // Example of usage: Display selected values
            const Divider(),
            // const Text(
            //   'Сонгогдсон захиалгын мэдээлэл:',
            //   style: TextStyle(fontWeight: FontWeight.bold),
            // ), // TRANSLATED
            // Text(
            //   'Эмнэлэг: ${_selectedHospital?.name ?? 'Байхгүй'} (Tenant: ${_selectedHospital?.tenant ?? 'Байхгүй'})', // TRANSLATED
            // ),
            // Text('Салбар: ${_selectedBranch?.name ?? 'Байхгүй'}'), // TRANSLATED
            // Text('Тасаг: ${_selectedTasag?.name ?? 'Байхгүй'}'), // TRANSLATED
            // Text('Эмч: ${_selectedDoctor?.name ?? 'Байхгүй'}'), // TRANSLATED

            // Check if all necessary selections have been made: Hospital, Branch, and Tasag
            if (_selectedHospital != null &&
                _selectedBranch != null &&
                _selectedTasag != null &&
                !_isLoadingDoctors) // Ensure doctors aren't still loading
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

                              // Navigate only if the button is enabled (and thus has slots)
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

                                // 3. Handle the result after TimeSelectionScreen is popped
                                if (isSuccess == true) {
                                  // SUCCESS: Clear all selections in THIS screen (TimeOrderScreen)
                                  _clearSelections();
                                  // Note: The success SnackBar is already shown in TimeSelectionScreen
                                }
                              }
                            }
                            : null, // Disable button if isEnabled is false
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
                      // Adjust background color for disabled state if necessary
                      backgroundColor:
                          isEnabled ? Theme.of(context).primaryColor : Colors.grey[400],
                    ),
                  ),
                ),
              ),

            // You might still want to keep the error text if there's an error outside the selections
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text('Алдаа: $_error', style: const TextStyle(color: Colors.red)),
              ),
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
 SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

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
