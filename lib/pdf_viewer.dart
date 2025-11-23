import 'dart:io';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:flutter/material.dart';

class PdfViewerScreen extends StatefulWidget {
  final String pdfPath;
  // 1. Add optional pdfTitle property
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

  @override
  Widget build(BuildContext context) {
    bool fileExists = File(widget.pdfPath).existsSync();

    // Debug logs confirming file status (as seen in your output)
    // print('PDF Path: ${widget.pdfPath}');
    // print('File Exists: $fileExists');

    return Scaffold(
      appBar: AppBar(
        // 2. Use the provided title or a default Mongolian text
        title: Text(widget.pdfTitle ?? 'Тайлан харах'), // View Report
        backgroundColor: Color(0xFF00CCCC),
      ),
      // Set the background color here or rely on the theme's background color
      backgroundColor: Colors.white,
      body: Stack(
        children: <Widget>[
          // 1. Main Content: PDF View (Positioned to fill the entire body)
          if (fileExists)
            Positioned.fill(
              child: PDFView(
                filePath: widget.pdfPath,
                enableSwipe: true,
                swipeHorizontal: true,
                autoSpacing: true, // CHANGE 1: Set to true for auto-spacing/fitting
                pageFling: true,
                backgroundColor: Colors.grey[700],
                // IMPORTANT: Use the default PDF background color to prevent masking
                // If you had a background color in the PDFView itself, remove it.
                // backgroundColor: Colors.transparent,
                onError: (error) {
                  print('PDF RENDER ERROR: ${error.toString()}');
                  setState(() {
                    _errorMessage = error.toString();
                    _isReady = true;
                  });
                },
                onRender: (pages) {
                  print('PDF RENDER SUCCESS. Pages: $pages');
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
            // Fallback for file not found
            Center(
              child: Text(
                'Файл олдсонгүй: ${widget.pdfPath}', // File not found:
                style: const TextStyle(color: Colors.red),
              ),
            ),

          // 2. Overlay: Error Message
          if (_errorMessage.isNotEmpty)
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white70,
                child: Text(
                  'PDF-ийг нээхэд алдаа гарлаа: $_errorMessage', // Error opening PDF:
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          // 3. Overlay: Loading indicator
          if (!_isReady && _errorMessage.isEmpty) const Center(child: CircularProgressIndicator()),
        ],
      ),
      // Display page counter at the bottom center
      floatingActionButton:
          _pages > 0 && _isReady
              ? Padding(
                padding: const EdgeInsets.only(left: 32.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_currentPage + 1}/$_pages',
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                  ),
                ),
              )
              : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.miniEndFloat,
    );
  }
}
