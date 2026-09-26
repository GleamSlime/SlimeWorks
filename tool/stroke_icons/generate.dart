// 描边图标生成器：把 Tabler outline 的笔画几何按映射表裁剪成 Dart 常量。
//
// 为什么构建期生成而不是直接引三方图标包：
// 1. icon font 的字形是填充轮廓，没有笔画中心线，做不了真正的 draw-on；
// 2. assets 目录是整体拷贝，放进 svg 目录的图标无论用没用到都会进包；
// 3. 只有 codegen 能做到"未引用的图标不进产物"。
//
// 用法：
//   dart run tool/stroke_icons/generate.dart          # 重新生成
//   dart run tool/stroke_icons/generate.dart --check   # 只校验 lib 里的引用是否都有映射
import 'dart:convert';
import 'dart:io';

const _dataDir = 'tool/stroke_icons/data';
const _outFile = 'lib/components/icons/stroke_icons.g.dart';
const _fixtureFile = 'test/fixtures/stroke_icons_all.dart';
const _libDir = 'lib';

/// 不走 Tabler、直接吃项目 svg 资产的图形。
///
/// 品牌标记那种自绘资产本来就在 assets 里，手抄 45 条 d 字符串必然和资产漂移；
/// 让生成器去读资产，SVG 仍然是唯一来源。
const _svgMarks = [
  (alias: 'brandMark', name: 'brand-mark', file: 'assets/image/svg/top_bar_logo.svg'),
];

/// Material 图标名的风格后缀，归一化时剥掉（Tabler 只有一种笔画风格）
final _styleSuffix = RegExp(r'_(rounded|outlined|sharp|circle|twotone)$');

void main(List<String> args) {
  final checkOnly = args.contains('--check');
  final map = _loadJson('$_dataDir/icon_map.json');
  final tabler = _loadJson('$_dataDir/tabler-nodes-outline.json');

  final material = Map<String, String>.from(map['material'] as Map);
  final asset = Map<String, String>.from(map['asset'] as Map);

  final missing = <String>[];
  for (final section in {'material': material, 'asset': asset}.entries) {
    for (final entry in section.value.entries) {
      if (!tabler.containsKey(entry.value)) {
        stderr.writeln('✗ ${section.key} ${entry.key} -> "${entry.value}" 在 Tabler 里不存在');
        missing.add(entry.value);
      }
    }
  }

  if (checkOnly) {
    final unresolved = _scanUnresolved(material);
    if (unresolved.isNotEmpty) {
      stderr.writeln('✗ lib 里这些 Icons.* 没有映射，补 icon_map.json 后重跑：');
      for (final n in unresolved) {
        stderr.writeln('    "$n": "<tabler-name>",');
      }
      exit(1);
    }
    stdout.writeln('✓ 映射完整（${material.length} 条 Material + ${asset.length} 条 asset）');
    return;
  }
  if (missing.isNotEmpty) exit(1);

  final source = _emit(material, asset, tabler);
  File(_outFile).writeAsStringSync(source);
  final used = {
    ...material.values,
    ...asset.values,
  };
  // 测试专用清单：把 335 个别名全引一遍，用来做几何校验与出图册。
  // 它只在 test/ 下被引用，不进 app 产物，所以不会破坏"未引用不进包"。
  File(_fixtureFile).createSync(recursive: true);
  File(_fixtureFile).writeAsStringSync(_emitFixture(material, asset));
  final svgNote = _svgMarks.isEmpty ? '' : ' + ${_svgMarks.length} 个 svg 资产几何';
  stdout.writeln('✓ 已生成 $_outFile：${used.length} 个 Tabler 图标几何$svgNote，'
      '${material.length + asset.length + _svgMarks.length} 个别名');
}

Map<String, dynamic> _loadJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// 扫 lib，找出没有映射的 Material 图标名（供 --check 提示补表）
///
/// 必须带词边界：`StrokeIcons.foo` 里也含子串 `Icons.foo`，不加边界会把
/// 生成物自己的每一根别名报成未解析，`--check` 永远红。
List<String> _scanUnresolved(Map<String, String> material) {
  final pattern = RegExp(r'\bIcons\.([a-zA-Z0-9_]+)');
  final found = <String>{};
  for (final entity in Directory(_libDir).listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    for (final m in pattern.allMatches(entity.readAsStringSync())) {
      found.add(normalize(m.group(1)!));
    }
  }
  return found.difference(material.keys.toSet()).toList()..sort();
}

/// `delete_outline_rounded` -> `delete_outline` -> `deleteOutline`
String normalize(String materialName) =>
    materialName.replaceAll(_styleSuffix, '');

