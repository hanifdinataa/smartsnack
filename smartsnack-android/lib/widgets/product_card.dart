import 'package:flutter/material.dart';

import '../models/api_models.dart';
import 'grade_badge.dart';
import 'smart_network_image.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.showSecondaryInfo = true,
    this.action,
    this.gradeOverride,
  });

  final ProductItem product;
  final VoidCallback onTap;
  final bool showSecondaryInfo;
  final Widget? action;
  final String? gradeOverride;

  @override
  Widget build(BuildContext context) {
    // ─── OLD build ───
    // return Card(margin: const EdgeInsets.symmetric(vertical: 6),
    //   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    //   child: InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap,
    //     child: Padding(padding: const EdgeInsets.all(12), child: Row(...))));
    // ─── NEW build ───
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x06000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 68,
                      height: 68,
                      child: SmartNetworkImage(
                        imageUrl: product.image,
                        width: 68,
                        height: 68,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFF111827),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sugar: ${product.grSugarContent.toStringAsFixed(2)} gram',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      if (showSecondaryInfo && product.netWeight.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            product.netWeight,
                            style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                          ),
                        ),
                      if (showSecondaryInfo && product.amountConsumed.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            product.amountConsumed,
                            style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    GradeBadge(grade: _resolveGrade(product)),
                    if (action != null) ...[
                      const SizedBox(height: 8),
                      action!,
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _resolveGrade(ProductItem item) {
    if (gradeOverride != null && gradeOverride!.trim().isNotEmpty) {
      return gradeOverride!;
    }
    if (item.sugarGrade.trim().isNotEmpty && item.sugarGrade != '-') {
      return item.sugarGrade;
    }
    final sugar = item.grSugarContent;
    final netWeight = double.tryParse(item.netWeight.toString()) ?? 0;
    if (sugar < 0 || netWeight <= 0) return '-';
    final per100 = (sugar / netWeight) * 100;
    if (per100 < 2.5) return 'Hijau';
    if (per100 <= 11.25) return 'Kuning';
    return 'Merah';
  }
}
