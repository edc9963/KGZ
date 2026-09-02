import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers.dart';
import '../../domain/financial_reports.dart';
import '../design_tokens.dart';
import '../widgets/common.dart';

enum _ReportTab { summary, balance, profitLoss, cashFlow }

enum _PeriodPreset {
  currentMonth,
  recentSixMonths,
  previousMonth,
  currentYear,
  previousYear,
  custom,
}

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  _ReportTab _tab = _ReportTab.summary;
  _PeriodPreset _preset = _PeriodPreset.currentMonth;
  int _assetTouched = -1;
  int _expenseTouched = -1;
  late DateTime _customStart;
  late DateTime _customEnd;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _customStart = DateTime(now.year, now.month, 1);
    _customEnd = now;
  }

  ReportPeriod get _period {
    final now = DateTime.now();
    return switch (_preset) {
      _PeriodPreset.currentMonth => ReportPeriod(
        start: DateTime(now.year, now.month, 1),
        end: now,
      ),
      _PeriodPreset.recentSixMonths => ReportPeriod(
        start: DateTime(now.year, now.month - 5, 1),
        end: now,
      ),
      _PeriodPreset.previousMonth => ReportPeriod(
        start: DateTime(now.year, now.month - 1, 1),
        end: DateTime(now.year, now.month, 1).subtract(const Duration(days: 1)),
      ),
      _PeriodPreset.currentYear => ReportPeriod(
        start: DateTime(now.year, 1, 1),
        end: now,
      ),
      _PeriodPreset.previousYear => ReportPeriod(
        start: DateTime(now.year - 1, 1, 1),
        end: DateTime(now.year - 1, 12, 31),
      ),
      _PeriodPreset.custom => ReportPeriod(
        start: _customStart,
        end: _customEnd,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(appStoreProvider);
    final service = FinancialReportService(store.data);
    final snapshot = service.build(_period);
    final netWorthTrend = service.netWorthTrend(_period.end);
    final currency = store.data.settings.defaultCurrency;
    final mask = store.data.settings.maskBalances;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: '財務報表',
          subtitle: '管理用報表・不等同 IFRS／GAAP 法定財報',
          action: IconButton.filledTonal(
            tooltip: mask ? '顯示金額' : '隱藏金額',
            onPressed: () => store.updateSettings(
              store.data.settings.copyWith(maskBalances: !mask),
            ),
            icon: Icon(
              mask ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            ),
          ),
        ),
        const SizedBox(height: 20),
        _periodControls(),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) => SegmentedButton<_ReportTab>(
            segments: const [
              ButtonSegment(value: _ReportTab.summary, label: Text('總覽')),
              ButtonSegment(value: _ReportTab.balance, label: Text('資產負債')),
              ButtonSegment(value: _ReportTab.profitLoss, label: Text('收支損益')),
              ButtonSegment(value: _ReportTab.cashFlow, label: Text('現金流')),
            ],
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: constraints.maxWidth < AppBreakpoints.mobile
                  ? VisualDensity.compact
                  : null,
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(
                  horizontal: constraints.maxWidth < AppBreakpoints.mobile
                      ? 6
                      : 12,
                ),
              ),
            ),
            selected: {_tab},
            onSelectionChanged: (value) => setState(() => _tab = value.first),
          ),
        ),
        if (snapshot.issues.isNotEmpty) ...[
          const SizedBox(height: 16),
          _issues(snapshot),
        ],
        const SizedBox(height: 20),
        switch (_tab) {
          _ReportTab.summary => _summary(
            snapshot,
            netWorthTrend,
            currency,
            mask,
          ),
          _ReportTab.balance => _balanceSheet(snapshot, currency, mask),
          _ReportTab.profitLoss => _profitLoss(snapshot, currency, mask),
          _ReportTab.cashFlow => _cashFlow(snapshot, currency, mask),
        },
      ],
    );
  }

  Widget _periodControls() => LayoutBuilder(
    builder: (context, constraints) {
      final mobile = constraints.maxWidth < AppBreakpoints.mobile;
      final periodMenu = DropdownMenu<_PeriodPreset>(
        width: mobile ? constraints.maxWidth : null,
        initialSelection: _preset,
        label: const Text('報表期間'),
        dropdownMenuEntries: const [
          DropdownMenuEntry(value: _PeriodPreset.currentMonth, label: '本月'),
          DropdownMenuEntry(
            value: _PeriodPreset.recentSixMonths,
            label: '近 6 個月',
          ),
          DropdownMenuEntry(value: _PeriodPreset.previousMonth, label: '上月'),
          DropdownMenuEntry(value: _PeriodPreset.currentYear, label: '今年'),
          DropdownMenuEntry(value: _PeriodPreset.previousYear, label: '去年'),
          DropdownMenuEntry(value: _PeriodPreset.custom, label: '自訂期間'),
        ],
        onSelected: (value) {
          if (value != null) setState(() => _preset = value);
        },
      );
      final startButton = OutlinedButton.icon(
        onPressed: () => _pickDate(start: true),
        icon: const Icon(Icons.calendar_today_outlined),
        label: Text('起 ${dateText(_customStart)}'),
      );
      final endButton = OutlinedButton.icon(
        onPressed: () => _pickDate(start: false),
        icon: const Icon(Icons.event_outlined),
        label: Text('迄 ${dateText(_customEnd)}'),
      );
      final cutoff = Text(
        '資產負債截止 ${dateText(_period.end)}',
        style: const TextStyle(color: Colors.black54),
      );
      if (!mobile) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            periodMenu,
            if (_preset == _PeriodPreset.custom) startButton,
            if (_preset == _PeriodPreset.custom) endButton,
            cutoff,
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          periodMenu,
          if (_preset == _PeriodPreset.custom) ...[
            const SizedBox(height: 10),
            if (constraints.maxWidth >= 300)
              Row(
                children: [
                  Expanded(child: startButton),
                  const SizedBox(width: 10),
                  Expanded(child: endButton),
                ],
              )
            else ...[
              startButton,
              const SizedBox(height: 10),
              endButton,
            ],
          ],
          const SizedBox(height: 8),
          cutoff,
        ],
      );
    },
  );

  Future<void> _pickDate({required bool start}) async {
    final initial = start ? _customStart : _customEnd;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _customStart = picked;
        if (_customEnd.isBefore(picked)) _customEnd = picked;
      } else {
        _customEnd = picked;
        if (_customStart.isAfter(picked)) _customStart = picked;
      }
    });
  }

  Widget _issues(FinancialReportSnapshot snapshot) => Card(
    color: const Color(0xFFFFF8E8),
    child: ExpansionTile(
      leading: const Icon(Icons.info_outline, color: Color(0xFF9A6A00)),
      title: Text('有 ${snapshot.issues.length} 項估值或資料品質提示'),
      children: [
        for (final issue in snapshot.issues)
          ListTile(
            dense: true,
            leading: const Icon(Icons.circle, size: 8),
            title: Text(issue.message),
          ),
      ],
    ),
  );

  Widget _summary(
    FinancialReportSnapshot data,
    List<NetWorthTrendPoint> netWorthTrend,
    String currency,
    bool mask,
  ) => Column(
    children: [
      ResponsiveGrid(
        children: [
          SummaryCard(
            label: '淨資產',
            value: moneyText(data.netWorth, currency: currency, mask: mask),
            compactValue: compactMoneyText(
              data.netWorth,
              currency: currency,
              mask: mask,
            ),
            icon: Icons.account_balance_wallet_outlined,
            tone: AppColors.asset,
          ),
          SummaryCard(
            label: '本期收入',
            value: moneyText(data.totalIncome, currency: currency, mask: mask),
            compactValue: compactMoneyText(
              data.totalIncome,
              currency: currency,
              mask: mask,
            ),
            icon: Icons.south_west_rounded,
            tone: AppColors.income,
          ),
          SummaryCard(
            label: '本期支出',
            value: moneyText(
              data.totalExpenses,
              currency: currency,
              mask: mask,
            ),
            compactValue: compactMoneyText(
              data.totalExpenses,
              currency: currency,
              mask: mask,
            ),
            icon: Icons.north_east_rounded,
            tone: AppColors.expense,
          ),
          SummaryCard(
            label: '本期餘絀',
            value: moneyText(data.netIncome, currency: currency, mask: mask),
            compactValue: compactMoneyText(
              data.netIncome,
              currency: currency,
              mask: mask,
            ),
            icon: Icons.balance_outlined,
            tone: data.netIncome >= 0 ? AppColors.asset : AppColors.expense,
          ),
        ],
      ),
      const SizedBox(height: 18),
      LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final charts = <Widget>[
            _netWorthCard(netWorthTrend, currency, mask),
            _barCard(
              data.monthlyTrend.length <= 6
                  ? data.monthlyTrend
                  : data.monthlyTrend.sublist(data.monthlyTrend.length - 6),
              currency,
              mask,
            ),
          ];
          return wide
              ? Row(
                  children: [
                    Expanded(child: charts[0]),
                    const SizedBox(width: 16),
                    Expanded(child: charts[1]),
                  ],
                )
              : Column(
                  children: [charts[0], const SizedBox(height: 16), charts[1]],
                );
        },
      ),
      const SizedBox(height: 18),
      LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final charts = <Widget>[
            _pieCard(
              '期間支出分類',
              data.expenseAllocation,
              currency,
              mask,
              asset: false,
            ),
            _cashFlowCard(data, currency, mask),
          ];
          return wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: charts[0]),
                    const SizedBox(width: 16),
                    Expanded(child: charts[1]),
                  ],
                )
              : Column(
                  children: [charts[0], const SizedBox(height: 16), charts[1]],
                );
        },
      ),
    ],
  );

  Widget _netWorthCard(
    List<NetWorthTrendPoint> points,
    String currency,
    bool mask,
  ) {
    final values = points.map((item) => item.amountMinor.toDouble()).toList();
    final rawMin = values.isEmpty
        ? 0.0
        : values.reduce((a, b) => a < b ? a : b);
    final rawMax = values.isEmpty
        ? 1.0
        : values.reduce((a, b) => a > b ? a : b);
    final spread = (rawMax - rawMin).abs();
    final padding = spread == 0 ? rawMax.abs() * .1 + 1 : spread * .15;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final title = Text(
                  '淨資產趨勢',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                );
                final latest = points.isEmpty
                    ? null
                    : Text(
                        constraints.maxWidth < AppBreakpoints.mobile
                            ? compactMoneyText(
                                points.last.amountMinor,
                                currency: currency,
                                mask: mask,
                              )
                            : moneyText(
                                points.last.amountMinor,
                                currency: currency,
                                mask: mask,
                              ),
                        style: const TextStyle(
                          color: AppColors.asset,
                          fontWeight: FontWeight.w800,
                        ),
                      );
                if (constraints.maxWidth < AppBreakpoints.mobile) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      if (latest != null) ...[
                        const SizedBox(height: 4),
                        latest,
                      ],
                    ],
                  );
                }
                return Row(
                  children: [title, const Spacer(), if (latest != null) latest],
                );
              },
            ),
            const SizedBox(height: 6),
            const Row(
              children: [
                Icon(Icons.circle, color: AppColors.asset, size: 10),
                SizedBox(width: 6),
                Text('資產扣除負債', style: TextStyle(color: AppColors.textMuted)),
              ],
            ),
            const SizedBox(height: 18),
            Semantics(
              label:
                  '近 6 個月淨資產：${points.map((item) => '${item.month.month} 月 ${moneyText(item.amountMinor, currency: currency, mask: mask)}').join('，')}',
              child: SizedBox(
                height: MediaQuery.sizeOf(context).width < AppBreakpoints.mobile
                    ? 240
                    : 300,
                child: LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: (points.length - 1).clamp(1, 100).toDouble(),
                    minY: rawMin - padding,
                    maxY: rawMax + padding,
                    gridData: const FlGridData(
                      show: true,
                      drawVerticalLine: false,
                    ),
                    borderData: FlBorderData(show: false),
                    lineTouchData: LineTouchData(enabled: !mask),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: !mask,
                          reservedSize: 54,
                          getTitlesWidget: (value, meta) => Text(
                            NumberFormat.compact(
                              locale: 'zh_TW',
                            ).format(value / 100),
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 || index >= points.length) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '${points[index].month.month}月',
                                style: const TextStyle(fontSize: 11),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: [
                          for (var i = 0; i < points.length; i++)
                            FlSpot(
                              i.toDouble(),
                              points[i].amountMinor.toDouble(),
                            ),
                        ],
                        color: AppColors.asset,
                        barWidth: 3,
                        isCurved: false,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                          show: true,
                          color: AppColors.assetPale.withValues(alpha: .7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cashFlowCard(
    FinancialReportSnapshot data,
    String currency,
    bool mask,
  ) {
    int total(List<StatementLine> lines) =>
        lines.fold(0, (sum, line) => sum + line.amountMinor);
    final rows = <(String, int, Color)>[
      ('營業活動', total(data.operatingCashFlow), AppColors.income),
      ('投資活動', total(data.investingCashFlow), const Color(0xFF6075A6)),
      ('融資活動', total(data.financingCashFlow), AppColors.liability),
      (
        '其他活動',
        total(data.otherCashFlow) + data.fxEffect,
        const Color(0xFF7B8B91),
      ),
    ];
    final maxAmount = rows.fold<int>(
      1,
      (value, row) => row.$2.abs() > value ? row.$2.abs() : value,
    );
    final mobile = MediaQuery.sizeOf(context).width < AppBreakpoints.mobile;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '現金流摘要',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 22),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Row(
                  children: [
                    SizedBox(width: mobile ? 64 : 74, child: Text(row.$1)),
                    SizedBox(width: mobile ? 8 : 10),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            height: 12,
                            width:
                                constraints.maxWidth * row.$2.abs() / maxAmount,
                            decoration: BoxDecoration(
                              color: row.$3,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: mobile ? 8 : 12),
                    SizedBox(
                      width: mobile ? 82 : 112,
                      child: Text(
                        mask
                            ? '$currency ••••••'
                            : '${row.$2 >= 0 ? '+' : '-'}${mobile ? compactMoneyText(row.$2.abs(), currency: currency) : moneyText(row.$2.abs(), currency: currency)}',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: row.$2 >= 0
                              ? AppColors.income
                              : AppColors.expense,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                '本期現金變動',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              trailing: Text(
                moneyText(data.cashChange, currency: currency, mask: mask),
                style: TextStyle(
                  color: data.cashChange >= 0
                      ? AppColors.asset
                      : AppColors.expense,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pieCard(
    String title,
    List<ChartSlice> slices,
    String currency,
    bool mask, {
    required bool asset,
  }) {
    const assetColors = [
      AppColors.asset,
      Color(0xFF568EAE),
      Color(0xFF6075A6),
      Color(0xFF719681),
      Color(0xFF7B8B91),
    ];
    Color sliceColor(int index) => asset
        ? assetColors[index % assetColors.length]
        : categoryVisual(slices[index].label).color;
    final total = slices.fold(0, (sum, item) => sum + item.amountMinor);
    final touched = asset ? _assetTouched : _expenseTouched;
    Widget chart() => PieChart(
      PieChartData(
        centerSpaceRadius: 44,
        sectionsSpace: 2,
        pieTouchData: PieTouchData(
          touchCallback: (event, response) {
            final next = event.isInterestedForInteractions
                ? response?.touchedSection?.touchedSectionIndex ?? -1
                : -1;
            if (next == touched) return;
            setState(() {
              if (asset) {
                _assetTouched = next;
              } else {
                _expenseTouched = next;
              }
            });
          },
        ),
        sections: [
          for (var i = 0; i < slices.length; i++)
            PieChartSectionData(
              color: sliceColor(i),
              value: slices[i].amountMinor.toDouble(),
              radius: touched == i ? 80 : 72,
              title: '${(slices[i].amountMinor / total * 100).round()}%',
              titleStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
    Widget legendRow(int i, {required bool compact}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: sliceColor(i),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(slices[i].label, overflow: TextOverflow.ellipsis),
          ),
          Text(
            compact
                ? compactMoneyText(
                    slices[i].amountMinor,
                    currency: currency,
                    mask: mask,
                  )
                : moneyText(
                    slices[i].amountMinor,
                    currency: currency,
                    mask: mask,
                  ),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            if (total <= 0)
              const SizedBox(
                height: 260,
                child: EmptyState(
                  icon: Icons.pie_chart_outline,
                  title: '尚無可繪製資料',
                  message: '新增收支或資產後將顯示圖表。',
                ),
              )
            else
              Semantics(
                label:
                    '$title：${slices.map((item) => '${item.label} ${moneyText(item.amountMinor, currency: currency, mask: mask)}').join('，')}',
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final mobile = constraints.maxWidth < AppBreakpoints.mobile;
                    if (mobile) {
                      return Column(
                        children: [
                          SizedBox(height: 210, child: chart()),
                          const SizedBox(height: 10),
                          for (var i = 0; i < slices.length; i++)
                            legendRow(i, compact: true),
                        ],
                      );
                    }
                    return SizedBox(
                      height: 260,
                      child: Row(
                        children: [
                          Expanded(child: chart()),
                          const SizedBox(width: 14),
                          Expanded(
                            child: ListView.builder(
                              itemCount: slices.length,
                              itemBuilder: (context, i) =>
                                  legendRow(i, compact: false),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            if (touched >= 0 && touched < slices.length) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${slices[touched].label}：${moneyText(slices[touched].amountMinor, currency: currency, mask: mask)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _barCard(List<MonthlyReportPoint> points, String currency, bool mask) {
    final maxValue = points.fold<int>(
      0,
      (value, item) => [
        value,
        item.incomeMinor,
        item.expenseMinor,
      ].reduce((a, b) => a > b ? a : b),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '近 6 個月收入／支出',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Row(
              children: [
                Icon(Icons.square, color: AppColors.income, size: 14),
                Text(' 收入   '),
                Icon(Icons.square, color: AppColors.expense, size: 14),
                Text(' 支出'),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: MediaQuery.sizeOf(context).width < AppBreakpoints.mobile
                  ? 240
                  : 300,
              child: BarChart(
                BarChartData(
                  maxY: maxValue <= 0 ? 1 : maxValue * 1.2,
                  gridData: const FlGridData(
                    show: true,
                    drawVerticalLine: false,
                  ),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(enabled: !mask),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: !mask,
                        reservedSize: 52,
                        getTitlesWidget: (value, meta) => Text(
                          NumberFormat.compact(
                            locale: 'zh_TW',
                          ).format(value / 100),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 ||
                              index >= points.length ||
                              index.isOdd) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '${points[index].month.month}月',
                              style: const TextStyle(fontSize: 11),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < points.length; i++)
                      BarChartGroupData(
                        x: i,
                        barsSpace: 3,
                        barRods: [
                          BarChartRodData(
                            toY: points[i].incomeMinor.toDouble(),
                            color: AppColors.income,
                            width: 9,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                          BarChartRodData(
                            toY: points[i].expenseMinor.toDouble(),
                            color: AppColors.expense,
                            width: 9,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _balanceSheet(
    FinancialReportSnapshot data,
    String currency,
    bool mask,
  ) => Column(
    children: [
      _statementCard('資產', data.assets, data.totalAssets, currency, mask),
      const SizedBox(height: 16),
      _statementCard(
        '負債',
        data.liabilities,
        data.totalLiabilities,
        currency,
        mask,
      ),
      const SizedBox(height: 16),
      _totalCard(
        '淨資產',
        data.netWorth,
        currency,
        mask,
        data.balanceSheetBalances,
      ),
    ],
  );

  Widget _profitLoss(
    FinancialReportSnapshot data,
    String currency,
    bool mask,
  ) => Column(
    children: [
      _statementCard('收入', data.income, data.totalIncome, currency, mask),
      const SizedBox(height: 16),
      _statementCard('支出', data.expenses, data.totalExpenses, currency, mask),
      const SizedBox(height: 16),
      _totalCard('本期餘絀', data.netIncome, currency, mask, true),
    ],
  );

  Widget _cashFlow(FinancialReportSnapshot data, String currency, bool mask) =>
      Column(
        children: [
          _statementCard(
            '營業活動',
            data.operatingCashFlow,
            _sum(data.operatingCashFlow),
            currency,
            mask,
            signed: true,
          ),
          const SizedBox(height: 16),
          _statementCard(
            '投資活動',
            data.investingCashFlow,
            _sum(data.investingCashFlow),
            currency,
            mask,
            signed: true,
          ),
          const SizedBox(height: 16),
          _statementCard(
            '籌資活動',
            data.financingCashFlow,
            _sum(data.financingCashFlow),
            currency,
            mask,
            signed: true,
          ),
          const SizedBox(height: 16),
          _statementCard(
            '其他調整',
            [
              ...data.otherCashFlow,
              if (data.fxEffect != 0)
                StatementLine(label: '匯率換算影響', amountMinor: data.fxEffect),
            ],
            _sum(data.otherCashFlow) + data.fxEffect,
            currency,
            mask,
            signed: true,
          ),
          const SizedBox(height: 16),
          _totalCard(
            '現金淨變動',
            data.cashChange,
            currency,
            mask,
            data.cashFlowBalances,
          ),
        ],
      );

  int _sum(List<StatementLine> lines) =>
      lines.fold(0, (sum, line) => sum + line.amountMinor);

  Widget _statementCard(
    String title,
    List<StatementLine> lines,
    int total,
    String currency,
    bool mask, {
    bool signed = false,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (lines.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('本期間無資料', style: TextStyle(color: Colors.black54)),
            )
          else
            for (final line in lines)
              _statementLine(line, currency, mask, signed: signed),
          const Divider(height: 26),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$title合計',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                moneyText(total, currency: currency, mask: mask),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _statementLine(
    StatementLine line,
    String currency,
    bool mask, {
    required bool signed,
  }) {
    final value = signed && line.amountMinor > 0
        ? '+${moneyText(line.amountMinor, currency: currency, mask: mask)}'
        : moneyText(line.amountMinor, currency: currency, mask: mask);
    if (line.children.isEmpty) {
      return ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        minVerticalPadding: 4,
        contentPadding: EdgeInsets.zero,
        title: Text(
          '${line.label}${line.estimated ? ' ・ 推估' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
    }
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 18),
      title: Text(
        '${line.label}${line.estimated ? ' ・ 推估' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      children: [
        for (final child in line.children)
          _statementLine(child, currency, mask, signed: signed),
      ],
    );
  }

  Widget _totalCard(
    String label,
    int value,
    String currency,
    bool mask,
    bool balanced,
  ) => Card(
    color: balanced
        ? const Color(0xFFEAF7F3)
        : Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(
            balanced ? Icons.check_circle_outline : Icons.error_outline,
            color: balanced
                ? const Color(0xFF0E7C66)
                : Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                moneyText(value, currency: currency, mask: mask),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
