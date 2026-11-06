import 'dart:typed_data';

import 'package:slime_works/mock/data/manga_mock_data.dart';
import 'package:slime_works/mock/mock_mode.dart';
import 'package:slime_works/src/rust/api/manga.dart' as rust;

MockMangaData get _m => MockMangaData.instance;

void mangaInit() {
  if (MockMode.enabled) return;
  rust.mangaInit();
}

void mangaSetProxy({required String proxyUrl}) {
  if (MockMode.enabled) return;
  rust.mangaSetProxy(proxyUrl: proxyUrl);
}

void mangaSetToken({required String token}) {
  if (MockMode.enabled) {
    _m.login();
    return;
  }
  rust.mangaSetToken(token: token);
}

String mangaGetToken() {
  if (MockMode.enabled) return 'mock-token';
  return rust.mangaGetToken();
}

void mangaLogout() {
  if (MockMode.enabled) {
    _m.logout();
    return;
  }
  rust.mangaLogout();
}

void mangaSetChannel({required int mode, required String custom}) {
  if (MockMode.enabled) return;
  rust.mangaSetChannel(mode: mode, custom: custom);
}

void mangaSetImageServer({required String server}) {
  if (MockMode.enabled) return;
  rust.mangaSetImageServer(server: server);
}

String mangaGetImageServer() {
  if (MockMode.enabled) return '';
  return rust.mangaGetImageServer();
}

Future<BigInt> mangaTestChannel({
  required int mode,
  required String custom,
}) async {
  if (MockMode.enabled) return BigInt.from(18 + mode * 7);
  return rust.mangaTestChannel(mode: mode, custom: custom);
}

Future<String> mangaLogin({
  required String email,
  required String password,
}) async {
  if (MockMode.enabled) {
    _m.login();
    return _m.userJson;
  }
  return rust.mangaLogin(email: email, password: password);
}

Future<String> mangaGetUserProfile() async {
  if (MockMode.enabled) return _m.userJson;
  return rust.mangaGetUserProfile();
}

Future<String> mangaPunchIn() async {
  if (MockMode.enabled) return '{"status":"ok"}';
  return rust.mangaPunchIn();
}

Future<String> mangaGetCollections() async {
  if (MockMode.enabled) return _m.collectionsJson();
  return rust.mangaGetCollections();
}

Future<String> mangaGetRandomComics() async {
  if (MockMode.enabled) return _m.randomJson();
  return rust.mangaGetRandomComics();
}

Future<String> mangaGetCategories() async {
  if (MockMode.enabled) return _m.categoriesJson();
  return rust.mangaGetCategories();
}

Future<String> mangaGetComicsByCategory({
  required String category,
  required int page,
  required String sort,
}) async {
  if (MockMode.enabled) return _m.categoryComicsJson(category, page);
  return rust.mangaGetComicsByCategory(
    category: category,
    page: page,
    sort: sort,
  );
}

Future<String> mangaSearchComics({
  required String keyword,
  required List<String> categories,
  required int page,
  required String sort,
}) async {
  if (MockMode.enabled) return _m.searchJson(keyword, page);
  return rust.mangaSearchComics(
    keyword: keyword,
    categories: categories,
    page: page,
    sort: sort,
  );
}

Future<String> mangaGetKeywords() async {
  if (MockMode.enabled) return _m.keywordsJson();
  return rust.mangaGetKeywords();
}

Future<String> mangaGetRankings({required String timeType}) async {
  if (MockMode.enabled) return _m.rankingsJson(timeType);
  return rust.mangaGetRankings(timeType: timeType);
}

Future<String> mangaGetComicDetail({required String comicId}) async {
  if (MockMode.enabled) return _m.detailJson(comicId);
  return rust.mangaGetComicDetail(comicId: comicId);
}

Future<String> mangaGetComicRecommendations({required String comicId}) async {
  if (MockMode.enabled) return _m.recommendationsJson(comicId);
  return rust.mangaGetComicRecommendations(comicId: comicId);
}

Future<String> mangaGetComicEps({
  required String comicId,
  required int page,
}) async {
  if (MockMode.enabled) return _m.epsJson(comicId, page);
  return rust.mangaGetComicEps(comicId: comicId, page: page);
}

Future<String> mangaGetEpsPages({
  required String comicId,
  required int epsOrder,
  required int page,
}) async {
  if (MockMode.enabled) return _m.pagesJson(comicId, epsOrder, page);
  return rust.mangaGetEpsPages(
    comicId: comicId,
    epsOrder: epsOrder,
    page: page,
  );
}

Future<String> mangaGetFavourites({required int page, required String sort}) async {
  if (MockMode.enabled) return _m.favouritesJson(page);
  return rust.mangaGetFavourites(page: page, sort: sort);
}

Future<String> mangaToggleFavourite({required String comicId}) async {
  if (MockMode.enabled) return _m.toggleFavourite(comicId);
  return rust.mangaToggleFavourite(comicId: comicId);
}

Future<String> mangaToggleLike({required String comicId}) async {
  if (MockMode.enabled) return _m.toggleLike(comicId);
  return rust.mangaToggleLike(comicId: comicId);
}

Future<String> mangaGetComments({
  required String comicId,
  required int page,
}) async {
  if (MockMode.enabled) return _m.commentsJson(comicId, page);
  return rust.mangaGetComments(comicId: comicId, page: page);
}

Future<String> mangaGetCommentChildren({
  required String commentId,
  required int page,
}) async {
  if (MockMode.enabled) return _m.commentChildrenJson(commentId, page);
  return rust.mangaGetCommentChildren(commentId: commentId, page: page);
}

Future<String> mangaSendComment({
  required String comicId,
  required String content,
}) async {
  if (MockMode.enabled) return '{"status":"ok"}';
  return rust.mangaSendComment(comicId: comicId, content: content);
}

Future<String> mangaLikeComment({required String commentId}) async {
  if (MockMode.enabled) return '{"action":"like"}';
  return rust.mangaLikeComment(commentId: commentId);
}

String mangaBuildImageUrl({required String fileServer, required String path}) {
  if (MockMode.enabled) return 'mock://image/$path';
  return rust.mangaBuildImageUrl(fileServer: fileServer, path: path);
}

Future<Uint8List> mangaFetchImage({
  required String fileServer,
  required String path,
}) async {
  if (MockMode.enabled) return _m.imageBytes(path);
  return rust.mangaFetchImage(fileServer: fileServer, path: path);
}

void mangaInitHistory({required String dbPath}) {
  if (MockMode.enabled) return;
  rust.mangaInitHistory(dbPath: dbPath);
}

String mangaLoadHistory() {
  if (MockMode.enabled) return _m.loadHistory();
  return rust.mangaLoadHistory();
}

void mangaSaveHistoryRaw({required String json}) {
  if (MockMode.enabled) {
    _m.saveHistory(json);
    return;
  }
  rust.mangaSaveHistoryRaw(json: json);
}

void mangaClearHistory() {
  if (MockMode.enabled) {
    _m.clearHistory();
    return;
  }
  rust.mangaClearHistory();
}
