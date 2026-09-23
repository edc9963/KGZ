import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../application/app_store.dart';
import '../design_tokens.dart';

String moneyText(int minor, {String currency = 'TWD', bool mask = false}) {
  if (mask) return '$currency ••••••';
  final digits = currency == 'TWD' || currency == 'JPY' ? 0 : 2;
  return NumberFormat.currency(
    locale: 'zh_TW',
    symbol: currency == 'TWD' ? r'NT$' : currency,
    decimalDigits: digits,
  ).format(minor / 100);
}

String compactMoneyText(
  int minor, {
  String currency = 'TWD',
  bool mask = false,
}) {
  if (mask) return '$currency ••••••';
  final major = minor / 100;
  if (major.abs() < 10000) {
    return moneyText(minor, currency: currency);
  }
  final divisor = major.abs() >= 100000000 ? 100000000 : 10000;
  final unit = divisor == 100000000 ? '億' : '萬';
  final scaled = major.abs() / divisor;
  final truncated = (scaled * 10).floor() / 10;
  final amount = NumberFormat('0.#', 'zh_TW').format(truncated);
  final sign = minor < 0 ? '-' : '';
  final symbol = currency == 'TWD' ? r'NT$' : currency;
  return '$sign$symbol$amount$unit';
}

String dateText(DateTime date) => DateFormat('yyyy/MM/dd').format(date);

int parseMoney(String text) =>
    ((double.tryParse(text.replaceAll(',', '')) ?? 0) * 100).round();

double parseQuantity(String text) =>
    double.tryParse(text.replaceAll(',', '')) ?? 0;

class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.title,
    required this.subtitle,
    this.action,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: context.colors.textMuted),
          ),
        ],
      );
      if (constraints.maxWidth < AppBreakpoints.mobile && action != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading,
            const SizedBox(height: 14),
            Align(alignment: Alignment.centerLeft, child: action!),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: heading),
          if (action != null) ...[
            const SizedBox(width: 16),
            Flexible(child: action!),
          ],
        ],
      );
    },
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    this.compactValue,
    this.tone,
    this.caption,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final String? compactValue;
  final IconData icon;
  final Color? tone;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 200;
        final valueStyle =
            (compact
                    ? Theme.of(context).textTheme.titleLarge
                    : Theme.of(context).textTheme.headlineSmall)
                ?.copyWith(fontWeight: FontWeight.w800, color: color);
        final valuePainter = TextPainter(
          text: TextSpan(text: value, style: valueStyle),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final valueWidth = constraints.maxWidth - (compact ? 28 : 40);
        const minimumFullValueScale = .64;
        final useCompactValue =
            compact &&
            compactValue != null &&
            valuePainter.width * minimumFullValueScale > valueWidth;
        final shownValue = useCompactValue ? compactValue! : value;
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(color: color, child: const SizedBox(height: 3)),
            Padding(
              padding: EdgeInsets.all(compact ? 14 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(compact ? 6 : 8),
                          child: Icon(
                            icon,
                            color: color,
                            size: compact ? 18 : 20,
                          ),
                        ),
                      ),
                      SizedBox(width: compact ? 8 : 12),
                      Expanded(
                        child: Text(
                          label,
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: context.colors.textMuted),
                        ),
                      ),
                      if (onTap != null) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right,
                          size: compact ? 16 : 18,
                          color: context.colors.textMuted,
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: compact ? 12 : 18),
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(shownValue, maxLines: 1, style: valueStyle),
                    ),
                  ),
                  if (caption != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      caption!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.colors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
        return Semantics(
          button: onTap != null,
          label:
              '${onTap == null ? '' : '查看'}$label，$value${caption == null ? '' : '，$caption'}',
          excludeSemantics: true,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: onTap == null
                ? content
                : InkWell(onTap: onTap, child: content),
          ),
        );
      },
    );
  }
}

class CategoryBadge extends StatelessWidget {
  const CategoryBadge({required this.category, super.key});

  final String category;

