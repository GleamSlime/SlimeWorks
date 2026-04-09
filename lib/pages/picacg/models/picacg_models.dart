/// PicACG 数据模型（Dart 侧）
///
/// 与 Rust 侧 JSON 结构对应，使用 dart:convert 解析

/// 图片资源
class PicacgImage {
  final String originalName;
  final String path;
  final String fileServer;

  const PicacgImage({required this.originalName, required this.path, required this.fileServer});

  factory PicacgImage.fromJson(Map<String, dynamic> json) => PicacgImage(
    originalName: json['originalName'] as String? ?? '',
    path: json['path'] as String? ?? '',
    fileServer: json['fileServer'] as String? ?? '',
  );

  /// 构建完整图片 URL
  String get fullUrl => '${fileServer.trimRight()}/static/$path';
}

/// 漫画信息
class PicacgComic {
  final String id;
  final String title;
  final String? author;
  final String? description;
  final PicacgImage thumb;
  final List<String> categories;
  final List<String> tags;
  final int epsCount;
  final int pagesCount;
  final int likesCount;
  final bool finished;
  final bool? isLiked;
  final bool? isFavourite;

  const PicacgComic({
    required this.id,
    required this.title,
    this.author,
    this.description,
    required this.thumb,
    required this.categories,
    required this.tags,
    required this.epsCount,
    required this.pagesCount,
    required this.likesCount,
    required this.finished,
    this.isLiked,
    this.isFavourite,
  });

  factory PicacgComic.fromJson(Map<String, dynamic> json) => PicacgComic(
    id: json['_id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    author: json['author'] as String?,
    description: json['description'] as String?,
    thumb: PicacgImage.fromJson(json['thumb'] as Map<String, dynamic>? ?? {}),
    categories: List<String>.from(json['categories'] as List? ?? []),
    tags: List<String>.from(json['tags'] as List? ?? []),
    epsCount: json['epsCount'] as int? ?? 0,
    pagesCount: json['pagesCount'] as int? ?? 0,
    likesCount: json['likesCount'] as int? ?? 0,
    finished: json['finished'] as bool? ?? false,
    isLiked: json['isLiked'] as bool?,
    isFavourite: json['isFavourite'] as bool?,
  );
}

/// 漫画章节
class PicacgEps {
  final String id;
  final String title;
  final int order;
  final String updatedAt;

  const PicacgEps({
    required this.id,
    required this.title,
    required this.order,
    required this.updatedAt,
  });

  factory PicacgEps.fromJson(Map<String, dynamic> json) => PicacgEps(
    id: json['_id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    order: json['order'] as int? ?? 1,
    updatedAt: json['updatedAt'] as String? ?? '',
  );
}

/// 章节图片单页
class PicacgPage {
  final String id;
  final PicacgImage media;

  const PicacgPage({required this.id, required this.media});

  factory PicacgPage.fromJson(Map<String, dynamic> json) => PicacgPage(
    id: json['_id'] as String? ?? '',
    media: PicacgImage.fromJson(json['media'] as Map<String, dynamic>? ?? {}),
  );
}

/// 分页信息
class PicacgPagination {
  final int total;
  final int limit;
  final int page;
  final int pages;

  const PicacgPagination({
    required this.total,
    required this.limit,
    required this.page,
    required this.pages,
  });

  factory PicacgPagination.fromJson(Map<String, dynamic> json) => PicacgPagination(
    total: json['total'] as int? ?? 0,
    limit: json['limit'] as int? ?? 20,
    page: json['page'] as int? ?? 1,
    pages: json['pages'] as int? ?? 1,
  );
}

/// 漫画列表（带分页）
class PicacgComicList {
  final List<PicacgComic> comics;
  final PicacgPagination pagination;

  const PicacgComicList({required this.comics, required this.pagination});

  factory PicacgComicList.fromJson(Map<String, dynamic> json) {
    final comicsJson = json['comics'] as Map<String, dynamic>?;
    final docs = comicsJson?['docs'] as List? ?? json['comics'] as List? ?? [];
    final paginationJson = comicsJson ?? json;
    return PicacgComicList(
      comics: docs.map((e) => PicacgComic.fromJson(e as Map<String, dynamic>)).toList(),
      pagination: PicacgPagination(
        total: paginationJson['total'] as int? ?? 0,
        limit: paginationJson['limit'] as int? ?? 20,
        page: paginationJson['page'] as int? ?? 1,
        pages: paginationJson['pages'] as int? ?? 1,
      ),
    );
  }
}

/// 章节列表（带分页）
class PicacgEpsList {
  final List<PicacgEps> eps;
  final PicacgPagination pagination;

  const PicacgEpsList({required this.eps, required this.pagination});

