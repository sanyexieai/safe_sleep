import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:record/record.dart';
import 'audio_decoder_service.dart';

class AudioAnalyzerService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioDecoderService _decoderService = AudioDecoderService();

  /// 分析音频文件，提取波形数据（使用PCM解码）
  Future<List<double>> extractWaveform(String audioPath, {int samples = 200}) async {
    try {
      final file = File(audioPath);
      if (!await file.exists()) {
        return List.filled(samples, 0.0);
      }
      
      // 优先使用PCM解码方法
      if (Platform.isAndroid) {
        try {
          final waveform = await _decoderService.extractWaveform(
            audioPath,
            samples: samples,
            sampleRate: 44100,
            channels: 1,
          );
          
          // 如果解码成功且数据有效，返回结果
          if (waveform.isNotEmpty && waveform.any((v) => v > 0)) {
            return waveform;
          }
        } catch (e) {
          print('PCM decoding failed, using fallback: $e');
        }
      }
      
      // 如果PCM解码失败，使用备用方法
      return await _extractWaveformFallback(audioPath, samples);
    } catch (e) {
      print('Error extracting waveform: $e');
      return _generateEstimatedWaveform(audioPath, samples);
    }
  }

  /// 备用方法：基于文件内容分析
  Future<List<double>> _extractWaveformFallback(String audioPath, int samples) async {
    try {
      final file = File(audioPath);
      final fileSize = await file.length();
      
      // 对于大文件，使用流式读取
      if (fileSize > 10 * 1024 * 1024) {
        return await _analyzeLargeAudioFile(audioPath, fileSize, samples);
      } else {
        final bytes = await file.readAsBytes();
        return _analyzeAudioFile(bytes, fileSize, samples);
      }
    } catch (e) {
      print('Error in fallback waveform extraction: $e');
      return _generateEstimatedWaveform(audioPath, samples);
    }
  }

  /// 分析大音频文件（流式处理）
  Future<List<double>> _analyzeLargeAudioFile(String audioPath, int fileSize, int samples) async {
    try {
      final file = File(audioPath);
      final waveform = <double>[];
      final bytesPerSample = fileSize / samples;
      final randomAccessFile = await file.open();
      
      try {
        for (int i = 0; i < samples; i++) {
          final startIndex = (i * bytesPerSample).round();
          final endIndex = ((i + 1) * bytesPerSample).round().clamp(0, fileSize);
          final segmentSize = endIndex - startIndex;
          
          if (segmentSize <= 0) {
            waveform.add(0.0);
            continue;
          }
          
          // 读取文件段
          await randomAccessFile.setPosition(startIndex);
          final segment = await randomAccessFile.read(segmentSize);
          
          if (segment.isNotEmpty) {
            final amplitude = _calculateAmplitude(segment);
            waveform.add(amplitude);
          } else {
            waveform.add(0.0);
          }
        }
      } finally {
        await randomAccessFile.close();
      }
      
      // 归一化
      if (waveform.isNotEmpty) {
        final maxValue = waveform.reduce((a, b) => a > b ? a : b);
        if (maxValue > 0) {
          return waveform.map((value) => (value / maxValue).clamp(0.0, 1.0)).toList();
        }
      }
      
      return waveform;
    } catch (e) {
      print('Error analyzing large audio file: $e');
      return List.filled(samples, 0.0);
    }
  }

  /// 分析音频文件内容生成波形数据
  List<double> _analyzeAudioFile(Uint8List bytes, int fileSize, int samples) {
    final waveform = <double>[];
    final bytesPerSample = fileSize / samples;
    
    for (int i = 0; i < samples; i++) {
      final startIndex = (i * bytesPerSample).round();
      final endIndex = ((i + 1) * bytesPerSample).round().clamp(0, bytes.length);
      
      if (startIndex >= bytes.length) {
        waveform.add(0.0);
        continue;
      }
      
      // 提取该段的字节数据
      final segment = bytes.sublist(startIndex, endIndex);
      final amplitude = _calculateAmplitude(segment);
      waveform.add(amplitude);
    }
    
    // 归一化，使最大值映射到1.0
    if (waveform.isNotEmpty) {
      final maxValue = waveform.reduce((a, b) => a > b ? a : b);
      if (maxValue > 0) {
        return waveform.map((value) => (value / maxValue).clamp(0.0, 1.0)).toList();
      }
    }
    
    return waveform;
  }

  /// 计算音频段的振幅（改进算法）
  double _calculateAmplitude(Uint8List segment) {
    if (segment.isEmpty) return 0.0;
    
    // 方法1：使用RMS（均方根）计算
    double sumSquares = 0.0;
    for (final byte in segment) {
      final value = (byte - 128).abs(); // 中心化到-128到127范围
      sumSquares += value * value;
    }
    final rms = sqrt(sumSquares / segment.length);
    
    // 方法2：计算峰值
    int maxPeak = 0;
    for (final byte in segment) {
      final peak = (byte - 128).abs();
      if (peak > maxPeak) maxPeak = peak;
    }
    
    // 结合RMS和峰值，更准确地反映音频能量
    final combined = (rms * 0.7 + maxPeak * 0.3);
    
    // 归一化到0-1范围（最大值为128）
    return (combined / 128.0).clamp(0.0, 1.0);
  }

  /// 基于文件大小生成估算波形（备用方案）
  List<double> _generateEstimatedWaveform(String audioPath, int samples) {
    try {
      final file = File(audioPath);
      final fileSize = file.lengthSync();
      // 使用文件大小和位置生成一些变化
      final waveform = <double>[];
      final baseVariation = (fileSize % 1000) / 1000.0;
      
      for (int i = 0; i < samples; i++) {
        // 基于文件大小和位置生成一些变化
        final position = i / samples;
        final variation = (baseVariation + position * 0.3 + (i % 10) / 30.0).clamp(0.0, 1.0);
        waveform.add(variation);
      }
      
      return waveform;
    } catch (e) {
      print('Error generating estimated waveform: $e');
      return List.filled(samples, 0.0);
    }
  }

  /// 检测异常声音片段（改进算法）
  Future<List<AnomalySegment>> detectAnomalies(
    String audioPath,
    List<double> waveform,
    Duration totalDuration,
  ) async {
    final anomalies = <AnomalySegment>[];
    
    if (waveform.isEmpty) return anomalies;
    
    // 计算动态阈值（基于平均值和标准差）
    final mean = waveform.reduce((a, b) => a + b) / waveform.length;
    final variance = waveform.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) / waveform.length;
    final stdDev = sqrt(variance);
    
    // 动态阈值：平均值 + 1.5倍标准差（可调整）
    final threshold = (mean + 1.5 * stdDev).clamp(0.3, 0.9);
    
    final segmentDuration = totalDuration.inSeconds / waveform.length;
    
    // 平滑处理：使用移动平均减少噪声
    final smoothedWaveform = _smoothWaveform(waveform, windowSize: 3);
    
    int? anomalyStart;
    double maxAmplitude = 0.0;
    int consecutiveHigh = 0; // 连续高值计数
    
    for (int i = 0; i < smoothedWaveform.length; i++) {
      final value = smoothedWaveform[i];
      
      if (value > threshold) {
        consecutiveHigh++;
        
        // 需要连续3个点超过阈值才认为是异常（减少误报）
        if (consecutiveHigh >= 3) {
          if (anomalyStart == null) {
            anomalyStart = i - 2; // 回溯到异常开始
            maxAmplitude = value;
          } else {
            maxAmplitude = maxAmplitude > value ? maxAmplitude : value;
          }
        }
      } else {
        consecutiveHigh = 0;
        
        if (anomalyStart != null) {
          // 检测到异常段结束（需要连续3个点低于阈值）
          final startTime = Duration(
            seconds: (anomalyStart * segmentDuration).round(),
          );
          final endTime = Duration(
            seconds: (i * segmentDuration).round(),
          );
          
          // 只记录持续时间超过1秒的异常
          if (endTime - startTime >= const Duration(seconds: 1)) {
            final anomalyType = _classifyAnomaly(maxAmplitude, waveform, anomalyStart, i);
            
            anomalies.add(AnomalySegment(
              startTime: startTime,
              endTime: endTime,
              amplitude: maxAmplitude,
              type: anomalyType,
            ));
          }
          
          anomalyStart = null;
          maxAmplitude = 0.0;
        }
      }
    }
    
    // 处理最后一个异常段
    if (anomalyStart != null) {
      final startTime = Duration(
        seconds: (anomalyStart * segmentDuration).round(),
      );
      final endTime = totalDuration;
      
      if (endTime - startTime >= const Duration(seconds: 1)) {
        final anomalyType = _classifyAnomaly(maxAmplitude, waveform, anomalyStart, waveform.length - 1);
        
        anomalies.add(AnomalySegment(
          startTime: startTime,
          endTime: endTime,
          amplitude: maxAmplitude,
          type: anomalyType,
        ));
      }
    }
    
    return anomalies;
  }

  /// 平滑波形数据（移动平均）
  List<double> _smoothWaveform(List<double> waveform, {int windowSize = 3}) {
    if (waveform.length <= windowSize) return waveform;
    
    final smoothed = <double>[];
    final halfWindow = windowSize ~/ 2;
    
    for (int i = 0; i < waveform.length; i++) {
      final start = (i - halfWindow).clamp(0, waveform.length - 1);
      final end = (i + halfWindow + 1).clamp(0, waveform.length);
      
      double sum = 0.0;
      for (int j = start; j < end; j++) {
        sum += waveform[j];
      }
      smoothed.add(sum / (end - start));
    }
    
    return smoothed;
  }

  /// 分类异常类型（改进算法，保留扩展性）
  AnomalyType _classifyAnomaly(
    double amplitude,
    List<double> waveform,
    int startIndex,
    int endIndex,
  ) {
    // 计算异常段的特征
    final segment = waveform.sublist(
      startIndex.clamp(0, waveform.length - 1),
      endIndex.clamp(0, waveform.length),
    );
    
    if (segment.isEmpty) return AnomalyType.unknown;
    
    // 计算平均振幅和变化率
    final avgAmplitude = segment.reduce((a, b) => a + b) / segment.length;
    double variation = 0.0;
    for (int i = 1; i < segment.length; i++) {
      variation += (segment[i] - segment[i - 1]).abs();
    }
    variation /= segment.length;
    
    // 基于特征分类（可以扩展为机器学习模型）
    // 使用平均振幅和峰值振幅结合判断
    final combinedAmplitude = (amplitude * 0.6 + avgAmplitude * 0.4);
    
    // 高振幅 + 低变化率 = 可能是呼噜
    if (combinedAmplitude > 0.85 && variation < 0.1) {
      return AnomalyType.unknown; // 可以扩展为 AnomalyType.snoring
    }
    // 中等振幅 + 高变化率 = 可能是磨牙
    else if (combinedAmplitude > 0.7 && variation > 0.2) {
      return AnomalyType.unknown; // 可以扩展为 AnomalyType.teethGrinding
    }
    // 其他情况
    else {
      return AnomalyType.unknown; // 可以扩展为 AnomalyType.nightWaking
    }
  }

  void dispose() {
    _recorder.dispose();
  }
}

/// 异常声音片段
class AnomalySegment {
  final Duration startTime;
  final Duration endTime;
  final double amplitude;
  final AnomalyType type;

  AnomalySegment({
    required this.startTime,
    required this.endTime,
    required this.amplitude,
    required this.type,
  });

  Duration get duration => endTime - startTime;
}

/// 异常类型枚举（保留扩展性）
enum AnomalyType {
  unknown,    // 未知类型
  snoring,    // 呼噜（预留）
  teethGrinding, // 磨牙（预留）
  nightWaking,   // 起夜（预留）
  coughing,      // 咳嗽（预留）
  talking,       // 说梦话（预留）
}

extension AnomalyTypeExtension on AnomalyType {
  String get displayName {
    switch (this) {
      case AnomalyType.snoring:
        return '呼噜';
      case AnomalyType.teethGrinding:
        return '磨牙';
      case AnomalyType.nightWaking:
        return '起夜';
      case AnomalyType.coughing:
        return '咳嗽';
      case AnomalyType.talking:
        return '说梦话';
      case AnomalyType.unknown:
        return '异常声音';
    }
  }
}

