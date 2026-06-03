// Manga 数据模型（Dart 侧）
//
// 与 Rust 侧 JSON 结构对应，使用 dart:convert 解析

/// 图片资源
class MangaImage {
  final String originalName;
  final String path;
  final String fileServer;

  const MangaImage({required this.originalName, required this.path, required this.fileServer});

  factory MangaImage.fromJson(Map<String, dynamic> json) => MangaImage(
    originalName: json['originalName'] as String? ?? '',
    path: json['path'] as String? ?? '',
    fileServer: json['fileServer'] as String? ?? '',
  );

  /// 构建完整图片 URL
  String get fullUrl => '${fileServer.trimRight()}/static/$path';
}

/// 漫画信息
/// 漫画发布者（_creator 字段）
class MangaCreator {
  final String id;
  final String name;
  final MangaImage? avatar;

  const MangaCreator({required this.id, required this.name, this.avatar});

  factory MangaCreator.fromJson(Map<String, dynamic> json) => MangaCreator(
    id: json['_id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    avatar: json['avatar'] != null
        ? MangaImage.fromJson(json['avatar'] as Map<String, dynamic>)
        : null,
  );
}

class MangaComic {
  final String id;
  final String title;
  final String? author;
  final String? chineseTeam;
  final String? description;
  final MangaImage thumb;
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
  final MangaCreator? creator;

