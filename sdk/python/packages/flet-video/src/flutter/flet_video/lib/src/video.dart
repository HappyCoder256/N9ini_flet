import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flet/flet.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'utils/video.dart';

class VideoControl extends StatefulWidget {
  final Control? parent;
  final Control control;
  final FletControlBackend backend;

  const VideoControl({
    super.key,
    required this.parent,
    required this.control,
    required this.backend,
  });

  @override
  State<VideoControl> createState() => _VideoControlState();
}

class _VideoControlState extends State<VideoControl> with FletStoreMixin {
  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();

  late final Player player;
  late final VideoController controller;

  StreamSubscription? _errorSub;
  StreamSubscription? _completedSub;
  StreamSubscription? _playlistSub;

  bool _disposed = false;

  @override
  void initState() {
    super.initState();

    // --- Player ---
    player = Player(
      configuration: PlayerConfiguration(
        title: widget.control.attrString("title", "Flet Video")!,
        muted: widget.control.attrBool("muted", false)!,
        pitch: widget.control.attrDouble("pitch") != null,
        ready: () {
          if (widget.control.attrBool("onLoaded", false)!) {
            widget.backend
                .triggerControlEvent(widget.control.id, "loaded");
          }
        },
      ),
    );

    // --- Controller ---
    controller = VideoController(
      player,
      configuration: parseControllerConfiguration(
        widget.control,
        "configuration",
        const VideoControllerConfiguration(),
      )!,
    );

    // --- Streams ---
    _errorSub = player.stream.error.listen((event) {
      if (widget.control.attrBool("onError", false)!) {
        _trigger("error", event.toString());
      }
    });

    _completedSub = player.stream.completed.listen((event) {
      if (widget.control.attrBool("onCompleted", false)!) {
        _trigger("completed", event.toString());
      }
    });

    _playlistSub = player.stream.playlist.listen((event) {
      if (widget.control.attrBool("onTrackChanged", false)!) {
        _trigger("track_changed", event.index.toString());
      }
    });

    // --- Methods ---
    widget.backend.subscribeMethods(widget.control.id, _handleMethods);

    // --- Safe init ---
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_disposed) return;

      await _applyMpvProperties();

      final playlist = parseVideoMedia(widget.control, "playlist");

      if (playlist.isEmpty) {
        debugPrint("⚠️ Empty playlist");
        return;
      }

      await player.open(
        Playlist(playlist),
        play: widget.control.attrBool("autoPlay", false)!,
      );
    });
  }

  // ================= METHODS =================

  Future<dynamic> _handleMethods(String method, Map<String, String> args) async {
    switch (method) {
      case "play":
        return player.play();

      case "pause":
        return player.pause();

      case "play_or_pause":
        return player.playOrPause();

      case "stop":
        await player.stop();
        return player.open(
          Playlist(parseVideoMedia(widget.control, "playlist")),
          play: false,
        );

      case "seek":
        return player.seek(Duration(
          milliseconds: int.tryParse(args["position"] ?? "") ?? 0,
        ));

      case "next":
        return player.next();

      case "previous":
        return player.previous();

      case "jump_to":
        return player.jump(parseInt(args["media_index"], 0)!);

      case "fullscreen":
        final value = args["value"] == "true";

        WidgetsBinding.instance.addPostFrameCallback((_) {
          final state = _videoKey.currentState;
          if (state == null) return;

          if (value) {
            state.enterFullscreen();
          } else {
            state.exitFullscreen();
          }
        });
        break;

      case "get_duration":
        return player.state.duration.inMilliseconds.toString();

      case "get_current_position":
        return player.state.position.inMilliseconds.toString();

      case "is_playing":
        return player.state.playing.toString();

      case "is_completed":
        return player.state.completed.toString();
    }
    return null;
  }

  // ================= MPV =================

  Future<void> _applyMpvProperties() async {
    final raw = widget.control.attrString("configuration");
    if (raw == null) return;

    Map<String, dynamic> cfg;
    try {
      cfg = json.decode(raw);
    } catch (_) {
      return;
    }

    final mpv = cfg["mpv_properties"];
    if (mpv is! Map) return;

    final platform = player.platform;
    if (platform is! NativePlayer) return;

    final native = platform as dynamic;

    for (final entry in mpv.entries) {
      final key = entry.key.toString();
      final val = entry.value;
      if (val == null) continue;

      final value = val is bool ? (val ? "yes" : "no") : val.toString();

      try {
        await native.setProperty(key, value);
        debugPrint("MPV: $key = $value");
      } catch (e) {
        debugPrint("MPV ERROR: $key -> $e");
      }
    }
  }

  // ================= EVENTS =================

  void _trigger(String name, String msg) {
    widget.backend.triggerControlEvent(widget.control.id, name, msg);
  }

  // ================= LIFECYCLE =================

  @override
  void dispose() {
    _disposed = true;

    _errorSub?.cancel();
    _completedSub?.cancel();
    _playlistSub?.cancel();

    widget.backend.unsubscribeMethods(widget.control.id);

    player.dispose();

    super.dispose();
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    return withPageArgs((context, pageArgs) {
      final filterQuality = parseFilterQuality(
          widget.control.attrString("filterQuality"), FilterQuality.low)!;

      // --- Subtitle ---
      SubtitleTrack? subtitleTrack;
      final subtitleConfig = parseSubtitleConfiguration(
          Theme.of(context), widget.control, "subtitleConfiguration");

      if (subtitleConfig?["src"] != null) {
        try {
          final assetSrc = getAssetSrc(
            subtitleConfig?["src"],
            pageArgs.pageUri!,
            pageArgs.assetsDir,
          );

          subtitleTrack = parseSubtitleTrack(
            assetSrc,
            subtitleConfig?["title"],
            subtitleConfig?["language"],
          );
        } catch (e) {
          subtitleTrack = SubtitleTrack.no();
          _trigger("error", e.toString());
        }
      }

      final fullscreen = widget.control.attrBool("fullscreen", false)!;
      final prevFullscreen = widget.control.state["fullscreen"] ?? false;

      // --- Sync fullscreen ---
      if (fullscreen != prevFullscreen) {
        widget.control.state["fullscreen"] = fullscreen;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          final state = _videoKey.currentState;
          if (state == null) return;

          fullscreen ? state.enterFullscreen() : state.exitFullscreen();
        });
      }

      final video = Video(
        key: _videoKey,
        controller: controller,
        wakelock: widget.control.attrBool("wakelock", true)!,
        controls: widget.control.attrBool("showControls", true)!
            ? AdaptiveVideoControls
            : null,
        fit: parseBoxFit(
            widget.control.attrString("fit"), BoxFit.contain)!,
        alignment:
            parseAlignment(widget.control, "alignment", Alignment.center)!,
        filterQuality: filterQuality,
        subtitleViewConfiguration:
            subtitleConfig?["subtitleViewConfiguration"] ??
                const SubtitleViewConfiguration(),
        fill: parseColor(
                Theme.of(context), widget.control.attrString("fillColor", "")!) ??
            const Color(0xFF000000),

        // --- Fullscreen callbacks ---
        onEnterFullscreen: () async {
          widget.control.state["fullscreen"] = true;
          _trigger("enter_fullscreen", "");
          await defaultEnterNativeFullscreen();
        },

        onExitFullscreen: () async {
          widget.control.state["fullscreen"] = false;
          _trigger("exit_fullscreen", "");
          await defaultExitNativeFullscreen();
        },
      );

      return constrainedControl(
          context, video, widget.parent, widget.control);
    });
  }
}
