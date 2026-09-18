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

class _VideoControlState extends State<VideoControl> {
  late final PlayerConfiguration playerConfig;
  late final Player player;
  late final VideoControllerConfiguration videoControllerConfiguration;
  late final VideoController controller;

  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<Playlist>? _playlistSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;

  Playlist? _playlist;
  // bool _fullscreen = false;
  bool _disposed = false;
  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();

  Future<void>? _openFuture;

  dynamic _configurationValue() {
    final value = widget.control.attrString("configuration");

    if (value == null || value.isEmpty) {
      return null;
    }

    try {
      return jsonDecode(value);
    } catch (_) {
      return null;
    }
  }

  Future<void> _enterFullscreenProgrammatically() async {
    if (_disposed) {
      return;
    }

    final state = _videoKey.currentState;

    if (state == null || !state.mounted) {
      debugPrint("VideoState is not available");
      return;
    }

    if (state.isFullscreen()) {
      return;
    }

    await state.enterFullscreen();

    if (!_disposed) {
      // _fullscreen = true;
      widget.control.state["fullscreen"] = true;
      _trigger("enter_fullscreen");
    }
  }

  Future<void> _exitFullscreenProgrammatically() async {
    if (_disposed) {
      return;
    }

    final state = _videoKey.currentState;

    if (state == null || !state.mounted) {
      debugPrint("VideoState is not available");
      return;
    }

    if (!state.isFullscreen()) {
      return;
    }

    await state.exitFullscreen();

    if (!_disposed) {
      // _fullscreen = false;
      widget.control.state["fullscreen"] = false;
      _trigger("exit_fullscreen");
    }
  }

  Future<void> _toggleFullscreenProgrammatically() async {
    if (_disposed) {
      return;
    }

    final state = _videoKey.currentState;

    if (state == null || !state.mounted) {
      debugPrint("VideoState is not available");
      return;
    }

    await state.toggleFullscreen();

    if (!_disposed) {
      final fullscreen = state.isFullscreen();

      // _fullscreen = fullscreen;
      widget.control.state["fullscreen"] = fullscreen;

      _trigger(
        fullscreen ? "enter_fullscreen" : "exit_fullscreen",
      );
    }
  }

  Future<void> _applyMpvProperties() async {
    final configuration = _configurationValue();
    if (configuration is! Map) {
      return;
    }

    final properties = configuration["mpv_properties"];
    if (properties is! Map) {
      return;
    }

    final platform = player.platform;
    if (platform is! NativePlayer) {
      return;
    }

    for (final entry in properties.entries) {
      final key = entry.key.toString();
      final value = entry.value;

      String valueString;
      if (value is bool) {
        valueString = value ? "yes" : "no";
      } else if (value == null) {
        continue;
      } else {
        valueString = value.toString();
      }

      try {
        await platform.setProperty(key, valueString);
      } catch (e) {
        debugPrint("Failed to set MPV property '$key': $e");
      }
    }
  }

  Playlist _parsePlaylist() {
    // final raw = widget.control.attrList("playlist");
    return Playlist(
      parseVideoMedia(widget.control, "playlist"),
    );
  }

  Future<void> _openPlaylist(
    Playlist playlist, {
    required bool play,
  }) async {
    _playlist = playlist;

    await _applyMpvProperties();

    if (_disposed) {
      return;
    }

    await player.open(playlist, play: play);
  }

  Future<void> _setup() async {
    final initialPlaylist = _parsePlaylist();
    final autoplay = widget.control.attrBool("autoPlay", false)!;

    _openFuture = _openPlaylist(
      initialPlaylist,
      play: autoplay,
    );

    await _openFuture;
  }

