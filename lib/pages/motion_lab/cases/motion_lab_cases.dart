import 'package:flutter/material.dart';

import 'case_01_card_resize.dart';
import 'case_02_number_pop_in.dart';
import 'case_03_notification_badge.dart';
import 'case_04_text_states_swap.dart';
import 'case_05_menu_dropdown.dart';
import 'case_06_confetti_burst.dart';
import 'case_07_modal_open_close.dart';
import 'case_08_panel_reveal.dart';
import 'case_09_gooey_plus_menu.dart';
import 'case_10_page_side_by_side.dart';
import 'case_11_icon_swap.dart';
import 'case_12_success_check.dart';
import 'case_13_avatar_group_hover.dart';
import 'case_14_card_stack_hover.dart';
import 'case_15_error_state_shake.dart';
import 'case_16_input_clear_with_dissolve.dart';
import 'case_17_skeleton_loader_and_reveal.dart';
import 'case_18_texts_reveal.dart';
import 'case_19_tabs_sliding.dart';
import 'case_20_drag_drop_with_physics.dart';
import 'case_21_shimmer_text.dart';
import 'case_22_organic_shimmer.dart';
import 'case_23_tooltip_open_close.dart';
import 'case_24_3d_tilt.dart';
import 'case_25_dropdown_menu_morph.dart';
import 'case_26_accordion.dart';
import 'case_27_toast_open_close.dart';
import 'case_28_like_button.dart';
import 'case_29_image_open_tilt.dart';
import 'case_30_learn_more_hover.dart';
import 'case_31_checkbox_check.dart';
import 'case_32_spinner_to_check_morph.dart';
import 'case_33_spinning_counter.dart';
import 'case_34_toggle_double_bounce.dart';
import 'case_35_pro_gradient_text.dart';
import 'case_36_delete_with_smoky_dissolve.dart';
import 'case_37_thinking_states.dart';
import 'case_38_reasoning_stream.dart';
import 'case_39_streaming_text.dart';
import 'case_40_matrix_dot_loader.dart';
import 'case_41_banner_stacking.dart';
import 'case_42_image_generation_placeholder.dart';
import 'case_43_get_pro_button.dart';

/// 分类：只用于这张页面上的筛选，不参与任何全局配置
enum LabCat {
  essential('基础'),
  texts('文本'),
  effects('效果'),
  ai('AI');

  const LabCat(this.label);

  final String label;
}

/// 一格案例
@immutable
class LabCase {
  const LabCase({
    required this.seq,
    required this.title,
    required this.subtitle,
    required this.cat,
    required this.build,
    this.pro = false,
  });

  final int seq;
  final String title;
  final String subtitle;
  final LabCat cat;
  final Widget Function() build;

  /// 参考稿里标 Pro 的那些：配方代码没公开，参数和外观按首页的演示复刻
  final bool pro;
}

