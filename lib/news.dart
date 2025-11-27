import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import 'package:medsoft_patient/api/blog_dao.dart';

class NewsFeedWidget extends StatelessWidget {
  const NewsFeedWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final BlogDAO blogDAO = BlogDAO();

    final double shortestSide = MediaQuery.of(context).size.shortestSide;

    const double tabletBreakpoint = 600.0;

    final double viewportFraction = shortestSide >= tabletBreakpoint ? 0.5 : 0.8;

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

        return Column(
          children: [
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

            Expanded(
              child: PageView.builder(
                itemCount: news.length,
                controller: PageController(viewportFraction: viewportFraction),
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

                  return Stack(
                    children: [
                      SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (item["image"] != null)
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                                child: Image.memory(_decodeBase64(item["image"])),
                              ),

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
                  );
                },
              ),
            ),
          ),
    );
  }
}
