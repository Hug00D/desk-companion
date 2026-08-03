import 'package:flutter/material.dart';

/// 全域路由觀察者，讓畫面能得知自己是否被其他畫面覆蓋（或重新顯示）。
///
/// 搭配 [RouteAware] 使用：`didPushNext()` 代表本畫面被新畫面蓋住，
/// `didPopNext()` 代表覆蓋在上方的畫面被移除、本畫面重新顯示。
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
