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
    """Scan every root, then generate every thumbnail — the one-time cold-cache warm-up."""
    print("scanning:", scan.scan_all(cfg["roots"]))
    done = 0
    for root in cfg["roots"]:
        off = 0
        while True:
            _, items = db.list_media(root=root["path"], decision="all", offset=off, limit=500)
            if not items:
                break
            for it in items:
                dst = media.thumb_path(cfg["thumbCache"], it["id"])
                if media.ensure_thumb(it["file_path"], dst, it["file_type"], cfg["thumbSize"]):
                    done += 1
            off += len(items)
            print(f"  {root['label']}: {off} processed ({done} thumbs cached)")
    print(f"✅ warm complete: {done} thumbnails cached")


if __name__ == "__main__":
    main()
