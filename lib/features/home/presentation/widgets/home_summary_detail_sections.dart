part of 'home_summary_page.dart';

class _DetailTabPill extends StatelessWidget {
  const _DetailTabPill({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? AppColors.primaryOf(context)
        : AppColors.textSecondaryOf(context);
    return Material(
      color: selected
          ? AppColors.primaryOf(context).withValues(alpha: 0.10)
          : AppColors.chipBackgroundOf(context),
      borderRadius: AppRadius.allSm,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.allSm,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            count == null ? label : '$label (${_integerLabel(count!)})',
            style: AppTextStyles.labelS.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _SalesBehaviorDetailsTable extends StatelessWidget {
  const _SalesBehaviorDetailsTable({
    required this.notPurchasedPage,
    required this.unreportedPage,
    required this.isLoadingMore,
    required this.loadMoreError,
    required this.onLoadMore,
  });

  final HomeSummaryDetailsPage<HomeNotPurchasedReportDetail>? notPurchasedPage;
  final HomeSummaryDetailsPage<HomeUnreportedOrderDetail>? unreportedPage;
  final bool isLoadingMore;
  final String? loadMoreError;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final isNotPurchased = notPurchasedPage != null;
    final rowCount = isNotPurchased
        ? notPurchasedPage!.items.length
        : unreportedPage!.items.length;
    final total = isNotPurchased
        ? notPurchasedPage!.total
        : unreportedPage!.total;
    final hasNextPage = isNotPurchased
        ? notPurchasedPage!.hasNextPage
        : unreportedPage!.hasNextPage;
    if (rowCount == 0) {
      return const AppStatePanel.empty(
        title: 'Chưa có dòng chi tiết',
        message: 'Không có báo cáo phù hợp với phạm vi và ngày đang xem.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _detailCountLabel(rowCount, total),
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textMutedOf(context),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: AppTwoAxisScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: isNotPurchased ? 940 : 820),
              child: isNotPurchased
                  ? _NotPurchasedDetailsDataTable(rows: notPurchasedPage!.items)
                  : _UnreportedOrdersDetailsDataTable(
                      rows: unreportedPage!.items,
                    ),
            ),
          ),
        ),
        _DetailsLoadMoreFooter(
          hasNextPage: hasNextPage,
          isLoading: isLoadingMore,
          errorMessage: loadMoreError,
          onLoadMore: onLoadMore,
        ),
      ],
    );
  }
}

class _NotPurchasedDetailsDataTable extends StatelessWidget {
  const _NotPurchasedDetailsDataTable({required this.rows});

  final List<HomeNotPurchasedReportDetail> rows;

  @override
  Widget build(BuildContext context) {
    return DataTable(
      key: const Key('home-not-purchased-details-table'),
      headingTextStyle: AppTextStyles.labelS.copyWith(
        color: AppColors.textPrimaryOf(context),
        fontWeight: FontWeight.w800,
      ),
      dataTextStyle: AppTextStyles.bodyS.copyWith(
        color: AppColors.textPrimaryOf(context),
      ),
      columns: const [
        DataColumn(label: Text('Mã showroom')),
        DataColumn(label: Text('Tên nhân viên')),
        DataColumn(label: Text('Tên khách hàng')),
        DataColumn(label: Text('Loại khách hàng')),
        DataColumn(label: Text('Ngành hàng')),
        DataColumn(label: Text('Lý do không mua')),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            cells: [
              DataCell(Text(_valueOrEmpty(row.storeCode))),
              DataCell(Text(_valueOrEmpty(row.salesName))),
              DataCell(Text(_valueOrEmpty(row.customerName))),
              DataCell(Text(_valueOrEmpty(row.customerTypeLabel))),
              DataCell(Text(_valueOrEmpty(row.categoryName))),
              DataCell(Text(_valueOrEmpty(row.notPurchasedReasonLabel))),
            ],
          ),
      ],
    );
  }
}

class _UnreportedOrdersDetailsDataTable extends StatelessWidget {
  const _UnreportedOrdersDetailsDataTable({required this.rows});

  final List<HomeUnreportedOrderDetail> rows;

  @override
  Widget build(BuildContext context) {
    return DataTable(
      key: const Key('home-unreported-orders-details-table'),
      headingTextStyle: AppTextStyles.labelS.copyWith(
        color: AppColors.textPrimaryOf(context),
        fontWeight: FontWeight.w800,
      ),
      dataTextStyle: AppTextStyles.bodyS.copyWith(
        color: AppColors.textPrimaryOf(context),
      ),
      columns: const [
        DataColumn(label: Text('Mã showroom')),
        DataColumn(label: Text('Tên nhân viên')),
        DataColumn(label: Text('Mã đơn hàng')),
        DataColumn(label: Text('Giá trị đơn (đã bao gồm VAT)')),
        DataColumn(label: Text('Thời gian bán')),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            cells: [
              DataCell(Text(_valueOrEmpty(row.storeCode))),
              DataCell(Text(_valueOrEmpty(row.salesName))),
              DataCell(Text(row.orderCode)),
              DataCell(Text(_valueOrEmpty(formatVndAmount(row.grandTotal)))),
              DataCell(Text(_dateTimeLabel(row.soldAt))),
            ],
          ),
      ],
    );
  }
}

