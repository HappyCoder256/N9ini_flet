import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flet/flet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// import 'utils/video.dart';

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

class _VideoControlState extends State<VideoControl>
    with WidgetsBindingObserver {
  late Player _player;
  late VideoController _controller;

  bool _initialized = false;
  bool _fullscreen = false;
  bool _disposed = false;

  // Property caching
  double? _volume;
  double? _pitch;
  double? _playbackRate;
  bool? _shufflePlaylist;
  // PlaylistMode? _playlistMode;
  dynamic _playlist;

  // Event subscriptions
  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<Playlist>? _playlistSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;

  // Position tracking
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  Timer? _positionTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  @override
  void didUpdateWidget(VideoControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.control != widget.control) {
      _teardown();
      _setup();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _teardown();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (parseBool(
          widget.control.attrString("pause_upon_entering_background_mode"),
          true)!) {
        _player.pause();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (parseBool(
          widget.control.attrString("resume_upon_entering_foreground_mode"),
          false)!) {
        _player.play();
      }
    }
  }

  void _setup() {
    try {
      // Create player
      _player = Player();

      // Create controller
      _controller = VideoController(_player);

      // Setup subscriptions
      _setupSubscriptions();

      // Load playlist
      _updatePlaylist();

      _initialized = true;

      // Trigger load event
      _trigger("load", true);
    } catch (e) {
      debugPrint("VideoControl setup error: $e");
      _trigger("error", e.toString());
    }
  }

  void _teardown() {
    try {
      _positionTimer?.cancel();
      _errorSub?.cancel();
      _completedSub?.cancel();
      _playlistSub?.cancel();
      _positionSub?.cancel();
      _durationSub?.cancel();

      _player.dispose();

      _initialized = false;
    } catch (e) {
      debugPrint("VideoControl teardown error: $e");
    }
  }

  void _setupSubscriptions() {
    // Error events
    _errorSub = _player.stream.error.listen((error) {
      if (!_disposed) {
        _trigger("error", error.toString());
      }
    });

    // Completion events
    _completedSub = _player.stream.completed.listen((completed) {
      if (!_disposed) {
        _trigger("complete", completed);
      }
    });

    // Playlist changes
    _playlistSub = _player.stream.playlist.listen((playlist) {
      if (!_disposed) {
        _trigger("playlist_change", playlist.medias.length);
      }
    });

    // Position updates
    _positionSub = _player.stream.position.listen((position) {
      if (!_disposed) {
        _currentPosition = position;
        _trigger("position_changed", position.inMilliseconds);
      }
    });

    // Duration updates
    _durationSub = _player.stream.duration.listen((duration) {
      if (!_disposed) {
        _totalDuration = duration;
        _trigger("duration_changed", duration.inMilliseconds);
      }
    });

    // Fallback timer for reliable position updates
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!_disposed && mounted) {
        _currentPosition = _player.state.position;
        _totalDuration = _player.state.duration;
      }
    });
  }

  Future<void> _updatePlaylist() async {
    try {
      final playlistAttr = widget.control.attrString("playlist");
      if (playlistAttr == null || playlistAttr.isEmpty) return;

      List<Media> newPlaylist = [];

      try {
        final parsed = jsonDecode(playlistAttr);
        if (parsed is List) {
          for (var item in parsed) {
            if (item is Map && item.containsKey("src")) {
              newPlaylist.add(Media(item["src"].toString()));
            } else if (item is String) {
              newPlaylist.add(Media(item));
            }
          }
        } else if (parsed is String) {
          newPlaylist.add(Media(parsed));
        }
      } catch (e) {
        // Fallback: treat as direct URL/path
        newPlaylist.add(Media(playlistAttr));
      }

      if (newPlaylist.isEmpty) return;

      // Optimize: detect if only item was added
      if (_playlist != null && _playlist is List<Media>) {
        final oldList = _playlist as List<Media>;

        if (newPlaylist.length == oldList.length + 1 &&
            const DeepCollectionEquality()
                .equals(newPlaylist.sublist(0, oldList.length), oldList)) {
          await _player.add(newPlaylist.last);
          _playlist = newPlaylist;
          return;
        }

        // Optimize: detect if only item was removed
        if (newPlaylist.length == oldList.length - 1) {
          for (int i = 0; i < newPlaylist.length; i++) {
            if (!const DeepCollectionEquality()
                .equals(newPlaylist[i], oldList[i])) {
              await _player.remove(i);
              _playlist = newPlaylist;
              return;
            }
          }
        }
      }

      // Full reload
      final playlist = Playlist(newPlaylist);
      final autoplay =
          parseBool(widget.control.attrString("autoplay"), false) ?? false;
      await _player.open(playlist, play: autoplay);
      _playlist = newPlaylist;
    } catch (e) {
      debugPrint("Playlist update error: $e");
      _trigger("error", "Playlist: $e");
    }
  }

  Future<String> _handleInvokeMethod(String method, dynamic args) async {
    try {
      debugPrint("Method: $method, Args: $args");

      switch (method) {
        case "play":
          await _player.play();
          return "true";

        case "pause":
          await _player.pause();
          return "true";

        case "play_or_pause":
          if (_player.state.playing) {
            await _player.pause();
          } else {
            await _player.play();
          }
          return "true";

        case "stop":
          await _player.stop();
          return "true";

        case "seek":
          final value = args;
          if (value is num) {
            await _player.seek(Duration(milliseconds: value.toInt()));
          }
          return "true";

        case "next":
          await _player.next();
          return "true";

        case "previous":
          await _player.previous();
          return "true";

        case "jump_to":
          final index = parseInt(args);
          if (index != null) {
            await _player.jump(index);
          }
          return "true";

        case "is_playing":
          return _player.state.playing.toString();

        case "is_completed":
          return _player.state.completed.toString();

        case "get_duration":
          return jsonEncode({
            "milliseconds": _totalDuration.inMilliseconds,
            "seconds": _totalDuration.inSeconds,
          });

        case "get_current_position":
          return jsonEncode({
            "milliseconds": _currentPosition.inMilliseconds,
            "seconds": _currentPosition.inSeconds,
          });

        default:
          debugPrint("Unknown method: $method");
          return "";
      }
    } catch (e) {
      debugPrint("Method error: $e");
      _trigger("error", e.toString());
      return "";
    }
  }

  Future<void> _applyProperties() async {
    if (!_initialized || _disposed) return;

    try {
      // Volume
      final volume = widget.control.attrDouble("volume");
      if (volume != null && volume != _volume) {
        await _player.setVolume(volume);
        _volume = volume;
      }

      // Pitch
      final pitch = widget.control.attrDouble("pitch");
      if (pitch != null && pitch != _pitch) {
        await _player.setPitch(pitch);
        _pitch = pitch;
      }

      // Playback rate
      final rate = widget.control.attrDouble("playbackRate");
      if (rate != null && rate != _playbackRate) {
        await _player.setRate(rate);
        _playbackRate = rate;
      }

      // Shuffle
      final shuffle = widget.control.attrBool("shufflePlaylist");
      if (shuffle != null && shuffle != _shufflePlaylist) {
        await _player.setShuffle(shuffle);
        _shufflePlaylist = shuffle;
      }

      // Muted
      final muted = widget.control.attrBool("muted") ?? false;
      if (muted) {
        await _player.setVolume(0);
      } else if (volume != null) {
        await _player.setVolume(volume);
      }
    } catch (e) {
      debugPrint("Property apply error: $e");
    }
  }

  void _trigger(String event, [dynamic data]) {
    if (_disposed) return;

    try {
      widget.backend.triggerControlEvent(
        widget.control.id,
        event,
        data,
      );
    } catch (e) {
      debugPrint("Event trigger error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // Register method handler
    widget.backend.subscribeMethods(
      widget.control.id,
      (method, args) async {
        await _handleInvokeMethod(method, args);
        return null;
      },
    );

    if (_initialized) {
      _applyProperties();
      _updatePlaylist();
    }

    final width = parseDouble(widget.control.attrString("width"));
    final height = parseDouble(widget.control.attrString("height"));
    final fillColor = parseColor(Theme.of(context),
                widget.control.attrString("fillColor", "")!) ??
            const Color(0xFF000000);

    if (!_initialized) {
      return Container(
        width: width,
        height: height,
        color: fillColor,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Handle fullscreen state changes
    final fullscreenAttr = widget.control.attrBool("fullscreen") ?? false;
    if (fullscreenAttr != _fullscreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed) return;

        if (fullscreenAttr) {
          _handleEnterFullscreen();
        } else {
          _handleExitFullscreen();
        }
      });
    }

    final showControls = widget.control.attrBool("showControls") ?? true;
    final alignment = parseAlignment(
            widget.control, "alignment", Alignment.center) ??
        Alignment.center;
    final fit = parseBoxFit(widget.control.attrString("fit"), BoxFit.contain) ??
        BoxFit.contain;

    Widget video = Video(
      controller: _controller,
      alignment: alignment,
      fit: fit,
      fill: fillColor,
      controls: showControls ? MaterialDesktopVideoControls : _noControls,
      onEnterFullscreen: _handleEnterFullscreen,
      onExitFullscreen: _handleExitFullscreen,
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

  Future<void> _handleEnterFullscreen() async {
    if (_fullscreen) return;

    _fullscreen = true;
    _trigger("enter_fullscreen");

    if (mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => _FullscreenVideoPage(
            controller: _controller,
            onExit: _handleExitFullscreen,
          ),
          fullscreenDialog: true,
        ),
      );
      _fullscreen = false;
      _trigger("exit_fullscreen");
    }
  }

  Future<void> _handleExitFullscreen() async {
    if (!_fullscreen) return;

    _fullscreen = false;
    _trigger("exit_fullscreen");

    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }
}

class _FullscreenVideoPage extends StatefulWidget {
  final VideoController controller;
  final VoidCallback onExit;

  const _FullscreenVideoPage({
    required this.controller,
    required this.onExit,
  });

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: widget.onExit,
        child: Center(
          child: Video(
            controller: widget.controller,
            controls: MaterialDesktopVideoControls,
          ),
        ),
      ),
    );
  }
}
