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

  late final playerConfig = PlayerConfiguration(
    title: widget.control.attrString("title", "Flet Video")!,
    muted: widget.control.attrBool("muted", false)!,
    pitch: widget.control.attrDouble("pitch") != null ? true : false,
    ready: () {
      if (widget.control.attrBool("onLoaded", false)!) {
        widget.backend.triggerControlEvent(widget.control.id, "loaded");
      }
    },
  );

  late final Player player = Player(
    configuration: playerConfig,
  );

  late final videoControllerConfiguration = parseControllerConfiguration(
      widget.control, "configuration", const VideoControllerConfiguration())!;

  late final controller =
      VideoController(player, configuration: videoControllerConfiguration);

  Future<void> _applyMpvProperties() async {
    final cfgRaw = widget.control.attrString("configuration", null);
    if (cfgRaw == null) return;
  
    Map<String, dynamic> cfg;
    try {
      cfg = json.decode(cfgRaw);
    } catch (_) {
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
      await native.setProperty(key, valueStr);
    }
  }

  @override
  void initState() {
    super.initState();
    () async {
      await _applyMpvProperties();
      await player.open(
        Playlist(parseVideoMedia(widget.control, "playlist")),
        play: widget.control.attrBool("autoPlay", false)!,
      );
    }();
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  void _onError(String? message) {
    debugPrint("Video onError: $message");
    widget.backend
        .triggerControlEvent(widget.control.id, "error", message ?? "");
  }

  void _onCompleted(String? message) {
    debugPrint("Video onCompleted: $message");
    widget.backend
        .triggerControlEvent(widget.control.id, "completed", message ?? "");
  }

  void _onTrackChanged(String? message) {
    debugPrint("Video onTrackChanged: $message");
    widget.backend
        .triggerControlEvent(widget.control.id, "track_changed", message ?? "");
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("Video build: ${widget.control.id}");

    FilterQuality filterQuality = parseFilterQuality(
        widget.control.attrString("filterQuality"), FilterQuality.low)!;

    return withPageArgs((context, pageArgs) {
      // --- Subtitle handling ---
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
          _onError(ex.toString());
          subtitleTrack = SubtitleTrack.no();
        }
      }

      SubtitleViewConfiguration? subtitleViewConfiguration =
          subtitleConfiguration?["subtitleViewConfiguration"];

      // --- Event flags ---
      bool onError = widget.control.attrBool("onError", false)!;
      bool onCompleted = widget.control.attrBool("onCompleted", false)!;
      bool onTrackChanged = widget.control.attrBool("onTrackChanged", false)!;

      // --- Current values ---
      double? volume = widget.control.attrDouble("volume");
      double? pitch = widget.control.attrDouble("pitch");
      double? playbackRate = widget.control.attrDouble("playbackRate");
      bool? shufflePlaylist = widget.control.attrBool("shufflePlaylist");
      bool showControls = widget.control.attrBool("showControls", true)!;
      PlaylistMode? playlistMode = PlaylistMode.values.firstWhereOrNull((e) =>
          e.name.toLowerCase() ==
          widget.control.attrString("playlistMode")?.toLowerCase());
      var fullscreen = widget.control.attrBool("fullscreen", false)!;

      // --- Previous values ---
      final double? prevVolume = widget.control.state["volume"];
      final double? prevPitch = widget.control.state["pitch"];
      final double? prevPlaybackRate = widget.control.state["playbackRate"];
      final bool? prevShufflePlaylist = widget.control.state["shufflePlaylist"];
      final PlaylistMode? prevPlaylistMode =
          widget.control.state["playlistMode"];
      final SubtitleTrack? prevSubtitleTrack =
          widget.control.state["subtitleTrack"];
      final bool prevFullscreen = widget.control.state["fullscreen"] ?? false;

      // --- Build Video widget ---
      Video video = Video(
        key: _videoKey,
        controller: controller,
        wakelock: widget.control.attrBool("wakelock", true)!,
        controls: showControls ? AdaptiveVideoControls : null,
        pauseUponEnteringBackgroundMode:
            widget.control.attrBool("pauseUponEnteringBackgroundMode", true)!,
        resumeUponEnteringForegroundMode:
            widget.control.attrBool("resumeUponEnteringForegroundMode", false)!,
        alignment:
            parseAlignment(widget.control, "alignment", Alignment.center)!,
        fit: parseBoxFit(widget.control.attrString("fit"), BoxFit.contain)!,
        filterQuality: filterQuality,
        subtitleViewConfiguration:
            subtitleViewConfiguration ?? const SubtitleViewConfiguration(),
        fill: parseColor(Theme.of(context),
                widget.control.attrString("fillColor", "")!) ??
            const Color(0xFF000000),
        onEnterFullscreen: () async {
          widget.control.state["fullscreen"] = true;
          if (widget.control.attrBool("onEnterFullscreen", false)!) {
            widget.backend.triggerControlEvent(
                widget.control.id, "enter_fullscreen", "");
          }
          await defaultEnterNativeFullscreen();
        },
        onExitFullscreen: () async {
          widget.control.state["fullscreen"] = false;
          if (widget.control.attrBool("onExitFullscreen", false)!) {
            widget.backend.triggerControlEvent(
                widget.control.id, "exit_fullscreen", "");
          }
          await defaultExitNativeFullscreen();
        },
      );

      // --- Apply property changes ---
      () async {
        if (volume != null &&
            volume != prevVolume &&
            volume >= 0 &&
            volume <= 100) {
          widget.control.state["volume"] = volume;
          debugPrint("Video.setVolume($volume)");
          await player.setVolume(volume);
        }

        if (pitch != null && pitch != prevPitch) {
          widget.control.state["pitch"] = pitch;
          debugPrint("Video.setPitch($pitch)");
          await player.setPitch(pitch);
        }

        if (playbackRate != null && playbackRate != prevPlaybackRate) {
          widget.control.state["playbackRate"] = playbackRate;
          debugPrint("Video.setPlaybackRate($playbackRate)");
          await player.setRate(playbackRate);
        }

        if (shufflePlaylist != null && shufflePlaylist != prevShufflePlaylist) {
          widget.control.state["shufflePlaylist"] = shufflePlaylist;
          debugPrint("Video.setShufflePlaylist($shufflePlaylist)");
          await player.setShuffle(shufflePlaylist);
        }

        if (playlistMode != null && playlistMode != prevPlaylistMode) {
          widget.control.state["playlistMode"] = playlistMode;
          debugPrint("Video.setPlaylistMode($playlistMode)");
          await player.setPlaylistMode(playlistMode);
        }

        if (subtitleTrack != null && subtitleTrack != prevSubtitleTrack) {
          widget.control.state["subtitleTrack"] = subtitleTrack;
          debugPrint("Video.setSubtitleTrack($subtitleTrack)");
          await player.setSubtitleTrack(subtitleTrack);
        }

        // --- Fullscreen toggle ---
        if (fullscreen != prevFullscreen) {
          widget.control.state["fullscreen"] = fullscreen;
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

        // --- Method subscriptions ---
        widget.backend.subscribeMethods(widget.control.id,
            (methodName, args) async {
          switch (methodName) {
            case "play":
              debugPrint("Video.play($hashCode)");
              await player.play();
              break;
            case "pause":
              debugPrint("Video.pause($hashCode)");
              await player.pause();
              break;
            case "play_or_pause":
              debugPrint("Video.playOrPause($hashCode)");
              await player.playOrPause();
              break;
            case "stop":
              debugPrint("Video.stop($hashCode)");
              await player.stop();
              await player.open(
                Playlist(parseVideoMedia(widget.control, "playlist")),
                play: false,
              );
              break;
            case "seek":
              debugPrint("Video.seek($hashCode)");
              await player.seek(Duration(
                  milliseconds: int.tryParse(args["position"] ?? "") ?? 0));
              break;
            case "next":
              debugPrint("Video.next($hashCode)");
              await player.next();
              break;
            case "previous":
              debugPrint("Video.previous($hashCode)");
              await player.previous();
              break;
            case "jump_to":
              debugPrint("Video.jump($hashCode)");
              await player.jump(parseInt(args["media_index"], 0)!);
              break;
            case "playlist_add":
              debugPrint("Video.add($hashCode)");
              Map<String, dynamic> extras =
                  json.decode(args["extras"]!.replaceAll("'", "\""));
              Map<String, String> httpHeaders = (json.decode(
                          args["http_headers"]!.replaceAll("'", "\"")) as Map)
                  .map((key, value) =>
                      MapEntry(key.toString(), value.toString()));
              await player.add(Media(
                args["resource"]!,
                extras: extras.isNotEmpty ? extras : null,
                httpHeaders: httpHeaders.isNotEmpty ? httpHeaders : null,
              ));
              break;
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
          }
          return null;
        });
      }();

      // --- Stream listeners ---
      player.stream.error.listen((event) {
        if (onError) _onError(event.toString());
      });

      player.stream.completed.listen((event) {
        if (onCompleted) _onCompleted(event.toString());
      });

      player.stream.playlist.listen((event) {
        if (onTrackChanged) _onTrackChanged(event.index.toString());
      });

      return constrainedControl(
          context, video, widget.parent, widget.control);
    });
  }
}
