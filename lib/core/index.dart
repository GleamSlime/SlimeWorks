/// Core exports
///
/// 统一导出 core 模块的所有公共 API
library;

// ViewModel
export 'viewmodels/base_viewmodel.dart';
export 'viewmodels/base_page.dart';

// Theme
export 'theme/app_colors.dart';
export 'theme/app_theme.dart';
export 'theme/app_semantics.dart';
export 'theme/app_motion.dart';

// Services
export 'services/websocket_manager.dart';
export 'services/window_position_service.dart';

// Routes
export 'routes/app_routes.dart';

// Utils
export 'utils/size_utils.dart';

// 共享组件库（UI 统一的地基，新代码请优先从这里取组件，不要再手写同名实现）
export 'widgets/common_widget.dart';
export 'widgets/binding_widget.dart';
export 'widgets/app_card.dart';
export 'widgets/app_chips.dart';
export 'widgets/section_header.dart';
export 'widgets/empty_state.dart';
export 'widgets/glass_surface.dart';
export 'widgets/page_container.dart';
