# art/

Source artwork for Epochs.

## Drop the board scan here

Put a high-resolution scan (or square-on photo) of the physical board in this
folder, named **`board.png`** (or `board.jpg`). Then tell Claude "it's in art/"
and it will:

1. become the map image the game renders (letterboxed to keep the board's real
   proportions), and
2. be read to rebuild the real territory data in `src/shared/data/board.ts`
   (the actual lands, the colour regions, the named seas, resource lands,
   terrain, and adjacencies).

Tips: the higher the resolution the better; shoot/scan flat and square-on so the
board isn't skewed; include the whole board (sea names, region colours, resource
symbols). Any other source images can live here too.
