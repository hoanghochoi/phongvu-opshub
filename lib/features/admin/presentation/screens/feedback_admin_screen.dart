import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';

class FeedbackAdminScreen extends StatefulWidget {
  const FeedbackAdminScreen({super.key});

  @override
  State<FeedbackAdminScreen> createState() => _FeedbackAdminScreenState();
}

class _FeedbackAdminScreenState extends State<FeedbackAdminScreen> {
  final _apiClient = ApiClient();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final startedAt = DateTime.now();
    await AppLogger.instance.info(
      'FeedbackAdmin',
      'Feedback admin list load started',
    );
    try {
      final response = await _apiClient.get(ApiConstants.adminFeedbackEndpoint);
      final data = jsonDecode(response.body) as List<dynamic>;
      final items = data.whereType<Map<String, dynamic>>().toList(
        growable: false,
      );
      if (!mounted) return;
      setState(() => _items = items);
      await AppLogger.instance.info(
        'FeedbackAdmin',
        'Feedback admin list load succeeded',
        context: {
          'count': items.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'FeedbackAdmin',
        'Feedback admin list load failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không tải được danh sách phản hồi')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientHeader(
        title: 'Danh sách phản hồi',
        showBack: true,
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Tải lại',
          ),
        ],
      ),
      body: AppResponsiveContent(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: AppLayoutTokens.formInlineGap),
                itemBuilder: (context, index) =>
                    _FeedbackTile(item: _items[index]),
              ),
      ),
    );
  }
}

class _FeedbackTile extends StatelessWidget {
  final Map<String, dynamic> item;

  const _FeedbackTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final user = item['user'] is Map<String, dynamic>
        ? item['user'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final email = user['email']?.toString() ?? 'unknown';
    final name = user['firstName']?.toString();
    final content = item['content']?.toString() ?? '';
    final rating = item['rating']?.toString();
    final createdAt = item['createdAt']?.toString();
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: const Icon(Icons.feedback_outlined),
        title: Text(
          name?.isNotEmpty == true ? '$name • $email' : email,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rating?.isNotEmpty == true) Text('Rating: $rating'),
            Text(content, maxLines: 4, overflow: TextOverflow.ellipsis),
            if (createdAt?.isNotEmpty == true)
              Text(createdAt!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
