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

class RoleManager {
  static UserRole currentUserRole = UserRole.guest;
  static final Map<UserRole, List<Permission>> rolePermissions = {
    UserRole.creator: Permission.values,
    UserRole.admin: [Permission.viewDashboard, Permission.manageUsers, Permission.editContent, Permission.accessSettings],
    UserRole.editor: [Permission.viewDashboard, Permission.editContent],
    UserRole.guest: [Permission.viewDashboard],
  };
  static bool hasPermission(UserRole role, Permission permission) {
    return rolePermissions[role]?.contains(permission) ?? false;
  }

  static List<Permission> getPermissionsForRole(UserRole role) {
    return rolePermissions[role] ?? [];
  }
}

enum Permission { viewDashboard, manageUsers, editContent, accessSettings }
