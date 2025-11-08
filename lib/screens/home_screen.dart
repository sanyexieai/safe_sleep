import 'package:flutter/material.dart';
import 'dart:async';
import '../services/audio_recorder_service.dart';
import '../services/audio_analyzer_service.dart';
import 'recording_detail_screen.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AudioRecorderService _recorderService = AudioRecorderService();
  final AudioAnalyzerService _analyzerService = AudioAnalyzerService();
  Duration _recordingDuration = Duration.zero;
  StreamSubscription<Duration>? _durationSubscription;
  List<String> _recordedFiles = [];
  bool _isLoading = false;
  bool _localeInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeLocale();
  }

  Future<void> _initializeLocale() async {
    await initializeDateFormatting('zh_CN', null);
    if (mounted) {
      setState(() {
        _localeInitialized = true;
      });
      _loadRecordedFiles();
    }
  }

  Future<void> _loadRecordedFiles() async {
    setState(() => _isLoading = true);
    final files = await _recorderService.getRecordedFiles();
    setState(() {
      _recordedFiles = files;
      _isLoading = false;
    });
  }

  Future<void> _startRecording() async {
    final success = await _recorderService.startRecording();
    if (success) {
      _durationSubscription = _recorderService.durationStream?.listen((duration) {
        setState(() {
          _recordingDuration = duration;
        });
      });
      setState(() {});
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法开始录音，请检查麦克风权限')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    final path = await _recorderService.stopRecording();
    _durationSubscription?.cancel();
    _durationSubscription = null;
    setState(() {
      _recordingDuration = Duration.zero;
    });
    
    if (path != null) {
      await _loadRecordedFiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('录音已保存')),
        );
      }
    }
  }

  Future<void> _showDeleteDialog(BuildContext context, String filePath) async {
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
      final success = await _recorderService.deleteRecording(filePath);
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('录音已删除'),
              backgroundColor: Colors.green,
            ),
          );
          await _loadRecordedFiles();
        } else {
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

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _getFileName(String path) {
    final parts = path.split('/');
    return parts.last;
  }

  String _getWeekdayName(int weekday) {
    const weekdays = ['', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    if (weekday >= 1 && weekday <= 7) {
      return weekdays[weekday];
    }
    return '';
  }

  DateTime? _getFileDate(String path) {
    try {
      final fileName = _getFileName(path);
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
      print('Error parsing file date: $e');
    }
    return null;
  }

  @override
  void dispose() {
    _durationSubscription?.cancel();
    _recorderService.dispose();
    _analyzerService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safe Sleep'),
        elevation: 2,
      ),
      body: Column(
        children: [
          // 录音控制区域
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                const Text(
                  '睡眠监测',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                if (_recorderService.isRecording) ...[
                  const Icon(
                    Icons.mic,
                    size: 48,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatDuration(_recordingDuration),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _stopRecording,
                    icon: const Icon(Icons.stop),
                    label: const Text('停止录音'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                  ),
                ] else ...[
                  const Icon(
                    Icons.mic_none,
                    size: 48,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _startRecording,
                    icon: const Icon(Icons.fiber_manual_record),
                    label: const Text('开始录音'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // 录音列表
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _recordedFiles.isEmpty
                    ? const Center(
                        child: Text(
                          '暂无录音记录',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _recordedFiles.length,
                        itemBuilder: (context, index) {
                          final filePath = _recordedFiles[index];
                          final fileDate = _getFileDate(filePath);
                          
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: const Icon(Icons.audiotrack, size: 32),
                              title: Text(
                                fileDate != null
                                    ? DateFormat('yyyy-MM-dd HH:mm').format(fileDate)
                                    : _getFileName(filePath),
                              ),
                              subtitle: Text(
                                fileDate != null && _localeInitialized
                                    ? DateFormat('EEEE', 'zh_CN').format(fileDate)
                                    : fileDate != null
                                        ? _getWeekdayName(fileDate.weekday)
                                        : '',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _showDeleteDialog(context, filePath),
                                    tooltip: '删除',
                                  ),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => RecordingDetailScreen(
                                      recordingPath: filePath,
                                      analyzerService: _analyzerService,
                                    ),
                                  ),
                                ).then((deleted) {
                                  // 如果返回true，说明录音被删除了，刷新列表
                                  if (deleted == true) {
                                    _loadRecordedFiles();
                                  }
                                });
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

