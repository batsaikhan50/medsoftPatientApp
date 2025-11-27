import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:medsoft_patient/api/history_dao.dart';
import 'package:medsoft_patient/pdf_viewer.dart';
import 'package:path_provider/path_provider.dart';

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

class HistoryAvailable {
  final String key;
  final String value;
  final List<HistoryAction> actions;

  HistoryAvailable.fromJson(Map<String, dynamic> json)
    : key = json['key'],
      value = json['value'],

      actions =
          (json['actions'] as List<dynamic>?)
              ?.map((e) => HistoryAction.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [];
}

class HistoryColumn {
  final String field;
  final String caption;
  final String? footer;
  final bool hidden;
  final bool html;
  final List<HistoryCellData> data;

  HistoryColumn.fromJson(Map<String, dynamic> json)
    : field = json['field'] ?? '',
      caption = json['caption'] ?? '',
      footer = json['footer'],
      hidden = json['hidden'] ?? false,
      html = json['html'] ?? false,
      data = (json['data'] as List).map((e) => HistoryCellData.fromJson(e)).toList();
}

class HistoryCellData {
  final String? value;
  final String? html;
  final Map<String, dynamic> props;

  HistoryCellData.fromJson(Map<String, dynamic> json)
    : value = json['value'],
      html = json['html'],
      props = json['props'] ?? {};
}

class HistoryScreen extends StatefulWidget {
  final String? initialHistoryKey;

  const HistoryScreen({super.key, this.initialHistoryKey});

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
      final tenantResponse = await _historyDAO.getHistoryTenants();
      if (tenantResponse.success && tenantResponse.data != null) {
        _tenants =
            (tenantResponse.data!)
                .map((e) => HistoryTenant.fromJson(e as Map<String, dynamic>))
                .toList();
        _selectedTenant = _tenants.isNotEmpty ? _tenants.first : null;
      } else {
        throw Exception('Түрээслэгчдийг татаж чадсангүй.');
      }

      final availableResponse = await _historyDAO.getHistoryAvailable();
      if (availableResponse.success && availableResponse.data != null) {
        _availableHistory =
            (availableResponse.data!)
                .map((e) => HistoryAvailable.fromJson(e as Map<String, dynamic>))
                .toList();

        if (widget.initialHistoryKey != null) {
          HistoryAvailable? matchingType;

          if (_availableHistory.isNotEmpty) {
            matchingType = _availableHistory.firstWhere(
              (type) => type.key == widget.initialHistoryKey,
              orElse: () => _availableHistory.first,
            );
          }

          _selectedHistoryType = matchingType;
        } else {
          _selectedHistoryType = _availableHistory.isNotEmpty ? _availableHistory.first : null;
        }
      } else {
        throw Exception('Боломжит түүхийн төрлүүдийг татаж чадсангүй.');
      }

      if (_selectedTenant != null && _selectedHistoryType != null) {
        await _fetchHistory();
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Эхний өгөгдлийг татахад алдаа гарлаа: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchHistory() async {
    if (_selectedTenant == null || _selectedHistoryType == null) return;

    setState(() {
      _isLoading = true;
      _historyData = [];
      _errorMessage = null;
    });

    try {
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
          _errorMessage = 'Дата олдсонгүй';
        }
      } else if (!historyResponse.success && historyResponse.data == null) {
        _errorMessage = 'Дата олдсонгүй';
      } else {
        throw Exception('Өвчтөний түүхийг татаж чадсангүй.');
      }
    } catch (e) {
      if (_errorMessage == null || _errorMessage!.isEmpty) {
        _errorMessage = 'Түүхийн өгөгдлийг татахад алдаа гарлаа: ${e.toString()}';
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

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
              backgroundColor: isSelected ? Colors.blue : Colors.blue.withAlpha(26),
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

  List<HistoryAction> _getPrintActions() {
    if (_selectedHistoryType == null) {
      return const [];
    }

    return _selectedHistoryType!.actions.where((action) => action.key == 'print').toList();
  }

  Future<String?> _showActionSelectionDialog(List<HistoryAction> actions) async {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Хэвлэх үйлдлийг сонгоно уу'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children:
                actions.map((action) {
                  return ListTile(
                    title: Text(action.value),
                    onTap: () {
                      Navigator.of(context).pop(action.key);
                    },
                  );
                }).toList(),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Цуцлах'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  String? _getPrintId(List<HistoryCellData> row) {
    final cellWithId = row.firstWhere(
      (cell) => cell.props.containsKey('id'),
      orElse: () => HistoryCellData.fromJson({}),
    );

    return cellWithId.props['id'] as String?;
  }

  Future<void> _openPdfViewer(Uint8List pdfBytes, String filename) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename.pdf');

    await file.writeAsBytes(pdfBytes, flush: true);
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PdfViewerScreen(pdfTitle: filename, pdfPath: file.path),
      ),
    );
  }

