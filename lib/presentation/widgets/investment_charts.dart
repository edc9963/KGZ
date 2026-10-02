import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/app_store.dart';
import '../../application/providers.dart';
import '../../domain/financial_reports.dart';
import '../../domain/models.dart';
import '../design_tokens.dart';
import 'common.dart';

/// Taiwan market convention: red for gains, blue for losses. Shared by the
/// holdings list and the profit chart so both read the same way.
const investmentGainColor = Color(0xFFB84B3E);
const investmentLossColor = Color(0xFF1680A8);

/// Market value / cost basis / unrealised profit of one holding, in the
/// product's own currency. [value] is 0 while the product has no price.
typedef HoldingMetrics = ({
  bool isPriced,
  int value,
  int cost,
  int profit,
  double rate,
});

HoldingMetrics holdingMetrics(InvestmentProduct product, Holding holding) {
  final isPriced = product.currentPriceMinor > 0;
  final value = isPriced
      ? (holding.quantityMicros * product.currentPriceMinor / 1000000).round()
      : 0;
  final cost = (holding.quantityMicros * holding.averageCostMinor / 1000000)
      .round();
  final profit = value - cost;
  return (
    isPriced: isPriced,
    value: value,
    cost: cost,
    profit: profit,
    rate: cost == 0 ? 0 : profit / cost * 100,
  );
}

class _ProductPosition {
  const _ProductPosition({
    required this.product,
    required this.valueMinor,
    required this.profitMinor,
    required this.rate,
  });

  final InvestmentProduct product;

  /// Converted to the default currency so products can be compared.
  final int valueMinor;
  final int profitMinor;
  final double rate;

  String get shortLabel {
    if (product.symbol.isNotEmpty) return product.symbol;
    final chars = product.name.characters;
    return chars.length <= 4 ? product.name : '${chars.take(4)}…';
  }
}

List<_ProductPosition> _pricedPositions(AppStore store) {
  final result = <_ProductPosition>[];
  for (final product in store.data.products) {
    final holding = store.holdings[product.id];
    if (holding == null || holding.quantityMicros <= 0) continue;
    final metrics = holdingMetrics(product, holding);
    if (!metrics.isPriced) continue;
    final value = store.convertToDefault(metrics.value, product.currency);
    final profit = store.convertToDefault(metrics.profit, product.currency);
    if (value == null || profit == null) continue;
    result.add(
      _ProductPosition(
        product: product,
        valueMinor: value,
        profitMinor: profit,
        rate: metrics.rate,
      ),
    );
  }
  return result;
}

/// Allocation pie, per-product profit bars and the value-vs-cost trend shown
/// between the summary cards and the tabs on the investments page.
class InvestmentCharts extends ConsumerStatefulWidget {
  const InvestmentCharts({super.key});

  @override
  ConsumerState<InvestmentCharts> createState() => _InvestmentChartsState();
}

