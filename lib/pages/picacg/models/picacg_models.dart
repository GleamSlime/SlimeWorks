// PicACG 数据模型（Dart 侧）
//
// 与 Rust 侧 JSON 结构对应，使用 dart:convert 解析

/// 图片资源
class PicAcgImage {
  final String originalName;
  final String path;
  final String fileServer;

  const PicAcgImage({required this.originalName, required this.path, required this.fileServer});

  factory PicAcgImage.fromJson(Map<String, dynamic> json) => PicAcgImage(
    originalName: json['originalName'] as String? ?? '',
    path: json['path'] as String? ?? '',
    fileServer: json['fileServer'] as String? ?? '',
  );

  /// 构建完整图片 URL
  String get fullUrl => '${fileServer.trimRight()}/static/$path';
}

/// 漫画信息
/// 漫画发布者（_creator 字段）
class PicAcgCreator {
  final String id;
  final String name;
  final PicAcgImage? avatar;

  const PicAcgCreator({required this.id, required this.name, this.avatar});

  factory PicAcgCreator.fromJson(Map<String, dynamic> json) => PicAcgCreator(
    id: json['_id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    avatar: json['avatar'] != null
        ? PicAcgImage.fromJson(json['avatar'] as Map<String, dynamic>)
        : null,
  );
}

class PicAcgComic {
  final String id;
  final String title;
  final String? author;
  final String? chineseTeam;
  final String? description;
  final PicAcgImage thumb;
  final List<String> categories;
  final List<String> tags;
  final int epsCount;
  final int pagesCount;
  final int likesCount;
  final int viewsCount;
  final int commentsCount;
  final bool finished;
  final bool? isLiked;
  final bool? isFavourite;
  final String? createdAt;
  final String? updatedAt;
  final int? shareId;
  final PicAcgCreator? creator;

  const PicAcgComic({
    required this.id,
    required this.title,
    this.author,
    this.chineseTeam,
    this.description,
    required this.thumb,
    required this.categories,
    required this.tags,
    required this.epsCount,
    required this.pagesCount,
    required this.likesCount,
    this.viewsCount = 0,
    this.commentsCount = 0,
    required this.finished,
    this.isLiked,
    this.isFavourite,
    this.createdAt,
    this.updatedAt,
    this.shareId,
    this.creator,
  });

  factory PicAcgComic.fromJson(Map<String, dynamic> json) => PicAcgComic(
    id: json['_id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    author: json['author'] as String?,
    chineseTeam: json['chineseTeam'] as String?,
    description: json['description'] as String?,
    thumb: PicAcgImage.fromJson(json['thumb'] as Map<String, dynamic>? ?? {}),
    categories: List<String>.from(json['categories'] as List? ?? []),
    tags: List<String>.from(json['tags'] as List? ?? []),
    epsCount: json['epsCount'] as int? ?? 0,
    pagesCount: json['pagesCount'] as int? ?? 0,
    likesCount: (json['totalLikes'] ?? json['likesCount']) as int? ?? 0,
    viewsCount: (json['totalViews'] ?? json['viewsCount']) as int? ?? 0,
    commentsCount: json['commentsCount'] as int? ?? 0,
    finished: json['finished'] as bool? ?? false,
    isLiked: json['isLiked'] as bool?,
    isFavourite: json['isFavourite'] as bool?,
    createdAt: json['created_at'] as String?,
    updatedAt: json['updated_at'] as String?,
    shareId: json['id'] as int?,
    creator: json['_creator'] != null
        ? PicAcgCreator.fromJson(json['_creator'] as Map<String, dynamic>)
        : null,
  );
}

/// 漫画章节
class PicAcgEps {
  final String id;
  final String title;
  final int order;
  final String updatedAt;

  const PicAcgEps({
    required this.id,
    required this.title,
    required this.order,
    required this.updatedAt,
  });

