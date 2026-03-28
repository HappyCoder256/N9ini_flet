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
  StreamSubscription<String?>? _errorSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<Playlist>? _playlistSub;
  late Player _player;
  late VideoController _controller;
  bool _initialized = false;

  Future<void> _applyMpvProperties(Control control) async {
    final cfg = control.get("configuration");
    if (cfg is! Map) return;

    final mpvPropsRaw = cfg["mpv_properties"];
    if (mpvPropsRaw is! Map) return;

    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    final native = platform as dynamic;

    for (final entry in mpvPropsRaw.entries) {
      final key = entry.key.toString();
      final val = entry.value;
      if (val == null) continue;
      final valueStr = val is bool ? (val ? "yes" : "no") : val.toString();
      await native.setProperty(key, valueStr);
    }
  }

  void _setup(Control control) {
    final playerConfig = PlayerConfiguration(
      title: control.getString("title", "flet-video")!,
      muted: control.getBool("muted", false)!,
      pitch: control.getDouble("pitch") != null,
      ready: control.hasEventHandler("load")
          ? () => control.triggerEvent("load")
          : null,
    );

    _player = Player(configuration: playerConfig);

    final videoControllerConfiguration = parseControllerConfiguration(
        control.get("configuration"),
        const VideoControllerConfiguration())!;
    _controller = VideoController(
      _player,
      configuration: videoControllerConfiguration,
    );

    _initialized = true;

    control.addInvokeMethodListener(_invokeMethod);

    if (control.getBool("on_error", false)!) {
      _errorSub = _player.stream.error.listen((message) {
        control.triggerEvent("error", message);
      });
    }

    if (control.getBool("on_complete", false)!) {
      _completedSub = _player.stream.completed.listen((completed) {
        control.triggerEvent("complete", completed);
      });
    }

    if (control.getBool("on_track_change", false)!) {
      _playlistSub = _player.stream.playlist.listen((playlist) {
        control.triggerEvent("track_change", playlist.index);
      });
    }

    final playlist = Playlist(parseVideoMedias(control.get("playlist"), [])!);
    final autoplay = control.getBool("autoplay", false)!;

    () async {
      await _applyMpvProperties(control);
      await _player.open(playlist, play: autoplay);
    }();
  }

  void _teardown(Control control) {
    if (!_initialized) return;

    control.removeInvokeMethodListener(_invokeMethod);

    _errorSub?.cancel();
    _errorSub = null;
    _completedSub?.cancel();
    _completedSub = null;
    _playlistSub?.cancel();
    _playlistSub = null;

    _player.dispose();
    _initialized = false;
  }

  Future<void> _handleEnterFullscreen() async {
    widget.control.updateProperties({"_fullscreen": true}, python: false);
    if (!widget.control.getBool("fullscreen", false)!) {
      widget.control.updateProperties({"fullscreen": true});
    }
    widget.control.triggerEvent("enter_fullscreen");
    await defaultEnterNativeFullscreen();
  }

  Future<void> _handleExitFullscreen() async {
    widget.control.updateProperties({"_fullscreen": false}, python: false);
    if (widget.control.getBool("fullscreen", false)!) {
      widget.control.updateProperties({"fullscreen": false});
    }
    widget.control.triggerEvent("exit_fullscreen");
    await defaultExitNativeFullscreen();
  }

  @override
  void initState() {
    super.initState();
    _setup(widget.control);
  }

  @override
  void didUpdateWidget(covariant VideoControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.control != widget.control) {
      _teardown(oldWidget.control);
      _videoKey = GlobalKey<VideoState>();
      _setup(widget.control);
    }
  }

  @override
  void dispose() {
    _teardown(widget.control);
    super.dispose();
  }

  Future<dynamic> _invokeMethod(String name, dynamic args) async {
    debugPrint("Video.$name($args)");
    switch (name) {
      case "play":
        await _player.play();
        break;
      case "pause":
        await _player.pause();
        break;
      case "play_or_pause":
        await _player.playOrPause();
        break;
      case "stop":
        await _player.stop();
        await _player.open(
          Playlist(parseVideoMedias(widget.control.get("playlist"), [])!),
          play: false,
        );
        break;
      case "seek":
        var position = parseDuration(args["position"]);
        if (position != null) await _player.seek(position);
        break;
      case "next":
        await _player.next();
        break;
      case "previous":
        await _player.previous();
        break;
      case "jump_to":
        final mediaIndex = parseInt(args["media_index"]);
        if (mediaIndex != null) await _player.jump(mediaIndex);
        break;
      case "playlist_add":
        // Support both old and new style args
        if (args["media"] != null) {
          var media = parseVideoMedia(args["media"]);
          if (media != null) await _player.add(media);
        } else {
          // Old style with separate resource/extras/http_headers args
          Map<String, dynamic> extras =
              json.decode(args["extras"]!.replaceAll("'", "\""));
          Map<String, String> httpHeaders =
              (json.decode(args["http_headers"]!.replaceAll("'", "\"")) as Map)
                  .map((key, value) =>
                      MapEntry(key.toString(), value.toString()));
          await _player.add(Media(
            args["resource"]!,
            extras: extras.isNotEmpty ? extras : null,
            httpHeaders: httpHeaders.isNotEmpty ? httpHeaders : null,
          ));
        }
        break;
      case "playlist_remove":
        final mediaIndex = parseInt(args["media_index"]);
        if (mediaIndex != null) await _player.remove(mediaIndex);
        break;
      case "is_playing":
        return _player.state.playing;
      case "is_completed":
        return _player.state.completed;
      case "get_duration":
        return _player.state.duration;
      case "get_current_position":
        return _player.state.position;
      default:
        throw Exception("Unknown Video method: $name");
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("Video build: ${widget.control.id}");

    return withPageArgs((context, pageArgs) {
      // --- Subtitle handling (kept from old code) ---
      SubtitleTrack? subtitleTrack;
      Map<String, dynamic>? subtitleConfiguration = parseSubtitleConfiguration(
          Theme.of(context), widget.control, "subtitleConfiguration");
      if (subtitleConfiguration?["src"] != null) {
        try {
          var assetSrc = getAssetSrc(subtitleConfiguration?["src"],
              pageArgs.pageUri!, pageArgs.assetsDir);
          subtitleTrack = parseSubtitleTrack(
            assetSrc,
            subtitleConfiguration?["title"],
            subtitleConfiguration?["language"],
          );
        } catch (ex) {
          widget.control.triggerEvent("error", ex.toString());
          subtitleTrack = SubtitleTrack.no();
        }
      }
      SubtitleViewConfiguration? subtitleViewConfiguration =
          subtitleConfiguration?["subtitleViewConfiguration"];

      // --- Current values ---
      var volume = widget.control.getDouble("volume");
      var pitch = widget.control.getDouble("pitch");
      var playbackRate = widget.control.getDouble("playback_rate");
      var shufflePlaylist = widget.control.getBool("shuffle_playlist");
      var showControls = widget.control.getBool("show_controls", true)!;
      var playlistMode =
          parsePlaylistMode(widget.control.getString("playlist_mode"));
      var fullscreen = widget.control.getBool("fullscreen", false)!;

      // --- Previous values (new style with underscore prefix) ---
      final prevVolume = widget.control.getDouble("_volume");
      final prevPitch = widget.control.getDouble("_pitch");
      final prevPlaybackRate = widget.control.getDouble("_playback_rate");
      final prevShufflePlaylist = widget.control.getBool("_shuffle_playlist");
      final PlaylistMode? prevPlaylistMode =
          widget.control.get("_playlist_mode");
      final SubtitleTrack? prevSubtitleTrack =
          widget.control.get("_subtitle_track");
      final prevFullscreen = widget.control.getBool("_fullscreen", false)!;

      // --- Build video widget ---
      Video video = Video(
        key: _videoKey,
        controller: _controller,
        wakelock: widget.control.getBool("wakelock", true)!,
        controls: showControls ? AdaptiveVideoControls : null,
        pauseUponEnteringBackgroundMode: widget.control
            .getBool("pause_upon_entering_background_mode", true)!,
        resumeUponEnteringForegroundMode: widget.control
            .getBool("resume_upon_entering_foreground_mode", false)!,
        alignment:
            widget.control.getAlignment("alignment", Alignment.center)!,
        fit: widget.control.getBoxFit("fit", BoxFit.contain)!,
        filterQuality: widget.control
            .getFilterQuality("filter_quality", FilterQuality.low)!,
        subtitleViewConfiguration:
            subtitleViewConfiguration ?? const SubtitleViewConfiguration(),
        fill: widget.control
            .getColor("fill_color", context, Colors.black)!,
        onEnterFullscreen: _handleEnterFullscreen,
        onExitFullscreen: _handleExitFullscreen,
      );

      // --- Apply property changes ---
      () async {
        if (volume != null &&
            volume != prevVolume &&
            volume >= 0 &&
            volume <= 100) {
          widget.control
              .updateProperties({"_volume": volume}, python: false);
          await _player.setVolume(volume);
        }

        if (pitch != null && pitch != prevPitch) {
          widget.control
              .updateProperties({"_pitch": pitch}, python: false);
          await _player.setPitch(pitch);
        }

        if (playbackRate != null && playbackRate != prevPlaybackRate) {
          widget.control.updateProperties(
              {"_playback_rate": playbackRate}, python: false);
          await _player.setRate(playbackRate);
        }

        if (shufflePlaylist != null &&
            shufflePlaylist != prevShufflePlaylist) {
          widget.control.updateProperties(
              {"_shuffle_playlist": shufflePlaylist}, python: false);
          await _player.setShuffle(shufflePlaylist);
        }

        if (playlistMode != null && playlistMode != prevPlaylistMode) {
          widget.control.updateProperties(
              {"_playlist_mode": playlistMode}, python: false);
          await _player.setPlaylistMode(playlistMode);
        }

        if (subtitleTrack != null && subtitleTrack != prevSubtitleTrack) {
          widget.control.updateProperties(
              {"_subtitle_track": subtitleTrack}, python: false);
          await _player.setSubtitleTrack(subtitleTrack);
        }

        if (fullscreen != prevFullscreen) {
          widget.control.updateProperties(
              {"_fullscreen": fullscreen}, python: false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final videoState = _videoKey.currentState;
            if (videoState == null) return;
            if (fullscreen) {
              videoState.enterFullscreen();
            } else {
              videoState.exitFullscreen();
            }
          });
        }
      }();

      return constrainedControl(
          context, video, widget.parent, widget.control);
    });
  }
}
