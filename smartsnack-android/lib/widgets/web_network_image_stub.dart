import 'package:flutter/material.dart';

Widget buildWebNetworkImage({
  required String url,
  required double width,
  required double height,
  required BoxFit fit,
  required String fallbackAsset,
  required double borderRadius,
}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(borderRadius),
    child: SizedBox(
      width: width,
      height: height,
      child: Image.network(
        url,
        fit: fit,
        errorBuilder: (_, __, ___) => Image.asset(fallbackAsset, fit: fit),
      ),
    ),
  );
}

