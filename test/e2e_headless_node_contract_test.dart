// 无头节点「假成功」契约测试 —— A 线：真进程 + 真 HTTP，不依赖 Flutter 树。
//
// ═══════════════════════════════════════════════════════════════════════════
// 为什么要有这个文件
// ═══════════════════════════════════════════════════════════════════════════
// 用户反馈的 bug 是「无头模式下很多操作**提示成功但数据没变化**」。
// 根因在 rust/src/node_server/handlers.rs：一批 mutation handler 把底层的
// `Result<bool>`（false = 目标不存在、什么都没改）当成了 `Result<()>`，
// 于是 `map_err(...)?; Ok(json!({"ok": true}))` 直接回 success:true。
// 客户端拿到 success 就弹「已删除」，用户回头一看东西还在。
//
// 这类缺陷**只有对着真节点的真数据库才抓得住**：假节点只能证明「客户端发了
// 什么请求」，证明不了「节点的数据到底变没变」。所以这里每一条断言都走
// 真进程 → 真 HTTP → 真 redb/SQLite，然后**回头再查一次列表**确认状态。
//
// ═══════════════════════════════════════════════════════════════════════════
// 跑法（HOME 隔离是硬要求，不隔离会写坏你真实那 217MB 的 media.db）
// ═══════════════════════════════════════════════════════════════════════════
//   mkdir -p /tmp/sw_e2e_home
//   HOME=/tmp/sw_e2e_home SLIME_E2E_HOME=/tmp/sw_e2e_home \
//     /private/tmp/fl/flutter/bin/flutter test test/e2e_headless_node_contract_test.dart --no-pub
//
// 想证明「修复前是红的」：用 git worktree 编一个基线版本的 slime_node，
// 再用 SLIME_E2E_NODE_BIN 指过去跑同一份文件：
//
//   git worktree add /tmp/sw_e2e_baseline <修复前的 commit>
//   (cd /tmp/sw_e2e_baseline/rust && CARGO_TARGET_DIR=/tmp/sw_e2e_baseline_target \
//      cargo build --bin slime_node)
//   HOME=/tmp/sw_e2e_home SLIME_E2E_HOME=/tmp/sw_e2e_home \
//     SLIME_E2E_NODE_BIN=/tmp/sw_e2e_baseline_target/debug/slime_node \
//     /private/tmp/fl/flutter/bin/flutter test test/e2e_headless_node_contract_test.dart --no-pub
//
// 前提：节点进程二进制已构建（cd rust && cargo build --bin slime_node）。
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/e2e_headless_node.dart';

