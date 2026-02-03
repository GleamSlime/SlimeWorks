enum UserRole {
  /// 创造者
  creator,

  /// 管理员
  admin,

  /// 编辑者
  editor,

  /// 游客/未登录
  guest,
}

enum Permission {
  viewDashboard,
  manageUsers,
  editContent,
  accessSettings,
  manageModules,
  accessCapture,
  accessNovelLibrary,
  accessNovelReader,
  accessThemePreview,
  accessHttpBridgeTest,
  accessWebSocketTest,
}

class RoleManager {
  static UserRole currentUserRole = UserRole.guest;

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
      Permission.accessNovelReader,
      Permission.accessThemePreview,
      Permission.accessHttpBridgeTest,
      Permission.accessWebSocketTest,
    ],
    UserRole.editor: [Permission.viewDashboard, Permission.editContent, Permission.accessNovelLibrary, Permission.accessNovelReader],
    UserRole.guest: [Permission.viewDashboard],
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
