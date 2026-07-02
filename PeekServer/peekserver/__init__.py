"""PeekServer — a LAN media-review service.

A small, dependency-free (Python stdlib + macOS `sips`/`qlmanage`) HTTP service that lets you
review "NEW … TO REVIEW" media folders fast from any Mac/iPad on the local network. It serves
cached thumbnails (so browsing never reads the big originals off slow/remote storage) and holds
ONE authoritative decisions database (keep/skip/favorite/title/caption/keywords/albums), so review
state is shared across every client. Runs on whichever host has the media attached (Vortex now,
the "airy" runner later).

Companion to the PurplePeek macOS app — it mirrors PurplePeek's data model and keep→Photos
pipeline (Phase 2 delegates the actual import to exiftool + osxphotos).
"""

__version__ = "0.7.2"