  @override
  Widget build(BuildContext context) {
    final visual = categoryVisual(category, context.colors);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: visual.pale,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        category,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: visual.color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({required this.category, super.key});

  final String category;

  @override
  Widget build(BuildContext context) {
    final visual = categoryVisual(category, context.colors);
    return CircleAvatar(
      backgroundColor: visual.pale,
      foregroundColor: visual.color,
      child: Icon(visual.icon),
    );
  }
}

/// Curated color-palette picker for a bookkeeping category: a row of
/// tappable swatches (one per [categoryColorOptions] entry) plus a trailing
/// swatch that opens [_CustomColorDialog] for picking any RGB color via a
/// saturation/value field, a hue slider and a hex code field. The result is
/// always reported back through [onChanged] as a category `colorKey` value —
/// either a preset key (e.g. `'teal'`) or a `#RRGGBB` hex string for a custom
/// pick — see [resolveCategoryColorKey] for how that key is turned back into
/// a [Color] everywhere else in the app (including the reports pie chart).
class CategoryColorPicker extends StatelessWidget {
  const CategoryColorPicker({required this.value, required this.onChanged, super.key});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final customColor = categoryColorOptions.containsKey(value)
        ? null
        : parseHexColor(value);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final entry in categoryColorOptions.entries)
          _ColorSwatch(
            color: entry.value,
            selected: value == entry.key,
            onTap: () => onChanged(entry.key),
          ),
        _ColorSwatch(
          color: customColor,
          selected: customColor != null,
          isCustom: true,
          onTap: () async {
            final picked = await showDialog<Color>(
              context: context,
              builder: (_) => _CustomColorDialog(
                initial: customColor ?? categoryColorOptions.values.first,
              ),
            );
            if (picked != null) onChanged(colorToHex(picked));
          },
        ),
      ],
    );
  }
}

Color _iconColorFor(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
    ? Colors.white
    : Colors.black87;

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.onTap,
    this.color,
    this.selected = false,
    this.isCustom = false,
  });

  final Color? color;
  final bool selected;
  final bool isCustom;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    customBorder: const CircleBorder(),
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        gradient: color == null
            ? const SweepGradient(
                colors: [
                  Color(0xFFE4765B),
                  Color(0xFFB8893E),
                  Color(0xFF719681),
                  Color(0xFF2A9D8F),
                  Color(0xFF568EAE),
                  Color(0xFF9277A6),
                  Color(0xFFBC7182),
                  Color(0xFFE4765B),
                ],
              )
            : null,
        border: Border.all(
          color: selected ? context.colors.text : context.colors.border,
          width: selected ? 2.5 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: color == null
          ? const Icon(Icons.colorize, size: 16, color: Colors.white)
          : selected
          ? Icon(Icons.check, size: 16, color: _iconColorFor(color!))
          : null,
    ),
  );
}

/// Full RGB custom-color picker shown from [CategoryColorPicker]'s trailing
/// swatch: a saturation/value field, a hue slider, and a hex code field, all
/// kept in sync with an internal [HSVColor]. Pops the chosen [Color] on
/// confirm, or null on cancel.
class _CustomColorDialog extends StatefulWidget {
  const _CustomColorDialog({required this.initial});

  final Color initial;

  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  late HSVColor _hsv;
  late final TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hexController = TextEditingController(
      text: colorToHex(widget.initial).substring(1),
    );
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Color get _color => _hsv.toColor();

  void _updateFromHsv(HSVColor next) {
    setState(() {
      _hsv = next;
      _hexController.text = colorToHex(next.toColor()).substring(1);
    });
  }

  void _updateFromHex(String text) {
    final parsed = parseHexColor(text);
    if (parsed == null) return;
    setState(() => _hsv = HSVColor.fromColor(parsed));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('自訂顏色'),
    content: SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SaturationValueField(
            hue: _hsv.hue,
            saturation: _hsv.saturation,
            value: _hsv.value,
            onChanged: (s, v) =>
                _updateFromHsv(_hsv.withSaturation(s).withValue(v)),
          ),
          const SizedBox(height: 16),
          _HueSlider(
            hue: _hsv.hue,
            onChanged: (h) => _updateFromHsv(_hsv.withHue(h)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _color,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.colors.border),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _hexController,
                  maxLength: 6,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: '色碼',
                    prefixText: '#',
                    counterText: '',
                  ),
                  onChanged: _updateFromHex,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _color),
        child: const Text('選擇'),
      ),
    ],
  );
}

/// Drag-to-pick saturation/value square for a fixed [hue]: horizontal axis
/// is saturation (white → fully-saturated hue), vertical axis is value
/// (that hue → black).
class _SaturationValueField extends StatelessWidget {
  const _SaturationValueField({
    required this.hue,
    required this.saturation,
    required this.value,
    required this.onChanged,
  });

  final double hue;
  final double saturation;
  final double value;
  final void Function(double saturation, double value) onChanged;