  factory PicAcgEps.fromJson(Map<String, dynamic> json) => PicAcgEps(
    id: json['_id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    order: json['order'] as int? ?? 1,
    updatedAt: json['updatedAt'] as String? ?? '',
  );
}

/// 章节图片单页
class PicAcgPage {
  final String id;
  final PicAcgImage media;

  const PicAcgPage({required this.id, required this.media});

  factory PicAcgPage.fromJson(Map<String, dynamic> json) => PicAcgPage(
    id: json['_id'] as String? ?? '',
    media: PicAcgImage.fromJson(json['media'] as Map<String, dynamic>? ?? {}),
  );
}

/// 分页信息
class PicAcgPagination {
  final int total;
  final int limit;
  final int page;
  final int pages;

  const PicAcgPagination({
    required this.total,
    required this.limit,
    required this.page,
    required this.pages,
  });

  factory PicAcgPagination.fromJson(Map<String, dynamic> json) => PicAcgPagination(
    total: json['total'] as int? ?? 0,
    limit: json['limit'] as int? ?? 20,
    page: json['page'] as int? ?? 1,
    pages: json['pages'] as int? ?? 1,
  );
}

/// 漫画列表（带分页）
class PicAcgComicList {
  final List<PicAcgComic> comics;
  final PicAcgPagination pagination;

  const PicAcgComicList({required this.comics, required this.pagination});

  factory PicAcgComicList.fromJson(Map<String, dynamic> json) {
    final comicsJson = json['comics'] as Map<String, dynamic>?;
    final docs = comicsJson?['docs'] as List? ?? json['comics'] as List? ?? [];
    final paginationJson = comicsJson ?? json;
    return PicAcgComicList(
      comics: docs.map((e) => PicAcgComic.fromJson(e as Map<String, dynamic>)).toList(),
      pagination: PicAcgPagination(
        total: paginationJson['total'] as int? ?? 0,
        limit: paginationJson['limit'] as int? ?? 20,
        page: paginationJson['page'] as int? ?? 1,
        pages: paginationJson['pages'] as int? ?? 1,
      ),
    );
  }
}

/// 章节列表（带分页）
class PicAcgEpsList {
  final List<PicAcgEps> eps;
  final PicAcgPagination pagination;

  const PicAcgEpsList({required this.eps, required this.pagination});

  factory PicAcgEpsList.fromJson(Map<String, dynamic> json) {
    final epsJson = json['eps'] as Map<String, dynamic>?;
    final docs = epsJson?['docs'] as List? ?? json['eps'] as List? ?? [];
    final paginationJson = epsJson ?? json;
    return PicAcgEpsList(
      eps: docs.map((e) => PicAcgEps.fromJson(e as Map<String, dynamic>)).toList(),
      pagination: PicAcgPagination(
        total: paginationJson['total'] as int? ?? 0,
        limit: paginationJson['limit'] as int? ?? 20,
        page: paginationJson['page'] as int? ?? 1,
        pages: paginationJson['pages'] as int? ?? 1,
      ),
    );
  }
}

/// 图片页列表（带分页）
class PicAcgPageList {
  final List<PicAcgPage> pages;
  final PicAcgPagination pagination;

  const PicAcgPageList({required this.pages, required this.pagination});

  factory PicAcgPageList.fromJson(Map<String, dynamic> json) {
    final pagesJson = json['pages'] as Map<String, dynamic>?;
    final docs = pagesJson?['docs'] as List? ?? json['pages'] as List? ?? [];
    final paginationJson = pagesJson ?? json;
    return PicAcgPageList(
      pages: docs.map((e) => PicAcgPage.fromJson(e as Map<String, dynamic>)).toList(),
      pagination: PicAcgPagination(
        total: paginationJson['total'] as int? ?? 0,
        limit: paginationJson['limit'] as int? ?? 40,
        page: paginationJson['page'] as int? ?? 1,
        pages: paginationJson['pages'] as int? ?? 1,
      ),
    );
  }
}

/// 用户信息
class PicAcgUser {
  final String id;
  final String email;
  final String name;
  final String title;
  final String status;
  final PicAcgImage? avatar;
  final int level;
  final int exp;
  final bool isPunched;

