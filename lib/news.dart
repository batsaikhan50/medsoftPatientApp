import 'dart:convert';
import 'dart:typed_data';

// Assuming BlogDAO is in a path accessible by the Patient App
// You might need to adjust this import based on your actual file structure
import 'package:medsoft_patient/api/blog_dao.dart';
import 'package:flutter/material.dart';

import 'package:flutter_html/flutter_html.dart';

class NewsFeedWidget extends StatelessWidget {
  const NewsFeedWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final BlogDAO blogDAO = BlogDAO(); // Instantiate the DAO

    return FutureBuilder(
      future: blogDAO.getAllNews(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final response = snapshot.data!;
        // Assuming response.data is a List<dynamic> of news items
        final List<dynamic>? news = response.data;

        if (news == null || news.isEmpty) {
          return const Center(child: Text("Мэдээ олдсонгүй"));
        }

        // The core content from Doctor App's HomeScreen
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(
                top: 8.0,
                bottom: 8.0,
                left: 16.0,
                right: 16.0,
              ), // Added horizontal padding for screen edges
              child: Row(
                children: [
                  // 1. The small, left-aligned header text
                  const Text(
                    'Мэдээ мэдээлэл',
                    style: TextStyle(
                      fontSize: 14, // Smaller font size
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(width: 8), // Small space between text and line
                  // 2. The middle line extending to the right
                  Expanded(
                    child: Divider(
                      color: Colors.grey, // Choose a suitable color for the line
                      height: 1, // Minimal height for a thin line
                      thickness: 1, // Line thickness
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              // Expanded is crucial inside the Column to make PageView work
              child: PageView.builder(
                itemCount: news.length,
                controller: PageController(viewportFraction: 0.8),
                itemBuilder: (context, index) {
                  final item = news[index];

                  return GestureDetector(
                    onTap: () => _openNewsDetail(context, item["_id"], blogDAO),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Card(
                        elevation: 0.5,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // IMAGE
                            Expanded(
                              flex: 3,
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                child: Image.memory(
                                  _decodeBase64(item["image"]),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),

                            // TITLE
                            Expanded(
                              flex: 3,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Center(
                                    child: Text(
                                      item["title"] ?? "",
                                      maxLines: 7,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // Converts base64 string to Uint8List - KEEP THIS HELPER
  Uint8List _decodeBase64(String img) {
    final base64String = img.split(',').last;
    return base64Decode(base64String);
  }

  void _openNewsDetail(BuildContext context, String id, BlogDAO blogDAO) {
    // You'll need to ensure flutter_html is also available in the Patient app
    // for this to work. Since I cannot assume that, I'll use a simple Text widget.
    // **NOTE**: For full functionality, you must import `package:flutter_html/flutter_html.dart`.
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (context) => FractionallySizedBox(
            // <--- WRAP DIALOG WITH FractionallySizedBox
            heightFactor: 0.8, // <--- Set height to 70% of screen height
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

                  // Use Stack to overlay the close button on the content
                  return Stack(
                    children: [
                      SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // IMAGE
                            if (item["image"] != null)
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                                child: Image.memory(_decodeBase64(item["image"])),
                              ),

                            const SizedBox(height: 12),

                            // TITLE
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                item["title"] ?? "",
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                            ),

                            const SizedBox(height: 10),

                            // CONTENT (Simplified due to flutter_html assumption)
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
                            color: Colors.black38, // Semi-transparent background for contrast
                            border: Border.all(
                              color: Colors.white, // The white outline
                              width: 2.0,
                            ),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.close, size: 24),
                            color: Colors.white, // Icon color set to white
                            onPressed: () {
                              // Close the dialog
                              Navigator.of(context).pop();
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
    );
  }
}
