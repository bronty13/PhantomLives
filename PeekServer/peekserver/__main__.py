"""Entry point: `python3 -m peekserver`. Loads config, opens the DB, kicks an initial
background scan, then serves until interrupted.
"""
from . import config, db, server


def main():
    cfg = config.load()
    db.init(cfg["dbPath"])
    server._CFG = cfg          # make config available to background_scan
    server.background_scan()   # initial scan runs in its own thread (server starts immediately)
    server.run(cfg)            # blocks (Ctrl-C to stop)


if __name__ == "__main__":
    main()
