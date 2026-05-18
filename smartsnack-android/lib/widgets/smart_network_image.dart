import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'web_network_image_stub.dart'
    if (dart.library.html) 'web_network_image_web.dart';

class SmartNetworkImage extends StatefulWidget {
  const SmartNetworkImage({
    super.key,
    required this.imageUrl,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.fallbackAsset = 'assets/images/dummyproduct.png',
    this.borderRadius = 0,
  });

  final String imageUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final String fallbackAsset;
  final double borderRadius;

  @override
  State<SmartNetworkImage> createState() => _SmartNetworkImageState();
}

class _SmartNetworkImageState extends State<SmartNetworkImage> {
  late List<String> _candidates;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _candidates = _buildCandidates(widget.imageUrl);
  }

  @override
  void didUpdateWidget(covariant SmartNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _candidates = _buildCandidates(widget.imageUrl);
      _index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget imageChild;

    if (_candidates.isEmpty) {
      imageChild = Image.asset(widget.fallbackAsset, fit: widget.fit);
    } else if (kIsWeb) {
      imageChild = buildWebNetworkImage(
        url: _candidates[_index],
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        fallbackAsset: widget.fallbackAsset,
        borderRadius: 0,
      );
    } else {
      imageChild = Image.network(
        _candidates[_index],
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (_, __, ___) {
          if (_index + 1 < _candidates.length) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _index += 1);
            });
            return const SizedBox.shrink();
          }
          return Image.asset(widget.fallbackAsset, fit: widget.fit);
        },
      );
    }

    if (widget.borderRadius <= 0 || kIsWeb) {
      return SizedBox(width: widget.width, height: widget.height, child: imageChild);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: SizedBox(width: widget.width, height: widget.height, child: imageChild),
    );
  }

  List<String> _buildCandidates(String rawUrl) {
    final raw = rawUrl.trim();
    if (raw.isEmpty) return <String>[];

    final result = <String>[];

    void add(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      if (!result.contains(trimmed)) {
        result.add(trimmed);
      }
    }

    add(raw);

    final rawUri = Uri.tryParse(raw);
    final base = Uri.base;

    if (rawUri != null && rawUri.hasScheme) {
      if (!kIsWeb && (rawUri.host == '127.0.0.1' || rawUri.host == 'localhost')) {
        add(rawUri.replace(host: '10.0.2.2').toString());
      }
    } else if (raw.startsWith('/')) {
      add(base.resolve(raw).toString());
    } else if (raw.startsWith('storage/')) {
      add(base.resolve('/$raw').toString());
    }

    return result;
  }
}
