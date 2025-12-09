import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/warranty_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'warranty_details_screen.dart';
import '../../../chat/presentation/widgets/barcode_scanner_screen.dart' show BarcodeScannerScreen;

class CheckWarrantyScreen extends StatefulWidget {
  const CheckWarrantyScreen({super.key});

  @override
  State<CheckWarrantyScreen> createState() => _CheckWarrantyScreenState();
}

class _CheckWarrantyScreenState extends State<CheckWarrantyScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  bool _isSearchMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllReceipts();
      // Auto-focus search field when screen loads
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadAllReceipts() async {
    final authProvider = context.read<AuthProvider>();
    final warrantyProvider = context.read<WarrantyProvider>();
    final userEmail = authProvider.user?.email ?? '';

    if (userEmail.isNotEmpty) {
      await warrantyProvider.showAllWarranty(userEmail);
    }
  }

  Future<void> _searchReceipt() async {
    if (_searchController.text.trim().isEmpty) {
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final warrantyProvider = context.read<WarrantyProvider>();
    final userEmail = authProvider.user?.email ?? '';

    if (userEmail.isEmpty) return;

    setState(() {
      _isSearchMode = true;
    });

    await warrantyProvider.searchWarranty(
      userEmail: userEmail,
      receiptNumber: _searchController.text.trim().toUpperCase(),
    );
  }

  Future<void> _scanBarcode() async {
    try {
      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) => const BarcodeScannerScreen(),
        ),
      );

      if (result != null && mounted) {
        _searchController.text = result;
        _searchReceipt();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi quét mã: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _isSearchMode = false;
    });
    _loadAllReceipts();
  }

  void _viewReceiptDetails(Map<String, dynamic> receipt) async {
    final receiptNumber = receipt['receipt']?.toString() ?? '';
    if (receiptNumber.isEmpty) return;

    // Navigate to details screen
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => WarrantyDetailsScreen(receiptNumber: receiptNumber),
      ),
    );

    // Refresh list when returning from details screen
    if (mounted) {
      if (_isSearchMode) {
        _searchReceipt();
      } else {
        _loadAllReceipts();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Xem lại biên nhận'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'Tìm kiếm biên nhận',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _isSearchMode
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: _clearSearch,
                              )
                            : IconButton(
                                icon: const Icon(Icons.qr_code_scanner),
                                onPressed: _scanBarcode,
                              ),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _searchReceipt(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _searchReceipt,
                    child: const Text('Tìm'),
                  ),
                ],
              ),
            ),

            // Receipt list
            Expanded(
              child: Consumer<WarrantyProvider>(
                builder: (context, warrantyProvider, _) {
                  if (warrantyProvider.isLoading) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (warrantyProvider.errorMessage != null) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            warrantyProvider.errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadAllReceipts,
                            child: const Text('Thử lại'),
                          ),
                        ],
                      ),
                    );
                  }

                  if (warrantyProvider.receipts.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.receipt_long_outlined,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _isSearchMode
                                ? 'Không tìm thấy biên nhận'
                                : 'Chưa có biên nhận nào',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.grey[600],
                                ),
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: _loadAllReceipts,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: warrantyProvider.receipts.length,
                      itemBuilder: (context, index) {
                        final receipt = warrantyProvider.receipts[index];
                        return _ReceiptCard(
                          receipt: receipt,
                          onTap: () => _viewReceiptDetails(receipt),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  final Map<String, dynamic> receipt;
  final VoidCallback onTap;

  const _ReceiptCard({
    required this.receipt,
    required this.onTap,
  });

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) {
      return 'N/A';
    }

    try {
      // Try to parse different date formats
      DateTime? dateTime;

      // Try ISO format first (yyyy-MM-dd or yyyy-MM-ddTHH:mm:ss)
      try {
        dateTime = DateTime.parse(dateString);
      } catch (e) {
        // Try dd/MM/yyyy format
        try {
          final parts = dateString.split('/');
          if (parts.length == 3) {
            dateTime = DateTime(
              int.parse(parts[2]), // year
              int.parse(parts[1]), // month
              int.parse(parts[0]), // day
            );
          }
        } catch (e) {
          // If all parsing fails, return original string
          return dateString;
        }
      }

      if (dateTime != null) {
        // Format as dd/MM/yyyy
        return DateFormat('dd/MM/yyyy').format(dateTime);
      }

      return dateString;
    } catch (e) {
      return dateString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final receiptNumber = receipt['receipt']?.toString() ?? 'N/A';
    final user = receipt['user']?.toString() ?? 'N/A';
    final dateString = receipt['date']?.toString();
    final formattedDate = _formatDate(dateString);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.receipt_long,
                  color: Colors.blue,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Receipt number
                    Text(
                      receiptNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // User info with label
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Người lưu: ',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            user,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Date info with label
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Ngày lưu: ',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          formattedDate,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Arrow
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
