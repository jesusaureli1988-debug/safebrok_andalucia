import 'package:flutter/material.dart';

Object progressiveRecordKey(Iterable<dynamic> rows) => Object.hashAll(
  rows.map((dynamic row) => row is Map ? row['id'] ?? row : row),
);

/// Paginación de presentación. No limita los datos usados en totales o Excel.
class ProgressiveRecords extends StatefulWidget {
  const ProgressiveRecords({
    super.key,
    required this.count,
    required this.builder,
    this.resetKey,
    this.showFooter = false,
  });

  final int count;
  final Object? resetKey;
  final bool showFooter;
  final Widget Function(BuildContext context, int visible) builder;

  @override
  State<ProgressiveRecords> createState() => _ProgressiveRecordsState();
}

class _ProgressiveRecordsState extends State<ProgressiveRecords> {
  int _visible = 10;
  bool _scheduled = false;
  ScrollPosition? _ancestor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ScrollPosition? position;
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final candidate = (element.state as ScrollableState).position;
        if (axisDirectionToAxis(candidate.axisDirection) == Axis.vertical) {
          position = candidate;
          return false;
        }
      }
      return true;
    });
    if (position != _ancestor) {
      _ancestor?.removeListener(_onAncestorScroll);
      _ancestor = position;
      _ancestor?.addListener(_onAncestorScroll);
    }
  }

  @override
  void didUpdateWidget(ProgressiveRecords oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetKey != oldWidget.resetKey) _visible = 10;
    if (_visible > widget.count) _visible = widget.count.clamp(10, 1 << 30);
  }

  void _onAncestorScroll() {
    final position = _ancestor;
    if (position != null &&
        position.hasContentDimensions &&
        position.pixels > 0 &&
        position.extentAfter < 160)
      _more();
  }

  void _more() {
    if (_scheduled || _visible >= widget.count) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || _visible >= widget.count) return;
      setState(() => _visible = (_visible + 10).clamp(0, widget.count));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _ancestor?.removeListener(_onAncestorScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            notification.metrics.axis == Axis.vertical &&
            notification.metrics.maxScrollExtent == 0)
          _more();
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth == 0 &&
              notification.metrics.axis == Axis.vertical &&
              notification.metrics.extentAfter < 160 &&
              notification is ScrollUpdateNotification)
            _more();
          return false;
        },
        child: widget.showFooter
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  widget.builder(context, _visible.clamp(0, widget.count)),
                  if (_visible < widget.count)
                    TextButton.icon(
                      onPressed: _more,
                      icon: const Icon(Icons.expand_more),
                      label: Text(
                        'Mostrar 10 más · ${_visible.clamp(0, widget.count)} de ${widget.count}',
                      ),
                    ),
                ],
              )
            : widget.builder(context, _visible.clamp(0, widget.count)),
      ),
    );
  }
}

/// Sustituto de ListView para listados de datos, con bloques de diez.
class ProgressiveListView extends StatelessWidget {
  const ProgressiveListView.builder({
    super.key,
    required this.itemBuilder,
    required this.itemCount,
    this.controller,
    this.padding,
    this.physics,
    this.shrinkWrap = false,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.primary,
    this.itemExtent,
    this.cacheExtent,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.addSemanticIndexes = true,
    this.resetKey,
  }) : separatorBuilder = null;

  const ProgressiveListView.separated({
    super.key,
    required this.itemBuilder,
    required this.itemCount,
    required this.separatorBuilder,
    this.controller,
    this.padding,
    this.physics,
    this.shrinkWrap = false,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.primary,
    this.cacheExtent,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.addSemanticIndexes = true,
    this.resetKey,
  }) : itemExtent = null;

  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder? separatorBuilder;
  final int itemCount;
  final ScrollController? controller;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final bool shrinkWrap, reverse;
  final Axis scrollDirection;
  final bool? primary;
  final double? itemExtent, cacheExtent;
  final bool addAutomaticKeepAlives, addRepaintBoundaries, addSemanticIndexes;
  final Object? resetKey;

