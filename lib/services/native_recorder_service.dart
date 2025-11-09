import 'package:flutter/services.dart';

class NativeRecorderService {
  static const MethodChannel _channel = MethodChannel('com.example.safe_sleep/native_recorder');

  /// 开始录音
  static Future<bool> startRecording(String outputPath) async {
    try {
      print('Starting native recording: $outputPath');
      final result = await _channel.invokeMethod<bool>('startRecording', {
        'outputPath': outputPath,
      });
      print('Native recording start result: $result');
      return result ?? false;
    } catch (e) {
      print('Error starting native recording: $e');
      return false;
    }
  }

  /// 停止录音
  static Future<String?> stopRecording() async {
    try {
      print('Stopping native recording...');
      final result = await _channel.invokeMethod<String>('stopRecording');
      print('Native recording stop result: $result');
      return result;
    } catch (e) {
      print('Error stopping native recording: $e');
      return null;
    }
  }

  /// 检查是否正在录音
  static Future<bool> isRecording() async {
    try {
      final result = await _channel.invokeMethod<bool>('isRecording');
      return result ?? false;
    } catch (e) {
      print('Error checking native recording status: $e');
      return false;
    }
  }

  /// 获取当前录音文件路径
  static Future<String?> getOutputPath() async {
    try {
      final result = await _channel.invokeMethod<String>('getOutputPath');
      return result;
    } catch (e) {
      print('Error getting native recording output path: $e');
      return null;
    }
  }
}

