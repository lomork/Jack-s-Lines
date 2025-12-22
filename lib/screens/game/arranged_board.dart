class ArrangedBoard {
  // 10x10 GRID = 100 ITEMS
  // ROW 0 is the TOP row. ROW 9 is the BOTTOM row.

  static const List<String> layout = [
    // --- ROW 0 (Top) ---
    "CORNER", "10C",   "9C",   "8C",   "7C",   "7H",  "8H",   "9H",   "10H",   "CORNER",

    // --- ROW 1 ---
    "10D",     "KD",   "6C",   "5C",   "4C",   "4H",   "5H",   "6H",   "KS",   "10S",

    // --- ROW 2 ---
    "9D",     "6D",   "QD",   "3C",   "2C",   "2H",   "3H",   "QS",  "6S",   "9S",

    // --- ROW 3 ---
    "8D",     "5D",   "3D",   "QC",   "AC",  "AH",   "QH",   "3S",   "5S",   "8S",

    // --- ROW 4 ---
    "7D",     "4D",   "2D",  "AD",   "KC",   "KH",   "AS",   "2S",   "4S",  "7S",

    // --- ROW 5 ---
    "7S",     "4S",   "2S",   "AS",   "KH",   "KC",   "AD",   "2D",   "4D",   "7D",

    // --- ROW 6 ---
    "8S",     "5S",   "3S",   "QH",   "AH",   "AC",   "QC",   "3D",   "5D",   "8D",

    // --- ROW 7 ---
    "9S",     "6S",   "QS",   "3H",   "2H",   "2C",   "3C",   "QD",   "6D",   "9D",

    // --- ROW 8 ---
    "10S",    "KS",  "6H",   "5H",   "4H",   "4C",   "5C",   "6C",   "KD",   "10D",

    // --- ROW 9 (Bottom) ---
    "CORNER", "10H",   "9H",   "8H",   "7H",   "7C",   "8C",   "9C",   "10C",   "CORNER",
  ];
}