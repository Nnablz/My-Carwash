import 'package:flutter/material.dart';

import '../models/carwash_order.dart';
import '../theme/clearwash_theme.dart';

/// High-contrast Indonesian vehicle license plate badge with optional vehicle
/// category indicator.
class LicensePlateBadge extends StatelessWidget {
  const LicensePlateBadge({
    super.key,
    required this.plate,
    this.vehicleType,
    this.compact = false,
  });

  final String plate;
  final VehicleType? vehicleType;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final normalizedPlate = plate.trim().toUpperCase();
    final displayText = normalizedPlate.isEmpty ? 'PLAT NOMOR' : normalizedPlate;
    final showType = vehicleType != null;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 5 : 8,
      ),
      decoration: BoxDecoration(
        color: ClearWashTheme.slateInk,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 0.8,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              displayText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ClearWashTheme.monoStyle(
                fontSize: compact ? 13 : 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: compact ? 0.9 : 1.3,
              ),
            ),
          ),
          if (showType) ...[
            SizedBox(width: compact ? 7 : 9),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 6 : 8,
                vertical: compact ? 2 : 3,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    vehicleType == VehicleType.mobil
                        ? Icons.directions_car_rounded
                        : Icons.two_wheeler_rounded,
                    size: compact ? 12 : 14,
                    color: const Color(0xFF64D2FF),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    vehicleType!.label.toUpperCase(),
                    style: TextStyle(
                      fontSize: compact ? 9.5 : 10.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFF2F2F7),
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
