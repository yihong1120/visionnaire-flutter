import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/violation_records_api_service.dart';

class ViolationAnalyticsPanel extends StatelessWidget {
  final ViolationAnalytics? analytics;
  final bool isLoading;
  final String? errorMessage;
  final Widget filterCard;
  final Future<void> Function() onRefresh;
  final ValueChanged<ViolationAnalyticsTypeStat> onTypeSelected;
  final ValueChanged<ViolationAnalyticsSiteStat> onSiteSelected;

  const ViolationAnalyticsPanel({
    super.key,
    required this.analytics,
    required this.isLoading,
    required this.errorMessage,
    required this.filterCard,
    required this.onRefresh,
    required this.onTypeSelected,
    required this.onSiteSelected,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: <Widget>[
          filterCard,
          if (isLoading)
            const _AnalyticsLoading()
          else if (errorMessage != null)
            _AnalyticsError(message: errorMessage!, onRefresh: onRefresh)
          else if (analytics == null || !analytics!.hasData)
            _AnalyticsEmpty(onRefresh: onRefresh)
          else
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return _AnalyticsDashboard(
                  analytics: analytics!,
                  maxWidth: constraints.maxWidth,
                  onTypeSelected: onTypeSelected,
                  onSiteSelected: onSiteSelected,
                );
              },
            ),
        ],
      ),
    );
  }
}

class _AnalyticsDashboard extends StatelessWidget {
  final ViolationAnalytics analytics;
  final double maxWidth;
  final ValueChanged<ViolationAnalyticsTypeStat> onTypeSelected;
  final ValueChanged<ViolationAnalyticsSiteStat> onSiteSelected;

  const _AnalyticsDashboard({
    required this.analytics,
    required this.maxWidth,
    required this.onTypeSelected,
    required this.onSiteSelected,
  });

