import 'package:flutter/material.dart';

class ErrorHandler {
  static Widget buildErrorWidget(String message, VoidCallback onRetry, {bool showRetry = true}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 80, color: Colors.red[400]),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
            const SizedBox(height: 24),
            if (showRetry)
              ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00CCCC),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Icon(Icons.refresh), SizedBox(width: 8), Text('Дахин оролдох')],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Widget buildNetworkErrorWidget(VoidCallback onRetry) {
    return buildErrorWidget('Интернэт холболтоо шалгана уу.\nСүлжээний алдаа.', onRetry);
  }

  static Widget buildServerErrorWidget(VoidCallback onRetry) {
    return buildErrorWidget('Сервертэй холбогдоход алдаа гарлаа.\nДахин оролдоно уу.', onRetry);
  }

  static void showSnackBar(BuildContext context, String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Хаах',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  static Future<void> showAlertDialog(BuildContext context, String title, String message) {
    return showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }
}

class LoadingIndicator extends StatelessWidget {
  final String? message;
  final bool showProgress;

  const LoadingIndicator({super.key, this.message, this.showProgress = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00CCCC)),
          ),
          const SizedBox(height: 16),
          if (message != null)
            Text(message!, style: const TextStyle(fontSize: 14, color: Colors.black54)),
        ],
      ),
    );
  }
}

class RetryButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String text;

  const RetryButton({super.key, required this.onPressed, this.text = 'Дахин оролдох'});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF00CCCC),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(Icons.refresh, size: 18), const SizedBox(width: 8), Text(text)],
      ),
    );
  }
}
