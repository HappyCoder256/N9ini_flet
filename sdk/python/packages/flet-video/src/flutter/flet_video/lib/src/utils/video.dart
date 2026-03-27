import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flet/flet.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import "file_utils_web.dart" if (dart.library.io) 'file_utils_io.dart';

// ✅ Kept old signature: accepts Control + key instead of raw dynamic
List<Media> parseVideoMedia(Control control, String attrName) {
  final rawJson = control.attrString(attrName, null);
  if (rawJson == null || rawJson.isEmpty) return [];

  dynamic playlist;
  try {
    playlist = jsonDecode(rawJson);
  } catch (_) {
    return [];
  }

  if (playlist is! List) return [];

  return playlist
      .map((item) => _parseSingleMedia(item))
      .whereType<Media>()
      .toList();
}

// ✅ Internal helper
Media? _parseSingleMedia(dynamic value) {
  if (value == null || value["resource"] == null) return null;

  final extras = (value["extras"] as Map?)?.map(
    (key, val) => MapEntry(key.toString(), val.toString()),
  );

  final httpHeaders = (value["http_headers"] as Map?)?.map(
    (key, val) => MapEntry(key.toString(), val.toString()),
  );

  return Media(value["resource"], extras: extras, httpHeaders: httpHeaders);
}

// ✅ Kept old signature: accepts ThemeData, Control + key
Map<String, dynamic>? parseSubtitleConfiguration(
    ThemeData theme, Control control, String attrName) {
  final rawJson = control.attrString(attrName, null);
  if (rawJson == null || rawJson.isEmpty) return null;

  // ✅ Fix: decode JSON string to Map first
  Map<String, dynamic> value;
  try {
    value = jsonDecode(rawJson);
  } catch (_) {
    return null;
  }

  // ✅ Fix: parseTextStyle in 0.28.3 takes (dynamic, ThemeData, TextStyle) — pass default as 3rd arg
  const TextStyle defaultStyle = TextStyle(
      height: 1.4,
      fontSize: 32.0,
      letterSpacing: 0.0,
      wordSpacing: 0.0,
      color: Color(0xffffffff),
      fontWeight: FontWeight.normal,
      backgroundColor: Color(0xaa000000));

  final subtitleViewConfiguration = SubtitleViewConfiguration(
    style: parseTextStyle(value["text_style"], theme, defaultStyle)!,
    visible: parseBool(value["visible"], true)!,
    textScaler: TextScaler.linear(parseDouble(value["text_scale_factor"], 1)!),
    textAlign: parseTextAlign(value["text_align"], TextAlign.center)!,
    // ✅ Fix: edgeInsetsFromJson is the correct 0.28.3 function (not parsePadding)
    padding: edgeInsetsFromJson(value["padding"]) ??
        const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 24.0),
  );

  return {
    "src": value["src"],
    "title": value["title"],
    "language": value["language"],
    "subtitleViewConfiguration": subtitleViewConfiguration,
  };
}

bool _isUrl(String value) {
  final urlPattern = RegExp(r'^(http:\/\/|https:\/\/|www\.)');
  return urlPattern.hasMatch(value);
}

// ✅ Kept old signature: accepts (assetSrc, title, language)
SubtitleTrack? parseSubtitleTrack(
    String? src, String? title, String? language) {
  if (src == null) return null;
  if (src == "none") return SubtitleTrack.no();
  if (src == "auto") return SubtitleTrack.auto();

  bool uri = false;
  String resolvedSrc = src;

  if (_isUrl(src)) {
    uri = true;
    resolvedSrc = src;
  } else {
    String? fileContents;
    if (!isWebPlatform()) {
      fileContents = readFileAsStringIfExists(src);
    }
    resolvedSrc = fileContents ?? src;
    uri = false;
  }

  return SubtitleTrack(
    resolvedSrc,
    title,
    language,
    data: !uri,
    uri: uri,
  );
}

// ✅ Kept old signature: accepts Control + key
VideoControllerConfiguration? parseControllerConfiguration(
    Control control, String attrName,
    [VideoControllerConfiguration? defaultValue]) {
  final rawJson = control.attrString(attrName, null);
  if (rawJson == null || rawJson.isEmpty) return defaultValue;

  // ✅ Fix: decode JSON string to Map first
  Map<String, dynamic> value;
  try {
    value = jsonDecode(rawJson);
  } catch (_) {
    return defaultValue;
  }

  return VideoControllerConfiguration(
    vo: value["output_driver"] as String?,
    hwdec: value["hardware_decoding_api"] as String?,
    enableHardwareAcceleration:
        parseBool(value["enable_hardware_acceleration"], true)!,
    // ✅ Fix: use parseInt/parseDouble — raw map values are dynamic, not int
    width: parseInt(value["width"]),
    height: parseInt(value["height"]),
    scale: parseDouble(value["scale"], 1.0)!,
  );
}

// ✅ Unchanged — no format dependency
PlaylistMode? parsePlaylistMode(String? value, [PlaylistMode? defaultValue]) {
  if (value == null) return defaultValue;
  return PlaylistMode.values.firstWhereOrNull(
          (e) => e.name.toLowerCase() == value.toLowerCase()) ??
      defaultValue;
}
