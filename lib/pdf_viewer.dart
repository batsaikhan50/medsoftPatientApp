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
        // Use the shareXFiles method for sharing a local file
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

    // Define the condition for a compact iOS device (iPhone/iPod Touch)
    // Standard cutoff is usually < 600.0 or < 700.0 for smaller devices.
    const double kIPhoneShortestSideLimit = 600.0;
    final bool isIPhone = platform == TargetPlatform.iOS && shortestSide < 600.0;

    final appBarWidget =
        // The AppBar is only created if:
        // 1. The device is a compact iOS device (iPhone) AND
        // 2. The orientation is portrait (as per your original code condition)
        (isIPhone && !isPortrait)
            ? null
            : AppBar(
              title: Text(
                widget.pdfTitle ?? 'Тайлан харах',
                style: const TextStyle(
                  fontSize: 20, // adjust size here
                  fontWeight: FontWeight.w500,
                ),
              ),
              backgroundColor: const Color(0xFF00CCCC),
              // actions: [
              //   if (fileExists)
              //     Padding(
              //       padding: const EdgeInsets.only(right: 10.0),
              //       child: IconButton(
              //         icon: const Icon(Icons.download, color: Colors.black),
              //         onPressed: _onShareFile,
              //         tooltip: 'Файл хуваалцах', // Share file
              //         iconSize: 26,
              //       ),
              //     ),
              // ],
            );

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
              ? SafeArea(
                // 👈 Wrap the entire button group in SafeArea
                child: Padding(
                  // Use horizontal padding for margin from the screen edges
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 1. Download button (Bottom Left) - HIDDEN BUT MAINTAINING SPACE
                      // Replace the original FloatingActionButton with Visibility
                      Visibility(
                        visible: false, // Set to false to hide the button
                        maintainSize: true, // Crucial: Keeps the space it occupies
                        maintainState: true,
                        maintainAnimation: true,
                        child: FloatingActionButton(
                          heroTag: "shareButton", // Must have a unique tag
                          onPressed: () {
                            // Add your action here
                          },
                          backgroundColor: const Color.fromARGB(
                            255,
                            170,
                            197,
                            245,
                          ), // Example color
                          mini: true,
                          child: const Icon(Icons.share, color: Colors.white),
                        ),
                      ),
                      // Use a Spacer to push the next elements further right
                      const Spacer(),
                      // 2. Page Counter (Optional: Center, or near the right button)
                      Container(
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
                      // Use another Spacer to ensure space for the right button
                      const Spacer(),
                      // 3. New Right Button (Example: Share/Another Action)
                      // This button's position is now symmetrical with the hidden button.
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
