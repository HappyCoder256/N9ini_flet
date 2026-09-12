import 'package:flet/flet.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import "file_utils_web.dart" if (dart.library.io) 'file_utils_io.dart';

/// Empty controls builder used when controls are explicitly disabled.
Widget _noVideoControls(VideoState state) => const SizedBox.shrink();

/// Controls builder that selects the controls implementation for the current
/// platform.
Widget _adaptiveVideoControls(VideoState state) {
  switch (Theme.of(state.context).platform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return MaterialVideoControls(state);
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.linux:
      return MaterialDesktopVideoControls(state);
    default:
      return _noVideoControls(state);
  }
}

Media? parseVideoMedia(dynamic value, FletBackend backend,
    [Media? defaultValue]) {
  if (value == null || value["resource"] == null) return defaultValue;

  final extras = (value["extras"] as Map?)?.map(
    (key, val) => MapEntry(key.toString(), val.toString()),
  );

  final httpHeaders = (value["http_headers"] as Map?)?.map(
    (key, val) => MapEntry(key.toString(), val.toString()),
  );

  // Resolve relative paths against assets_dir / page URI, matching how
  // every other Flet media control handles `src`. media_kit's Media()
  // accepts both URLs and absolute filesystem paths, so a single
  // resolved string works for both web and native backends.
  final resource = backend.getAssetSource(value["resource"] as String).path;

  return Media(resource, extras: extras, httpHeaders: httpHeaders);
}

List<Media>? parseVideoMedias(dynamic value, FletBackend backend,
    [List<Media>? defaultValue]) {
  if (value == null) return defaultValue;

  if (value is List) {
    return value.map((e) => parseVideoMedia(e, backend)).nonNulls.toList();
  }

  final media = parseVideoMedia(value, backend);
  return media != null ? [media] : defaultValue;
}

SubtitleViewConfiguration? parseSubtitleConfiguration(
    dynamic value, ThemeData theme,
    [SubtitleViewConfiguration? defaultValue]) {
  if (value == null) return defaultValue;

  return SubtitleViewConfiguration(
    style: parseTextStyle(
        value["text_style"],
        theme,
        const TextStyle(
            height: 1.4,
            fontSize: 32.0,
            letterSpacing: 0.0,
            wordSpacing: 0.0,
            color: Color(0xffffffff),
            fontWeight: FontWeight.normal,
            backgroundColor: Color(0xaa000000)))!,
    visible: parseBool(value["visible"], true)!,
    textScaler: TextScaler.linear(parseDouble(value["text_scale_factor"], 1)!),
    textAlign: parseTextAlign(value["text_align"], TextAlign.center)!,
    padding: parsePadding(
        value["padding"], const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 24.0))!,
  );
}

bool isUrl(String value) {
  final urlPattern = RegExp(r'^(http:\/\/|https:\/\/|www\.)');
  return urlPattern.hasMatch(value);
}

SubtitleTrack? parseSubtitleTrack(
  dynamic value,
  BuildContext context, [
  SubtitleTrack? defaultValue,
]) {
  if (value == null) return defaultValue;

  String src;
  final String rawSrc = value["src"] as String;
  if (rawSrc == "none") return SubtitleTrack.no();
  if (rawSrc == "auto") return SubtitleTrack.auto();

  bool uri = false;

  if (isUrl(rawSrc)) {
    uri = true;
    src = rawSrc;
  } else {
    // Non-URL: on non-web platforms, try reading it as a file path
    String? fileContents;
    if (!isWebPlatform()) {
      // todo: add support for relative paths to assets-dir
      fileContents = readFileAsStringIfExists(rawSrc);
    }

    // If reading succeeded, use the file's contents;
    // otherwise assume rawSrc is already subtitle text
    src = fileContents ?? rawSrc;
    uri = false;
  }

  return SubtitleTrack(
    src,
    value["title"],
    value["language"],
    channelscount: parseInt(value["channels_count"]),
    channels: value["channels"],
    samplerate: parseInt(value["sample_rate"]),
    fps: parseDouble(value["fps"]),
    bitrate: parseInt(value["bitrate"]),
    rotate: parseInt(value["rotate"]),
    par: parseDouble(value["par"]),
    audiochannels: parseInt(value["audio_channels"]),
    albumart: parseBool(value["album_art"]),
    codec: value["codec"],
    decoder: value["decoder"],
    data: !uri,
    // true when providing raw subtitle text
    uri: uri, // true when providing a URL
  );
}

