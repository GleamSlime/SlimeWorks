enum UserRole {
  /// 创造者
  creator,

  /// 管理员
  admin,

  /// 编辑者
  editor,

  /// 游客/未登录
  guest,

  /// 开发角色
  developer,
}

enum Permission {
  viewDashboard,
  manageUsers,
  editContent,
  accessSettings,
  manageModules,
  accessCapture,
  accessNovelLibrary,
  accessGameLibrary,
  accessNovelReader,
  accessThemePreview,
  accessHttpBridgeTest,
  accessWebSocketTest,
  accessCollection,
  accessDemo,
  accessPicAcg,
  accessTools,
  accessSentryLog,
  accessAliyunDdns,
}

class RoleManager {
  static UserRole currentUserRole = UserRole.creator;

  static final Map<UserRole, List<Permission>> rolePermissions = {
    UserRole.creator: Permission.values,
    UserRole.admin: [
      Permission.viewDashboard,
      Permission.manageUsers,
      Permission.editContent,
      Permission.accessSettings,
      Permission.manageModules,
      Permission.accessCapture,
      Permission.accessNovelLibrary,
      Permission.accessGameLibrary,
      Permission.accessNovelReader,
      Permission.accessThemePreview,
      Permission.accessHttpBridgeTest,
      Permission.accessWebSocketTest,
      Permission.accessPicAcg,
      Permission.accessTools,
      Permission.accessSentryLog,
      Permission.accessAliyunDdns,
    ],
    UserRole.editor: [
      Permission.viewDashboard,
      Permission.editContent,
      Permission.accessNovelLibrary,
      Permission.accessNovelReader,
      Permission.accessGameLibrary,
      Permission.accessPicAcg,
    ],
    UserRole.guest: [Permission.viewDashboard],
    UserRole.developer: Permission.values,
  };

  static bool hasPermission(UserRole role, Permission permission) {
    return rolePermissions[role]?.contains(permission) ?? false;
  }

  static List<Permission> getPermissionsForRole(UserRole role) {
    return rolePermissions[role] ?? [];
  }

  /// 检查当前用户是否有访问指定权限
  static bool canAccess(Permission permission) {
    return hasPermission(currentUserRole, permission);
  }

  /// 设置当前用户角色
  static void setUserRole(UserRole role) {
    currentUserRole = role;
  }
}