  Future<void> _updatePlaylist() async {
    final newPlaylist = _parsePlaylist();

    if (_playlist == null) {
      final playing = player.state.playing;
      await _openPlaylist(newPlaylist, play: playing);
      return;
    }

    final oldMedias = _playlist!.medias;
    final newMedias = newPlaylist.medias;

    // Fast path for one item appended.
    if (newMedias.length == oldMedias.length + 1 &&
        const ListEquality<Media>().equals(
          newMedias.take(oldMedias.length).toList(),
          oldMedias,
        )) {
      await player.add(newMedias.last);
      _playlist = newPlaylist;
      return;
    }

    // Fast path for one item removed.
    if (newMedias.length == oldMedias.length - 1) {
      final removedIndex = oldMedias.indexed
          .where((entry) =>
              entry.$1 >= newMedias.length ||
              !const DeepCollectionEquality()
                  .equals(entry.$2, newMedias[entry.$1]))
          .map((entry) => entry.$1)
          .firstOrNull;

      if (removedIndex != null && removedIndex >= 0) {
        await player.remove(removedIndex);
        _playlist = newPlaylist;
        return;
      }
    }

    final wasPlaying = player.state.playing;
    final index = player.state.playlist.index;
    await player.open(newPlaylist, play: wasPlaying);
    _playlist = newPlaylist;

    if (index >= 0 && index < newMedias.length) {
      await player.jump(index);
    }
  }

  void _trigger(String event, [dynamic data]) {
    if (_disposed) {
      return;
    }

    widget.backend.triggerControlEvent(
      widget.control.id,
      event,
      data,
    );
  }

  void _subscribeEvents() {
    _errorSubscription = player.stream.error.listen((error) {
      _trigger("error", error);
    });

    _completedSubscription = player.stream.completed.listen((completed) {
      _trigger("completed", completed);
    });

    _playlistSubscription = player.stream.playlist.listen((playlist) {
      _trigger("playlist_changed", playlist.medias.length);
    });

    _positionSubscription = player.stream.position.listen((position) {
      widget.control.state["position"] = position.inMilliseconds;
      _trigger("position_changed", position.inMilliseconds);
    });

    _durationSubscription = player.stream.duration.listen((duration) {
      widget.control.state["duration"] = duration.inMilliseconds;
      _trigger("duration_changed", duration.inMilliseconds);
    });
  }

  Future<String> _handleInvokeMethod(String method, dynamic args) async {
    switch (method) {
      case "play":
        await player.play();
        break;

      case "pause":
        await player.pause();
        break;

      case "play_or_pause":
        await player.playOrPause();
        break;

      case "stop":
        await player.stop();
        break;

      case "seek":
        final seconds = parseDouble(args);
        if (seconds != null) {
          await player.seek(Duration(milliseconds: (seconds * 1000).round()));
        }
        break;

      case "next":
        await player.next();
        break;

      case "previous":
        await player.previous();
        break;

      case "jump_to":
        final index = parseInt(args);
        if (index != null) {
          await player.jump(index);
        }
        break;

      // case "playlist_add":
      //   final media = parseVideoMedia(args, "playlist_add");
      //   if (media != null) {
      //     await player.add(media);
      //     _playlist = Playlist([
      //       ...player.state.playlist.medias,
      //     ]);
      //   }
      //   break;

      case "playlist_remove":
        debugPrint("Video.remove($hashCode)");
        await player.remove(parseInt(args["media_index"], 0)!);
        break;
      case "is_playing":
        debugPrint("Video.isPlaying($hashCode)");
        return player.state.playing.toString();
      case "is_completed":
        debugPrint("Video.isCompleted($hashCode)");
        return player.state.completed.toString();
      case "get_duration":
        debugPrint("Video.getDuration($hashCode)");
        return player.state.duration.inMilliseconds.toString();
      case "get_current_position":
        debugPrint("Video.getCurrentPosition($hashCode)");
        return player.state.position.inMilliseconds.toString();

      case "take_screenshot":
        final path = await player.screenshot();
        _trigger("screenshot", path);
        break;
      case "enter_fullscreen":
        await _enterFullscreenProgrammatically();
        break;

      case "exit_fullscreen":
        await _exitFullscreenProgrammatically();
        break;

      case "toggle_fullscreen":
        await _toggleFullscreenProgrammatically();
        break;

      case "is_fullscreen":
        return _videoKey.currentState?.isFullscreen().toString() ?? "false";

      default:
        debugPrint("Unknown video method: $method");
        return "";
    }
    return "";
  }

