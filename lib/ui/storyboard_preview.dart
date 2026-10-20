import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../storyboard.dart';
import '../widgets/video_progress_bar.dart';

/// The progress bar's preview of the video at a time: one frame cut out of
/// a storyboard sprite sheet, fetched when first needed.
ProgressPreview storyboardPreview(Storyboard board, StoryboardSheets sheets, {double width = 160}) {
  final size = Size(width, width * board.height / board.width);
  return ProgressPreview(size, (time) => _TileView(board: board, sheets: sheets, tile: board.tileAt(time)));
}

class _TileView extends StatefulWidget {
  const _TileView({required this.board, required this.sheets, required this.tile});
  final Storyboard board;
  final StoryboardSheets sheets;
  final StoryboardTile tile;

  @override
  State<_TileView> createState() => _TileViewState();
}

class _TileViewState extends State<_TileView> {
  ui.Image? _image;
  int? _loaded;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(_TileView old) {
    super.didUpdateWidget(old);
    if (old.tile.sheet != widget.tile.sheet) _fetch();
  }

  void _fetch() {
    final sheet = widget.tile.sheet;
    widget.sheets.sheet(widget.board.sheets[sheet].url).then((image) {
      // The pointer may have moved to another sheet meanwhile; the frame
      // shown stays until the right one arrives.
      if (mounted && image != null && widget.tile.sheet == sheet) {
        setState(() {
          _image = image;
          _loaded = sheet;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: _image == null ? null : CustomPaint(painter: _TilePainter(_image!, widget.board, widget.tile, _loaded == widget.tile.sheet)),
      );
}

class _TilePainter extends CustomPainter {
  const _TilePainter(this.image, this.board, this.tile, this.current);
  final ui.Image image;
  final Storyboard board;
  final StoryboardTile tile;
  /// Whether [image] is the sheet [tile] is on; otherwise it is the last one
  /// shown and the tile is only a stand-in.
  final bool current;

  @override
  void paint(Canvas canvas, Size size) {
    if (!current) return;
    final source = Rect.fromLTWH(tile.column * board.width.toDouble(), tile.row * board.height.toDouble(), board.width.toDouble(), board.height.toDouble());
    canvas.drawImageRect(image, source, Offset.zero & size, Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_TilePainter old) => old.image != image || old.tile.row != tile.row || old.tile.column != tile.column || old.tile.sheet != tile.sheet || old.current != current;
}
