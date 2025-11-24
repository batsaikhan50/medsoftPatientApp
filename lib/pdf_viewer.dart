import 'dart:io';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

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

  // 2. NEW METHOD: Handle file sharing/downloading
  // 2. TEMPORARY FIX: Reverting to the original, deprecated static method
  Future<void> _onShareFile() async {
    final file = File(widget.pdfPath);

    if (await file.exists()) {
      try {
        // FIX: Revert to the original static method Share.shareXFiles()
        // This is deprecated, but it is the most likely signature to work
        // with a wide range of older, inconsistent package versions.
        await SharePlus.instance.share(
          ShareParams(
            // text: 'Тайлан хавсаргасан байна.',
            subject: widget.pdfTitle ?? 'Shared PDF Report',
            files: [XFile(widget.pdfPath)],
          ),
        );
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

    // --- FIX START ---
    // Get the current orientation from the context
    final orientation = MediaQuery.of(context).orientation;

    // Check if the device is in portrait mode
    final isPortrait = orientation == Orientation.portrait;

    // Conditionally create the AppBar
    final appBarWidget =
        isPortrait
            ? AppBar(
              title: Text(
                widget.pdfTitle ?? 'Тайлан харах',
                style: const TextStyle(
                  fontSize: 20, // adjust size here
                  fontWeight: FontWeight.w500,
                ),
              ),
              backgroundColor: const Color(0xFF00CCCC),
              actions: [
                if (fileExists)
                  Padding(
                    padding: const EdgeInsets.only(right: 10.0),
                    child: IconButton(
                      icon: const Icon(Icons.download, color: Colors.black),
                      onPressed: _onShareFile,
                      tooltip: 'Файл хуваалцах', // Share file
                      iconSize: 26,
                    ),
                  ),
              ],
            )
            : null; // Set to null when in landscape mode
    // --- FIX END ---

    // Debug logs confirming file status (as seen in your output)
    // print('PDF Path: ${widget.pdfPath}');
    // print('File Exists: $fileExists');

    return Scaffold(
      // --- APPLY FIX ---
      appBar: appBarWidget, // Use the conditionally defined AppBar
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
