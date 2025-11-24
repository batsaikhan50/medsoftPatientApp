import 'package:flutter/material.dart';
// Assuming history_dao.dart is in the same folder or path 'history_dao.dart'
// If running in a separate environment, this import needs to be adjusted.
// Define models used for data structure
import 'package:flutter_html/flutter_html.dart';
import 'package:medsoft_patient/api/history_dao.dart'; // Using flutter_html for robust HTML rendering
import 'package:medsoft_patient/pdf_viewer.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

// --- Data Models (Based on API Responses) ---

// Tenant Model
class HistoryTenant {
  final String tenantName;
  final String fullName;
  final String shortName;

  HistoryTenant.fromJson(Map<String, dynamic> json)
    : tenantName = json['tenantName'],
      fullName = json['fullName'],
      shortName = json['shortName'];
}

class HistoryAction {
  final String key;
  final String value;

  HistoryAction.fromJson(Map<String, dynamic> json) : key = json['key'], value = json['value'];
}

// Available History Type Model
class HistoryAvailable {
  final String key;
  final String value;
  final List<HistoryAction> actions; // <-- NEW FIELD

  HistoryAvailable.fromJson(Map<String, dynamic> json)
    : key = json['key'],
      value = json['value'],
      // Parse the list of actions, safely handling null or missing data
      actions =
          (json['actions'] as List<dynamic>?)
              ?.map((e) => HistoryAction.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const []; // Default to an empty list
}
// History Column Data Model
// --- Data Models (Based on API Responses) ---

// History Column Data Model
class HistoryColumn {
  // Use 'String?' if it's truly optional, but if it must be a string for display/logic,
  // providing a default value is safer during parsing.

  final String field;
  final String caption;
  final String? footer;
  final bool hidden;
  final bool html;
  final List<HistoryCellData> data;

  HistoryColumn.fromJson(Map<String, dynamic> json)
    // **FIX: Use null-coalescing operator (??) to safely handle null values for non-nullable String fields**
    : field = json['field'] ?? '', // Default to empty string if null
      caption = json['caption'] ?? '', // Default to empty string if null
      footer = json['footer'],
      hidden = json['hidden'] ?? false,
      html = json['html'] ?? false,
      data = (json['data'] as List).map((e) => HistoryCellData.fromJson(e)).toList();
}

// History Cell Data Model
class HistoryCellData {
  final String? value;
  final String? html;
  final Map<String, dynamic> props;

  HistoryCellData.fromJson(Map<String, dynamic> json)
    : value = json['value'], // Nullable, safe
      html = json['html'], // Nullable, safe
      props = json['props'] ?? {}; // Nullable Map, safe
}
// --- History Screen Implementation ---

class HistoryScreen extends StatefulWidget {
  final String? initialHistoryKey; // <-- NEW FIELD

  const HistoryScreen({super.key, this.initialHistoryKey}); // <-- UPDATED CONSTRUCTOR

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final HistoryDAO _historyDAO = HistoryDAO();

  List<HistoryTenant> _tenants = [];
  List<HistoryAvailable> _availableHistory = [];
  List<HistoryColumn> _historyData = [];

  HistoryTenant? _selectedTenant;
  HistoryAvailable? _selectedHistoryType;
  bool _isLoading = true;
  String? _errorMessage;

  int _selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Fetch Tenants
      final tenantResponse = await _historyDAO.getHistoryTenants();
      if (tenantResponse.success && tenantResponse.data != null) {
        _tenants =
            (tenantResponse.data!)
                .map((e) => HistoryTenant.fromJson(e as Map<String, dynamic>))
                .toList();
        _selectedTenant = _tenants.isNotEmpty ? _tenants.first : null;
      } else {
        throw Exception('Түрээслэгчдийг татаж чадсангүй.'); // Failed to fetch tenants
      }