  Future<void> _handlePrint(List<HistoryCellData> row) async {
    if (_selectedTenant == null || _selectedHistoryType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Түрээслэгч эсвэл Түүхийн төрөл сонгогдоогүй.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final String? printId = _getPrintId(row);
    final String historyKey = _selectedHistoryType!.key;
    final String tenantName = _selectedTenant!.tenantName;

    if (printId == null || printId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Хэвлэхэд шаардлагатай ID олдсонгүй.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final List<HistoryAction> printActions = _getPrintActions();
    String? actionKey;

    if (printActions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сонгосон түүхэнд хэвлэх үйлдэл тодорхойлогдоогүй.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    } else if (printActions.length == 1) {
      actionKey = printActions.first.key;
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Үйлдлийг сонгоно уу.')));
      actionKey = await _showActionSelectionDialog(printActions);

      if (actionKey == null) {
        return;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Хэвлэх хүсэлт илгээж байна...')));

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

        await _openPdfViewer(pdfBytes, '${historyKey}_${tenantName}_$formatted');
      } else {
        throw Exception('Серверээс PDF өгөгдөл ирсэнгүй (Хоосон файл).');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Тайланг нээх явцад алдаа гарлаа: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildHistoryTable() {
    final rows = _getRows();
    final columns = _historyData.where((col) => col.hidden == false).toList();

    final bool shouldShowPrintColumn = _selectedHistoryType?.value != 'Цаг захиалгын түүх';

    if (rows.isEmpty && !_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text('Өгөгдөл олдсонгүй.', style: TextStyle(fontSize: 16, color: Colors.grey)),
        ),
      );
    }

    final List<DataColumn> tableColumns = <DataColumn>[
      if (shouldShowPrintColumn)
        const DataColumn(
          label: SizedBox(
            width: 50,
            child: Text(
              'Хэвлэх',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ),
        ),

      ...columns.map((col) {
        return DataColumn(
          label: SizedBox(
            width: col.field == 'status' ? 80 : 150,
            child: Text(
              col.caption,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ),
        );
      }),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidget = DataTable(
          columnSpacing: 16.0,
          dataRowMinHeight: 80.0,
          dataRowMaxHeight: 80.0,
          columns: tableColumns,
          rows:
              rows.map((row) {
                final rowCells =
                    row
                        .asMap()
                        .entries
                        .where((entry) {
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

                final bool shouldShowPrintButton =
                    shouldShowPrintColumn && rowHasPrintId && hasPrintActions;

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
                            : const SizedBox.shrink(),
                  ),
                );

                final List<DataCell> cells = [];
                if (shouldShowPrintColumn) {
                  cells.add(printCell);
                }
                cells.addAll(rowCells);

                return DataRow(cells: cells);
              }).toList(),
        );

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,

          child: Center(child: tableWidget),
        );
      },
    );
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

  Widget _buildSelectionRow() {
    final currentYear = DateTime.now().year;

    final years = List<int>.generate(6, (index) => currentYear - index);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: DropdownButtonFormField<int>(
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Он',
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

          const SizedBox(width: 8.0),

          Expanded(
            child: DropdownButtonFormField<HistoryTenant>(
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Эмнэлэг сонгох',
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
              hint: const Text('Түрээслэгч сонгоно уу'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final orientation = mediaQuery.orientation;
    final screenWidth = mediaQuery.size.width;
    final shortestSide = mediaQuery.size.shortestSide;
    final platform = Theme.of(context).platform;

    final isCompactIOS = platform == TargetPlatform.iOS && shortestSide < 600.0;
    final isLandscape = orientation == Orientation.landscape;
    final double? maxWidth = isCompactIOS && isLandscape ? 700.0 : null;

    final Widget content = Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildSelectionRow(),

          const Divider(height: 1),

          _availableHistory.isNotEmpty ? _buildHistoryTypeButtons() : const SizedBox.shrink(),

          const Divider(height: 1),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _errorMessage!,

                style: TextStyle(
                  color: _errorMessage == 'Дата олдсонгүй' ? Colors.black : Colors.redAccent,
                  fontWeight:
                      _errorMessage == 'Дата олдсонгүй' ? FontWeight.normal : FontWeight.bold,
                ),

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
                    Text('Өгөгдөл татаж байна...', style: TextStyle(color: Colors.blueGrey)),
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

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? screenWidth),
        child: content,
      ),
    );
  }
}