class _InstallmentNeedDetailsTable extends StatelessWidget {
  const _InstallmentNeedDetailsTable({
    required this.page,
    required this.isLoadingMore,
    required this.loadMoreError,
    required this.onLoadMore,
  });

  final HomeSummaryDetailsPage<HomeInstallmentNeedDetail> page;
  final bool isLoadingMore;
  final String? loadMoreError;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final rows = page.items;
    if (rows.isEmpty) {
      return const AppStatePanel.empty(
        title: 'Chưa có dòng chi tiết',
        message: 'Không có nhu cầu trả góp trong phạm vi và ngày đang xem.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _detailCountLabel(rows.length, page.total),
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textMutedOf(context),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: AppTwoAxisScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 820),
              child: _InstallmentNeedDetailsDataTable(rows: rows),
            ),
          ),
        ),
        _DetailsLoadMoreFooter(
          hasNextPage: page.hasNextPage,
          isLoading: isLoadingMore,
          errorMessage: loadMoreError,
          onLoadMore: onLoadMore,
        ),
      ],
    );
  }
}

class _DetailsLoadMoreFooter extends StatelessWidget {
  const _DetailsLoadMoreFooter({
    required this.hasNextPage,
    required this.isLoading,
    required this.errorMessage,
    required this.onLoadMore,
  });

  final bool hasNextPage;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (!hasNextPage && errorMessage == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (errorMessage != null) ...[
            Expanded(
              child: Text(
                errorMessage!,
                key: const Key('home-details-load-more-error'),
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.errorOf(context),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          AppSecondaryButton(
            key: const Key('home-details-load-more-button'),
            onPressed: isLoading ? null : onLoadMore,
            icon: PhosphorIconsRegular.caretDown,
            label: 'Xem thêm',
            isLoading: isLoading,
            loadingLabel: 'Đang tải thêm',
            expand: false,
            height: AppButtonMetrics.compactActionHeight,
          ),
        ],
      ),
    );
  }
}

class _InstallmentNeedDetailsDataTable extends StatelessWidget {
  const _InstallmentNeedDetailsDataTable({required this.rows});

  final List<HomeInstallmentNeedDetail> rows;

  @override
  Widget build(BuildContext context) {
    return DataTable(
      key: const Key('home-installment-need-details-table'),
      headingTextStyle: AppTextStyles.labelS.copyWith(
        color: AppColors.textPrimaryOf(context),
        fontWeight: FontWeight.w800,
      ),
      dataTextStyle: AppTextStyles.bodyS.copyWith(
        color: AppColors.textPrimaryOf(context),
      ),
      columns: const [
        DataColumn(label: Text('Mã showroom')),
        DataColumn(label: Text('Tên nhân viên')),
        DataColumn(label: Text('Đối tác trả góp')),
        DataColumn(label: Text('Thành công')),
        DataColumn(label: Text('Ghi chú')),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            cells: [
              DataCell(Text(_valueOrEmpty(row.storeCode))),
              DataCell(Text(_valueOrEmpty(row.salesName))),
              DataCell(
                Text(
                  row.installmentPartnerLabels.isEmpty
                      ? 'Chưa có thông tin'
                      : row.installmentPartnerLabels.join(', '),
                ),
              ),
              DataCell(
                row.successful
                    ? Icon(
                        PhosphorIconsRegular.checkCircle,
                        color: AppColors.successOf(context),
                        size: 18,
                      )
                    : Text(
                        'Không',
                        style: AppTextStyles.bodyS.copyWith(
                          color: AppColors.errorOf(context),
                        ),
                      ),
              ),
              DataCell(Text(_valueOrEmpty(row.note))),
            ],
          ),
      ],
    );
  }
}

String _detailCountLabel(int visible, int total) {
  if (visible >= total) return 'Hiển thị ${_integerLabel(visible)} dòng.';
  return 'Hiển thị ${_integerLabel(visible)}/${_integerLabel(total)} dòng gần nhất.';
}

String _dateTimeLabel(DateTime? value) {
  if (value == null) return 'Chưa có thông tin';
  return DateFormat('dd/MM/yyyy HH:mm').format(value.toLocal());
}

String _valueOrEmpty(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? 'Chưa có thông tin' : text;
}