      // 2. Fetch Available History Types
      final availableResponse = await _historyDAO.getHistoryAvailable();
      if (availableResponse.success && availableResponse.data != null) {
        _availableHistory =
            (availableResponse.data!)
                .map((e) => HistoryAvailable.fromJson(e as Map<String, dynamic>))
                .toList();

        // --- FIX START: Logic to select initial history type ---
        if (widget.initialHistoryKey != null) {
          // Attempt to find the matching type using the key from the navigation argument
          final matchingType = _availableHistory.firstWhere(
            (type) => type.key == widget.initialHistoryKey,
            // If no match is found, use the first available type as a fallback,
            // otherwise, set it to null.
            orElse:
                () =>
                    _availableHistory.isNotEmpty
                        ? _availableHistory.first
                        : null as HistoryAvailable,
          );

          _selectedHistoryType = matchingType;
        } else {
          // Fallback: If no initial key is provided, select the first available type
          _selectedHistoryType = _availableHistory.isNotEmpty ? _availableHistory.first : null;
        }
        // --- FIX END ---
      } else {
        throw Exception(
          'Боломжит түүхийн төрлүүдийг татаж чадсангүй.',
        ); // Failed to fetch available history types
      }

      // 3. Fetch initial history data if selections are available
      if (_selectedTenant != null && _selectedHistoryType != null) {
        await _fetchHistory();
      } else {
        setState(() {
          // If no selections were made, stop loading
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage =
            'Эхний өгөгдлийг татахад алдаа гарлаа: ${e.toString()}'; // Error fetching initial data
        _isLoading = false;
      });
    }
  }

  // Function to fetch the actual patient history data
  Future<void> _fetchHistory() async {
    if (_selectedTenant == null || _selectedHistoryType == null) return;

    setState(() {
      _isLoading = true;
      _historyData = [];
      _errorMessage = null;
    });

    try {
      // Use current year for the year parameter
      final yearString = _selectedYear.toString();
      final historyResponse = await _historyDAO.getHistory(
        yearString,
        _selectedHistoryType!.key,
        _selectedTenant!.tenantName,
      );

      if (historyResponse.success) {
        if (historyResponse.data != null) {
          _historyData =
              (historyResponse.data!)
                  .map((e) => HistoryColumn.fromJson(e as Map<String, dynamic>))
                  .toList();
        } else {
          // If success is true but data is null, show 'Дата олдсонгүй'
          _errorMessage = 'Дата олдсонгүй'; // Data not found
        }
      } else if (!historyResponse.success && historyResponse.data == null) {
        _errorMessage = 'Дата олдсонгүй';
      } else {
        // If success is false, treat it as a failure to fetch history
        throw Exception('Өвчтөний түүхийг татаж чадсангүй.'); // Failed to fetch patient history
      }
    } catch (e) {
      // Catch any exceptions (including the thrown one above)
      if (_errorMessage == null || _errorMessage!.isEmpty) {
        _errorMessage =
            'Түүхийн өгөгдлийг татахад алдаа гарлаа: ${e.toString()}'; // Error fetching history data
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Transpose data for row-by-row rendering
  List<List<HistoryCellData>> _getRows() {
    if (_historyData.isEmpty || _historyData.first.data.isEmpty) {
      return [];
    }

    final numRows = _historyData.first.data.length;
    final List<List<HistoryCellData>> rows = [];

    for (int i = 0; i < numRows; i++) {
      final List<HistoryCellData> row = [];
      for (final column in _historyData) {
        if (i < column.data.length) {
          row.add(column.data[i]);
        }
      }
      rows.add(row);
    }
    return rows;
  }

  // history_screen.dart
  // Widget _buildTenantDropdown() {
  //   final platform = Theme.of(context).platform;
  //   final orientation = MediaQuery.of(context).orientation;
  //   final shortestSide = MediaQuery.of(context).size.shortestSide;

  //   // 2. Define conditions for applying extra top padding
  //   // Must be in Landscape mode AND must be an iPhone/Compact iOS Device (shortestSide < 600)
  //   final isLandscape = orientation == Orientation.landscape;
  //   final isCompactIOS = platform == TargetPlatform.iOS && shortestSide < 600;
  //   final double extraTopMargin = isLandscape && isCompactIOS ? 10.0 : 0.0;

  //   return Padding(
  //     padding: EdgeInsets.fromLTRB(16.0, 8.0 + extraTopMargin, 16.0, 8.0), // <--- FIX APPLIED HERE
  //     child: DropdownButtonFormField<HistoryTenant>(
  //       isExpanded: true,

  //       // Use standard, non-conditional InputDecoration
  //       decoration: const InputDecoration(
  //         labelText: 'Түрээслэгч сонгох', // Select Tenant
  //         border: OutlineInputBorder(),
  //         // Keep contentPadding standard unless internal padding is also required
  //         // contentPadding: EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 12.0),
  //       ),
  //       initialValue: _selectedTenant,
  //       items:
  //           _tenants.map((tenant) {
  //             // Also ensure the Text widget inside the DropdownMenuItem is constrained,
  //             // though isExpanded: true often handles this.
  //             return DropdownMenuItem<HistoryTenant>(
  //               value: tenant,
  //               // Use Flexible or a fixed width if truncation is not desired,
  //               // but usually the default Text behavior with isExpanded is fine.
  //               child: Text(tenant.fullName, overflow: TextOverflow.ellipsis),
  //             );
  //           }).toList(),
  //       onChanged: (HistoryTenant? newValue) {
  //         setState(() {
  //           _selectedTenant = newValue;
  //           if (_selectedTenant != null && _selectedHistoryType != null) {
  //             _fetchHistory();
  //           }
  //         });
  //       },
  //       hint: const Text('Түрээслэгч сонгоно уу'), // Select a tenant
  //     ),
  //   );
  // }

  Widget _buildHistoryTypeButtons() {
    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _availableHistory.length,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        itemBuilder: (context, index) {
          final historyType = _availableHistory[index];
          final isSelected = historyType == _selectedHistoryType;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ActionChip(
              label: Text(
                historyType.value,
                style: TextStyle(color: isSelected ? Colors.white : Colors.blue),
              ),
              backgroundColor: isSelected ? Colors.blue : Colors.blue.withOpacity(0.1),
              side: isSelected ? BorderSide.none : const BorderSide(color: Colors.blue),
              onPressed: () {
                setState(() {
                  _selectedHistoryType = historyType;
                  _fetchHistory();
                });
              },
            ),
          );
        },
      ),
    );
  }