  @override
  Widget build(BuildContext context) {
    final bool isWide = maxWidth >= 980;
    final bool isMedium = maxWidth >= 640;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SummaryGrid(
          summary: analytics.summary,
          columns: isWide ? 4 : (isMedium ? 2 : 1),
        ),
        const SizedBox(height: 8),
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: _TrendCard(points: analytics.trend)),
              const SizedBox(width: 8),
              SizedBox(
                width: 380,
                child: _TypeDonutCard(
                  items: analytics.byType,
                  onSelected: onTypeSelected,
                ),
              ),
            ],
          )
        else ...<Widget>[
          _TrendCard(points: analytics.trend),
          const SizedBox(height: 8),
          _TypeDonutCard(
            items: analytics.byType,
            onSelected: onTypeSelected,
          ),
        ],
        const SizedBox(height: 8),
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _TypeRankingCard(
                  items: analytics.byType,
                  onSelected: onTypeSelected,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SiteRankingCard(
                  items: analytics.bySite,
                  onSelected: onSiteSelected,
                ),
              ),
            ],
          )
        else ...<Widget>[
          _TypeRankingCard(
            items: analytics.byType,
            onSelected: onTypeSelected,
          ),
          const SizedBox(height: 8),
          _SiteRankingCard(
            items: analytics.bySite,
            onSelected: onSiteSelected,
          ),
        ],
        const SizedBox(height: 8),
        _HourlyCard(items: analytics.byHour),
      ],
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final ViolationAnalyticsSummary summary;
  final int columns;

  const _SummaryGrid({
    required this.summary,
    required this.columns,
  });

  @override
  Widget build(BuildContext context) {
    final List<_SummaryItem> items = <_SummaryItem>[
      _SummaryItem(
        icon: Icons.warning_amber_rounded,
        label: _t(context, '總違規數', 'Total violations'),
        value: summary.total.toString(),
      ),
      _SummaryItem(
        icon: Icons.today_rounded,
        label: _t(context, '今日違規', 'Today'),
        value: summary.today.toString(),
      ),
      _SummaryItem(
        icon: Icons.location_on_outlined,
        label: _t(context, '最高風險工地', 'Top site'),
        value: summary.topSite?.label ?? '-',
        trailing: summary.topSite != null ? '${summary.topSite!.count}' : null,
      ),
      _SummaryItem(
        icon: Icons.category_outlined,
        label: _t(context, '主要類型', 'Top type'),
        value: summary.topType?.label ?? '-',
        trailing: summary.topType != null ? '${summary.topType!.count}' : null,
      ),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double gap = columns == 1 ? 0 : 8;
        final double tileWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: 8,
          children: items
              .map((item) => SizedBox(
                    width: tileWidth,
                    child: _SummaryTile(item: item),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _SummaryItem {
  final IconData icon;
  final String label;
  final String value;
  final String? trailing;

  const _SummaryItem({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });
}

class _SummaryTile extends StatelessWidget {
  final _SummaryItem item;

  const _SummaryTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Icon(item.icon, color: colors.primary, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          item.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (item.trailing != null)
                        Text(
                          item.trailing!,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: colors.primary),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  final List<ViolationAnalyticsTrendPoint> points;

  const _TrendCard({required this.points});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: _t(context, '違規趨勢', 'Violation trend'),
      child: SizedBox(
        width: double.infinity,
        height: 240,
        child: points.isEmpty
            ? _InlineEmpty(text: _t(context, '沒有趨勢資料', 'No trend data'))
            : CustomPaint(
                painter: _TrendPainter(
                  points: points,
                  color: Theme.of(context).colorScheme.primary,
                  gridColor: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withAlpha(90),
                  labelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  textDirection: Directionality.of(context),
                ),
                child: const SizedBox.expand(),
              ),
      ),
    );
  }
}

class _TypeDonutCard extends StatelessWidget {
  final List<ViolationAnalyticsTypeStat> items;
  final ValueChanged<ViolationAnalyticsTypeStat> onSelected;

  const _TypeDonutCard({
    required this.items,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final List<ViolationAnalyticsTypeStat> visible = items
        .where((ViolationAnalyticsTypeStat item) => item.count > 0)
        .take(6)
        .toList();
    return _SectionCard(
      title: _t(context, '項目分類', 'Type breakdown'),
      child: visible.isEmpty
          ? SizedBox(
              height: 180,
              child: _InlineEmpty(
                text: _t(context, '沒有分類資料', 'No type data'),
              ),
            )
          : LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool compact = constraints.maxWidth < 430;
                final Widget chart = SizedBox(
                  width: compact ? 150 : 172,
                  height: compact ? 150 : 172,
                  child: CustomPaint(
                    painter: _DonutPainter(
                      values: visible
                          .map((ViolationAnalyticsTypeStat item) => item.count)
                          .toList(),
                      colors: List<Color>.generate(
                        visible.length,
                        (int index) => _chartColor(context, index),
                      ),
                    ),
                  ),
                );
                final Widget legend = Column(
                  children: visible.asMap().entries.map(
                    (MapEntry<int, ViolationAnalyticsTypeStat> entry) {
                      return _LegendRow(
                        color: _chartColor(context, entry.key),
                        label: entry.value.label,
                        count: entry.value.count,
                        onTap: () => onSelected(entry.value),
                      );
                    },
                  ).toList(),
                );
                if (compact) {
                  return Column(
                    children: <Widget>[
                      chart,
                      const SizedBox(height: 12),
                      legend,
                    ],
                  );
                }
                return Row(
                  children: <Widget>[
                    chart,
                    const SizedBox(width: 16),
                    Expanded(child: legend),
                  ],
                );
              },
            ),
    );
  }
}

class _TypeRankingCard extends StatelessWidget {
  final List<ViolationAnalyticsTypeStat> items;
  final ValueChanged<ViolationAnalyticsTypeStat> onSelected;

  const _TypeRankingCard({
    required this.items,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: _t(context, '違規項目排行', 'Violation type ranking'),
      child: _RankedBars<ViolationAnalyticsTypeStat>(
        items: items,
        labelBuilder: (ViolationAnalyticsTypeStat item) => item.label,
        countBuilder: (ViolationAnalyticsTypeStat item) => item.count,
        onTap: onSelected,
      ),
    );
  }
}

class _SiteRankingCard extends StatelessWidget {
  final List<ViolationAnalyticsSiteStat> items;
  final ValueChanged<ViolationAnalyticsSiteStat> onSelected;

  const _SiteRankingCard({
    required this.items,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: _t(context, '工地排行', 'Site ranking'),
      child: _RankedBars<ViolationAnalyticsSiteStat>(
        items: items,
        labelBuilder: (ViolationAnalyticsSiteStat item) =>
            item.siteName.isEmpty ? '-' : item.siteName,
        countBuilder: (ViolationAnalyticsSiteStat item) => item.count,
        onTap: (ViolationAnalyticsSiteStat item) {
          if (item.siteId != null) onSelected(item);
        },
      ),
    );
  }
}

class _HourlyCard extends StatelessWidget {
  final List<ViolationAnalyticsHourStat> items;

  const _HourlyCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final Map<int, int> values = <int, int>{
      for (final ViolationAnalyticsHourStat item in items)
        item.hour: item.count,
    };
    final int maxCount = values.values
        .fold<int>(0, (int max, int value) => math.max(max, value));
    return _SectionCard(
      title: _t(context, '時段分布', 'Hourly distribution'),
      child: SizedBox(
        height: 148,
        child: maxCount == 0
            ? _InlineEmpty(text: _t(context, '沒有時段資料', 'No hourly data'))
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List<Widget>.generate(24, (int hour) {
                  final int count = values[hour] ?? 0;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Tooltip(
                        message: '$hour:00  $count',
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            Flexible(
                              child: FractionallySizedBox(
                                heightFactor:
                                    maxCount == 0 ? 0 : count / maxCount,
                                alignment: Alignment.bottomCenter,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const SizedBox(width: double.infinity),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (hour % 3 == 0)
                              Text(
                                '$hour',
                                style: Theme.of(context).textTheme.labelSmall,
                              )
                            else
                              const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
      ),
    );
  }
}

class _RankedBars<T> extends StatelessWidget {
  final List<T> items;
  final String Function(T item) labelBuilder;
  final int Function(T item) countBuilder;
  final ValueChanged<T> onTap;

  const _RankedBars({
    required this.items,
    required this.labelBuilder,
    required this.countBuilder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final List<T> visible =
        items.where((T item) => countBuilder(item) > 0).take(8).toList();
    if (visible.isEmpty) {
      return SizedBox(
        height: 120,
        child: _InlineEmpty(text: _t(context, '沒有排行資料', 'No ranking data')),
      );
    }
    final int maxCount = visible.fold<int>(
      0,
      (int max, T item) => math.max(max, countBuilder(item)),
    );
    return Column(
      children: visible.asMap().entries.map((MapEntry<int, T> entry) {
        final T item = entry.value;
        final int count = countBuilder(item);
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onTap(item),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        labelBuilder(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      count.toString(),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: maxCount == 0 ? 0 : count / maxCount,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    color: _chartColor(context, entry.key),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final int count;
  final VoidCallback onTap;

  const _LegendRow({
    required this.color,
    required this.label,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: <Widget>[
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              count.toString(),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _AnalyticsLoading extends StatelessWidget {
  const _AnalyticsLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 80),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _AnalyticsError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRefresh;

  const _AnalyticsError({
    required this.message,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.query_stats_rounded,
            size: 54,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            _t(context, '統計資料暫時無法載入', 'Analytics are unavailable'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(_t(context, '重新整理', 'Refresh')),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsEmpty extends StatelessWidget {
  final Future<void> Function() onRefresh;

  const _AnalyticsEmpty({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.analytics_outlined,
            size: 58,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(_t(context, '目前沒有統計資料', 'No analytics data')),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(_t(context, '重新整理', 'Refresh')),
          ),
        ],
      ),
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  final String text;

  const _InlineEmpty({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<ViolationAnalyticsTrendPoint> points;
  final Color color;
  final Color gridColor;
  final Color labelColor;
  final TextDirection textDirection;

  const _TrendPainter({
    required this.points,
    required this.color,
    required this.gridColor,
    required this.labelColor,
    required this.textDirection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double left = 42;
    const double top = 10;
    const double right = 12;
    const double bottom = 34;
    final Rect chart = Rect.fromLTWH(
      left,
      top,
      math.max(0, size.width - left - right),
      math.max(0, size.height - top - bottom),
    );
    final Paint gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final Paint linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3;
    final Paint fillPaint = Paint()
      ..color = color.withAlpha(25)
      ..style = PaintingStyle.fill;
    final Paint dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final int maxCount = math.max(
      1,
      points.fold<int>(
        0,
        (int max, ViolationAnalyticsTrendPoint point) =>
            math.max(max, point.count),
      ),
    );

    for (int i = 0; i <= 4; i += 1) {
      final double y = chart.top + chart.height * i / 4;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      _drawText(
        canvas,
        '${(maxCount * (4 - i) / 4).round()}',
        Offset(0, y - 8),
        Size(left - 8, 20),
        TextAlign.right,
      );
    }

    final List<Offset> offsets = <Offset>[];
    for (int i = 0; i < points.length; i += 1) {
      final double x = points.length == 1
          ? chart.center.dx
          : chart.left + chart.width * i / (points.length - 1);
      final double y = chart.bottom - chart.height * points[i].count / maxCount;
      offsets.add(Offset(x, y));
    }

    if (offsets.length == 1) {
      canvas.drawCircle(offsets.first, 4, dotPaint);
    } else if (offsets.length > 1) {
      final Path line = Path()..moveTo(offsets.first.dx, offsets.first.dy);
      for (final Offset offset in offsets.skip(1)) {
        line.lineTo(offset.dx, offset.dy);
      }
      final Path area = Path.from(line)
        ..lineTo(offsets.last.dx, chart.bottom)
        ..lineTo(offsets.first.dx, chart.bottom)
        ..close();
      canvas.drawPath(area, fillPaint);
      canvas.drawPath(line, linePaint);
      for (final Offset offset in offsets) {
        canvas.drawCircle(offset, 3.5, dotPaint);
      }
    }

    if (points.isNotEmpty) {
      final List<int> labelIndexes = <int>{
        0,
        if (points.length > 2) points.length ~/ 2,
        points.length - 1,
      }.toList();
      for (final int index in labelIndexes) {
        final Offset offset = offsets[index];
        _drawText(
          canvas,
          points[index].bucket,
          Offset(offset.dx - 56, chart.bottom + 8),
          const Size(112, 20),
          TextAlign.center,
        );
      }
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    Size size,
    TextAlign align,
  ) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: labelColor, fontSize: 11),
      ),
      textAlign: align,
      textDirection: textDirection,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: size.width);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.color != color ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.labelColor != labelColor;
  }
}

class _DonutPainter extends CustomPainter {
  final List<int> values;
  final List<Color> colors;

  const _DonutPainter({
    required this.values,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final int total = values.fold<int>(0, (int sum, int value) => sum + value);
    if (total <= 0) return;

    final double strokeWidth = math.min(size.width, size.height) * 0.16;
    final Rect rect = Offset.zero & size;
    final Rect arcRect = rect.deflate(strokeWidth / 2);
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    double start = -math.pi / 2;
    for (int i = 0; i < values.length; i += 1) {
      final double sweep = values[i] / total * math.pi * 2;
      paint.color = colors[i % colors.length];
      canvas.drawArc(arcRect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.colors != colors;
  }
}

Color _chartColor(BuildContext context, int index) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  final List<Color> palette = <Color>[
    colors.primary,
    colors.secondary,
    colors.tertiary,
    colors.error,
    const Color(0xFF2E7D32),
    const Color(0xFF64748B),
    const Color(0xFF0E7490),
    const Color(0xFFB45309),
    const Color(0xFF475569),
  ];
  return palette[index % palette.length];
}

String _t(BuildContext context, String zh, String en) {
  final Locale locale = Localizations.localeOf(context);
  return locale.languageCode == 'zh' ? zh : en;
}