VideoControllerConfiguration? parseControllerConfiguration(dynamic value,
    [VideoControllerConfiguration? defaultValue]) {
  if (value == null) return defaultValue;
  return VideoControllerConfiguration(
    vo: value["output_driver"],
    hwdec: value["hardware_decoding_api"],
    enableHardwareAcceleration:
        parseBool(value["enable_hardware_acceleration"], true)!,
    width: value["width"],
    height: value["height"],
    scale: parseDouble(value["scale"], 1.0)!,
  );
}

List<int> parseVideoControlsIntList(dynamic value, List<int> defaultValue) {
  if (value == null) return defaultValue;
  if (value is List) {
    final result = value.map((e) => parseInt(e)).nonNulls.toList();
    return result.isNotEmpty ? result : defaultValue;
  }
  return defaultValue;
}

Widget? parseVideoControlsBarItem(
    dynamic value, ThemeData theme, bool materialDesktop) {
  final controlWidget = parseControlWidget(value);
  if (controlWidget != null) return controlWidget;
  if (value is! Map) return null;

  final icon = parseControlWidget(value["icon"]);
  final iconSize = parseDouble(value["icon_size"]);
  final iconColor = parseColor(value["icon_color"], theme);

  switch (value["_type"]) {
    case "playOrPauseButton":
      return materialDesktop
          ? MaterialDesktopPlayOrPauseButton(
              iconSize: iconSize,
              iconColor: iconColor,
            )
          : MaterialPlayOrPauseButton(
              iconSize: iconSize,
              iconColor: iconColor,
            );
    case "skipNextButton":
      return materialDesktop
          ? MaterialDesktopSkipNextButton(
              icon: icon,
              iconSize: iconSize,
              iconColor: iconColor,
            )
          : MaterialSkipNextButton(
              icon: icon,
              iconSize: iconSize,
              iconColor: iconColor,
            );
    case "skipPreviousButton":
      return materialDesktop
          ? MaterialDesktopSkipPreviousButton(
              icon: icon,
              iconSize: iconSize,
              iconColor: iconColor,
            )
          : MaterialSkipPreviousButton(
              icon: icon,
              iconSize: iconSize,
              iconColor: iconColor,
            );
    case "fullscreenButton":
      return materialDesktop
          ? MaterialDesktopFullscreenButton(
              icon: icon,
              iconSize: iconSize,
              iconColor: iconColor,
            )
          : MaterialFullscreenButton(
              icon: icon,
              iconSize: iconSize,
              iconColor: iconColor,
            );
    case "seekBar":
      return materialDesktop
          ? MaterialDesktopSeekBar()
          : MaterialSeekBar();
    case "volumeButton":
      return MaterialVolumeButton(
        iconSize: iconSize,
        iconColor: iconColor,
      );
    default:
      return null;
  }
}

VideoControlsBar? parseVideoControlsBar(
    dynamic value, ThemeData theme, bool materialDesktop) {
  if (value == null) return null;
  if (value is! Map) return null;

  final height = parseDouble(value["height"]);
  final padding = parsePadding(value["padding"]);
  final margin = parsePadding(value["margin"]);
  final alignment = parseAlignment(value["alignment"]);

  final itemsRaw = value["items"];
  final items = itemsRaw is List
      ? itemsRaw
          .map((item) => parseVideoControlsBarItem(item, theme, materialDesktop))
          .nonNulls
          .toList()
      : null;

  final overflowButtonIcon = parseControlWidget(value["overflow_button_icon"]);
  final overflowButtonIconSize =
      parseDouble(value["overflow_button_icon_size"]);
  final overflowButtonIconColor =
      parseColor(value["overflow_button_icon_color"], theme);

  return VideoControlsBar(
    height: height,
    padding: padding,
    margin: margin,
    alignment: alignment,
    items: items,
    overflowButtonIcon: overflowButtonIcon,
    overflowButtonIconSize: overflowButtonIconSize,
    overflowButtonIconColor: overflowButtonIconColor,
  );
}

