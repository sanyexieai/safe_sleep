import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/services.dart';

class AudioDecoderService {
  static const MethodChannel _channel = MethodChannel('com.example.safe_sleep/audio_decoder');

  /// 将音频文件解码为PCM数据
  Future<Uint8List?> decodeToPCM(String audioPath) async {
    try {
      if (Platform.isAndroid) {
        final result = await _channel.invokeMethod<Uint8List>('decodeToPCM', {
          'audioPath': audioPath,
        });
        return result;
      }
      return null;
    } catch (e) {
      print('Error decoding audio to PCM: $e');
      return null;
    }
  }

  /// 从PCM数据提取波形
  List<double> extractWaveformFromPCM(
    Uint8List pcmData,
    int sampleRate,
    int channels,
    int samples,
  ) {
    if (pcmData.isEmpty) {
      return List.filled(samples, 0.0);
    }

    // PCM数据通常是16位（2字节）采样
    final bytesPerSample = 2 * channels; // 16位 = 2字节，乘以声道数
    final totalSamples = pcmData.length ~/ bytesPerSample;
    final samplesPerPoint = (totalSamples / samples).ceil();

    final waveform = <double>[];
    
    for (int i = 0; i < samples; i++) {
      final startSample = i * samplesPerPoint;
      final endSample = ((i + 1) * samplesPerPoint).clamp(0, totalSamples);
      
      if (startSample >= totalSamples) {
        waveform.add(0.0);
        continue;
      }

      // 计算该段的RMS值
      double sumSquares = 0.0;
      int count = 0;

      for (int j = startSample; j < endSample && j < totalSamples; j++) {
        final byteIndex = j * bytesPerSample;
        if (byteIndex + 1 < pcmData.length) {
          // 读取16位PCM样本（小端序，Android MediaCodec默认）
          // 低字节在前，高字节在后
          final lowByte = pcmData[byteIndex];
          final highByte = pcmData[byteIndex + 1];
          // 组合为16位无符号整数
          final unsignedSample = (highByte << 8) | lowByte;
          // 转换为有符号16位整数（-32768 到 32767）
          int signedSample = unsignedSample > 32767 ? unsignedSample - 65536 : unsignedSample;
          // 归一化到-1.0到1.0范围
          final normalized = signedSample / 32768.0;
          sumSquares += normalized * normalized;
          count++;
        }
      }

      if (count > 0) {
        final rms = sqrt(sumSquares / count);
        waveform.add(rms);
      } else {
        waveform.add(0.0);
      }
    }

    // 归一化到0-1范围
    if (waveform.isNotEmpty) {
      final maxValue = waveform.reduce((a, b) => a > b ? a : b);
      if (maxValue > 0) {
        return waveform.map((value) => (value / maxValue).clamp(0.0, 1.0)).toList();
      }
    }

    return waveform;
  }

  /// 提取波形数据（完整流程：解码+提取）
  Future<List<double>> extractWaveform(
    String audioPath, {
    int samples = 200,
    int sampleRate = 44100,
    int channels = 1,
  }) async {
    try {
      // 先解码为PCM
      final pcmData = await decodeToPCM(audioPath);
      
      if (pcmData != null && pcmData.isNotEmpty) {
        // 从PCM数据提取波形
        final waveform = extractWaveformFromPCM(pcmData, sampleRate, channels, samples);
        
        // 验证波形数据有效性
        if (waveform.isNotEmpty && waveform.any((v) => v > 0.01)) {
          return waveform;
        }
      }
      
      // 如果解码失败或数据无效，返回空波形
      print('PCM decoding returned empty or invalid data');
      return List.filled(samples, 0.0);
    } catch (e) {
      print('Error extracting waveform from PCM: $e');
      return List.filled(samples, 0.0);
    }
  }
}

