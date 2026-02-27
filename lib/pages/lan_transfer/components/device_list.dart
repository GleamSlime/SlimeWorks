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
  final Future<bool> Function(String) isTrustedDevice;

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
    final isDark = Get.isDarkMode;

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: devices.length,
      separatorBuilder: (context, index) => SizedBox(height: AppTheme.metrics.kSpace12),
      itemBuilder: (context, index) {
        final device = devices[index];
        final isSelected = selectedDevice?.deviceId == device.deviceId;

        return FutureBuilder<bool>(
          future: isTrustedDevice(device.deviceId),
          builder: (context, snapshot) {
            final isTrusted = snapshot.data ?? false;

            return _DeviceCard(
              device: device,
              isSelected: isSelected,
              isTrusted: isTrusted,
              isDark: isDark,
              onTap: () => onDeviceSelected(device),
              onTrust: () => onDeviceTrust(device),
            );
          },
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
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onTrust;

  const _DeviceCard({
    required this.device,
    required this.isSelected,
    required this.isTrusted,
    required this.isDark,
    required this.onTap,
    required this.onTrust,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                    ? DarkColors.primary.withValues(alpha: 0.2)
                    : LightColors.primary.withValues(alpha: 0.1))
              : (isDark ? DarkColors.background1 : LightColors.background1),
          border: Border.all(
            color: isSelected
                ? (isDark ? DarkColors.primary : LightColors.primary)
                : (isDark ? DarkColors.white10 : LightColors.black10),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // 设备图标
            Container(
              width: scaleW(48),
              height: scaleW(48),
              decoration: BoxDecoration(
                color: isDark ? DarkColors.white10 : LightColors.black10,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getDeviceIcon(device.deviceType),
                size: scaleW(24),
                color: isDark ? DarkColors.white80 : LightColors.black80,
              ),
            ),

            SizedBox(width: AppTheme.metrics.kSpace16),

            // 设备信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          device.deviceName,
                          style: AppTextStyles.body1(fontWeight: AppFontWeights.semiBold),
                        ),
                      ),
                      if (isTrusted)
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppTheme.metrics.kSpace8,
                            vertical: AppTheme.metrics.kSpace4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('已信任', style: AppTextStyles.caption(color: Colors.green)),
                        ),
                    ],
                  ),

                  SizedBox(height: AppTheme.metrics.kSpace4),

                  Text(
                    '${device.deviceType} • ${device.ipAddress}:${device.port}',
                    style: AppTextStyles.caption(
                      color: isDark ? DarkColors.white80 : LightColors.black80,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(width: AppTheme.metrics.kSpace16),

            // 信任按钮
            if (!isTrusted)
              IconButton(onPressed: onTrust, icon: const Icon(Icons.security), tooltip: '信任此设备'),
          ],
        ),
      ),
    );
  }

  IconData _getDeviceIcon(String deviceType) {
    switch (deviceType.toLowerCase()) {
      case 'windows':
        return Icons.computer;
      case 'macos':
        return Icons.laptop_mac;
      case 'ios':
      case 'ipad':
        return Icons.phone_iphone;
      case 'android':
        return Icons.phone_android;
      default:
        return Icons.devices;
    }
  }
}
