import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:share_plus/share_plus.dart';

class PdfViewerScreen extends StatefulWidget {
  final String pdfPath;

  final String? pdfTitle;

  const PdfViewerScreen({super.key, required this.pdfPath, this.pdfTitle});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  int _pages = 0;
  int _currentPage = 0;
  bool _isReady = false;
  String _errorMessage = '';

  Future<void> _onShareFile() async {
    final file = File(widget.pdfPath);

    if (await file.exists()) {
      try {
        await Share.shareXFiles([
          XFile(widget.pdfPath),
        ], subject: widget.pdfTitle ?? 'Shared PDF Report');
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Файл хуваалцахад алдаа гарлаа: $e')));
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Файл олдсонгүй.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool fileExists = File(widget.pdfPath).existsSync();

    final mediaQuery = MediaQuery.of(context);
    final platform = Theme.of(context).platform;
    final shortestSide = mediaQuery.size.shortestSide;
    final isPortrait = mediaQuery.orientation == Orientation.portrait;

    final bool isIPhone = platform == TargetPlatform.iOS && shortestSide < 600.0;

    final appBarWidget =
        (isIPhone && !isPortrait)
            ? null
            : AppBar(
              title: Text(
                widget.pdfTitle ?? 'Тайлан харах',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
              ),
              backgroundColor: const Color(0xFF00CCCC),
            );

    return Scaffold(
      appBar: appBarWidget,

      backgroundColor: Colors.white,
      body: Stack(
        children: <Widget>[
          if (fileExists)
            Positioned.fill(
              child: PDFView(
                filePath: widget.pdfPath,
                enableSwipe: true,
                swipeHorizontal: false,
                autoSpacing: true,
                pageFling: true,
                pageSnap: true,
                backgroundColor: Colors.grey[700],

                onError: (error) {
                  debugPrint('PDF RENDER ERROR: ${error.toString()}');
                  setState(() {
                    _errorMessage = error.toString();
                    _isReady = true;
                  });
                },
                onRender: (pages) {
                  debugPrint('PDF RENDER SUCCESS. Pages: $pages');
                  setState(() {
                    _pages = pages ?? 0;
                    _isReady = true;
                  });
                },
                onPageChanged: (int? page, int? total) {
                  setState(() {
                    _currentPage = page ?? 0;
                  });
                },
              ),
            )
          else
            Center(
              child: Text(
                'Файл олдсонгүй: ${widget.pdfPath}',
                style: const TextStyle(color: Colors.red),
              ),
            ),

          if (_errorMessage.isNotEmpty)
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white70,
                child: Text(
                  'PDF-ийг нээхэд алдаа гарлаа: $_errorMessage',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          if (!_isReady && _errorMessage.isEmpty) const Center(child: CircularProgressIndicator()),
        ],
      ),

      floatingActionButton:
          _pages > 0 && _isReady
              ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Visibility(
                        visible: false,
                        maintainSize: true,
                        maintainState: true,
                        maintainAnimation: true,
                        child: FloatingActionButton(
                          heroTag: "shareButton",
                          onPressed: () {},
                          backgroundColor: const Color.fromARGB(255, 170, 197, 245),
                          mini: true,
                          child: const Icon(Icons.share, color: Colors.white),
                        ),
                      ),

                      const Spacer(),

                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_currentPage + 1}/$_pages',
                          style: const TextStyle(fontSize: 14, color: Colors.white),
                        ),
                      ),

                      const Spacer(),

                      if (fileExists)
                        FloatingActionButton(
                          heroTag: "downloadButton",
                          onPressed: _onShareFile,
                          backgroundColor: const Color(0xFF00CCCC),
                          mini: true,
                          child: const Icon(Icons.download, color: Colors.black),
                        ),
                    ],
                  ),
                ),
              )
              : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