void main() {
  // 安全闸门：没隔离 HOME 就整组跳过，并在输出里说清楚为什么。
  final isolatedHome = e2eIsolatedHome;
  if (isolatedHome == null) {
    test('真端到端用例已跳过（未隔离 HOME）', () {
      // ignore: avoid_print
      print(kNeedIsolatedHomeHint);
    }, skip: kNeedIsolatedHomeHint);
    return;
  }

  late RealHeadlessNode node;

  /// 每个用例独占一个新节点（新 dataDir）：不用 setUp 共享，是因为
  /// 「删文件」「删集合」这几种用例会真的把磁盘样本删掉，共享状态会互相干扰。
  Future<RealHeadlessNode> startNode() async {
    final created = await RealHeadlessNode.start(
      sandboxRoot: Directory(isolatedHome),
    );
    return created;
  }

  /// 导入一组 wav 样本，返回 (集合 id, 集合在磁盘上的目录)。
  /// 导入是后面「真删文件」类断言的前提：没有真实条目就没法验证删除语义。
  Future<({String collectionId, String mediaDir})> importSample(
    RealHeadlessNode target,
    int fileCount, {
    String name = '样本集合',
  }) async {
    final mediaRoot = Directory('${target.dataDir}/media')..createSync(recursive: true);
    final sampleDir = createAudioSampleDir(mediaRoot.path, fileCount, name: name);
    final data = await target.callOk('import_media_folder', <String, dynamic>{
      'folder_path': sampleDir.path,
      'generate_thumbnails': false,
    });
    return (
      collectionId: (data as Map)['id'].toString(),
      mediaDir: sampleDir.path,
    );
  }

  group('A1 不存在的目标必须报错，不能假成功', () {
    setUp(() async {
      node = await startNode();
    });
    tearDown(() async {
      await node.dispose();
    });

    /// 这是本次修复最核心的一条契约：整个 group 里的每个 action 在修复前
    /// 都会回 success:true（用户看到「操作成功」但库里什么都没变）。
    /// 断言里额外要求错误文案带具体 id —— 只回一句"失败"用户没法排查。
    test('文件夹 rename / delete 对不存在的 id 报错且带 id', () async {
      const ghost = 'media_folder_ghost_9f2c';

      final renameError = await node.callFails('rename_media_folder', <String, dynamic>{
        'folder_id': ghost,
        'name': '新名字',
      });
      expect(renameError, contains(ghost), reason: '重命名的错误文案必须带上目标 id');

      final deleteError = await node.callFails('delete_media_folder', <String, dynamic>{
        'folder_id': 'media_folder_ghost_a1b2',
      });
      expect(deleteError, contains('media_folder_ghost_a1b2'));
    });

    test('集合 rename / delete 对不存在的 id 报错且带 id', () async {
      const ghost = 'media_collection_ghost_7e41';

      final renameError = await node.callFails('rename_media_collection', <String, dynamic>{
        'collection_id': ghost,
        'title': '新标题',
      });
      expect(renameError, contains(ghost));

      final deleteError = await node.callFails('delete_media_collection', <String, dynamic>{
        'collection_id': 'media_collection_ghost_0c33',
      });
      expect(deleteError, contains('media_collection_ghost_0c33'));
    });

    /// 移动有**两个**独立的假成功来源：集合不存在、目标文件夹不存在。
    /// 后者更隐蔽：底层只把 collection.folder_id 写进去就回 true，
    /// 集合会挂到一个永远没有卡片能进的幽灵夹上（用户体感是"集合丢了"）。
    test('集合移动到不存在的文件夹要报错（两个 id 各自都要判）', () async {
      final ghostFolder = 'media_folder_ghost_move';
      // 目标文件夹不存在 → 必须报错（修复前回 success:true）
      final folderError = await node.callFails(
        'move_media_collection_to_folder',
        <String, dynamic>{
          'collection_id': 'media_collection_ghost_move',
          'folder_id': ghostFolder,
        },
      );
      expect(folderError, contains(ghostFolder), reason: '目标文件夹不存在时错误要指向它');
    });

    test('移动集合：集合存在但目标夹不存在时同样报错、且集合没被挪走', () async {
      // 先建一个真集合 + 一个真文件夹，再拿一个假 folder_id 去移动
      final imported = await importSample(node, 1, name: '移动守卫');
      final foldersBefore = await node.listFolders();

      final error = await node.callFails(
        'move_media_collection_to_folder',
        <String, dynamic>{
          'collection_id': imported.collectionId,
          'folder_id': 'media_folder_definitely_missing',
        },
      );
      expect(error, contains('media_folder_definitely_missing'));

      // 关键：失败的移动不能有副作用 —— 集合必须仍在根目录
      final collections = await node.listCollections();
      final moved = collections.firstWhere((c) => c['id'] == imported.collectionId);
      expect(moved['folder_id'], isNull, reason: '移动失败后集合必须留在根目录，不能挂到幽灵夹');
      expect(await node.listFolders(), hasLength(foldersBefore.length));
    });

    test('delete_collection_local_files 对不存在的集合报错（不是 deleted:0）', () async {
      // 修复前这里回 {"deleted":0} + success:true，与「集合在但文件早被清空」
      // 完全同形，客户端据此会以为操作成功。
      final error = await node.callFails(
        'delete_collection_local_files',
        <String, dynamic>{'collection_id': 'media_collection_ghost_files'},
      );
      expect(error, contains('media_collection_ghost_files'));
    });

    /// 这个 action 是本次**新增**的：修复前无头节点根本没有它，
    /// 客户端调用得到的是「不支持的动作: delete_media_item_local_file」。
    test('delete_media_item_local_file 存在该 action 且对不存在的条目报错', () async {
      // 先确认 action 存在：不存在时会回「不支持的动作: ...」
      final unknown = await node.call('delete_media_item_local_file', <String, dynamic>{
        'item_id': 'ghost_item',
        'collection_id': 'ghost_collection',
      });
      expect(
        (unknown['error'] ?? '').toString().contains('不支持的动作'),
        isFalse,
        reason: '无头节点必须实现 delete_media_item_local_file（客户端 media_library_vm_actions 在调它）',
      );

      final error = await node.callFails('delete_media_item_local_file', <String, dynamic>{
        'item_id': 'media_ghost_item_x',
        'collection_id': 'media_ghost_collection_x',
      });
      expect(error, anyOf(contains('media_ghost_item_x'), contains('media_ghost_collection_x')));
    });

    test('create_child_media_folder 父夹不存在时报错，不建孤儿夹', () async {
      const ghostParent = 'media_folder_ghost_parent';
      final error = await node.callFails('create_child_media_folder', <String, dynamic>{
        'name': '孤儿夹',
        'parent_id': ghostParent,
      });
      expect(error, contains(ghostParent));

      // 更硬的断言：库里绝不能出现 name=孤儿夹 的文件夹（修复前它会真的被建出来，
      // 只是 parent_id 指向一个不存在的父级，UI 上永远看不见）
      final folders = await node.listFolders();
      expect(
        folders.any((f) => f['name'] == '孤儿夹'),
        isFalse,
        reason: '父夹不存在时不能建出孤儿文件夹',
      );
    });

    test('小说 delete / tags / favorite / info / move 对不存在的书报错', () async {
      const ghostNovel = 'novel_ghost_1234';

      // 五个 action 在修复前都是 `let _ =` / 丢弃 bool，全部回 success:true
      for (final entry in <String, Map<String, dynamic>>{
        'delete_novel': <String, dynamic>{'novel_id': ghostNovel},
        'update_novel_tags': <String, dynamic>{
          'novel_id': ghostNovel,
          'tags': <String>['标签'],
        },
        'set_novel_favorite': <String, dynamic>{
          'novel_id': ghostNovel,
          'is_favorite': true,
        },
        'update_novel_info': <String, dynamic>{
          'novel_id': ghostNovel,
          'title': '新书名',
        },
        'move_novel_to_folder': <String, dynamic>{
          'novel_id': ghostNovel,
          'folder_id': '',
        },
      }.entries) {
        final error = await node.callFails(entry.key, entry.value);
        expect(error, contains(ghostNovel), reason: '${entry.key} 的错误文案必须带小说 id');
      }
    });
  });

  group('A2 对真实目标的操作必须真的改变数据', () {
    setUp(() async {
      node = await startNode();
    });
    tearDown(() async {
      await node.dispose();
    });

    /// 修复前即使"目标真的存在"，删除也只是回 ok 而**不校验**是否真删了 ——
    /// 这条用例的作用是：证明 success:true 在今天确实对应"数据真的变了"，
    /// 于是 A1 里那些 success:false 才有意义（不是把所有调用都判失败）。
    test('文件夹 create → rename → delete，每一步都回查列表', () async {
      // 1) 创建
      final created = await node.callOk('create_media_folder', <String, dynamic>{
        'name': '待改名夹',
      }) as Map;
      final folderId = created['id'].toString();
      expect(folderId, isNotEmpty);

      var folders = await node.listFolders();
      expect(
        folders.map((f) => f['name']),
        contains('待改名夹'),
        reason: '创建成功后列表里必须能看到它',
      );

      // 2) 重命名
      await node.callOk('rename_media_folder', <String, dynamic>{
        'folder_id': folderId,
        'name': '已改名夹',
      });
      folders = await node.listFolders();
      final renamed = folders.firstWhere((f) => f['id'] == folderId);
      expect(renamed['name'], '已改名夹', reason: '重命名必须落到库里，不能只是回了个 ok');

      // 3) 删除
      await node.callOk('delete_media_folder', <String, dynamic>{'folder_id': folderId});
      folders = await node.listFolders();
      expect(
        folders.any((f) => f['id'] == folderId),
        isFalse,
        reason: '删除成功后列表里不能还有它',
      );

      // 4) 再删一次必须是失败（幂等性靠报错表达，不是靠假成功）
      await node.callFails('delete_media_folder', <String, dynamic>{'folder_id': folderId});
    });

    test('子文件夹挂在真父夹下，且能在列表里看到父子关系', () async {
      final parent = await node.callOk('create_media_folder', <String, dynamic>{
        'name': '父夹',
      }) as Map;
      final parentId = parent['id'].toString();

      final child = await node.callOk('create_child_media_folder', <String, dynamic>{
        'name': '子夹',
        'parent_id': parentId,
      }) as Map;

      final folders = await node.listFolders();
      final childRow = folders.firstWhere((f) => f['id'] == child['id'].toString());
      expect(childRow['parent_id'], parentId, reason: '子夹的 parent_id 必须指向真父夹');
    });

    test('集合 rename 真的改了标题，delete 真的从列表消失', () async {
      final imported = await importSample(node, 2, name: '集合增删');

      // 列表里先有它
      var collections = await node.listCollections();
      expect(collections.any((c) => c['id'] == imported.collectionId), isTrue);

      // 重命名
      await node.callOk('rename_media_collection', <String, dynamic>{
        'collection_id': imported.collectionId,
        'title': '改过的标题',
      });
      collections = await node.listCollections();
      expect(
        collections.firstWhere((c) => c['id'] == imported.collectionId)['title'],
        '改过的标题',
      );

      // 删除（只删库记录，不动磁盘 —— 这是 delete_media_collection 的语义）
      await node.callOk('delete_media_collection', <String, dynamic>{
        'collection_id': imported.collectionId,
      });
      collections = await node.listCollections();
      expect(collections.any((c) => c['id'] == imported.collectionId), isFalse);
      expect(
        Directory(imported.mediaDir).existsSync(),
        isTrue,
        reason: 'delete_media_collection 只移除库记录，磁盘文件必须还在',
      );
    });
  });

  group('A3 删除节点本地文件：磁盘真没了、记录口径分明', () {
    setUp(() async {
      node = await startNode();
    });
    tearDown(() async {
      await node.dispose();
    });

    /// 单条目删除：客户端 vm 的 deleteRemoteItemLocalFile 走这里。
    /// 语义 = 删磁盘文件；集合记录保留（条目因重扫自然消失）。
    test('delete_media_item_local_file：文件消失、集合仍在、条目随重扫消失', () async {
      final imported = await importSample(node, 2, name: '单条删除');

      final itemsBefore = await node.listItems(imported.collectionId);
      expect(itemsBefore, hasLength(2), reason: '导入 2 个 wav 就该有 2 条');
      final target = itemsBefore.first;
      final targetPath = target['file_path'].toString();
      expect(File(targetPath).existsSync(), isTrue, reason: '前提：文件此刻在磁盘上');

      final result = await node.callOk('delete_media_item_local_file', <String, dynamic>{
        'item_id': target['id'],
        'collection_id': imported.collectionId,
      }) as Map;
      expect(result['deleted_file'], isTrue, reason: '节点应如实回报物理文件是否真被删掉');

      // ★ 断言一：磁盘文件真的没了（这是「假成功」最直接的照妖镜）
      expect(
        File(targetPath).existsSync(),
        isFalse,
        reason: '删了却还在磁盘上 = 用户报警的那个 bug',
      );

      // ★ 断言二：集合记录必须还在
      final collections = await node.listCollections();
      final collection = collections.firstWhere(
        (c) => c['id'] == imported.collectionId,
        orElse: () => <String, dynamic>{},
      );
      expect(collection, isNotEmpty, reason: '单条目删除不能把整个集合记录也删掉');
      expect(
        int.parse(collection['item_count'].toString()),
        1,
        reason: '集合条数应随删除降到 1',
      );

      // ★ 断言三：条目列表里只剩另一个，被删的那条不能再出现
      final itemsAfter = await node.listItems(imported.collectionId);
      expect(itemsAfter, hasLength(1));
      expect(
        itemsAfter.any((i) => i['id'] == target['id']),
        isFalse,
        reason: '被删的条目不能还留在集合里（幽灵项指向已删路径）',
      );

      // ★ 断言四：同一个条目再删一次必须报错（修复前会静默成功）
      final secondError = await node.callFails(
        'delete_media_item_local_file',
        <String, dynamic>{
          'item_id': target['id'],
          'collection_id': imported.collectionId,
        },
      );
      expect(secondError, contains(target['id'].toString()));
    });

    /// 集合级删除：客户端 vm 的 deleteNodeLocalFilesForCollection 走这里。
    /// 语义 = 删该集合目录下全部文件；集合记录**保留**、item_count 归零。
    test('delete_collection_local_files：文件全没、集合记录在、item_count 归零', () async {
      final imported = await importSample(node, 3, name: '整集删除');
      final itemsBefore = await node.listItems(imported.collectionId);
      expect(itemsBefore, hasLength(3));
      final paths = itemsBefore.map((i) => i['file_path'].toString()).toList();
      for (final path in paths) {
        expect(File(path).existsSync(), isTrue);
      }

      final result = await node.callOk('delete_collection_local_files', <String, dynamic>{
        'collection_id': imported.collectionId,
      }) as Map;
      expect(int.parse(result['deleted'].toString()), 3, reason: '应回报真的删掉了 3 个文件');

      // ★ 逐条确认磁盘上没有漏网之鱼
      for (final path in paths) {
        expect(
          File(path).existsSync(),
          isFalse,
          reason: 'delete_collection_local_files 之后 $path 必须不存在',
        );
      }

      // ★ 集合记录保留、条数归零（不是把集合一起删了）
      final collections = await node.listCollections();
      final collection = collections.firstWhere(
        (c) => c['id'] == imported.collectionId,
        orElse: () => <String, dynamic>{},
      );
      expect(collection, isNotEmpty, reason: '删本地文件不应连集合记录一起删');
      expect(
        int.parse(collection['item_count'].toString()),
        0,
        reason: '节点应把现存条数改写进聚合表，否则客户端看到的还是旧体积',
      );
      // 注意条目记录的**口径差别**（这里刻意写清楚，避免下一个人照抄错断言）：
      // delete_collection_local_files 保留条目记录、只把聚合表的 live 值归零，
      // 所以 get_media_collection_items 仍会返回那几条指向已删路径的记录。
      // 集合卡读的是 item_count（已归零），因此界面上表现为「空了」。
      // 单条目删除（A3 上一条用例）才是「条目随重扫一起消失」，两者语义不同。
      final itemsAfterWipe = await node.listItems(imported.collectionId);
      expect(
        itemsAfterWipe, hasLength(3),
        reason: '整集删文件刻意保留条目记录（口径与单条目删除不同）',
      );
      for (final item in itemsAfterWipe) {
        expect(
          File(item['file_path'].toString()).existsSync(),
          isFalse,
          reason: '虽然记录留着，但它指向的磁盘文件必须真的没了',
        );
      }

      // 再删一次：集合还在、没有文件可删 → 回 deleted:0 是**正确**语义
      // （与 A1 里「集合不存在」必须报错形成对照，两者不能同形）
      final again = await node.callOk('delete_collection_local_files', <String, dynamic>{
        'collection_id': imported.collectionId,
      }) as Map;
      expect(int.parse(again['deleted'].toString()), 0);
    });
  });

  group('A4 客户端实际发出的调用形状', () {
    setUp(() async {
      node = await startNode();
    });
    tearDown(() async {
      await node.dispose();
    });

    /// 这条用例盯着「客户端与服务端的参数名契约」：
    /// NodeSettingsService 里各个 mutation 方法写的 params 键名，
    /// 必须和 handlers.rs 读的键名一致——不一致就是"请求发出去了、节点什么也没做"，
    /// 同样表现为「提示成功但数据没变化」。
    test('客户端形参名与节点解析名一致（folder_id / collection_id / title / name）', () async {
      final folder = await node.callOk('create_media_folder', <String, dynamic>{
        'name': '形参对齐',
      }) as Map;
      final folderId = folder['id'].toString();

      // NodeSettingsService.renameNodeMediaFolder 发的就是这两个键
      await node.callOk('rename_media_folder', <String, dynamic>{
        'folder_id': folderId,
        'name': '形参对齐-改',
      });
      final folders = await node.listFolders();
      expect(
        folders.firstWhere((f) => f['id'] == folderId)['name'],
        '形参对齐-改',
        reason: '键名对不上时节点会当成空串处理，表现为静默无效',
      );

      // NodeSettingsService.deleteNodeMediaFolder 发的就是 folder_id
      await node.callOk('delete_media_folder', <String, dynamic>{'folder_id': folderId});
    });
  });
}
