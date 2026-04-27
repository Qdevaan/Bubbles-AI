import 'dart:math';

int xpForLevel(int level) => 50 * level * (level - 1);

int levelForXp(int totalXp) {
  // Inverse of xpForLevel's quadratic: solves totalXp = 50·level·(level-1) for level.
  if (totalXp <= 0) return 1;
  final level = ((1 + sqrt(1 + 4 * totalXp / 50)) / 2).floor();
  return max(1, level);
}
