import 'package:flutter/material.dart';

class BrandIcon extends StatelessWidget {
  const BrandIcon({this.size = 40, this.borderRadius = 10, super.key});

  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(borderRadius),
    child: Image.asset(
      'web/icons/icon-192.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      semanticLabel: '快記帳',
    ),
  );
}
