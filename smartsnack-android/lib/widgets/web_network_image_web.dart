// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

final Map<String, String> _registeredViewTypes = <String, String>{};

Widget buildWebNetworkImage({
  required String url,
  required double width,
  required double height,
  required BoxFit fit,
  required String fallbackAsset,
  required double borderRadius,
}) {
  final src = url.trim();
  if (src.isEmpty) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: Image.asset(fallbackAsset, fit: fit),
      ),
    );
  }

  final viewType = _registeredViewTypes[src] ?? 'web-img-${src.hashCode}';
  if (!_registeredViewTypes.containsKey(src)) {
    final fallbackSrc = 'assets/$fallbackAsset';
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
      final img = html.ImageElement()
        ..src = src
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = _toCssFit(fit)
        ..style.display = 'block';
      img.onError.listen((_) {
        img.src = fallbackSrc;
      });
      return img;
    });
    _registeredViewTypes[src] = viewType;
  }

  return ClipRRect(
    borderRadius: BorderRadius.circular(borderRadius),
    child: SizedBox(
      width: width,
      height: height,
      child: HtmlElementView(viewType: viewType),
    ),
  );
}

String _toCssFit(BoxFit fit) {
  switch (fit) {
    case BoxFit.contain:
      return 'contain';
    case BoxFit.fill:
      return 'fill';
    case BoxFit.fitHeight:
    case BoxFit.fitWidth:
    case BoxFit.scaleDown:
      return 'contain';
    case BoxFit.none:
      return 'none';
    case BoxFit.cover:
    default:
      return 'cover';
  }
}
