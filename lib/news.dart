import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import 'package:medsoft_patient/api/blog_dao.dart';

class NewsFeedWidget extends StatelessWidget {
  final bool isVerticalScroll; // Added parameter to control scroll direction

  const NewsFeedWidget({super.key, this.isVerticalScroll = false}); // Default to horizontal scroll

  @override
  Widget build(BuildContext context) {
    final BlogDAO blogDAO = BlogDAO();

    final double shortestSide = MediaQuery.of(context).size.shortestSide;

    const double tabletBreakpoint = 600.0;

    // Use a smaller viewportFraction for horizontal scroll on phones/portrait tablets
    final double viewportFraction =
        shortestSide >= tabletBreakpoint && !isVerticalScroll ? 0.5 : 0.8;

    return FutureBuilder(
      future: blogDAO.getAllNews(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final response = snapshot.data!;

        final List<dynamic>? news = response.data;

        if (news == null || news.isEmpty) {
          return const Center(child: Text("Мэдээ олдсонгүй"));
        }

        Widget newsList;

        if (isVerticalScroll) {
          // New: Vertical ListView for tablet landscape mode
          newsList = ListView.builder(
            itemCount: news.length,
            // Add vertical padding/margin to cards for ListView
            itemBuilder: (context, index) {
              final item = news[index];
              return Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
                // Use a fixed aspect ratio for cards in the vertical list to maintain size consistency
                child: _buildNewsCard(context, item, blogDAO, 2.05),
              );
            },
          );
        } else {
          // Existing: Horizontal PageView.builder for phone/portrait tablet mode
          newsList = PageView.builder(
            itemCount: news.length,
            controller: PageController(viewportFraction: viewportFraction),
            itemBuilder: (context, index) {
              final item = news[index];
              return Padding(
                padding: const EdgeInsets.all(12),
                child: _buildNewsCard(context, item, blogDAO, null),
              );
            },
          );
        }

        return Column(
          children: [
            // The header 'Мэдээ мэдээлэл'
            Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 8.0, left: 16.0, right: 16.0),
              child: Row(
                children: [
                  const Text(
                    'Мэдээ мэдээлэл',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Divider(color: Colors.grey, height: 1, thickness: 1)),
                ],
              ),
            ),

            // The news list (Page View or List View)
            Expanded(child: newsList),
          ],
        );
      },
    );
  }

  // Helper function to build the news card for both PageView and ListView
  Widget _buildNewsCard(
    BuildContext context,
    Map<String, dynamic> item,
    BlogDAO blogDAO,
    double? aspectRatio,
  ) {
    return GestureDetector(
      onTap: () => _openNewsDetail(context, item["blogId"], blogDAO),
      child: Card(
        elevation: 0.5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
        child:
            aspectRatio != null
                ? AspectRatio(aspectRatio: aspectRatio, child: _buildCardContent(item))
                : _buildCardContent(item),
      ),
    );
  }

  // Helper function to build the card content (Image and Title)
  Widget _buildCardContent(Map<String, dynamic> item) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Image.memory(_decodeBase64(item["image"]), fit: BoxFit.cover),
          ),
        ),
        Expanded(
          flex: 3,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: _buildDynamicText(
                  item["title"] ?? "",
                  maxLines: 7,
                  maxFontSize: 18,
                  minFontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Dynamic text widget that adjusts font size based on content length
  Widget _buildDynamicText(
    String text, {
    required int maxLines,
    required double maxFontSize,
    required double minFontSize,
    required FontWeight fontWeight,
  }) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: _calculateFontSize(text, constraints, maxFontSize, minFontSize),
            fontWeight: fontWeight,
          ),
        );
      },
    );
  }

  // Calculate optimal font size based on text length and available space
  double _calculateFontSize(
    String text,
    BoxConstraints constraints,
    double maxFontSize,
    double minFontSize,
  ) {
    if (text.isEmpty) return maxFontSize;

    // Base font size calculation
    double fontSize = maxFontSize;

    // Adjust font size based on text length
    final int textLength = text.length;

    if (textLength > 50) {
      // For very long titles, reduce font size more aggressively
      fontSize = maxFontSize - (textLength * 0.15);
    } else if (textLength > 30) {
      // For moderately long titles, reduce font size moderately
      fontSize = maxFontSize - (textLength * 0.1);
    } else if (textLength > 20) {
      // For slightly long titles, reduce font size slightly
      fontSize = maxFontSize - (textLength * 0.05);
    }

    // Ensure font size stays within bounds
    fontSize = fontSize.clamp(minFontSize, maxFontSize);

    // Additional check based on available width (if constraints are available)
    if (constraints.maxWidth > 0) {
      // Simple heuristic: if the text is too long for the available width, reduce font size
      final double estimatedWidth = text.length * fontSize * 0.6; // Rough width estimation
      if (estimatedWidth > constraints.maxWidth * 0.9) {
        fontSize = fontSize * 0.85; // Reduce by 15% if it's too wide
        fontSize = fontSize.clamp(minFontSize, maxFontSize);
      }
    }

    return fontSize;
  }

  Uint8List _decodeBase64(String img) {
    final base64String = img.split(',').last;
    return base64Decode(base64String);
  }

  void _openNewsDetail(BuildContext context, String id, BlogDAO blogDAO) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (context) => FractionallySizedBox(
            heightFactor: 0.8,
            child: Dialog(
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.all(16),
              child: FutureBuilder(
                future: blogDAO.getNewsDetail(id),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final response = snapshot.data!;
                  final item = response.data;

                  if (!response.success || item == null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          response.message ?? 'Мэдээллийг татаж чадсангүй.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  // 1. Define the Radius once
                  const double dialogRadius = 30.0;

                  return ClipRRect(
                    // <-- ADD ClipRRect HERE
                    borderRadius: BorderRadius.circular(
                      dialogRadius,
                    ), // Use the same radius as the image/dialog
                    child: Stack(
                      children: [
                        SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // The image itself can now use the full width
                              if (item["image"] != null) Image.memory(_decodeBase64(item["image"])),

                              // REMOVED ClipRRect from the image here
                              // since the outer ClipRRect handles it for the whole dialog.
                              // If you want the image to have a different radius, keep the ClipRRect above.
                              // However, for a consistent look, removing it here is usually better.
                              const SizedBox(height: 12),

                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  item["title"] ?? "",
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                              ),

                              const SizedBox(height: 10),

                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Html(data: '${item["mergedValues"] ?? "No content"}'),
                              ),

                              const SizedBox(height: 20),
                            ],
                          ),
                        ),

                        Positioned(
                          top: 10.0,
                          right: 10.0,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black38,
                              border: Border.all(color: Colors.white, width: 2.0),
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.close, size: 24),
                              color: Colors.white,
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
    );
  }
}