  @override
  Widget build(BuildContext context) {
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    return LayoutBuilder(
      builder: (context, constraints) {
        void handle(Offset local) {
          final width = constraints.maxWidth;
          const height = 160.0;
          final s = (local.dx / width).clamp(0.0, 1.0);
          final v = 1 - (local.dy / height).clamp(0.0, 1.0);
          onChanged(s, v);
        }

        return GestureDetector(
          onPanDown: (details) => handle(details.localPosition),
          onPanUpdate: (details) => handle(details.localPosition),
          child: SizedBox(
            height: 160,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.white, hueColor],
                      ),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black],
                      ),
                    ),
                  ),
                  Positioned(
                    left: saturation * constraints.maxWidth - 8,
                    top: (1 - value) * 160 - 8,
                    child: IgnorePointer(
                      child: _Thumb(
                        color: HSVColor.fromAHSV(
                          1,
                          hue,
                          saturation,
                          value,
                        ).toColor(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Drag-to-pick hue strip across the full spectrum, driving
/// [_SaturationValueField]'s background hue.
class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  static final _hueColors = List.generate(
    7,
    (i) => HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor(),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      void handle(Offset local) {
        final h = (local.dx / constraints.maxWidth).clamp(0.0, 1.0) * 360;
        onChanged(h.clamp(0.0, 359.9));
      }

      return GestureDetector(
        onPanDown: (details) => handle(details.localPosition),
        onPanUpdate: (details) => handle(details.localPosition),
        child: SizedBox(
          height: 28,
          width: double.infinity,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: _hueColors),
                  ),
                ),
              ),
              Positioned(
                left: (hue / 360) * constraints.maxWidth - 4,
                top: -2,
                bottom: -2,
                child: IgnorePointer(
                  child: Container(
                    width: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: Colors.white,
                      border: Border.all(color: Colors.black26),
                      boxShadow: const [
                        BoxShadow(color: Colors.black38, blurRadius: 2),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 16,
    height: 16,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
    ),
  );
}

class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    required this.children,
    this.minWidth = 230,
    this.spacing = 16,
    this.mobileSpacing = 12,
    this.mobileColumns = 2,
    super.key,
  });

  final List<Widget> children;
  final double minWidth;
  final double spacing;
  final double mobileSpacing;
  final int mobileColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (children.isEmpty) return const SizedBox.shrink();
      final mobile = constraints.maxWidth < AppBreakpoints.mobile;
      final effectiveSpacing = mobile ? mobileSpacing : spacing;
      final columns = mobile
          ? mobileColumns.clamp(1, children.length)
          : (constraints.maxWidth / minWidth).floor().clamp(
              1,
              children.length.clamp(1, 4),
            );
      final width =
          (constraints.maxWidth - effectiveSpacing * (columns - 1)) / columns;
      return Wrap(
        spacing: effectiveSpacing,
        runSpacing: effectiveSpacing,
        children: children
            .map((child) => SizedBox(width: width, child: child))
            .toList(),
      );
    },
  );
}

Future<bool> confirmDelete(BuildContext context, String label) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('刪除$label？'),
        content: const Text('相關金額將立即重新計算，此動作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              Navigator.pop(context, true);
            },
            child: const Text('刪除'),
          ),
        ],
      ),
    ) ??
    false;

void showSaved(BuildContext context, [String message = '已儲存']) {
  HapticFeedback.lightImpact();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String accountName(AppStore store, String? id) =>
    store.accountById(id)?.name ?? '未指定';

/// A drop-in replacement for [TextFormField] used on every money-amount
/// input across the app. Tapping the field (or its calculator icon) opens
/// a small pop-up calculator so the user can add/subtract/multiply/divide
/// their way to the amount instead of typing it digit by digit.
///
/// It accepts (and ignores) [keyboardType]/[inputFormatters]/
/// [textInputAction] so it can be swapped in for an existing
/// `TextField`/`TextFormField` without touching those call sites.
class MoneyField extends StatelessWidget {
  const MoneyField({
    required this.controller,
    this.decoration,
    this.style,
    this.validator,
    this.onChanged,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.textAlign = TextAlign.start,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    super.key,
  });

  final TextEditingController controller;
  final InputDecoration? decoration;
  final TextStyle? style;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final TextAlign textAlign;

  // Accepted for drop-in compatibility with TextField/TextFormField call
  // sites; the calculator pop-up replaces the on-screen keyboard entirely.
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;

  bool get _calculatorEnabled => enabled && !readOnly;

  Future<void> _openCalculator(BuildContext context) async {
    if (!_calculatorEnabled) return;
    final result = await showMoneyCalculator(
      context,
      initialValue: controller.text,
    );
    if (result == null) return;
    controller.value = TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
    onChanged?.call(result);
  }

  @override
  Widget build(BuildContext context) {
    final baseDecoration = decoration ?? const InputDecoration();
    final calculatorButton = _calculatorEnabled
        ? IconButton(
            tooltip: '小算盤',
            icon: const Icon(Icons.calculate_outlined),
            onPressed: () => _openCalculator(context),
          )
        : null;
    final existingSuffix = baseDecoration.suffixIcon;
    final mergedSuffix = calculatorButton == null
        ? existingSuffix
        : existingSuffix == null
        ? calculatorButton
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [existingSuffix, calculatorButton],
          );
    return TextFormField(
      controller: controller,
      readOnly: true,
      showCursor: true,
      enableInteractiveSelection: false,
      enabled: enabled,
      autofocus: autofocus,
      style: style,
      textAlign: textAlign,
      decoration: baseDecoration.copyWith(suffixIcon: mergedSuffix),
      validator: validator,
      onTap: readOnly ? null : () => _openCalculator(context),
    );
  }
}