MaterialVideoControlsThemeData parseMaterialVideoControlsThemeData(
    dynamic value, ThemeData theme) {
  value ??= const {};
  return MaterialVideoControlsThemeData(
    // behavior
    displaySeekBar: parseBool(value["display_seek_bar"], true)!,
    automaticallyImplySkipNextButton:
        parseBool(value["automatically_imply_skip_next_button"], true)!,
    automaticallyImplySkipPreviousButton:
        parseBool(value["automatically_imply_skip_previous_button"], true)!,
    modifyVolumeOnScroll: parseBool(value["modify_volume_on_scroll"], false)!,
    toggleFullscreenOnDoublePress:
        parseBool(value["toggle_fullscreen_on_double_press"], true)!,
    hideMouseOnControlsRemoval:
        parseBool(value["hide_mouse_on_controls_removal"], false)!,
    playAndPauseOnTap: parseBool(value["play_and_pause_on_tap"], true)!,
    visibleOnMount: parseBool(value["visible_on_mount"], true)!,
    // generic
    padding: parsePadding(value["padding"]),
    controlsHoverDuration: parseDuration(
        value["controls_hover_duration"], const Duration(seconds: 3))!,
    controlsTransitionDuration: parseDuration(
        value["controls_transition_duration"],
        const Duration(milliseconds: 150))!,
    // button bar
    primaryButtonBar:
        parseVideoControlsBar(value["primary_button_bar"], theme, false) ??
            kDefaultMaterialVideoControlsThemeData.primaryButtonBar,
    bottomButtonBar:
        parseVideoControlsBar(value["bottom_button_bar"], theme, false) ??
            kDefaultMaterialVideoControlsThemeData.bottomButtonBar,
    bottomButtonBarMargin: parsePadding(value["bottom_button_bar_margin"],
        const EdgeInsets.symmetric(horizontal: 16.0))!,
    buttonBarHeight: parseDouble(value["button_bar_height"], 56.0)!,
    buttonBarButtonSize: parseDouble(value["button_bar_button_size"], 24.0)!,
    buttonBarButtonColor: parseColor(
        value["button_bar_button_color"], theme, const Color(0xFFFFFFFF))!,
    // seek bar
    seekBarContainerHeight:
        parseDouble(value["seek_bar_container_height"], 36.0)!,
    seekBarMargin: parsePadding(value["seek_bar_margin"],
        const EdgeInsets.symmetric(horizontal: 16.0))!,
    seekBarHeight: parseDouble(value["seek_bar_height"], 3.2)!,
    seekBarColor:
        parseColor(value["seek_bar_color"], theme, const Color(0x3DFFFFFF))!,
    seekBarPositionColor: parseColor(
        value["seek_bar_position_color"], theme, const Color(0xFFFF0000))!,
    seekBarBufferColor: parseColor(
        value["seek_bar_buffer_color"], theme, const Color(0x3DFFFFFF))!,
    seekBarThumbSize: parseDouble(value["seek_bar_thumb_size"], 12.0)!,
    seekBarThumbColor: parseColor(
        value["seek_bar_thumb_color"], theme, const Color(0xFFFF0000))!,
    // subtitle
    shiftSubtitlesOnControlsVisibilityChange: parseBool(
        value["shift_subtitles_on_controls_visibility_change"], false)!,
  );
}