  factory PicacgEpsList.fromJson(Map<String, dynamic> json) {
    final epsJson = json['eps'] as Map<String, dynamic>?;
    final docs = epsJson?['docs'] as List? ?? json['eps'] as List? ?? [];
    final paginationJson = epsJson ?? json;
    return PicacgEpsList(
      eps: docs.map((e) => PicacgEps.fromJson(e as Map<String, dynamic>)).toList(),
      pagination: PicacgPagination(
        total: paginationJson['total'] as int? ?? 0,
        limit: paginationJson['limit'] as int? ?? 20,
        page: paginationJson['page'] as int? ?? 1,
        pages: paginationJson['pages'] as int? ?? 1,
      ),
    );
  }
}

/// 图片页列表（带分页）
class PicacgPageList {
  final List<PicacgPage> pages;
  final PicacgPagination pagination;

  const PicacgPageList({required this.pages, required this.pagination});

  factory PicacgPageList.fromJson(Map<String, dynamic> json) {
    final pagesJson = json['pages'] as Map<String, dynamic>?;
    final docs = pagesJson?['docs'] as List? ?? json['pages'] as List? ?? [];
    final paginationJson = pagesJson ?? json;
    return PicacgPageList(
      pages: docs.map((e) => PicacgPage.fromJson(e as Map<String, dynamic>)).toList(),
      pagination: PicacgPagination(
        total: paginationJson['total'] as int? ?? 0,
        limit: paginationJson['limit'] as int? ?? 40,
        page: paginationJson['page'] as int? ?? 1,
        pages: paginationJson['pages'] as int? ?? 1,
      ),
    );
  }
}

/// 用户信息
class PicacgUser {
  final String id;
  final String email;
  final String name;
  final String title;
  final String status;
  final PicacgImage? avatar;
  final int level;
  final int exp;
  final bool isPunched;

  const PicacgUser({
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

  factory PicacgUser.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? json;
    return PicacgUser(
      id: user['_id'] as String? ?? '',
      email: user['email'] as String? ?? '',
      name: user['name'] as String? ?? '',
      title: user['title'] as String? ?? '',
      status: user['status'] as String? ?? '',
      avatar: user['avatar'] != null
          ? PicacgImage.fromJson(user['avatar'] as Map<String, dynamic>)
          : null,
      level: user['level'] as int? ?? 0,
      exp: user['exp'] as int? ?? 0,
      isPunched: user['isPunched'] as bool? ?? false,
    );
  }
}

/// 分类信息
class PicacgCategory {
  final String title;
  final PicacgImage? thumb;
  final bool active;

  const PicacgCategory({required this.title, this.thumb, required this.active});

  factory PicacgCategory.fromJson(Map<String, dynamic> json) => PicacgCategory(
    title: json['title'] as String? ?? '',
    thumb: json['thumb'] != null
        ? PicacgImage.fromJson(json['thumb'] as Map<String, dynamic>)
        : null,
    active: json['active'] as bool? ?? true,
  );
}

/// 首页推荐集合
class PicacgCollection {
  final String title;
  final List<PicacgComic> comics;

  const PicacgCollection({required this.title, required this.comics});

  factory PicacgCollection.fromJson(Map<String, dynamic> json) => PicacgCollection(
    title: json['title'] as String? ?? '',
    comics: (json['comics'] as List? ?? [])
        .map((e) => PicacgComic.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// 评论用户简要信息
class PicacgCommentUser {
  final String id;
  final String name;
  final String? title;
  final PicacgImage? avatar;
  final int? level;

  const PicacgCommentUser({
    required this.id,
    required this.name,
    this.title,
    this.avatar,
    this.level,
  });

  factory PicacgCommentUser.fromJson(Map<String, dynamic> json) => PicacgCommentUser(
    id: json['_id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    title: json['title'] as String?,
    avatar: json['avatar'] != null
        ? PicacgImage.fromJson(json['avatar'] as Map<String, dynamic>)
        : null,
    level: json['level'] as int?,
  );
}

/// 评论
class PicacgComment {
  final String id;
  final String content;
  final int totalComments;
  final int likesCount;
  final bool? isLiked;
  final String createdAt;
  final PicacgCommentUser user;

  const PicacgComment({
    required this.id,
    required this.content,
    required this.totalComments,
    required this.likesCount,
    this.isLiked,
    required this.createdAt,
    required this.user,
  });

  factory PicacgComment.fromJson(Map<String, dynamic> json) => PicacgComment(
    id: json['_id'] as String? ?? '',
    content: json['content'] as String? ?? '',
    totalComments: json['totalComments'] as int? ?? 0,
    likesCount: json['likesCount'] as int? ?? 0,
    isLiked: json['isLiked'] as bool?,
    createdAt: json['createdAt'] as String? ?? '',
    user: PicacgCommentUser.fromJson(json['_user'] as Map<String, dynamic>? ?? {}),
  );
}

/// 排序方式枚举
enum PicacgSortOrder {
  /// 最新发布
  dateDescending('dd'),

  /// 最旧发布
  dateAscending('da'),

  /// 最多点赞
  likeDescending('ld'),

  /// 最多观看
  viewDescending('vd');

  const PicacgSortOrder(this.value);

  final String value;
}