  @override
  Widget build(BuildContext context) => ProgressiveRecords(
    count: itemCount,
    resetKey: resetKey,
    builder: (context, visible) {
      // Los chips horizontales y los historiales invertidos no se recortan.
      if (scrollDirection == Axis.horizontal || reverse) visible = itemCount;
      if (separatorBuilder != null) {
        return ListView.separated(
          controller: controller,
          padding: padding,
          physics: physics,
          shrinkWrap: shrinkWrap,
          scrollDirection: scrollDirection,
          reverse: reverse,
          primary: primary,
          cacheExtent: cacheExtent,
          addAutomaticKeepAlives: addAutomaticKeepAlives,
          addRepaintBoundaries: addRepaintBoundaries,
          addSemanticIndexes: addSemanticIndexes,
          itemCount: visible,
          itemBuilder: itemBuilder,
          separatorBuilder: separatorBuilder!,
        );
      }
      return ListView.builder(
        controller: controller,
        padding: padding,
        physics: physics,
        shrinkWrap: shrinkWrap,
        scrollDirection: scrollDirection,
        reverse: reverse,
        primary: primary,
        itemExtent: itemExtent,
        cacheExtent: cacheExtent,
        addAutomaticKeepAlives: addAutomaticKeepAlives,
        addRepaintBoundaries: addRepaintBoundaries,
        addSemanticIndexes: addSemanticIndexes,
        itemCount: visible,
        itemBuilder: itemBuilder,
      );
    },
  );
}

class ProgressiveGridView extends StatelessWidget {
  const ProgressiveGridView.builder({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.gridDelegate,
    this.padding,
    this.physics,
    this.shrinkWrap = false,
    this.resetKey,
  });
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final SliverGridDelegate gridDelegate;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final Object? resetKey;

  @override
  Widget build(BuildContext context) => ProgressiveRecords(
    count: itemCount,
    resetKey: resetKey,
    builder: (_, visible) => GridView.builder(
      itemCount: visible,
      itemBuilder: itemBuilder,
      gridDelegate: gridDelegate,
      padding: padding,
      physics: physics,
      shrinkWrap: shrinkWrap,
    ),
  );
}

class ProgressiveSliverList extends StatefulWidget {
  const ProgressiveSliverList.builder({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.separatorBuilder,
    this.resetKey,
  });
  const ProgressiveSliverList.separated({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.separatorBuilder,
    this.resetKey,
  });
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder? separatorBuilder;
  final Object? resetKey;

  @override
  State<ProgressiveSliverList> createState() => _ProgressiveSliverListState();
}

class _ProgressiveSliverListState extends State<ProgressiveSliverList> {
  int _visible = 10;
  bool _scheduled = false;
  ScrollPosition? _position;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Scrollable.maybeOf(context)?.position;
    if (_position != next) {
      _position?.removeListener(_scroll);
      _position = next;
      next?.addListener(_scroll);
    }
  }

  void _scroll() {
    if (_position!.hasContentDimensions &&
        _position!.extentAfter < 160 &&
        _visible < widget.itemCount &&
        !_scheduled) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduled = false;
        if (mounted && _visible < widget.itemCount) {
          setState(() => _visible = (_visible + 10).clamp(0, widget.itemCount));
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  @override
  void didUpdateWidget(ProgressiveSliverList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetKey != oldWidget.resetKey) _visible = 10;
  }

  @override
  void dispose() {
    _position?.removeListener(_scroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _position != null &&
          _position!.hasContentDimensions &&
          _position!.maxScrollExtent == 0)
        _scroll();
    });
    final count = _visible.clamp(0, widget.itemCount);
    if (widget.separatorBuilder != null) {
      return SliverList.separated(
        itemCount: count,
        itemBuilder: widget.itemBuilder,
        separatorBuilder: widget.separatorBuilder!,
      );
    }
    return SliverList.builder(
      itemCount: count,
      itemBuilder: widget.itemBuilder,
    );
  }
}