  // history_screen.dart (inside _HistoryScreenState)

  // ... existing code ...

  List<HistoryAction> _getPrintActions() {
    if (_selectedHistoryType == null) {
      return const [];
    }
    // This line is safe because of the check above.
    return _selectedHistoryType!.actions.where((action) => action.key == 'print').toList();
  }

  Future<String?> _showActionSelectionDialog(List<HistoryAction> actions) async {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Хэвлэх үйлдлийг сонгоно уу'), // Select Print Action
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children:
                actions.map((action) {
                  return ListTile(
                    title: Text(action.value),
                    onTap: () {
                      Navigator.of(context).pop(action.key); // Return the selected action key
                    },
                  );
                }).toList(),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Цуцлах'), // Cancel
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // Helper function to find the 'id' from the cell props
  String? _getPrintId(List<HistoryCellData> row) {
    // Search all cells in the row for one containing 'id' in its props
    final cellWithId = row.firstWhere(
      (cell) => cell.props.containsKey('id'),
      orElse: () => HistoryCellData.fromJson({}),
    );
    // Safely return the 'id' value if the key exists and is a String
    return cellWithId.props['id'] as String?;
  }

  Future<void> _openPdf(Uint8List pdfBytes, String filename) async {
    try {
      // 1. Get the temporary directory
      final tempDir = await getTemporaryDirectory(); // Requires 'path_provider' package
      final file = File('${tempDir.path}/$filename.pdf'); // Requires 'dart:io'

      // 2. Write the bytes to a local file
      await file.writeAsBytes(pdfBytes, flush: true);

      // 3. Open the file (or navigate to a PDF viewer screen)
      // Option A: Use a package like 'open_filex'
      // await OpenFilex.open(file.path);

      // Option B: Navigate to a custom PDF viewer widget
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PdfViewerScreen(pdfTitle: filename, pdfPath: file.path),
        ),
      );

      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(
      //     content: Text(
      //       'Тайланг амжилттай нээлээ.', // Report successfully opened.
      //     ),
      //     backgroundColor: Colors.green,
      //   ),
      // );
    } catch (e) {
      throw Exception('PDF-ийг нээхэд алдаа гарлаа: $e'); // Error opening PDF.
    }
  }