class _InvestmentChartsState extends ConsumerState<InvestmentCharts> {
  int _pieTouched = -1;
  int _trendMonths = 6;

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(appStoreProvider);
    final currency = store.data.settings.defaultCurrency;
    final mask = store.data.settings.maskBalances;
    final positions = _pricedPositions(store);
    if (positions.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Icon(Icons.insights_outlined, color: context.colors.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '尚無持股可分析，建立庫存並設定目前價格後會顯示圖表。',
                  key: const ValueKey('investment-charts-empty'),
                  style: TextStyle(color: context.colors.textMuted),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final trend = store.investmentTrend(months: _trendMonths);
    final allocation = _allocationCard(positions, currency, mask);
    final profit = _profitCard(positions, currency, mask);
    final trendCard = _trendCard(trend, currency, mask);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: allocation),
                  const SizedBox(width: 16),
                  Expanded(child: profit),
                ],
              ),
              const SizedBox(height: 16),
              trendCard,
            ],
          );
        }
        return Column(
          children: [
            allocation,
            const SizedBox(height: 16),
            profit,
            const SizedBox(height: 16),
            trendCard,
          ],
        );
      },
    );
  }

  Widget _title(String text) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
  );

  double get _chartHeight =>
      MediaQuery.sizeOf(context).width < AppBreakpoints.mobile ? 240 : 300;

  Widget _allocationCard(
    List<_ProductPosition> positions,
    String currency,
    bool mask,
  ) {
    // Same fixed palette as the reports page asset pie: slices carry white
    // labels, so the colors stay dark regardless of theme.
    const palette = [
      AppColors.primary,
      Color(0xFF568EAE),
      Color(0xFF6075A6),
      Color(0xFF719681),
      Color(0xFF7B8B91),
    ];
    const otherColor = Color(0xFF8C8F99);
    final sorted = positions.where((item) => item.valueMinor > 0).toList()
      ..sort((a, b) => b.valueMinor.compareTo(a.valueMinor));
    final slices = <ChartSlice>[
      for (final item in sorted.take(sorted.length > 6 ? 5 : 6))
        ChartSlice(item.product.name, item.valueMinor),
      if (sorted.length > 6)
        ChartSlice(
          '其他',
          sorted.skip(5).fold(0, (sum, item) => sum + item.valueMinor),
        ),
    ];
    Color colorAt(int i) => sorted.length > 6 && i == slices.length - 1
        ? otherColor
        : palette[i % palette.length];
    final total = slices.fold(0, (sum, item) => sum + item.amountMinor);
    final touched = _pieTouched < slices.length ? _pieTouched : -1;
    final chart = PieChart(
      PieChartData(
        centerSpaceRadius: 44,
        sectionsSpace: 2,
        pieTouchData: PieTouchData(
          touchCallback: (event, response) {
            final index = response?.touchedSection?.touchedSectionIndex ?? -1;
            final next = event.isInterestedForInteractions ? index : -1;
            if (next == _pieTouched) return;
            setState(() => _pieTouched = next);
          },
        ),
        sections: [
          for (var i = 0; i < slices.length; i++)
            PieChartSectionData(
              color: colorAt(i),
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
    Widget legendRow(int i) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: colorAt(i),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              slices[i].label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: touched == i ? FontWeight.w800 : null,
              ),
            ),
          ),
          Text(
            '${(slices[i].amountMinor / total * 100).toStringAsFixed(1)}%',
            style: TextStyle(color: context.colors.textMuted),
          ),
          const SizedBox(width: 10),
          Text(
            compactMoneyText(
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
      key: const ValueKey('investment-allocation-chart'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('持股配置'),
            const SizedBox(height: 16),
            if (total <= 0)
              SizedBox(
                height: 120,
                child: Center(
                  child: Text(
                    '持股市值為 0，無法繪製配置。',
                    style: TextStyle(color: context.colors.textMuted),
                  ),
                ),
              )
            else
              Semantics(
                label:
                    '持股配置：${slices.map((item) => '${item.label} ${moneyText(item.amountMinor, currency: currency, mask: mask)}').join('，')}',
                child: Column(
                  children: [
                    SizedBox(height: 210, child: chart),
                    const SizedBox(height: 10),
                    for (var i = 0; i < slices.length; i++) legendRow(i),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _profitCard(
    List<_ProductPosition> positions,
    String currency,
    bool mask,
  ) {
    final sorted = positions.toList()
      ..sort((a, b) => b.profitMinor.compareTo(a.profitMinor));
    final values = sorted.map((item) => item.profitMinor.toDouble());
    final rawMax = values.fold(0.0, (a, b) => a > b ? a : b);
    final rawMin = values.fold(0.0, (a, b) => a < b ? a : b);
    final spread = rawMax - rawMin;
    final padding = spread == 0 ? 100.0 : spread * .15;
    final totalProfit = sorted.fold(0, (sum, item) => sum + item.profitMinor);
    final barWidth = (220 / sorted.length).clamp(8, 28).toDouble();
    return Card(
      key: const ValueKey('investment-profit-chart'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _title('各商品損益')),
                Text(
                  '${totalProfit >= 0 ? '+' : ''}${compactMoneyText(totalProfit, currency: currency, mask: mask)}',
                  style: TextStyle(
                    color: totalProfit >= 0
                        ? investmentGainColor
                        : investmentLossColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '未實現損益（目前市值 − 持有成本）',
              style: TextStyle(color: context.colors.textMuted),
            ),
            const SizedBox(height: 18),
            Semantics(
              label:
                  '各商品損益：${sorted.map((item) => '${item.product.name} ${moneyText(item.profitMinor, currency: currency, mask: mask)}').join('，')}',
              child: SizedBox(
                height: _chartHeight,
                child: BarChart(
                  BarChartData(
                    minY: rawMin - (rawMin < 0 ? padding : 0),
                    maxY: rawMax + (rawMax > 0 ? padding : 0),
                    alignment: BarChartAlignment.spaceAround,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: value == 0
                            ? context.colors.textMuted
                            : context.colors.border,
                        strokeWidth: value == 0 ? 1.2 : .8,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    barTouchData: BarTouchData(
                      enabled: !mask,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          final item = sorted[group.x];
                          return BarTooltipItem(
                            '${item.product.name}\n'
                            '${item.profitMinor >= 0 ? '+' : ''}${moneyText(item.profitMinor, currency: currency)}'
                            ' (${item.rate.toStringAsFixed(2)}%)',
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          );
                        },
                      ),
                    ),
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
                          reservedSize: 30,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 || index >= sorted.length) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                sorted[index].shortLabel,
                                style: const TextStyle(fontSize: 10),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barGroups: [
                      for (var i = 0; i < sorted.length; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: sorted[i].profitMinor.toDouble(),
                              width: barWidth,
                              color: sorted[i].profitMinor >= 0
                                  ? investmentGainColor
                                  : investmentLossColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
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

  Widget _trendCard(
    List<InvestmentTrendPoint> points,
    String currency,
    bool mask,
  ) {
    final values = [
      for (final item in points) ...[
        item.valueMinor.toDouble(),
        item.costMinor.toDouble(),
      ],
    ];
    final rawMin = values.reduce((a, b) => a < b ? a : b);
    final rawMax = values.reduce((a, b) => a > b ? a : b);
    final spread = (rawMax - rawMin).abs();
    final padding = spread == 0 ? rawMax.abs() * .1 + 1 : spread * .15;
    final latest = points.last;
    final costColor = context.colors.textMuted;
    Widget legend(Color color, String label, {bool dashed = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 3,
          decoration: BoxDecoration(
            color: dashed ? null : color,
            border: dashed
                ? Border(
                    top: BorderSide(color: color, width: 2),
                    bottom: BorderSide.none,
                  )
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: context.colors.textMuted)),
      ],
    );
    return Card(
      key: const ValueKey('investment-trend-chart'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                _title('投資總值與成本'),
                SegmentedButton<int>(
                  key: const ValueKey('investment-trend-range'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 6, label: Text('6 個月')),
                    ButtonSegment(value: 12, label: Text('12 個月')),
                  ],
                  selected: {_trendMonths},
                  onSelectionChanged: (value) =>
                      setState(() => _trendMonths = value.first),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                legend(
                  context.colors.asset,
                  '市值 ${compactMoneyText(latest.valueMinor, currency: currency, mask: mask)}',
                ),
                legend(
                  costColor,
                  '成本 ${compactMoneyText(latest.costMinor, currency: currency, mask: mask)}',
                  dashed: true,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Semantics(
              label:
                  '近 $_trendMonths 個月投資市值與成本：${points.map((item) => '${item.month.month} 月 市值 ${moneyText(item.valueMinor, currency: currency, mask: mask)} 成本 ${moneyText(item.costMinor, currency: currency, mask: mask)}').join('，')}',
              child: SizedBox(
                height: _chartHeight,
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
                    lineTouchData: LineTouchData(
                      enabled: !mask,
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (spots) => [
                          for (final spot in spots)
                            LineTooltipItem(
                              '${spot.barIndex == 0 ? '市值' : '成本'} '
                              '${compactMoneyText(spot.y.round(), currency: currency)}',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
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
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 ||
                                index >= points.length ||
                                value != index.toDouble()) {
                              return const SizedBox.shrink();
                            }
                            // 12 months is crowded on phones: label every
                            // other month.
                            if (points.length > 6 &&
                                MediaQuery.sizeOf(context).width <
                                    AppBreakpoints.mobile &&
                                (points.length - 1 - index).isOdd) {
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
                              points[i].valueMinor.toDouble(),
                            ),
                        ],
                        color: context.colors.asset,
                        barWidth: 3,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                          show: true,
                          color: context.colors.assetPale.withValues(alpha: .7),
                        ),
                      ),
                      LineChartBarData(
                        spots: [
                          for (var i = 0; i < points.length; i++)
                            FlSpot(
                              i.toDouble(),
                              points[i].costMinor.toDouble(),
                            ),
                        ],
                        color: costColor,
                        barWidth: 2,
                        dashArray: const [6, 4],
                        dotData: const FlDotData(show: false),
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
}