  Future<void> _handleEnterFullscreen() async {
    if (_disposed) {
      return;
    }

    // _fullscreen = true;
    widget.control.state["fullscreen"] = true;

    await defaultEnterNativeFullscreen();

    if (!_disposed) {
      _trigger("enter_fullscreen");
    }
  }

  Future<void> _handleExitFullscreen() async {
    if (_disposed) {
      return;
    }

    // _fullscreen = false;
    widget.control.state["fullscreen"] = false;

    await defaultExitNativeFullscreen();

    if (!_disposed) {
      _trigger("exit_fullscreen");
    }
  }
  @override
  void initState() {
    super.initState();

    playerConfig = const PlayerConfiguration();
    player = Player(configuration: playerConfig);

    videoControllerConfiguration = const VideoControllerConfiguration();
    controller = VideoController(
      player,
      configuration: videoControllerConfiguration,
    );

    _subscribeEvents();

    widget.backend.subscribeMethods(
      widget.control.id,
      (method, args) async {
        return await _handleInvokeMethod(method, args);
      },
    );

    unawaited(_setup());
  }

  @override
  void didUpdateWidget(covariant VideoControl oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.control != widget.control) {
      unawaited(_updatePlaylist());
    }
  }

  @override
  void dispose() {
    _disposed = true;

    _errorSubscription?.cancel();
    _completedSubscription?.cancel();
    _playlistSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();

    player.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    final volume = widget.control.attrDouble("volume");
    final pitch = widget.control.attrDouble("pitch");
    final playbackRate = widget.control.attrDouble("playbackRate");

    if (volume != null) {
      player.setVolume(volume);
    }

    if (pitch != null) {
      player.setPitch(pitch);
    }

    if (playbackRate != null) {
      player.setRate(playbackRate);
    }

    final subtitleConfiguration = parseSubtitleConfiguration(
      Theme.of(context),
      widget.control,
      "subtitleConfiguration",
    );

    final subtitleTrack = parseSubtitleTrack(
      widget.control.attrString("subtitleTrack"),
      context,
    );

    if (subtitleTrack != null) {
      unawaited(player.setSubtitleTrack(subtitleTrack));
    }


    final showControls =
        widget.control.attrBool("showControls", true)!;

    final alignment =
        parseAlignment(widget.control, "alignment", Alignment.center)!;

    final fit =
        parseBoxFit(widget.control.attrString("fit"), BoxFit.contain)!;

    final fillColor = parseColor(Theme.of(context),
                widget.control.attrString("fillColor", "")!) ??
            const Color(0xFF000000);

    final wakelock =
        widget.control.attrBool("wakelock", false)!;

    // final pauseUponBackground =
    //     widget.control.attrBool("pauseUponBackground", true)!;

    // final resumeUponBackground =
    //     widget.control.attrBool("resumeUponBackground", true)!;

    // final fullscreen =
    //     widget.control.attrBool("fullscreen", false)!;

    

    Widget video = Video(
      key: _videoKey,
      controller: controller,
      alignment: alignment,
      fit: fit,
      fill: fillColor,
      wakelock: wakelock,
      // pauseUponBackground: pauseUponBackground,
      // resumeUponBackground: resumeUponBackground,
      controls: showControls
          ? _adaptiveControlsForCurrentPlatform()
          : _noControls,
      onEnterFullscreen: _handleEnterFullscreen,
      onExitFullscreen: _handleExitFullscreen,
      subtitleViewConfiguration: subtitleConfiguration,
    );


    return constrainedControl(
      context,
      video,
      widget.parent,
      widget.control,
    );
  }

  Widget Function(VideoState) get _noControls =>
      (_) => const SizedBox.shrink();

  Widget Function(VideoState) _adaptiveControlsForCurrentPlatform() {
    switch (Theme.of(context).platform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return MaterialVideoControls;
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return MaterialDesktopVideoControls;
      default:
        return _noControls;
    }
  }
}