  Future<void> _openPdfViewer(Uint8List pdfBytes, String filename) async {
    // 1. Get the temporary directory
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename.pdf');

    // 2. Write the bytes to a local file
    await file.writeAsBytes(pdfBytes, flush: true);

    // 3. Navigate to the PDF viewer screen (Assuming this class exists)
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PdfViewerScreen(pdfTitle: filename, pdfPath: file.path),
      ),
    );
  }

  Future<void> _handlePrint(List<HistoryCellData> row) async {
    // 1. Validate necessary components
    if (_selectedTenant == null || _selectedHistoryType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Түрээслэгч эсвэл Түүхийн төрөл сонгогдоогүй.',
          ), // Tenant or History Type not selected.
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 2. Extract parameters
    final String? printId = _getPrintId(row);
    final String historyKey = _selectedHistoryType!.key;
    final String tenantName = _selectedTenant!.tenantName;
    // Assuming 'actionKey' is the same as 'historyKey'
    // final String actionKey = historyKey;

    if (printId == null || printId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Хэвлэхэд шаардлагатай ID олдсонгүй.',
          ), // Required ID for printing not found.
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    // --- NEW ACTION KEY LOGIC START ---

    final List<HistoryAction> printActions = _getPrintActions();
    String? actionKey;

    if (printActions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Сонгосон түүхэнд хэвлэх үйлдэл тодорхойлогдоогүй.',
          ), // Print action not defined for selected history.
          backgroundColor: Colors.red,
        ),
      );
      return;
    } else if (printActions.length == 1) {
      // Case 1: Only one print action, use it directly
      actionKey = printActions.first.key;
    } else {
      // Case 2: Multiple print actions, show selection dialog
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Үйлдлийг сонгоно уу.'), // Select action.
        ),
      );
      actionKey = await _showActionSelectionDialog(printActions);

      if (actionKey == null) {
        // User canceled the dialog
        return;
      }
    }
    // --- NEW ACTION KEY LOGIC END ---

    // Show a temporary loading message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Хэвлэх хүсэлт илгээж байна...'), // Sending print request...
      ),
    );

    try {
      final Uint8List pdfBytes = await _historyDAO.printHistoryRaw(
        printId,
        historyKey,
        actionKey,
        tenantName,
      );
      if (pdfBytes.isNotEmpty) {
        final now = DateTime.now();
        final formatted =
            '${now.year}.'
            '${now.month.toString().padLeft(2, '0')}.'
            '${now.day.toString().padLeft(2, '0')} '
            '${now.hour.toString().padLeft(2, '0')}:'
            '${now.minute.toString().padLeft(2, '0')}';
        // Use the helper to save and open the PDF

        await _openPdfViewer(pdfBytes, '${historyKey}_${tenantName}_$formatted');

        // ScaffoldMessenger.of(context).showSnackBar(
        //   const SnackBar(
        //     content: Text('Тайланг амжилттай нээлээ.'), // Report successfully opened.
        //     backgroundColor: Colors.green,
        //   ),
        // );
      } else {
        // This handles cases where the API returns success (200) but an empty body.
        throw Exception('Серверээс PDF өгөгдөл ирсэнгүй (Хоосон файл).');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // CHANGE 3: Update error message to reflect PDF viewing failure
          content: Text('Тайланг нээх явцад алдаа гарлаа: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ... existing code ...

  bool _hasRowPrintId(List<HistoryCellData> row) {
    return row.any((cell) => cell.props.containsKey('id'));
  }
  // history_screen.dart (inside _HistoryScreenState)

  // history_screen.dart (inside _HistoryScreenState)
  // history_screen.dart (inside _HistoryScreenState)

  Widget _buildHistoryTable() {
    final rows = _getRows();
    final columns = _historyData.where((col) => col.hidden == false).toList();

    // 1. **Determine if the print column should be visible**
    final bool shouldShowPrintColumn = _selectedHistoryType?.value != 'Цаг захиалгын түүх';

    if (rows.isEmpty && !_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            'Өгөгдөл олдсонгүй.', // No data found.
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    // 2. Conditionally build the DataColumns list
    final List<DataColumn> tableColumns = <DataColumn>[
      // Conditionally add the Print DataColumn
      if (shouldShowPrintColumn)
        const DataColumn(
          label: SizedBox(
            width: 50, // Fixed width for the button column
            child: Text(
              'Хэвлэх', // Print
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ),
        ),
      // Existing columns:
      ...columns.map((col) {
        return DataColumn(
          label: SizedBox(
            width: col.field == 'status' ? 80 : 150, // Fixed width for better layout
            child: Text(
              col.caption,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ),
        );
      }),
    ];

    // --- FIX START: Use LayoutBuilder to get max width for centering ---
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidget = DataTable(
          columnSpacing: 16.0,
          dataRowHeight: 80.0, // Increased height for multiline HTML content
          // Use the conditionally built column list
          columns: tableColumns,
          rows:
              rows.map((row) {
                final rowCells =
                    row
                        .asMap()
                        .entries
                        .where((entry) {
                          // Only include cells that correspond to visible columns
                          final colIndex = entry.key;
                          return colIndex < _historyData.length && !_historyData[colIndex].hidden;
                        })
                        .map((entry) {
                          final cellData = entry.value;
                          return DataCell(
                            SizedBox(
                              width: _historyData[entry.key].field == 'status' ? 80 : 150,
                              child: SingleChildScrollView(
                                child: Html(
                                  data: cellData.html ?? cellData.value ?? '',
                                  style: {
                                    "body": Style(
                                      margin: Margins.zero,
                                      padding: HtmlPaddings.zero,
                                      fontSize: FontSize(12.0),
                                      color: Colors.black87,
                                      fontWeight: FontWeight.normal,
                                      lineHeight: LineHeight.em(1.2),
                                    ),
                                  },
                                ),
                              ),
                            ),
                          );
                        })
                        .toList();

                final bool rowHasPrintId = _getPrintId(row) != null;
                final bool hasPrintActions =
                    _selectedHistoryType != null &&
                    (_selectedHistoryType!.actions.any((action) => action.key == 'print'));

                // Only show the button if the column is visible AND the row/type supports it
                final bool shouldShowPrintButton =
                    shouldShowPrintColumn && // Check if column is visible
                    rowHasPrintId &&
                    hasPrintActions;

                final printCell = DataCell(
                  Center(
                    child:
                        shouldShowPrintButton
                            ? IconButton(
                              icon: const Icon(Icons.print, color: Colors.blue),
                              onPressed: () {
                                _handlePrint(row);
                              },
                            )
                            : const SizedBox.shrink(), // Empty space if button should be hidden
                  ),
                );

                // 3. Conditionally add the print cell to the row
                final List<DataCell> cells = [];
                if (shouldShowPrintColumn) {
                  cells.add(printCell);
                }
                cells.addAll(rowCells);

                return DataRow(
                  cells: cells, // Use the conditionally built cell list
                );
              }).toList(),
        );

        // Use SingleChildScrollView to allow horizontal scrolling
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // Constrain the inner content to the full available width,
          // allowing the Center widget to effectively center the narrower table.
          child: SizedBox(width: constraints.maxWidth, child: Center(child: tableWidget)),
        );
      },
    );
    // --- FIX END ---
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children:
            _historyData
                .where((col) => col.footer != null)
                .map(
                  (col) => Text(
                    '${col.caption} | ${col.footer!}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.blueGrey,
                    ),
                  ),
                )
                .toList(),
      ),
    );
  }

  // Widget _buildYearDropdown() {
  //   final currentYear = DateTime.now().year;
  //   // Generate a list of years, e.g., current year and the previous 5 years
  //   final years = List<int>.generate(
  //     6,
  //     (index) => currentYear - index,
  //   ); // e.g., 2025, 2024, ..., 2020

  //   return Padding(
  //     padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
  //     child: DropdownButtonFormField<int>(
  //       isExpanded: true,
  //       decoration: const InputDecoration(
  //         labelText: 'Он сонгох', // Select Year
  //         border: OutlineInputBorder(),
  //       ),
  //       // Use _selectedYear (an int) as the initial value
  //       initialValue: _selectedYear,
  //       items:
  //           years.map((year) {
  //             return DropdownMenuItem<int>(value: year, child: Text(year.toString()));
  //           }).toList(),
  //       onChanged: (int? newValue) {
  //         setState(() {
  //           // Update the selected year
  //           _selectedYear = newValue!;
  //           // Fetch history data for the new year
  //           if (_selectedTenant != null && _selectedHistoryType != null) {
  //             _fetchHistory();
  //           }
  //         });
  //       },
  //       hint: const Text('Он сонгоно уу'), // Select a year
  //     ),
  //   );
  // }

  Widget _buildSelectionRow() {
    final currentYear = DateTime.now().year;
    // Generate a list of years, e.g., current year and the previous 5 years
    final years = List<int>.generate(6, (index) => currentYear - index);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0), // Standard padding for the row
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Year Dropdown (Takes a fixed, smaller width)
          SizedBox(
            width: 100, // Give the year dropdown a fixed width
            child: DropdownButtonFormField<int>(
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Он', // Year
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 12.0),
              ),
              initialValue: _selectedYear,
              items:
                  years.map((year) {
                    return DropdownMenuItem<int>(value: year, child: Text(year.toString()));
                  }).toList(),
              onChanged: (int? newValue) {
                setState(() {
                  _selectedYear = newValue!;
                  if (_selectedTenant != null && _selectedHistoryType != null) {
                    _fetchHistory();
                  }
                });
              },
            ),
          ),

          const SizedBox(width: 8.0), // Spacer between fields
          // 2. Tenant Dropdown (Takes remaining space using Expanded)
          Expanded(
            child: DropdownButtonFormField<HistoryTenant>(
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Түрээслэгч сонгох', // Select Tenant
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 12.0),
              ),
              initialValue: _selectedTenant,
              items:
                  _tenants.map((tenant) {
                    return DropdownMenuItem<HistoryTenant>(
                      value: tenant,
                      child: Text(tenant.fullName, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
              onChanged: (HistoryTenant? newValue) {
                setState(() {
                  _selectedTenant = newValue;
                  if (_selectedTenant != null && _selectedHistoryType != null) {
                    _fetchHistory();
                  }
                });
              },
              hint: const Text('Түрээслэгч сонгоно уу'), // Select a tenant
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Get the current orientation and screen width
    final mediaQuery = MediaQuery.of(context);
    final orientation = mediaQuery.orientation;
    final screenWidth = mediaQuery.size.width;
    final shortestSide = mediaQuery.size.shortestSide;
    final platform = Theme.of(context).platform;

    // 2. Define the condition for the maximum width constraint:
    // Only apply the constraint if it is a compact iOS device (like iPhone)
    // AND it is in landscape mode.
    final isCompactIOS = platform == TargetPlatform.iOS && shortestSide < 600.0;
    final isLandscape = orientation == Orientation.landscape;
    final double? maxWidth = isCompactIOS && isLandscape ? 700.0 : null;
    // 3. Use Center and ConstrainedBox/SizedBox to apply the max width
    final Widget content = Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 1. Tenant Dropdown
          _buildSelectionRow(),

          const Divider(height: 1),

          // 2. History Type Buttons
          _availableHistory.isNotEmpty ? _buildHistoryTypeButtons() : const SizedBox.shrink(),

          // const Divider(height: 1),
          // _buildYearDropdown(),
          const Divider(height: 1),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _errorMessage!,
                // Remove 'const' from TextStyle and its properties to allow runtime comparison
                style: TextStyle(
                  // Conditional color based on the message content
                  color: _errorMessage == 'Дата олдсонгүй' ? Colors.black : Colors.redAccent,
                  fontWeight:
                      _errorMessage == 'Дата олдсонгүй' ? FontWeight.normal : FontWeight.bold,
                ),
                // Conditional alignment based on the message content
                textAlign: _errorMessage == 'Дата олдсонгүй' ? TextAlign.center : TextAlign.start,
              ),
            )
          else if (_isLoading)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Өгөгдөл татаж байна...',
                      style: TextStyle(color: Colors.blueGrey),
                    ), // Fetching data...
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: SingleChildScrollView(child: _buildHistoryTable())),
                  _buildFooter(),
                ],
              ),
            ),
        ],
      ),
    );

    // 4. Apply the width constraint using Center and ConstrainedBox
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? screenWidth, // Use 600 or the screen width
        ),
        child: content,
      ),
    );
  }
}