  const MangaComic({
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

  factory MangaComic.fromJson(Map<String, dynamic> json) => MangaComic(
    id: json['_id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    author: json['author'] as String?,
    chineseTeam: json['chineseTeam'] as String?,
    description: json['description'] as String?,
    thumb: MangaImage.fromJson(json['thumb'] as Map<String, dynamic>? ?? {}),
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
        ? MangaCreator.fromJson(json['_creator'] as Map<String, dynamic>)
        : null,
  );
}

/// 漫画章节
class MangaEps {
  final String id;
  final String title;
  final int order;
  final String updatedAt;

  const MangaEps({
    required this.id,
    required this.title,
    required this.order,
    required this.updatedAt,
  });

  factory MangaEps.fromJson(Map<String, dynamic> json) => MangaEps(
    id: json['_id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    order: json['order'] as int? ?? 1,
    updatedAt: json['updatedAt'] as String? ?? '',
  );
}

/// 章节图片单页
class MangaPage {
  final String id;
  final MangaImage media;

  const MangaPage({required this.id, required this.media});

  factory MangaPage.fromJson(Map<String, dynamic> json) => MangaPage(
    id: json['_id'] as String? ?? '',
    media: MangaImage.fromJson(json['media'] as Map<String, dynamic>? ?? {}),
  );
}

/// 分页信息
class MangaPagination {
  final int total;
  final int limit;
  final int page;
  final int pages;

  const MangaPagination({
    required this.total,
    required this.limit,
    required this.page,
    required this.pages,
  });

  factory MangaPagination.fromJson(Map<String, dynamic> json) => MangaPagination(
    total: json['total'] as int? ?? 0,
    limit: json['limit'] as int? ?? 20,
    page: json['page'] as int? ?? 1,
    pages: json['pages'] as int? ?? 1,
  );
}

/// 漫画列表（带分页）
class MangaComicList {
  final List<MangaComic> comics;
  final MangaPagination pagination;

  const MangaComicList({required this.comics, required this.pagination});

  factory MangaComicList.fromJson(Map<String, dynamic> json) {
    final comicsJson = json['comics'] as Map<String, dynamic>?;
    final docs = comicsJson?['docs'] as List? ?? json['comics'] as List? ?? [];
    final paginationJson = comicsJson ?? json;
    return MangaComicList(
      comics: docs.map((e) => MangaComic.fromJson(e as Map<String, dynamic>)).toList(),
      pagination: MangaPagination(
        total: paginationJson['total'] as int? ?? 0,
        limit: paginationJson['limit'] as int? ?? 20,
        page: paginationJson['page'] as int? ?? 1,
        pages: paginationJson['pages'] as int? ?? 1,
      ),
    );
  }
}

/// 章节列表（带分页）
class MangaEpsList {
  final List<MangaEps> eps;
  final MangaPagination pagination;

  const MangaEpsList({required this.eps, required this.pagination});

  factory MangaEpsList.fromJson(Map<String, dynamic> json) {
    final epsJson = json['eps'] as Map<String, dynamic>?;
    final docs = epsJson?['docs'] as List? ?? json['eps'] as List? ?? [];
    final paginationJson = epsJson ?? json;
    return MangaEpsList(
      eps: docs.map((e) => MangaEps.fromJson(e as Map<String, dynamic>)).toList(),
      pagination: MangaPagination(
        total: paginationJson['total'] as int? ?? 0,
        limit: paginationJson['limit'] as int? ?? 20,
        page: paginationJson['page'] as int? ?? 1,
        pages: paginationJson['pages'] as int? ?? 1,
      ),
    );
  }
}

/// 图片页列表（带分页）
class MangaPageList {
  final List<MangaPage> pages;
  final MangaPagination pagination;

  const MangaPageList({required this.pages, required this.pagination});

  factory MangaPageList.fromJson(Map<String, dynamic> json) {
    final pagesJson = json['pages'] as Map<String, dynamic>?;
    final docs = pagesJson?['docs'] as List? ?? json['pages'] as List? ?? [];
    final paginationJson = pagesJson ?? json;
    return MangaPageList(
      pages: docs.map((e) => MangaPage.fromJson(e as Map<String, dynamic>)).toList(),
      pagination: MangaPagination(
        total: paginationJson['total'] as int? ?? 0,
        limit: paginationJson['limit'] as int? ?? 40,
        page: paginationJson['page'] as int? ?? 1,
        pages: paginationJson['pages'] as int? ?? 1,
      ),
    );
  }
}

/// 用户信息
class MangaUser {
  final String id;
  final String email;
  final String name;
  final String title;
  final String status;
  final MangaImage? avatar;
  final int level;
  final int exp;
  final bool isPunched;

  const MangaUser({
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

  factory MangaUser.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? json;
    return MangaUser(
      id: user['_id'] as String? ?? '',
      email: user['email'] as String? ?? '',
      name: user['name'] as String? ?? '',
      title: user['title'] as String? ?? '',
      status: user['status'] as String? ?? '',
      avatar: user['avatar'] != null
          ? MangaImage.fromJson(user['avatar'] as Map<String, dynamic>)
          : null,
      level: user['level'] as int? ?? 0,
      exp: user['exp'] as int? ?? 0,
      isPunched: user['isPunched'] as bool? ?? false,
    );
  }
}

/// 分类信息
class MangaCategory {
  final String title;
  final MangaImage? thumb;
  final bool active;

  const MangaCategory({required this.title, this.thumb, required this.active});

  factory MangaCategory.fromJson(Map<String, dynamic> json) => MangaCategory(
    title: json['title'] as String? ?? '',
    thumb: json['thumb'] != null
        ? MangaImage.fromJson(json['thumb'] as Map<String, dynamic>)
        : null,
    active: json['active'] as bool? ?? true,
  );
}

/// 首页推荐集合
class MangaCollection {
  final String title;
  final List<MangaComic> comics;

  const MangaCollection({required this.title, required this.comics});

  factory MangaCollection.fromJson(Map<String, dynamic> json) => MangaCollection(
    title: json['title'] as String? ?? '',
    comics: (json['comics'] as List? ?? [])
        .map((e) => MangaComic.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// 评论用户简要信息
class MangaCommentUser {
  final String id;
  final String name;
  final String? title;
  final MangaImage? avatar;
  final int? level;

  const MangaCommentUser({
    required this.id,
    required this.name,
    this.title,
    this.avatar,
    this.level,
  });

  factory MangaCommentUser.fromJson(Map<String, dynamic> json) => MangaCommentUser(
    id: json['_id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    title: json['title'] as String?,
    avatar: json['avatar'] != null
        ? MangaImage.fromJson(json['avatar'] as Map<String, dynamic>)
        : null,
    level: json['level'] as int?,
  );
}

/// 评论
class MangaComment {
  final String id;
  final String content;
  final int totalComments;
  final int likesCount;
  final bool? isLiked;
  final String createdAt;
  final MangaCommentUser user;

  const MangaComment({
    required this.id,
    required this.content,
    required this.totalComments,
    required this.likesCount,
    this.isLiked,
    required this.createdAt,
    required this.user,
  });

  factory MangaComment.fromJson(Map<String, dynamic> json) => MangaComment(
    id: json['_id'] as String? ?? '',
    content: json['content'] as String? ?? '',
    totalComments: json['totalComments'] as int? ?? 0,
    likesCount: json['likesCount'] as int? ?? 0,
    isLiked: json['isLiked'] as bool?,
    createdAt: json['createdAt'] as String? ?? '',
    user: MangaCommentUser.fromJson(json['_user'] as Map<String, dynamic>? ?? {}),
  );
}

/// 排序方式枚举
enum MangaSortOrder {
  /// 最新发布
  dateDescending('dd'),

  /// 最旧发布
  dateAscending('da'),

  /// 最多点赞
  likeDescending('ld'),

  /// 最多观看
  viewDescending('vd');

  const MangaSortOrder(this.value);

  final String value;
}