MaterialDesktopVideoControlsThemeData
    parseMaterialDesktopVideoControlsThemeData(dynamic value, ThemeData theme) {
  value ??= const {};
  return MaterialDesktopVideoControlsThemeData(
    // behavior
    displaySeekBar: parseBool(value["display_seek_bar"], true)!,
    automaticallyImplySkipNextButton:
        parseBool(value["automatically_imply_skip_next_button"], true)!,
    automaticallyImplySkipPreviousButton:
        parseBool(value["automatically_imply_skip_previous_button"], true)!,
    modifyVolumeOnScroll: parseBool(value["modify_volume_on_scroll"], true)!,
    toggleFullscreenOnDoublePress:
        parseBool(value["toggle_fullscreen_on_double_press"], true)!,
    hideMouseOnControlsRemoval:
        parseBool(value["hide_mouse_on_controls_removal"], false)!,
    playAndPauseOnTap: parseBool(value["play_and_pause_on_tap"], false)!,
    visibleOnMount: parseBool(value["visible_on_mount"], false)!,
    // generic
    padding: parsePadding(value["padding"]),
    controlsHoverDuration: parseDuration(
        value["controls_hover_duration"], const Duration(seconds: 3))!,
    controlsTransitionDuration: parseDuration(
        value["controls_transition_duration"],
        const Duration(milliseconds: 150))!,
    // button bar
    primaryButtonBar:
        parseVideoControlsBar(value["primary_button_bar"], theme, true) ??
            kDefaultMaterialDesktopVideoControlsThemeData.primaryButtonBar,
    topButtonBar: parseVideoControlsBar(value["top_button_bar"], theme, true) ??
        kDefaultMaterialDesktopVideoControlsThemeData.topButtonBar,
    topButtonBarMargin: parsePadding(value["top_button_bar_margin"],
        const EdgeInsets.symmetric(horizontal: 16.0))!,
    bottomButtonBar:
        parseVideoControlsBar(value["bottom_button_bar"], theme, true) ??
            kDefaultMaterialDesktopVideoControlsThemeData.bottomButtonBar,
    bottomButtonBarMargin: parsePadding(value["bottom_button_bar_margin"],
        const EdgeInsets.symmetric(horizontal: 16.0))!,
    buttonBarHeight: parseDouble(value["button_bar_height"], 56.0)!,
    buttonBarButtonSize: parseDouble(value["button_bar_button_size"], 28.0)!,
    buttonBarButtonColor: parseColor(
        value["button_bar_button_color"], theme, const Color(0xFFFFFFFF))!,
    // seek bar
    seekBarTransitionDuration: parseDuration(
        value["seek_bar_transition_duration"],
        const Duration(milliseconds: 300))!,
    seekBarThumbTransitionDuration: parseDuration(
        value["seek_bar_thumb_transition_duration"],
        const Duration(milliseconds: 150))!,
    seekBarMargin: parsePadding(value["seek_bar_margin"],
        const EdgeInsets.symmetric(horizontal: 16.0))!,
    seekBarHeight: parseDouble(value["seek_bar_height"], 3.2)!,
    seekBarHoverHeight: parseDouble(value["seek_bar_hover_height"], 5.6)!,
    seekBarContainerHeight:
        parseDouble(value["seek_bar_container_height"], 36.0)!,
    seekBarColor:
        parseColor(value["seek_bar_color"], theme, const Color(0x3DFFFFFF))!,
    seekBarHoverColor: parseColor(
        value["seek_bar_hover_color"], theme, const Color(0x3DFFFFFF))!,
    seekBarPositionColor: parseColor(
        value["seek_bar_position_color"], theme, const Color(0xFFFF0000))!,
    seekBarBufferColor: parseColor(
        value["seek_bar_buffer_color"], theme, const Color(0x3DFFFFFF))!,
    seekBarThumbSize: parseDouble(value["seek_bar_thumb_size"], 12.0)!,
    seekBarThumbColor: parseColor(
        value["seek_bar_thumb_color"], theme, const Color(0xFFFF0000))!,
    // volume bar
    volumeBarColor:
        parseColor(value["volume_bar_color"], theme, const Color(0x3DFFFFFF))!,
    volumeBarActiveColor: parseColor(
        value["volume_bar_active_color"], theme, const Color(0xFFFFFFFF))!,
    volumeBarThumbSize: parseDouble(value["volume_bar_thumb_size"], 12.0)!,
    volumeBarThumbColor: parseColor(
        value["volume_bar_thumb_color"], theme, const Color(0xFFFFFFFF))!,
    volumeBarTransitionDuration: parseDuration(
        value["volume_bar_transition_duration"],
        const Duration(milliseconds: 150))!,
    // subtitle
    shiftSubtitlesOnControlsVisibilityChange: parseBool(
        value["shift_subtitles_on_controls_visibility_change"], true)!,
  );
}

bool _isVideoControlsModeMap(dynamic value) {
  if (value is! Map) return false;
  if (value.containsKey("_type")) return false;
  return value.keys.every(
      (key) => key == "normal" || key == "fullscreen" || key == "default");
}

