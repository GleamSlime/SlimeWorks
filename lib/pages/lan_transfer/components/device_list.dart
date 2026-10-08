import 'package:flutter/material.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/services/lan_transfer_service.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';

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
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.base,
        padding: EdgeInsets.symmetric(
          horizontal: m.kSpace16,
          vertical: m.kSpace12,
        ),
        decoration: BoxDecoration(
          // 选中态走"强调容器 + 其描边"，未选中走一级表面 + 常规描边
          color: isSelected ? s.accentContainer : s.surface,
          border: Border.all(
            color: isSelected ? s.accentContainerBorder : s.border,
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: m.radius14,
        ),
        child: Row(
          children: [
            // 设备图标容器
            Container(
              width: scaleW(44),
              height: scaleW(44),
              decoration: BoxDecoration(
                color: isSelected ? s.accentContainer : s.surfaceSunken,
                borderRadius: m.radius12,
              ),
              child: DrawIcon(
                _getDeviceIcon(device.deviceType),
                size: scaleW(22),
                color: isSelected ? s.accent : s.textSecondary,
              ),
            ),

            SizedBox(width: m.kSpace12),

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
                          style: AppTextStyles.role(
                            context,
                            fontSize: m.fontSize15,
                            height: 1.5,
                            weight: FontWeight.w600,
                            color: isSelected ? s.accent : s.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isTrusted) ...[
                        SizedBox(width: m.kSpace8),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: m.kSpace8,
                            vertical: m.kSpace2,
                          ),
                          decoration: BoxDecoration(
                            color: s.success.container,
                            borderRadius: m.radius6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              DrawIcon(StrokeIcons.verifiedUser, size: scaleW(10), color: s.success.color),
                              SizedBox(width: scaleW(3)),
                              Text(
                                '已信任',
                                style: AppTextStyles.role(
                                  context,
                                  fontSize: m.fontSize11,
                                  height: 1.4,
                                  color: s.success.onContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: m.kSpace2),
                  Text(
                    '${device.deviceType} · ${device.ipAddress}',
                    style: AppTextStyles.role(
                      context,
                      fontSize: m.fontSize11,
                      height: 1.4,
                      color: s.textSecondary,
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
                        horizontal: m.kSpace8,
                        vertical: m.kSpace4,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: s.border,
                        ),
                        borderRadius: m.radius8,
                      ),
                      child: Text(
                        '信任',
                        style: AppTextStyles.role(
                          context,
                          fontSize: m.fontSize11,
                          height: 1.4,
                          color: s.textSecondary,
                        ),
                      ),
                    ),
                  ),
                if (isSelected)
                  Padding(
                    padding: EdgeInsets.only(top: isTrusted ? 0 : m.kSpace4),
                    child: DrawIcon(StrokeIcons.check, size: scaleW(20), color: s.accent),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  StrokeIcon _getDeviceIcon(String deviceType) {
    switch (deviceType.toLowerCase()) {
      case 'ios':
      case 'iphone':
        return StrokeIcons.phoneIphone;
      case 'android':
        return StrokeIcons.phoneAndroid;
      case 'macos':
      case 'mac':
        return StrokeIcons.laptopMac;
      case 'windows':
        return StrokeIcons.laptopWindows;
      default:
        return StrokeIcons.devices;
    }
  }
}