  const PicAcgUser({
    required this.id,
    required this.email,
    required this.name,
    required this.title,
    required this.status,
    this.avatar,
    required this.level,
    required this.exp,
    required this.isPunched,
  });

  factory PicAcgUser.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? json;
    return PicAcgUser(
      id: user['_id'] as String? ?? '',
      email: user['email'] as String? ?? '',
      name: user['name'] as String? ?? '',
      title: user['title'] as String? ?? '',
      status: user['status'] as String? ?? '',
      avatar: user['avatar'] != null
          ? PicAcgImage.fromJson(user['avatar'] as Map<String, dynamic>)
          : null,
      level: user['level'] as int? ?? 0,
      exp: user['exp'] as int? ?? 0,
      isPunched: user['isPunched'] as bool? ?? false,
    );
  }
}

/// 分类信息
class PicAcgCategory {
  final String title;
  final PicAcgImage? thumb;
  final bool active;

  const PicAcgCategory({required this.title, this.thumb, required this.active});

  factory PicAcgCategory.fromJson(Map<String, dynamic> json) => PicAcgCategory(
    title: json['title'] as String? ?? '',
    thumb: json['thumb'] != null
        ? PicAcgImage.fromJson(json['thumb'] as Map<String, dynamic>)
        : null,
    active: json['active'] as bool? ?? true,
  );
}

/// 首页推荐集合
class PicAcgCollection {
  final String title;
  final List<PicAcgComic> comics;

  const PicAcgCollection({required this.title, required this.comics});

  factory PicAcgCollection.fromJson(Map<String, dynamic> json) => PicAcgCollection(
    title: json['title'] as String? ?? '',
    comics: (json['comics'] as List? ?? [])
        .map((e) => PicAcgComic.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// 评论用户简要信息
class PicAcgCommentUser {
  final String id;
  final String name;
  final String? title;
  final PicAcgImage? avatar;
  final int? level;

  const PicAcgCommentUser({
    required this.id,
    required this.name,
    this.title,
    this.avatar,
    this.level,
  });

  factory PicAcgCommentUser.fromJson(Map<String, dynamic> json) => PicAcgCommentUser(
    id: json['_id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    title: json['title'] as String?,
    avatar: json['avatar'] != null
        ? PicAcgImage.fromJson(json['avatar'] as Map<String, dynamic>)
        : null,
    level: json['level'] as int?,
  );
}

/// 评论
class PicAcgComment {
  final String id;
  final String content;
  final int totalComments;
  final int likesCount;
  final bool? isLiked;
  final String createdAt;
  final PicAcgCommentUser user;

  const PicAcgComment({
    required this.id,
    required this.content,
    required this.totalComments,
    required this.likesCount,
    this.isLiked,
    required this.createdAt,
    required this.user,
  });

  factory PicAcgComment.fromJson(Map<String, dynamic> json) => PicAcgComment(
    id: json['_id'] as String? ?? '',
    content: json['content'] as String? ?? '',
    totalComments: json['totalComments'] as int? ?? 0,
    likesCount: json['likesCount'] as int? ?? 0,
    isLiked: json['isLiked'] as bool?,
    createdAt: json['createdAt'] as String? ?? '',
    user: PicAcgCommentUser.fromJson(json['_user'] as Map<String, dynamic>? ?? {}),
  );
}

/// 排序方式枚举
enum PicAcgSortOrder {
  /// 最新发布
  dateDescending('dd'),

  /// 最旧发布
  dateAscending('da'),

  /// 最多点赞
  likeDescending('ld'),

  /// 最多观看
  viewDescending('vd');

  const PicAcgSortOrder(this.value);

  final String value;
}
