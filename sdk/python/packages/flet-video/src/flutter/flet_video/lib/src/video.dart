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
  GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();

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
            _trigger("loaded", "");
          }
        },
      ),
    );

    // --- Controller ---
    // ✅ parse configuration from attrString then decode
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

    // --- Init player safely ---
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

  Future<String?> _handleMethods(
      String method, Map<String, String> args) async {
    switch (method) {
      case "play":
        await player.play();
        return null;

      case "pause":
        await player.pause();
        return null;

      case "play_or_pause":
        await player.playOrPause();
        return null;

      case "stop":
        await player.stop();
        await player.open(
          Playlist(parseVideoMedia(widget.control, "playlist")),
          play: false,
        );
        return null;

      case "seek":
        await player.seek(Duration(
          milliseconds: int.tryParse(args["position"] ?? "") ?? 0,
        ));
        return null;

      case "next":
        await player.next();
        return null;

      case "previous":
        await player.previous();
        return null;

      case "jump_to":
        await player.jump(parseInt(args["media_index"], 0)!);
        return null;

      case "playlist_add":
        Map<String, dynamic> extras =
            json.decode(args["extras"]!.replaceAll("'", "\""));
        Map<String, String> httpHeaders =
            (json.decode(args["http_headers"]!.replaceAll("'", "\"")) as Map)
                .map((key, value) =>
                    MapEntry(key.toString(), value.toString()));
        await player.add(Media(
          args["resource"]!,
          extras: extras.isNotEmpty ? extras : null,
          httpHeaders: httpHeaders.isNotEmpty ? httpHeaders : null,
        ));
        return null;

      case "playlist_remove":
        await player.remove(parseInt(args["media_index"], 0)!);
        return null;

      case "fullscreen":
        final value = args["value"] == "true";
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final state = _videoKey.currentState;
          if (state == null) return;
          value ? state.enterFullscreen() : state.exitFullscreen();
        });
        return null;

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

  // ================= MPV CONFIG =================

  Future<void> _applyMpvProperties() async {
    // ✅ use attrString + json.decode since control.get() doesn't exist
    final raw = widget.control.attrString("configuration", null);
    if (raw == null) return;

    Map<String, dynamic> cfg;
    try {
      cfg = json.decode(raw);
    } catch (e) {
      debugPrint("MPV config decode error: $e");
      return;
    }

    final mpvPropsRaw = cfg["mpv_properties"];
    if (mpvPropsRaw is! Map) return;

    final platform = player.platform;
    if (platform is! NativePlayer) return;
    final native = platform as dynamic;

    for (final entry in mpvPropsRaw.entries) {
      final key = entry.key.toString();
      final val = entry.value;
      if (val == null) continue;
      final valueStr = val is bool ? (val ? "yes" : "no") : val.toString();
      try {
        await native.setProperty(key, valueStr);
        debugPrint("MPV SET: $key = $valueStr ✅");
      } catch (e) {
        debugPrint("MPV ERROR: $key -> $e ❌");
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
    if (_disposed) return const SizedBox.shrink();

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

      // --- Current property values ---
      final double? volume = widget.control.attrDouble("volume");
      final double? pitch = widget.control.attrDouble("pitch");
      final double? playbackRate = widget.control.attrDouble("playbackRate");
      final bool? shufflePlaylist = widget.control.attrBool("shufflePlaylist");
      final PlaylistMode? playlistMode =
          PlaylistMode.values.firstWhereOrNull((e) =>
              e.name.toLowerCase() ==
              widget.control.attrString("playlistMode")?.toLowerCase());
      final bool fullscreen = widget.control.attrBool("fullscreen", false)!;

      // --- Previous property values ---
      final double? prevVolume = widget.control.state["volume"];
      final double? prevPitch = widget.control.state["pitch"];
      final double? prevPlaybackRate = widget.control.state["playbackRate"];
      final bool? prevShufflePlaylist =
          widget.control.state["shufflePlaylist"];
      final PlaylistMode? prevPlaylistMode =
          widget.control.state["playlistMode"];
      final SubtitleTrack? prevSubtitleTrack =
          widget.control.state["subtitleTrack"];
      final bool prevFullscreen =
          widget.control.state["fullscreen"] ?? false;

      // --- Apply property changes ---
      () async {
        if (_disposed) return;

        if (volume != null &&
            volume != prevVolume &&
            volume >= 0 &&
            volume <= 100) {
          widget.control.state["volume"] = volume;
          await player.setVolume(volume);
          debugPrint("Video.setVolume($volume)");
        }

        if (pitch != null && pitch != prevPitch) {
          widget.control.state["pitch"] = pitch;
          await player.setPitch(pitch);
          debugPrint("Video.setPitch($pitch)");
        }

        if (playbackRate != null && playbackRate != prevPlaybackRate) {
          widget.control.state["playbackRate"] = playbackRate;
          await player.setRate(playbackRate);
          debugPrint("Video.setRate($playbackRate)");
        }

        if (shufflePlaylist != null &&
            shufflePlaylist != prevShufflePlaylist) {
          widget.control.state["shufflePlaylist"] = shufflePlaylist;
          await player.setShuffle(shufflePlaylist);
          debugPrint("Video.setShuffle($shufflePlaylist)");
        }

        if (playlistMode != null && playlistMode != prevPlaylistMode) {
          widget.control.state["playlistMode"] = playlistMode;
          await player.setPlaylistMode(playlistMode);
          debugPrint("Video.setPlaylistMode($playlistMode)");
        }

        if (subtitleTrack != null && subtitleTrack != prevSubtitleTrack) {
          widget.control.state["subtitleTrack"] = subtitleTrack;
          await player.setSubtitleTrack(subtitleTrack);
          debugPrint("Video.setSubtitleTrack($subtitleTrack)");
        }

        // --- Fullscreen toggle ---
        if (fullscreen != prevFullscreen) {
          widget.control.state["fullscreen"] = fullscreen;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_disposed) return;
            final state = _videoKey.currentState;
            if (state == null) return;
            fullscreen ? state.enterFullscreen() : state.exitFullscreen();
          });
        }
      }();

      // --- Build Video widget ---
      final video = Video(
        key: _videoKey,
        controller: controller,
        wakelock: widget.control.attrBool("wakelock", true)!,
        controls: widget.control.attrBool("showControls", true)!
            ? AdaptiveVideoControls
            : null,
        pauseUponEnteringBackgroundMode:
            widget.control.attrBool("pauseUponEnteringBackgroundMode", true)!,
        resumeUponEnteringForegroundMode: widget.control
            .attrBool("resumeUponEnteringForegroundMode", false)!,
        fit: parseBoxFit(widget.control.attrString("fit"), BoxFit.contain)!,
        alignment:
            parseAlignment(widget.control, "alignment", Alignment.center)!,
        filterQuality: filterQuality,
        subtitleViewConfiguration:
            subtitleConfig?["subtitleViewConfiguration"] ??
                const SubtitleViewConfiguration(),
        fill: parseColor(Theme.of(context),
                widget.control.attrString("fillColor", "")!) ??
            const Color(0xFF000000),
        // ✅ fixed - no extra }, 
        onEnterFullscreen: () async {
          _trigger("enter_fullscreen", "");
          await defaultEnterNativeFullscreen();
        },
        onExitFullscreen: () async {
          _trigger("exit_fullscreen", "");
          await defaultExitNativeFullscreen();
        },
      );

      return constrainedControl(
          context, video, widget.parent, widget.control);
    });
  }
}
