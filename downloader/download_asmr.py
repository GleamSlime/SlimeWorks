#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
asmr.one 作品下载工具

用法:
    python3 download_asmr.py RJ01418453
    python3 download_asmr.py https://asmr.one/work/RJ01418453
    python3 download_asmr.py 1418453

原理:
    1. 从作品标识中提取 work_id
    2. 请求 https://api.asmr-200.com/api/tracks/{work_id}?v=2 拿到文件清单
    3. 逐个下载每个文件的 mediaDownloadUrl，按 mp3/wav/txt 文件夹结构保存

依赖: 仅 Python3 标准库 (urllib), 无需安装第三方包。
需要能访问 asmr.one 的 API/下载域名 (raw.kiko-play-niptan.one), 如受限请配置网络/代理。
"""
import argparse
import os
import re
import sys
import time
import ssl
import urllib.request
import urllib.error

# 全局 SSL context。默认验证证书; 传 --insecure 时使用不验证的 context,
# 以兼容走代理(MITM)导致证书链无法被 Python 识别的情况。
UNVERIFIED_CTX = ssl._create_unverified_context()

API_TEMPLATE = "https://api.asmr-200.com/api/tracks/{work_id}?v=2"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                  "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
    "Accept": "application/json",
    "Referer": "https://asmr.one/",
}
# 下载分块大小
CHUNK = 1024 * 256
# 失败重试次数
MAX_RETRY = 3


def extract_work_id(ident: str) -> str:
    """从 URL / RJ号 / 纯数字中提取 work_id。
    https://asmr.one/work/RJ01418453 -> 01418453
    RJ01418453 / RJ123456 -> 01418453
    1418453              -> 1418453
    """
    s = ident.strip().rstrip("/")
    # 取 URL 最后一段带 RJ 或纯数字的部分
    m = re.search(r"(RJ\s*\d+|RJ\d+|\d+)", s, re.IGNORECASE)
    if not m:
        raise ValueError(f"无法从输入提取作品ID: {ident!r}")
    token = m.group(1).upper()
    digits = re.sub(r"[^\d]", "", token)
    if not digits:
        raise ValueError(f"提取到的作品ID为空: {ident!r}")
    return digits


def _ctx(insecure: bool):
    """返回 ssl context: insecure 时跳过证书验证(代理 MITM 场景)。"""
    return UNVERIFIED_CTX if insecure else None


def fetch_tracks(work_id: str, timeout: int = 30, insecure: bool = False) -> list:
    """请求 tracks API, 返回 JSON 数组。"""
    url = API_TEMPLATE.format(work_id=work_id)
    req = urllib.request.Request(url, headers=HEADERS)
    last_err = None
    for attempt in range(1, MAX_RETRY + 1):
        try:
            with urllib.request.urlopen(req, timeout=timeout, context=_ctx(insecure)) as resp:
                import json
                data = json.load(resp)
            if not isinstance(data, list):
                raise ValueError(f"API 返回非数组: {type(data).__name__}")
            return data
        except Exception as e:
            last_err = e
            print(f"[tracks] 第 {attempt} 次请求失败: {e}", file=sys.stderr)
            if attempt < MAX_RETRY:
                time.sleep(2 * attempt)
    raise RuntimeError(f"获取作品 {work_id} 的文件清单失败: {last_err}")


def iter_entries(nodes: list, base_dir=""):
    """把 API 返回的树形结构展平为 (保存相对路径, 文件名, 下载URL, 大小) 迭代器。
    folder 元素 -> 子目录; audio/text 元素 -> 文件。
    """
    for node in nodes:
        if not isinstance(node, dict):
            continue
        ntype = node.get("type")
        if ntype == "folder":
            sub = node.get("title", "") if base_dir == "" else base_dir
            # folder 下 children 平铺在当前目录; 若 folder 有 title 则作为子目录
            child_dir = os.path.join(base_dir, str(node.get("title", ""))) if ntype == "folder" else base_dir
            for c in node.get("children", []) or []:
                if not isinstance(c, dict):
                    continue
                if c.get("type") == "folder":
                    yield from iter_entries([c], base_dir=child_dir)
                else:
                    yield _yield_file(child_dir, c)
        else:
            yield _yield_file(base_dir, node)


def _yield_file(dirpath, node):
    title = node.get("title") or ""
    url = node.get("mediaDownloadUrl") or ""
    size = node.get("size") or 0
    return (dirpath, title, url, size)


def download_file(url: str, save_path: str, expected_size=0, timeout: int = 60,
                  insecure: bool = False):
    """带断点续传/重试的单个文件下载, 返回是否成功。"""
    mode = "ab"
    exist_size = os.path.getsize(save_path) if os.path.exists(save_path) else 0
    if expected_size and exist_size >= expected_size:
        print(f"  [skip] 已存在 {save_path} ({exist_size} bytes)")
        return True

    for attempt in range(1, MAX_RETRY + 1):
        headers = dict(HEADERS)
        if exist_size > 0:
            headers["Range"] = f"bytes={exist_size}-"
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=timeout, context=_ctx(insecure)) as resp, open(save_path, mode) as f:
                total = exist_size
                while True:
                    chunk = resp.read(CHUNK)
                    if not chunk:
                        break
                    f.write(chunk)
                    total += len(chunk)
                    _progress(total, expected_size, save_path)
            # 校验
            if expected_size and total < expected_size:
                raise IOError(f"下载不完整 {total}/{expected_size}")
            print(f"  [ok] {save_path}")
            return True
        except Exception as e:
            print(f"  [retry {attempt}/{MAX_RETRY}] {os.path.basename(save_path)}: {e}", file=sys.stderr)
            exist_size = os.path.getsize(save_path) if os.path.exists(save_path) else 0
            if attempt < MAX_RETRY:
                time.sleep(2 * attempt)
    return False


def _progress(done, total, name):
    if not total:
        print(f"\r  {os.path.basename(name)}: {done/1024/1024:.1f} MB", end="", flush=True)
        return
    pct = done / total * 100
    bar_len = 30
    filled = int(bar_len * done / total)
    bar = "#" * filled + "-" * (bar_len - filled)
    print(f"\r  {os.path.basename(name)}: [{bar}] {pct:5.1f}% {done/1024/1024:.1f}MB/{total/1024/1024:.1f}MB", end="", flush=True)
    if done >= total:
        print()


def main():
    ap = argparse.ArgumentParser(description="asmr.one 作品下载工具")
    ap.add_argument("ident", help="作品标识: RJ号 / work URL / 纯数字")
    ap.add_argument("-o", "--outdir", default="downloads", help="下载保存根目录 (默认 downloads)")
    ap.add_argument("-f", "--format", default="", help="只下载指定格式, 如 mp3/wav (默认全部)")
    ap.add_argument("-k", "--insecure", action="store_true",
                    help="跳过 SSL 证书验证 (走代理/自签证书场景用)")
    args = ap.parse_args()

    work_id = extract_work_id(args.ident)
    print(f"[info] work_id = {work_id}")

    # 获取文件清单
    tracks = fetch_tracks(work_id, insecure=args.insecure)

    # 确定顶层输出目录(去掉前导0的RJ作品号作为目录名)
    dir_name = f"RJ{work_id.lstrip('0') or '0'}".upper()
    root = os.path.join(args.outdir, dir_name)
    os.makedirs(root, exist_ok=True)

    entries = list(iter_entries(tracks))
    print(f"[info] 共 {len(entries)} 个文件, 保存到 {root}")

    fmt_filter = args.format.lower() if args.format else None
    ok = 0
    fail = 0
    for rel_dir, title, url, size in entries:
        # 格式过滤: 按目录名(如 mp3/wav)或文件扩展名
        lower_title = title.lower()
        if fmt_filter:
            in_dir = fmt_filter in (rel_dir or "") .lower().split(os.sep)[-1:]
            in_ext = lower_title.endswith(fmt_filter)
            if not (in_dir or in_ext):
                continue
        if not url:
            print(f"  [warn] 无下载地址, 跳过 {rel_dir}/{title}")
            fail += 1
            continue
        save_dir = os.path.join(root, rel_dir) if rel_dir else root
        os.makedirs(save_dir, exist_ok=True)
        save_path = os.path.join(save_dir, title)
        if download_file(url, save_path, expected_size=size, insecure=args.insecure):
            ok += 1
        else:
            fail += 1

    print(f"\n[完成] 成功 {ok} 个, 失败 {fail} 个, 目录: {root}")
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())