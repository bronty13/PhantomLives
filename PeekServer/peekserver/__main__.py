"""Entry point: `python3 -m peekserver [command]`.

  (no args)              serve the review UI/API (kicks an initial background scan)
  --warm                 scan + pre-generate ALL thumbnails, then exit (the one-time cold-cache pass)
  --migrate-purplepeek [DB]   import existing PurplePeek decisions (default: config purplePeekDb), then exit
  --import [--execute] [--limit N]   run the keep→Photos worker (DRY-RUN unless --execute)
"""
import argparse
import json

from . import config, db, importer, media, migrate, scan, server


def main():
    ap = argparse.ArgumentParser(prog="peekserver")
    ap.add_argument("--warm", action="store_true",
                    help="scan + pre-generate all thumbnails, then exit")
    ap.add_argument("--migrate-purplepeek", nargs="?", const="", metavar="DB",
                    help="import PurplePeek decisions (default: config purplePeekDb), then exit")
    ap.add_argument("--import", dest="do_import", action="store_true",
                    help="run the keep→Photos import worker, then exit")
    ap.add_argument("--execute", action="store_true",
                    help="with --import: actually import/trash (default is a dry-run)")
    ap.add_argument("--limit", type=int, default=None, help="cap items processed")
    a = ap.parse_args()

    cfg = config.load()
    db.init(cfg["dbPath"])

    if a.warm:
        return warm(cfg)
    if a.migrate_purplepeek is not None:
        pp = a.migrate_purplepeek or cfg["purplePeekDb"]
        print(json.dumps(migrate.migrate_from_purplepeek(pp), indent=2))
        return
    if a.do_import:
        res = importer.process_pending(cfg, execute=a.execute, limit=a.limit)
        print(json.dumps(res["summary"], indent=2))
        if not a.execute:
            print("(dry-run — pass --execute to apply)")
        return

    # default: serve
    server._CFG = cfg
    server.background_scan()
    server.run(cfg)


def warm(cfg):
    """Scan every root, then generate every thumbnail concurrently — the one-time cold-cache pass.
    Parallel workers overlap the slow per-file reads (sips/qlmanage are subprocesses), which is the
    whole point on a slow drive: serial generation is what makes first-browse 'unusably slow'."""
    from concurrent.futures import ThreadPoolExecutor
    print("scanning:", scan.scan_all(cfg["roots"]))
    items = []
    for root in cfg["roots"]:
        off = 0
        while True:
            _, batch = db.list_media(root=root["path"], decision="all", offset=off, limit=500)
            if not batch:
                break
            items += batch
            off += len(batch)
    total = len(items)
    print(f"warming {total} thumbnails ({cfg.get('warmWorkers', 6)} workers)…")
    cache, size = cfg["thumbCache"], cfg["thumbSize"]

    def one(it):
        return media.ensure_thumb(it["file_path"], media.thumb_path(cache, it["id"]),
                                  it["file_type"], size)

    done = 0
    with ThreadPoolExecutor(max_workers=cfg.get("warmWorkers", 6)) as ex:
        for i, ok in enumerate(ex.map(one, items), 1):
            if ok:
                done += 1
            if i % 250 == 0 or i == total:
                print(f"  {i}/{total} processed ({done} cached)")
    print(f"✅ warm complete: {done}/{total} thumbnails cached")

    # Video streaming proxies (720p faststart) — transcode each video once so review playback is
    # smooth over the LAN. Serial: ffmpeg already uses many cores, so parallel transcodes just thrash.
    vids = [it for it in items if it["file_type"] == "video"]
    if vids:
        pcache, ff = cfg["proxyCache"], cfg.get("ffmpegBin", "ffmpeg")
        ph, pbr = cfg.get("proxyHeight", 720), cfg.get("proxyMaxBitrateK", 4000)
        print(f"generating {len(vids)} video proxies…")
        pdone = 0
        for i, it in enumerate(vids, 1):
            dst = media.proxy_path(pcache, it["id"])
            if media.ensure_video_proxy(it["file_path"], dst, ff, ph, pbr):
                pdone += 1
            if i % 25 == 0 or i == len(vids):
                print(f"  proxy {i}/{len(vids)} ({pdone} ok)")
        print(f"✅ proxies: {pdone}/{len(vids)} cached")


if __name__ == "__main__":
    main()