String camel(String snake) {
  final parts = snake.split(RegExp(r'[_\-]')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return snake;
  return parts.first.toLowerCase() +
      parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
}

String _emit(
  Map<String, String> material,
  Map<String, String> asset,
  Map<String, dynamic> tabler,
) {
  final byTabler = (material.values.toList()..addAll(asset.values)).toSet().toList()
    ..sort();
  final buffer = StringBuffer()
    ..writeln('''// GENERATED — 由 tool/stroke_icons/generate.dart 生成，请勿手改。
// 改图标只改 tool/stroke_icons/data/icon_map.json，然后重跑生成器。
// 几何来源：Tabler outline（MIT），笔画为 24x24 viewBox 的中心线路径；
// 少数品牌标记类图形直接读自项目的 svg 资产，viewBox 跟着资产走。
import 'stroke_geometry.dart';''');

  for (final name in byTabler) {
    final nodes = tabler[name] as List;
    buffer.writeln();
    buffer.writeln('/// ${_commentFor(name, material, asset)}');
    buffer.writeln('const StrokeIcon _\$${camel(name)} = StrokeIcon(');
    buffer.writeln("  name: '$name',");
    buffer.writeln('  paths: [');
    for (final node in nodes) {
      final attrs = (node as List)[1] as Map<String, dynamic>;
      final d = (attrs['d'] as String).replaceAll("'", r"\'");
      final solid = attrs['fill'] == 'currentColor';
      buffer.writeln(solid
          ? "    StrokePath.filled('$d'),"
          : "    StrokePath('$d'),");
    }
    buffer.writeln('  ],');
    buffer.writeln(');');
  }

  for (final mark in _svgMarks) {
    final geometry = _readSvgMark(mark.file);
    buffer.writeln();
    buffer.writeln('/// ${mark.name}：直接读自 ${mark.file}，viewBox ${geometry.viewBox}');
    buffer.writeln('const StrokeIcon _\$${mark.alias} = StrokeIcon(');
    buffer.writeln("  name: '${mark.name}',");
    buffer.writeln('  viewBox: ${geometry.viewBox},');
    buffer.writeln('  paths: [');
    for (final (d, solid) in geometry.paths) {
      final escaped = d.replaceAll("'", r"\'");
      buffer.writeln(solid
          ? "    StrokePath.filled('$escaped'),"
          : "    StrokePath('$escaped'),");
    }
    buffer.writeln('  ],');
    buffer.writeln(');');
  }

  buffer.writeln();
  buffer.writeln('/// 项目里用到的描边图标集合，替代 `Icons.*` 与自绘 svg 资产。');
  buffer.writeln('abstract final class StrokeIcons {');
  final aliasKeys = _aliasKeys(material, asset);
  for (final entry in (aliasKeys.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key)))) {
    buffer.writeln('  static const StrokeIcon ${entry.key} = _\$${camel(entry.value)};');
  }
  for (final mark in _svgMarks) {
    buffer.writeln('  static const StrokeIcon ${mark.alias} = _\$${mark.alias};');
  }
  buffer.writeln('}');
  return buffer.toString();
}

/// 从项目 svg 资产里裁出描边几何
///
/// 只认 `<path>`：rect/circle 那些图元没有 d 字符串，`computeMetrics` 拿不到中心线。
/// 笔顺按文档顺序，也就是设计师在矢量软件里的叠放顺序，读起来是对的。
({double viewBox, List<(String d, bool solid)> paths}) _readSvgMark(String file) {
  final source = File(file).readAsStringSync();
  final viewBoxMatch = RegExp(r'viewBox="[\d.\s-]+"').firstMatch(source);
  final box = viewBoxMatch == null
      ? 24.0
      : double.parse(viewBoxMatch.group(0)!.split('"')[1].trim().split(RegExp(r'\s+'))[2]);
  final paths = <(String, bool)>[];
  for (final m in RegExp(r'<path\b[^>]*>').allMatches(source)) {
    final tag = m.group(0)!;
    final d = RegExp(r'\bd="([^"]*)"').firstMatch(tag)?.group(1);
    if (d == null || d.isEmpty) continue;
    // 根节点写的是 fill="none"，没带 fill 属性的 path 继承它，就是纯描边；
    // 只有显式的实色 fill（眼睛、刻度点那种小块）才是描不出来的实心块
    final fill = RegExp(r'\bfill="([^"]*)"').firstMatch(tag)?.group(1);
    final solid = fill != null && fill != 'none' && fill != 'white';
    paths.add((d, solid));
  }
  return (viewBox: box, paths: paths);
}

/// 生成物里每个几何常量的注释：它服务哪些调用名（便于回查为什么留这个图标）
String _commentFor(String tablerName, Map<String, String> material, Map<String, String> asset) {
  final from = <String>[
    ...material.entries.where((e) => e.value == tablerName).map((e) => e.key),
    ...asset.entries.where((e) => e.value == tablerName).map((e) => 'asset:${e.key}'),
  ];
  if (from.length == 1) return from.single;
  if (from.length <= 4) return '用于 ${from.join(' / ')}';
  return '用于 ${from.take(3).join(' / ')} 等 ${from.length} 处';
}

/// Dart 侧常量名 -> Tabler 图标名。asset 那批加 `Asset` 前缀，避免与 Material 撞名
Map<String, String> _aliasKeys(
  Map<String, String> material,
  Map<String, String> asset,
) {
  final keys = <String, String>{};
  for (final entry in material.entries) {
    keys[camel(entry.key)] = entry.value;
  }
  for (final entry in asset.entries) {
    final name = camel(entry.key);
    keys['asset${name[0].toUpperCase()}${name.substring(1)}'] = entry.value;
  }
  return keys;
}

/// 测试用的全量清单：把每个别名都引一遍
String _emitFixture(Map<String, String> material, Map<String, String> asset) {
  final keys = _aliasKeys(material, asset).keys.toList()..sort();
  final entries = keys.map((k) => "  ('$k', StrokeIcons.$k),").join('\n');
  final header = [
    '// GENERATED - 由 tool/stroke_icons/generate.dart 生成，请勿手改。',
    '// 只在测试里引用：把所有描边图标过一遍几何校验与出图，不进 app 产物。',
    "import 'package:slime_works/components/icons/stroke_geometry.dart';",
    "import 'package:slime_works/components/icons/stroke_icons.g.dart';",
    '',
    'const List<(String, StrokeIcon)> kAllStrokeIcons = [',
  ].join('\n');
  return '$header\n$entries\n];\n';
}