dynamic _resolveVideoControlsMode(dynamic value, bool fullscreen) {
  if (!_isVideoControlsModeMap(value)) return value;

  if (fullscreen) {
    if (value.containsKey("fullscreen")) return value["fullscreen"];
  }
  if (value.containsKey("normal")) return value["normal"];
  if (value.containsKey("default")) return value["default"];
  return null;
}

Widget Function(VideoState) _customVideoControls(dynamic value) {
  return (_) => parseControlWidget(value) ?? const SizedBox.shrink();
}

/// Selects the controls builder requested by the serialized controls value.
Widget Function(VideoState)? parseVideoControls(dynamic value) {
  if (_isVideoControlsModeMap(value)) {
    return (state) {
      final modeValue =
          _resolveVideoControlsMode(value, isFullscreen(state.context));
      final controls = parseVideoControls(modeValue);
      return controls?.call(state) ?? const SizedBox.shrink();
    };
  }

  if (value is Control) {
    return _customVideoControls(value);
  }

  if (value == null) return _noVideoControls;

  switch (value["_type"]) {
    case "adaptive":
      return _adaptiveVideoControls;
    case "material":
      return MaterialVideoControls;
    case "materialDesktop":
      return MaterialDesktopVideoControls;
    default:
      return _adaptiveVideoControls;
  }
}

/// Wraps the video with the theme provider required by the selected built-in
/// controls implementation.
Widget wrapVideoControlsTheme(Widget child, dynamic value, ThemeData theme) {
  if (_isVideoControlsModeMap(value)) {
    final normal = _resolveVideoControlsMode(value, false);
    final fullscreen = _resolveVideoControlsMode(value, true);
    return MaterialVideoControlsTheme(
      normal: parseMaterialVideoControlsThemeData(
          _materialVideoControlsThemeValue(normal), theme),
      fullscreen: parseMaterialVideoControlsThemeData(
          _materialVideoControlsThemeValue(fullscreen), theme),
      child: MaterialDesktopVideoControlsTheme(
        normal: parseMaterialDesktopVideoControlsThemeData(
            _materialDesktopVideoControlsThemeValue(normal), theme),
        fullscreen: parseMaterialDesktopVideoControlsThemeData(
            _materialDesktopVideoControlsThemeValue(fullscreen), theme),
        child: child,
      ),
    );
  }

  if (value == null || value is Control) return child;

  switch (value["_type"]) {
    case "adaptive":
      final material = value["material"];
      final materialDesktop = value["material_desktop"];
      return MaterialVideoControlsTheme(
        normal: parseMaterialVideoControlsThemeData(material, theme),
        fullscreen: parseMaterialVideoControlsThemeData(material, theme),
        child: MaterialDesktopVideoControlsTheme(
          normal: parseMaterialDesktopVideoControlsThemeData(
              materialDesktop, theme),
          fullscreen: parseMaterialDesktopVideoControlsThemeData(
              materialDesktop, theme),
          child: child,
        ),
      );
    case "material":
      return MaterialVideoControlsTheme(
        normal: parseMaterialVideoControlsThemeData(value, theme),
        fullscreen: parseMaterialVideoControlsThemeData(value, theme),
        child: child,
      );
    case "materialDesktop":
      return MaterialDesktopVideoControlsTheme(
        normal: parseMaterialDesktopVideoControlsThemeData(value, theme),
        fullscreen: parseMaterialDesktopVideoControlsThemeData(value, theme),
        child: child,
      );
    default:
      return child;
  }
}

dynamic _materialVideoControlsThemeValue(dynamic value) {
  if (value is! Map) return null;
  if (value["_type"] == "material") return value;
  if (value["_type"] == "adaptive") return value["material"];
  return null;
}

dynamic _materialDesktopVideoControlsThemeValue(dynamic value) {
  if (value is! Map) return null;
  if (value["_type"] == "materialDesktop") return value;
  if (value["_type"] == "adaptive") return value["material_desktop"];
  return null;
}

PlaylistMode? parsePlaylistMode(String? value, [PlaylistMode? defaultValue]) {
  return parseEnum(PlaylistMode.values, value, defaultValue);
}
