import 'package:flutter/services.dart';

class ForegroundService {
  static const MethodChannel _channel = MethodChannel('com.example.safe_sleep/foreground_service');

  /// 启动前台服务（用于保持应用在后台运行）
  static Future<bool> start() async {
    try {
      print('Starting foreground service...');
      final result = await _channel.invokeMethod<bool>('startForegroundService');
      print('Foreground service start result: $result');
      return result ?? false;
    } catch (e) {
      print('Error starting foreground service: $e');
      print('Stack trace: ${StackTrace.current}');
      return false;
    }
  }

  /// 停止前台服务
  static Future<bool> stop() async {
    try {
      final result = await _channel.invokeMethod<bool>('stopForegroundService');
      return result ?? false;
    } catch (e) {
      print('Error stopping foreground service: $e');
      return false;
    }
  }
}