/// 43 格，顺序和参考稿首页一致
final List<LabCase> kLabCases = <LabCase>[
  LabCase(
    seq: 1,
    title: 'Card resize',
    subtitle: 'Smooth card resize transition',
    cat: LabCat.essential,
    build: Case01CardResize.new,
  ),
  LabCase(
    seq: 2,
    title: 'Number pop-in',
    subtitle: 'Digit flip with blur and stagger',
    cat: LabCat.texts,
    build: Case02NumberPopIn.new,
  ),
  LabCase(
    seq: 3,
    title: 'Notification badge',
    subtitle: 'Diagonal slide with spring pop-in',
    cat: LabCat.essential,
    build: Case03NotificationBadge.new,
  ),
  LabCase(
    seq: 4,
    title: 'Text states swap',
    subtitle: 'Text swap transition with blur',
    cat: LabCat.essential,
    build: Case04TextStatesSwap.new,
  ),
  LabCase(
    seq: 5,
    title: 'Menu dropdown',
    subtitle: 'Origin-aware open / close transition',
    cat: LabCat.essential,
    build: Case05MenuDropdown.new,
  ),
  LabCase(
    seq: 6,
    title: 'Confetti burst',
    subtitle: 'Physics confetti lands on the button',
    cat: LabCat.effects,
    pro: true,
    build: Case06ConfettiBurst.new,
  ),
  LabCase(
    seq: 7,
    title: 'Modal open/close',
    subtitle: 'Modal transition with scale',
    cat: LabCat.essential,
    build: Case07ModalOpenClose.new,
  ),
  LabCase(
    seq: 8,
    title: 'Panel reveal',
    subtitle: 'Panel open / close transition',
    cat: LabCat.essential,
    build: Case08PanelReveal.new,
  ),
  LabCase(
    seq: 9,
    title: 'Gooey plus menu',
    subtitle: 'Liquid split into a fan of actions',
    cat: LabCat.effects,
    pro: true,
    build: Case09GooeyPlusMenu.new,
  ),
  LabCase(
    seq: 10,
    title: 'Page side-by-side',
    subtitle: 'Forward / back page transition',
    cat: LabCat.essential,
    build: Case10PageSideBySide.new,
  ),
  LabCase(
    seq: 11,
    title: 'Icon swap',
    subtitle: 'Scale and blur icon swap',
    cat: LabCat.essential,
    build: Case11IconSwap.new,
  ),
  LabCase(
    seq: 12,
    title: 'Success check',
    subtitle: 'Success check with blur and rotate',
    cat: LabCat.essential,
    build: Case12SuccessCheck.new,
  ),
  LabCase(
    seq: 13,
    title: 'Avatar group hover',
    subtitle: 'Distance-falloff lift with bouncy return',
    cat: LabCat.effects,
    build: Case13AvatarGroupHover.new,
  ),
  LabCase(
    seq: 14,
    title: 'Card stack hover',
    subtitle: 'Stack fans out with a spring on hover',
    cat: LabCat.effects,
    pro: true,
    build: Case14CardStackHover.new,
  ),
  LabCase(
    seq: 15,
    title: 'Error state shake',
    subtitle: 'Cubic-bezier shake on error',
    cat: LabCat.essential,
    build: Case15ErrorStateShake.new,
  ),
  LabCase(
    seq: 16,
    title: 'Input clear with dissolve',
    subtitle: 'Clear with per-word dissolve',
    cat: LabCat.effects,
    build: Case16InputClearWithDissolve.new,
  ),
  LabCase(
    seq: 17,
    title: 'Skeleton loader and reveal',
    subtitle: 'Pulse to content cross-fade',
    cat: LabCat.essential,
    build: Case17SkeletonLoaderAndReveal.new,
  ),
  LabCase(
    seq: 18,
    title: 'Texts reveal',
    subtitle: 'Two lines rise with offset stagger',
    cat: LabCat.texts,
    build: Case18TextsReveal.new,
  ),
  LabCase(
    seq: 19,
    title: 'Tabs sliding',
    subtitle: 'Pill indicator follows the active tab',
    cat: LabCat.essential,
    build: Case19TabsSliding.new,
  ),
  LabCase(
    seq: 20,
    title: 'Drag & drop with physics',
    subtitle: 'Zone morphs into the image',
    cat: LabCat.effects,
    pro: true,
    build: Case20DragDropWithPhysics.new,
  ),
  LabCase(
    seq: 21,
    title: 'Shimmer text',
    subtitle: 'Masked gradient sweep across text',
    cat: LabCat.texts,
    build: Case21ShimmerText.new,
  ),
  LabCase(
    seq: 22,
    title: 'Organic shimmer',
    subtitle: 'Wavy shimmer with edge glow',
    cat: LabCat.effects,
    pro: true,
    build: Case22OrganicShimmer.new,
  ),
  LabCase(
    seq: 23,
    title: 'Tooltip open/close',
    subtitle: 'Delayed in, travels, instant out',
    cat: LabCat.essential,
    build: Case23TooltipOpenClose.new,
  ),
  LabCase(
    seq: 24,
    title: '3D tilt',
    subtitle: '3D pointer tilt with cursor glare',
    cat: LabCat.effects,
    build: Case24Tilt3D.new,
  ),
  LabCase(
    seq: 25,
    title: 'Dropdown menu morph',
    subtitle: 'Button morphs into a menu surface',
    cat: LabCat.essential,
    build: Case25DropdownMenuMorph.new,
  ),
  LabCase(
    seq: 26,
    title: 'Accordion',
    subtitle: 'Grid-rows height with chevron morph',
    cat: LabCat.essential,
    build: Case26Accordion.new,
  ),
  LabCase(
    seq: 27,
    title: 'Toast open/close',
    subtitle: 'Rises in with fade, blur and scale',
    cat: LabCat.essential,
    build: Case27ToastOpenClose.new,
  ),
  LabCase(
    seq: 28,
    title: 'Like button',
    subtitle: 'Heart fills and bursts particles',
    cat: LabCat.effects,
    build: Case28LikeButton.new,
  ),
  LabCase(
    seq: 29,
    title: 'Image open tilt',
    subtitle: 'Zoom with 3D tilt and bend',
    cat: LabCat.effects,
    pro: true,
    build: Case29ImageOpenTilt.new,
  ),
  LabCase(
    seq: 30,
    title: 'Learn more hover',
    subtitle: 'Chevron shifts and opens on hover',
    cat: LabCat.essential,
    build: Case30LearnMoreHover.new,
  ),
  LabCase(
    seq: 31,
    title: 'Checkbox check',
    subtitle: 'Check draws on with a stroke path',
    cat: LabCat.essential,
    build: Case31CheckboxCheck.new,
  ),
  LabCase(
    seq: 32,
    title: 'Spinner to check morph',
    subtitle: 'Spinner pops into a drawn check',
    cat: LabCat.ai,
    pro: true,
    build: Case32SpinnerToCheckMorph.new,
  ),
  LabCase(
    seq: 33,
    title: 'Spinning counter',
    subtitle: 'Digits spin like a reel to the value',
    cat: LabCat.texts,
    build: Case33SpinningCounter.new,
  ),
  LabCase(
    seq: 34,
    title: 'Toggle',
    subtitle: 'Thumb slides with a double bounce',
    cat: LabCat.essential,
    build: Case34ToggleDoubleBounce.new,
  ),
  LabCase(
    seq: 35,
    title: 'Pro gradient text',
    subtitle: 'Colour washes orbit the letters',
    cat: LabCat.texts,
    pro: true,
    build: Case35ProGradientText.new,
  ),
  LabCase(
    seq: 36,
    title: 'Delete with smoky dissolve',
    subtitle: 'Image shreds and falls into smoke',
    cat: LabCat.effects,
    pro: true,
    build: Case36DeleteWithSmokyDissolve.new,
  ),
  LabCase(
    seq: 37,
    title: 'Thinking states',
    subtitle: 'Status line shimmers, then swaps to the next',
    cat: LabCat.ai,
    build: Case37ThinkingStates.new,
  ),
  LabCase(
    seq: 38,
    title: 'Reasoning stream',
    subtitle: 'Agent reasoning scrolls by two lines',
    cat: LabCat.ai,
    build: Case38ReasoningStream.new,
  ),
  LabCase(
    seq: 39,
    title: 'Streaming text',
    subtitle: 'Words resolve through a soft cross-blur',
    cat: LabCat.ai,
    build: Case39StreamingText.new,
  ),
  LabCase(
    seq: 40,
    title: 'Matrix dot loader',
    subtitle: '16-dot matrix pulses in four patterns',
    cat: LabCat.ai,
    build: Case40MatrixDotLoader.new,
  ),
  LabCase(
    seq: 41,
    title: 'Banner stacking',
    subtitle: 'Banners stack like toasts, three deep',
    cat: LabCat.essential,
    build: Case41BannerStacking.new,
  ),
  LabCase(
    seq: 42,
    title: 'Image generation placeholder',
    subtitle: 'Dot noise wakes, then resolves into the image',
    cat: LabCat.ai,
    pro: true,
    build: Case42ImageGenerationPlaceholder.new,
  ),
  LabCase(
    seq: 43,
    title: 'Get Pro button',
    subtitle: 'Pro gradient glows in from the pill’s rim',
    cat: LabCat.effects,
    pro: true,
    build: Case43GetProButton.new,
  ),
];
