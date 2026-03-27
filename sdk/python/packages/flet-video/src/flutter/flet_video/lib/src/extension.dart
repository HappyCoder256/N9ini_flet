import 'package:flet/flet.dart';
import 'package:flutter/cupertino.dart';
import 'package:media_kit/media_kit.dart';
import 'video.dart';

class Extension extends FletExtension {
  @override
  void ensureInitialized() {
    MediaKit.ensureInitialized();
  }

  @override
  Widget? createWidget(Key? key, Control control, Control? parent,
      bool parentDisabled, bool? parentAdaptive, FletControlBackend backend) {
    switch (control.type) {
      case "Video":
        return VideoControl(
          key: key,
          parent: parent,
          control: control,
          backend: backend,
        );
      default:
        return null;
    }
  }
}