/// Shows the mini calculator used by [MoneyField] and returns the
/// confirmed amount as a plain decimal string (e.g. `1234.5`), or null if
/// the user dismissed it without confirming.
Future<String?> showMoneyCalculator(
  BuildContext context, {
  String? initialValue,
}) {
  final compact = MediaQuery.sizeOf(context).width < 600;
  if (compact) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _MoneyCalculatorSheet(initialValue: initialValue),
      ),
    );
  }
  return showDialog<String>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: _MoneyCalculatorSheet(initialValue: initialValue),
      ),
    ),
  );
}

enum _CalcOp { add, subtract, multiply, divide }

extension on _CalcOp {
  String get symbol => switch (this) {
    _CalcOp.add => '+',
    _CalcOp.subtract => '−',
    _CalcOp.multiply => '×',
    _CalcOp.divide => '÷',
  };
}

class _MoneyCalculatorSheet extends StatefulWidget {
  const _MoneyCalculatorSheet({this.initialValue});

  final String? initialValue;

  @override
  State<_MoneyCalculatorSheet> createState() => _MoneyCalculatorSheetState();
}

class _MoneyCalculatorSheetState extends State<_MoneyCalculatorSheet> {
  late String _display;
  double? _accumulator;
  _CalcOp? _pendingOp;
  bool _justEvaluatedOrOperated = true;
  bool _overwriteOnNextDigit = true;

  @override
  void initState() {
    super.initState();
    final seed = double.tryParse(
      (widget.initialValue ?? '').replaceAll(',', '').trim(),
    );
    _display = seed == null || seed == 0 ? '0' : _formatNumber(seed);
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toStringAsFixed(0);
    }
    var text = value.toStringAsFixed(2);
    text = text.replaceFirst(RegExp(r'0$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
    return text;
  }

  double get _currentValue => double.tryParse(_display) ?? 0;

  double _compute(double a, _CalcOp op, double b) => switch (op) {
    _CalcOp.add => a + b,
    _CalcOp.subtract => a - b,
    _CalcOp.multiply => a * b,
    _CalcOp.divide => b == 0 ? 0 : a / b,
  };

  void _pressDigit(String digit) {
    setState(() {
      if (_overwriteOnNextDigit) {
        _display = digit == '.' ? '0.' : digit;
      } else if (digit == '.') {
        if (!_display.contains('.')) _display += '.';
      } else if (_display == '0') {
        _display = digit;
      } else {
        _display += digit;
      }
      _overwriteOnNextDigit = false;
      _justEvaluatedOrOperated = false;
    });
  }

  void _pressOperator(_CalcOp op) {
    setState(() {
      if (_pendingOp != null && !_justEvaluatedOrOperated) {
        _accumulator = _compute(_accumulator ?? 0, _pendingOp!, _currentValue);
      } else {
        _accumulator = _currentValue;
      }
      _pendingOp = op;
      _display = _formatNumber(_accumulator!);
      _overwriteOnNextDigit = true;
      _justEvaluatedOrOperated = true;
    });
  }

  void _pressEquals() {
    setState(() {
      if (_pendingOp != null) {
        _accumulator = _compute(_accumulator ?? 0, _pendingOp!, _currentValue);
        _display = _formatNumber(_accumulator!);
        _pendingOp = null;
      }
      _overwriteOnNextDigit = true;
      _justEvaluatedOrOperated = true;
    });
  }

  void _pressClear() {
    setState(() {
      _display = '0';
      _accumulator = null;
      _pendingOp = null;
      _overwriteOnNextDigit = true;
      _justEvaluatedOrOperated = true;
    });
  }

  void _pressBackspace() {
    setState(() {
      if (_overwriteOnNextDigit || _display.length <= 1) {
        _display = '0';
        _overwriteOnNextDigit = true;
      } else {
        _display = _display.substring(0, _display.length - 1);
      }
    });
  }

  void _pressSign() {
    setState(() {
      if (_display == '0') return;
      _display = _display.startsWith('-')
          ? _display.substring(1)
          : '-$_display';
    });
  }

  void _confirm() {
    if (_pendingOp != null) {
      _accumulator = _compute(_accumulator ?? 0, _pendingOp!, _currentValue);
      _display = _formatNumber(_accumulator!);
    }
    Navigator.pop(context, _display == '0' ? '0' : _display);
  }

  @override
  Widget build(BuildContext context) {
    final expression = _pendingOp == null
        ? ''
        : '${_formatNumber(_accumulator ?? 0)} ${_pendingOp!.symbol}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '小算盤',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '關閉',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (expression.isNotEmpty)
                    Text(
                      expression,
                      style: TextStyle(color: context.colors.textMuted),
                    ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _display,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _CalculatorGrid(
              onDigit: _pressDigit,
              onOperator: _pressOperator,
              onEquals: _pressEquals,
              onClear: _pressClear,
              onBackspace: _pressBackspace,
              onSign: _pressSign,
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: _confirm, child: const Text('確定帶入金額')),
          ],
        ),
      ),
    );
  }
}

