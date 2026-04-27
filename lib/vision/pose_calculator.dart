import 'dart:math';

class PoseCalculator {
  // 傳入 Kotlin 給你的四個坐標，回傳寬度
  static double getWidth(double x1, double y1, double x2, double y2) {
    return sqrt(pow(x1 - x2, 2) + pow(y1 - y2, 2));
  }
}