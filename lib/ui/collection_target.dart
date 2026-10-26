import 'package:flutter/material.dart';
import '../data/library.dart';

/// Shared by the room and its detail route, so collection follows the actual
/// shelf entry through custom orders, safe areas and centered desktop layouts.
final _shelfAnchors = Expando<GlobalKey>();
GlobalKey shelfAnchor(Library library) =>
    _shelfAnchors[library] ??= GlobalKey(debugLabel: 'shelf-destination');

Offset? shelfDestination(Library library, OverlayState overlay) {
  final target = shelfAnchor(library).currentContext?.findRenderObject();
  final origin = overlay.context.findRenderObject();
  if (target is! RenderBox ||
      !target.attached ||
      !target.hasSize ||
      origin is! RenderBox ||
      !origin.attached) {
    return null;
  }
  return origin.globalToLocal(
    target.localToGlobal(target.size.center(Offset.zero)),
  );
}