class _CalculatorGrid extends StatelessWidget {
  const _CalculatorGrid({
    required this.onDigit,
    required this.onOperator,
    required this.onEquals,
    required this.onClear,
    required this.onBackspace,
    required this.onSign,
  });

  final ValueChanged<String> onDigit;
  final ValueChanged<_CalcOp> onOperator;
  final VoidCallback onEquals;
  final VoidCallback onClear;
  final VoidCallback onBackspace;
  final VoidCallback onSign;

  @override
  Widget build(BuildContext context) {
    Widget button(
      String label, {
      VoidCallback? onPressed,
      Color? background,
      Color? foreground,
      int flex = 1,
    }) => Expanded(
      flex: flex,
      child: AspectRatio(
        aspectRatio: 1.4 * flex,
        child: Material(
          color: background ?? Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onPressed,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Widget spacer() => const SizedBox(width: 8);

    final accent = Theme.of(context).colorScheme.primary;
    final onAccent = Theme.of(context).colorScheme.onPrimary;
    final error = Theme.of(context).colorScheme.error;
    final opBg = accent.withValues(alpha: .12);

    return Column(
      children: [
        Row(
          children: [
            button('C', onPressed: onClear, foreground: error),
            spacer(),
            button('±', onPressed: onSign),
            spacer(),
            button('⌫', onPressed: onBackspace),
            spacer(),
            button(
              '÷',
              onPressed: () => onOperator(_CalcOp.divide),
              background: opBg,
              foreground: accent,
            ),
          ],
        ),
        spacer(),
        Row(
          children: [
            button('7', onPressed: () => onDigit('7')),
            spacer(),
            button('8', onPressed: () => onDigit('8')),
            spacer(),
            button('9', onPressed: () => onDigit('9')),
            spacer(),
            button(
              '×',
              onPressed: () => onOperator(_CalcOp.multiply),
              background: opBg,
              foreground: accent,
            ),
          ],
        ),
        spacer(),
        Row(
          children: [
            button('4', onPressed: () => onDigit('4')),
            spacer(),
            button('5', onPressed: () => onDigit('5')),
            spacer(),
            button('6', onPressed: () => onDigit('6')),
            spacer(),
            button(
              '−',
              onPressed: () => onOperator(_CalcOp.subtract),
              background: opBg,
              foreground: accent,
            ),
          ],
        ),
        spacer(),
        Row(
          children: [
            button('1', onPressed: () => onDigit('1')),
            spacer(),
            button('2', onPressed: () => onDigit('2')),
            spacer(),
            button('3', onPressed: () => onDigit('3')),
            spacer(),
            button(
              '+',
              onPressed: () => onOperator(_CalcOp.add),
              background: opBg,
              foreground: accent,
            ),
          ],
        ),
        spacer(),
        Row(
          children: [
            button('0', onPressed: () => onDigit('0'), flex: 2),
            spacer(),
            button('.', onPressed: () => onDigit('.')),
            spacer(),
            button(
              '=',
              onPressed: onEquals,
              background: accent,
              foreground: onAccent,
            ),
          ],
        ),
      ],
    );
  }
}
