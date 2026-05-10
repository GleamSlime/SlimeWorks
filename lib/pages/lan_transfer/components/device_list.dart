import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/services/lan_transfer_service.dart';

/// 设备列表组件
class DeviceList extends StatelessWidget {
  final List<DeviceInfo> devices;
  final DeviceInfo? selectedDevice;
  final Function(DeviceInfo) onDeviceSelected;
  final Function(DeviceInfo) onDeviceTrust;

  /// 同步判断设备是否已信任（使用已加载的 trustedDevices 列表，避免 FutureBuilder 每次重建都重置）
  final bool Function(String deviceId) isTrustedDevice;

  const DeviceList({
    super.key,
    required this.devices,
    required this.selectedDevice,
    required this.onDeviceSelected,
    required this.onDeviceTrust,
    required this.isTrustedDevice,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: devices.length,
      separatorBuilder: (context, index) => SizedBox(height: AppTheme.metrics.kSpace8),
      itemBuilder: (context, index) {
        final device = devices[index];
        final isSelected = selectedDevice?.deviceId == device.deviceId;
        final isTrusted = isTrustedDevice(device.deviceId);

        return _DeviceCard(
          device: device,
          isSelected: isSelected,
          isTrusted: isTrusted,
          onTap: () => onDeviceSelected(device),
          onTrust: () => onDeviceTrust(device),
        );
      },
    );
  }
}

/// 设备卡片
class _DeviceCard extends StatelessWidget {
  final DeviceInfo device;
  final bool isSelected;
  final bool isTrusted;
  final VoidCallback onTap;
  final VoidCallback onTrust;

  const _DeviceCard({
    required this.device,
    required this.isSelected,
    required this.isTrusted,
    required this.onTap,
    required this.onTrust,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Get.isDarkMode;
    final primaryColor = isDark ? DarkColors.primary : LightColors.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.metrics.kSpace16,
          vertical: AppTheme.metrics.kSpace12,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.12)
              : (isDark ? DarkColors.background1 : LightColors.background1),
          border: Border.all(
            color: isSelected
                ? primaryColor.withValues(alpha: 0.6)
                : (isDark ? DarkColors.white10 : LightColors.black10),
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: AppTheme.metrics.radius14,
        ),
        child: Row(
          children: [
            // 设备图标容器
            Container(
              width: scaleW(44),
              height: scaleW(44),
              decoration: BoxDecoration(
                color: isSelected
                    ? primaryColor.withValues(alpha: 0.18)
                    : (isDark ? DarkColors.white10 : LightColors.black10),
                borderRadius: AppTheme.metrics.radius12,
              ),
              child: Icon(
                _getDeviceIcon(device.deviceType),
                size: scaleW(22),
                color: isSelected
                    ? primaryColor
                    : (isDark ? DarkColors.white80 : LightColors.black80),
              ),
            ),

            SizedBox(width: AppTheme.metrics.kSpace12),

            // 设备信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          device.deviceName,
                          style: TextStyle(fontSize: AppTheme.metrics.fontSize15, height: 1.5,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? primaryColor
                                : (isDark ? DarkColors.white100 : LightColors.black100),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isTrusted) ...[
                        SizedBox(width: AppTheme.metrics.kSpace8),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppTheme.metrics.kSpace8,
                            vertical: AppTheme.metrics.kSpace2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: AppTheme.metrics.radius6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified_user, size: scaleW(10), color: isDark ? DarkColors.success : LightColors.success),
                              SizedBox(width: scaleW(3)),
                              Text('已信任', style: TextStyle(fontSize: AppTheme.metrics.fontSize11, height: 1.4, color: isDark ? DarkColors.success : LightColors.success)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: AppTheme.metrics.kSpace2),
                  Text(
                    '${device.deviceType} · ${device.ipAddress}',
                    style: TextStyle(fontSize: AppTheme.metrics.fontSize11, height: 1.4,
                      color: isDark ? DarkColors.white80 : LightColors.black80,
                    ),
                  ),
                ],
              ),
            ),

            // 操作按钮区域
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isTrusted)
                  GestureDetector(
                    onTap: onTrust,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppTheme.metrics.kSpace8,
                        vertical: AppTheme.metrics.kSpace4,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isDark ? DarkColors.white20 : LightColors.black20,
                        ),
                        borderRadius: AppTheme.metrics.radius8,
                      ),
                      child: Text(
                        '信任',
                        style: TextStyle(fontSize: AppTheme.metrics.fontSize11, height: 1.4,
                          color: isDark ? DarkColors.white80 : LightColors.black80,
                        ),
                      ),
                    ),
                  ),
                if (isSelected)
                  Padding(
                    padding: EdgeInsets.only(top: isTrusted ? 0 : AppTheme.metrics.kSpace4),
                    child: Icon(Icons.check_circle, size: scaleW(20), color: primaryColor),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getDeviceIcon(String deviceType) {
    switch (deviceType.toLowerCase()) {
      case 'ios':
      case 'iphone':
        return Icons.phone_iphone;
      case 'android':
        return Icons.phone_android;
      case 'macos':
      case 'mac':
        return Icons.laptop_mac;
      case 'windows':
        return Icons.laptop_windows;
      default:
        return Icons.devices;
    }
  }
}
