import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hls_video_player.dart';

class HlsVideoWallTile {
  final String slotKey;
  final String slotId;
  final String title;
  final Uri? playbackUri;
  final bool isPlayable;
  final bool isOverlayPending;
  final bool hasWarning;
  final String? overlayIndex;
  final String overlayStatus;
  final String overlayStatusColor;

  const HlsVideoWallTile({
    required this.slotKey,
    required this.slotId,
    required this.title,
    required this.playbackUri,
    required this.isPlayable,
    required this.isOverlayPending,
    required this.hasWarning,
    required this.overlayIndex,
    required this.overlayStatus,
    required this.overlayStatusColor,
  });
}

class HlsVideoWall extends StatelessWidget {
  final List<HlsVideoWallTile> tiles;
  final int crossAxisCount;
  final double aspectRatio;
  final Map<String, String> httpHeaders;
  final String dividerColor;
  final String warningColor;
  final void Function(String slotKey)? onTileTap;
  final FutureOr<void> Function(String reason, String slotKey)?
      onPlaybackUnauthorized;

  const HlsVideoWall({
    super.key,
    required this.tiles,
    required this.crossAxisCount,
    required this.aspectRatio,
    this.httpHeaders = const <String, String>{},
    required this.dividerColor,
    required this.warningColor,
    this.onTileTap,
    this.onPlaybackUnauthorized,
  });

  Color _parseCssColor(String value, Color fallback) {
    final raw = value.trim();
    final hex = raw.startsWith('#') ? raw.substring(1) : raw;
    if (hex.length != 6) return fallback;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return fallback;
    return Color(0xFF000000 | parsed);
  }

  @override
  Widget build(BuildContext context) {
    final columns = math.max(1, crossAxisCount);
    final divider = _parseCssColor(dividerColor, const Color(0xFF4A4A4A));
    final warning = _parseCssColor(warningColor, const Color(0xFFB3261E));

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: tiles.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: aspectRatio,
      ),
      itemBuilder: (context, index) {
        final tile = tiles[index];
        final playbackUri = tile.playbackUri;
        final handleTap =
            onTileTap == null ? null : () => onTileTap?.call(tile.slotKey);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: tile.hasWarning ? warning : divider,
          ),
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: ColoredBox(
              color: const Color(0xFF0D0D11),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  tile.isPlayable && playbackUri != null
                      ? HlsVideoPlayer(
                          key: ValueKey(tile.slotKey),
                          playbackUri: playbackUri,
                          httpHeaders: httpHeaders,
                          showControls: false,
                          overlayTitle: tile.title,
                          overlayStatus: tile.overlayStatus,
                          overlayIndex: tile.overlayIndex,
                          overlayStatusColor: tile.overlayStatusColor,
                          onPlaybackUnauthorized: onPlaybackUnauthorized == null
                              ? null
                              : (reason) =>
                                  onPlaybackUnauthorized!(reason, tile.slotKey),
                        )
                      : Center(
                          child: Icon(
                            Icons.play_arrow,
                            size: 48,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                  Positioned.fill(
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        onTap: handleTap,
                        splashColor: Colors.white.withValues(alpha: 0.08),
                        highlightColor: Colors.white.withValues(alpha: 0.04),
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
