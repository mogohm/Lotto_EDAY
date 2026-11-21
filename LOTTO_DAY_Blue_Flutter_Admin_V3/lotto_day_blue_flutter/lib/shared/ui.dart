import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../core/api/models.dart';
import '../core/theme/app_theme.dart';

class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFFFFF4D4), borderRadius: BorderRadius.circular(12)),
        child: const Row(children: [
          Icon(Icons.info_outline, size: 18, color: LottoColors.navy),
          SizedBox(width: 8),
          Expanded(child: Text('ระบบสาธิต • ไม่มีการซื้อขายหรือชำระเงินจริง', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
        ]),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 10),
        child: Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: LottoColors.navy))),
          if (trailing != null) trailing!,
        ]),
      );
}

class QuickTile extends StatelessWidget {
  const QuickTile({super.key, required this.label, required this.icon, required this.onTap, this.color = LottoColors.primary});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Center(
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                        width: 96,
                        child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                            child: Icon(icon, color: color, size: 26),
                          ),
                          const SizedBox(height: 8),
                          Text(label, maxLines: 2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ])))),
          ),
        ),
      );
}

class PageWidth extends StatelessWidget {
  const PageWidth({super.key, required this.child, this.maxWidth = 1080});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child));
}

/// Standard scrollable page body with max width and padding.
class PageList extends StatelessWidget {
  const PageList({super.key, required this.children, this.maxWidth = 1080, this.padding = const EdgeInsets.all(16), this.onRefresh});
  final List<Widget> children;
  final double maxWidth;
  final EdgeInsets padding;
  final Future<void> Function()? onRefresh;
  @override
  Widget build(BuildContext context) {
    final list = ListView(padding: padding, physics: const AlwaysScrollableScrollPhysics(), children: children);
    return PageWidth(maxWidth: maxWidth, child: onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list));
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key, this.icon = Icons.inbox_outlined, this.action});
  final String message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
          child: Column(children: [
            Icon(icon, size: 42, color: LottoColors.secondary),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: LottoColors.ink)),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ]),
        ),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView(this.error, {super.key, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_outlined, size: 40, color: LottoColors.negative),
              const SizedBox(height: 8),
              Text('$error', textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('ลองใหม่')),
              ],
            ]),
          ),
        ),
      );
}

/// Loads data from the API and renders loading / error (with retry) / data states.
class AsyncView<T> extends StatefulWidget {
  const AsyncView({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  @override
  State<AsyncView<T>> createState() => _AsyncViewState<T>();
}

class _AsyncViewState<T> extends State<AsyncView<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final d = await widget.load();
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    if (_error != null && _data == null) return ErrorView(_error!, onRetry: _reload);
    return widget.builder(context, _data as T, _reload);
  }
}

void toast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? LottoColors.negative : LottoColors.navy, behavior: SnackBarBehavior.floating));
}

/// Runs an API action and shows success/error toasts. Returns true on success.
Future<bool> runAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (context.mounted && success != null) toast(context, success);
    return true;
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message, error: true);
  } catch (e) {
    if (context.mounted) toast(context, '$e', error: true);
  }
  return false;
}

Future<bool> confirmDialog(BuildContext context, String title, String message, {String ok = 'ยืนยัน'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok))
        ],
      ),
    ) ??
    false;

Future<String?> promptText(BuildContext context, String title, {String label = 'เหตุผล', bool required = true}) async {
  final c = TextEditingController();
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, maxLines: 3, decoration: InputDecoration(labelText: label)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
        FilledButton(
            onPressed: () {
              if (!required || c.text.trim().isNotEmpty) Navigator.pop(ctx, c.text.trim());
            },
            child: const Text('ตกลง')),
      ],
    ),
  );
  return r;
}

/// Status pill that never relies on color alone (always has text + icon).
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.color = LottoColors.primary, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  static Color drawColor(String s) => switch (s) {
        'PUBLISHED' => LottoColors.positive,
        'APPROVED' => LottoColors.secondary,
        'AWAITING_REVIEW' => const Color(0xFFB7791F),
        'CANCELLED' => LottoColors.negative,
        'DRAFT' => LottoColors.primary,
        _ => LottoColors.navy,
      };
  static IconData drawIcon(String s) => switch (s) {
        'PUBLISHED' => Icons.verified,
        'APPROVED' => Icons.thumb_up_alt_outlined,
        'AWAITING_REVIEW' => Icons.hourglass_top,
        'CANCELLED' => Icons.block,
        'DRAFT' => Icons.edit_note,
        _ => Icons.schedule,
      };
  factory StatusChip.draw(String status) => StatusChip(drawStatusTh[status] ?? status, color: drawColor(status), icon: drawIcon(status));
  factory StatusChip.sales(String s) => StatusChip(salesStateTh[s] ?? s,
      color: s == 'OPEN'
          ? LottoColors.positive
          : s == 'UPCOMING'
              ? LottoColors.primary
              : LottoColors.negative,
      icon: s == 'OPEN' ? Icons.lock_open : Icons.lock_clock);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.35))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
      );
}

/// Blue wallet-style gradient panel.
class GradientPanel extends StatelessWidget {
  const GradientPanel({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.radius = 22});
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [LottoColors.primary, LottoColors.secondary], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [BoxShadow(color: LottoColors.primary.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: child,
      );
}

/// Renders the 2/3/4-digit × position result matrix.
class ResultGrid extends StatelessWidget {
  const ResultGrid({super.key, required this.results, this.compact = false});
  final Map<String, String> results;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const Text('ยังไม่มีผล', style: TextStyle(color: LottoColors.ink));
    final digits = results.keys.map((k) => int.parse(k.split(':')[0])).toSet().toList()..sort((a, b) => b.compareTo(a));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final d in digits) ...[
        Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text('เลข $d ตัว', style: const TextStyle(fontWeight: FontWeight.w800, color: LottoColors.navy))),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in positionOrder)
            if (results.containsKey(resultKey(d, p)))
              Container(
                padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: compact ? 6 : 10),
                decoration: BoxDecoration(color: LottoColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: LottoColors.border)),
                child: Column(children: [
                  Text(positionTh[p]!, style: const TextStyle(fontSize: 11, color: LottoColors.primary, fontWeight: FontWeight.w700)),
                  Text(results[resultKey(d, p)]!,
                      style: TextStyle(fontSize: compact ? 18 : 24, fontWeight: FontWeight.w900, color: LottoColors.navy, letterSpacing: 2)),
                ]),
              ),
        ]),
      ],
    ]);
  }
}

class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(label, style: const TextStyle(color: Color(0xFF4A6380)))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}

bool isWide(BuildContext context, [double breakpoint = 720]) => MediaQuery.sizeOf(context).width >= breakpoint;
