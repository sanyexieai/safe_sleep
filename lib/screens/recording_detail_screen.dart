import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import '../services/audio_analyzer_service.dart';
import '../services/audio_player_service.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:audioplayers/audioplayers.dart';

class RecordingDetailScreen extends StatefulWidget {
  final String recordingPath;
  final AudioAnalyzerService analyzerService;

  const RecordingDetailScreen({
    super.key,
    required this.recordingPath,
    required this.analyzerService,
  });

  @override
  State<RecordingDetailScreen> createState() => _RecordingDetailScreenState();
}

class _RecordingDetailScreenState extends State<RecordingDetailScreen> {
  final AudioPlayerService _playerService = AudioPlayerService();
  List<double> _waveform = [];
  List<AnomalySegment> _anomalies = [];
  bool _isLoading = true;
  Duration? _totalDuration;
  Duration _currentPosition = Duration.zero;
  bool _isPlaying = false;
  DateTime? _recordingStartTime;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;

  @override
  void initState() {
    super.initState();
    _loadRecordingData();
    _setupAudioPlayer();
  }

  void _setupAudioPlayer() {
    _positionSubscription = _playerService.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    });

    _durationSubscription = _playerService.durationStream.listen((duration) {
      if (mounted && duration != Duration.zero) {
        setState(() {
          _totalDuration = duration;
        });
      }
    });

    _playerService.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });
  }

  Future<void> _loadRecordingData() async {
    setState(() => _isLoading = true);
    
    try {
      final file = File(widget.recordingPath);
      if (await file.exists()) {
        // 从文件名提取录音开始时间
        _recordingStartTime = _extractRecordingStartTime(widget.recordingPath);
        
        // 使用文件大小估算时长（实际时长会在播放时从播放器获取）
        final fileSize = await file.length();
        final estimatedSeconds = (fileSize / (128000 / 8)).round();
        _totalDuration = Duration(seconds: estimatedSeconds);
        
        // 提取波形
        _waveform = await widget.analyzerService.extractWaveform(
          widget.recordingPath,
          samples: 200,
        );
        
        // 检测异常
        _anomalies = await widget.analyzerService.detectAnomalies(
          widget.recordingPath,
          _waveform,
          _totalDuration!,
        );
      }
    } catch (e) {
      print('Error loading recording: $e');
    }
    
    setState(() => _isLoading = false);
  }

  DateTime? _extractRecordingStartTime(String path) {
    try {
      final fileName = _getFileName();
      // 从文件名提取时间戳 sleep_recording_20240101_120000.m4a
      final match = RegExp(r'(\d{8})_(\d{6})').firstMatch(fileName);
      if (match != null) {
        final dateStr = match.group(1)!; // 20240101
        final timeStr = match.group(2)!; // 120000
        
        // 手动解析日期和时间
        final year = int.parse(dateStr.substring(0, 4));
        final month = int.parse(dateStr.substring(4, 6));
        final day = int.parse(dateStr.substring(6, 8));
        final hour = int.parse(timeStr.substring(0, 2));
        final minute = int.parse(timeStr.substring(2, 4));
        final second = int.parse(timeStr.substring(4, 6));
        
        return DateTime(year, month, day, hour, minute, second);
      }
    } catch (e) {
      print('Error extracting recording start time: $e');
    }
    return null;
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _playerService.pause();
      setState(() => _isPlaying = false);
    } else {
      if (_currentPosition == Duration.zero || _currentPosition >= _totalDuration!) {
        await _playerService.play(widget.recordingPath);
      } else {
        await _playerService.resume();
      }
      setState(() => _isPlaying = true);
    }
  }

  Future<void> _stop() async {
    await _playerService.stop();
    setState(() {
      _isPlaying = false;
      _currentPosition = Duration.zero;
    });
  }

  Future<void> _seekTo(Duration position) async {
    await _playerService.seek(position);
    setState(() => _currentPosition = position);
  }

  String _formatTime(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    if (hours == '00') {
      return '$minutes:$seconds';
    }
    return '$hours:$minutes:$seconds';
  }

  String _formatDateTime(DateTime dateTime) {
    final year = dateTime.year.toString();
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  String _getFileName() {
    final parts = widget.recordingPath.split('/');
    return parts.last;
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerService.dispose();
    super.dispose();
  }

  Future<void> _showDeleteDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('确认删除'),
          content: const Text('确定要删除这条录音吗？删除后无法恢复。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        final file = File(widget.recordingPath);
        if (await file.exists()) {
          await file.delete();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('录音已删除'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.of(context).pop(true); // 返回并传递删除成功标志
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('删除失败，请重试'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('录音详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: _showDeleteDialog,
            tooltip: '删除录音',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 文件信息
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getFileName(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_totalDuration != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              '时长: ${_formatTime(_totalDuration!)}',
                              style: TextStyle(
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 播放控制
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // 进度条
                          if (_totalDuration != null && _totalDuration! > Duration.zero)
                            Column(
                              children: [
                                Slider(
                                  value: _currentPosition.inSeconds.toDouble().clamp(
                                    0.0,
                                    _totalDuration!.inSeconds.toDouble(),
                                  ),
                                  min: 0.0,
                                  max: _totalDuration!.inSeconds.toDouble(),
                                  onChanged: (value) {
                                    _seekTo(Duration(seconds: value.toInt()));
                                  },
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatTime(_currentPosition),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    Text(
                                      _formatTime(_totalDuration!),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          const SizedBox(height: 12),
                          // 播放按钮
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.stop),
                                onPressed: _stop,
                                iconSize: 32,
                              ),
                              const SizedBox(width: 16),
                              IconButton(
                                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                                onPressed: _togglePlayPause,
                                iconSize: 48,
                                color: Theme.of(context).primaryColor,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 波形图
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '音频波形',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 220,
                            child: _buildWaveformChart(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 异常列表
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '异常声音',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Chip(
                                label: Text('${_anomalies.length} 处'),
                                backgroundColor: _anomalies.isEmpty
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_anomalies.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: Text(
                                  '未检测到异常声音',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            )
                          else
                            ..._anomalies.asMap().entries.map((entry) {
                              final index = entry.key;
                              final anomaly = entry.value;
                              return _buildAnomalyItem(index + 1, anomaly);
                            }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildWaveformChart() {
    if (_waveform.isEmpty) {
      return const Center(
        child: Text('无波形数据'),
      );
    }

    if (_totalDuration == null || _totalDuration == Duration.zero) {
      return const Center(
        child: Text('加载中...'),
      );
    }

    // 计算时间轴标签
    final totalSeconds = _totalDuration!.inSeconds;
    final sampleCount = _waveform.length;
    final secondsPerSample = totalSeconds / sampleCount;
    
    // 计算显示5个标签的间隔
    final labelCount = 5;
    final interval = sampleCount / (labelCount - 1);

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey.withOpacity(0.2),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              interval: interval,
              getTitlesWidget: (value, meta) {
                // 只显示关键点的标签（0, interval, 2*interval, 3*interval, 4*interval）
                final normalizedValue = value / interval;
                final isKeyPoint = (normalizedValue - normalizedValue.round()).abs() < 0.01;
                
                if (!isKeyPoint) {
                  return const SizedBox.shrink(); // 不显示非关键点的标签
                }
                
                if (_recordingStartTime != null) {
                  // 计算该点对应的具体时间
                  final secondsOffset = (value * secondsPerSample).round();
                  final pointTime = _recordingStartTime!.add(Duration(seconds: secondsOffset));
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      _formatDateTime(pointTime),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 9,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                } else {
                  // 如果没有开始时间，显示相对时间
                  final time = Duration(
                    seconds: (value * secondsPerSample).round(),
                  );
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      _formatTime(time),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: 25,
              getTitlesWidget: (value, meta) {
                return Text(
                  '${value.toInt()}%',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(color: Colors.grey.withOpacity(0.3)),
            left: BorderSide(color: Colors.grey.withOpacity(0.3)),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: _waveform.asMap().entries.map((entry) {
              return FlSpot(
                entry.key.toDouble(),
                entry.value * 100,
              );
            }).toList(),
            isCurved: true,
            color: Colors.blue,
            barWidth: 2,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.blue.withOpacity(0.1),
            ),
          ),
          // 播放位置指示线
          if (_isPlaying && _currentPosition > Duration.zero)
            LineChartBarData(
              spots: [
                FlSpot(
                  (_currentPosition.inSeconds / secondsPerSample).clamp(0.0, sampleCount.toDouble()),
                  0,
                ),
                FlSpot(
                  (_currentPosition.inSeconds / secondsPerSample).clamp(0.0, sampleCount.toDouble()),
                  100,
                ),
              ],
              isCurved: false,
              color: Colors.red,
              barWidth: 2,
              dotData: FlDotData(show: false),
            ),
        ],
        minY: 0,
        maxY: 100,
        minX: 0,
        maxX: sampleCount.toDouble(),
      ),
    );
  }

  Widget _buildAnomalyItem(int index, AnomalySegment anomaly) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.orange,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$index',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  anomaly.type.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatTime(anomaly.startTime)} - ${_formatTime(anomaly.endTime)}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                Text(
                  '持续时间: ${_formatTime(anomaly.duration)}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${(anomaly.amplitude * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

