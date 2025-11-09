import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'foreground_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'native_recorder_service.dart';

class AudioRecorderService {
  // 单例模式
  static final AudioRecorderService _instance = AudioRecorderService._internal();
  factory AudioRecorderService() => _instance;
  AudioRecorderService._internal();

  bool _isRecording = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  StreamController<Duration>? _durationController;
  Timer? _durationTimer;
  
  static const String _prefKeyRecordingPath = 'recording_path';
  static const String _prefKeyRecordingStartTime = 'recording_start_time';

  bool get isRecording => _isRecording;
  String? get currentRecordingPath => _currentRecordingPath;
  DateTime? get recordingStartTime => _recordingStartTime;

  Stream<Duration>? get durationStream => _durationController?.stream;

  Future<bool> checkPermissions() async {
    // 检查麦克风权限
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      return false;
    }
    
    // Android 13+ 需要通知权限
    if (Platform.isAndroid) {
      final notificationStatus = await Permission.notification.request();
      if (!notificationStatus.isGranted) {
        print('Warning: Notification permission not granted. Foreground service may not show notification.');
      }
    }
    
    return true;
  }

  Future<bool> startRecording() async {
    if (_isRecording) return false;

    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      return false;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'sleep_recording_$timestamp.m4a';
      _currentRecordingPath = path.join(directory.path, fileName);
      _recordingStartTime = DateTime.now();

      // 使用原生录音（在 Android 原生层运行，应用恢复时不会停止）
      final success = await NativeRecorderService.startRecording(_currentRecordingPath!);
      if (!success) {
        print('Failed to start native recording');
        return false;
      }

      // 保存录音状态到 SharedPreferences
      await _saveRecordingState();

      // 启动前台服务以保持应用在后台运行
      await ForegroundService.start();

      _isRecording = true;
      _durationController = StreamController<Duration>();
      _startDurationTimer();
      print('Native recording started successfully: $_currentRecordingPath');
      return true;
    } catch (e) {
      print('Error starting recording: $e');
      return false;
    }
  }
  
  /// 保存录音状态
  Future<void> _saveRecordingState() async {
    if (_currentRecordingPath != null && _recordingStartTime != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyRecordingPath, _currentRecordingPath!);
      await prefs.setString(_prefKeyRecordingStartTime, _recordingStartTime!.toIso8601String());
    }
  }
  
  /// 清除录音状态
  Future<void> _clearRecordingState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyRecordingPath);
    await prefs.remove(_prefKeyRecordingStartTime);
  }
  
  /// 恢复录音状态（应用恢复时调用）
  /// 优先从 SharedPreferences 恢复，因为单例可能在应用恢复时被重置
  Future<bool> restoreRecordingState() async {
    try {
      print('Restoring recording state...');
      print('Singleton state: _isRecording=$_isRecording, path=$_currentRecordingPath');
      
      // 首先检查 SharedPreferences（更可靠，因为单例可能在应用恢复时被重置）
      final prefs = await SharedPreferences.getInstance();
      final savedPath = prefs.getString(_prefKeyRecordingPath);
      final savedStartTimeStr = prefs.getString(_prefKeyRecordingStartTime);
      
      if (savedPath == null || savedStartTimeStr == null) {
        print('No saved recording state found in SharedPreferences');
        // 如果 SharedPreferences 中没有，但单例中有，也尝试恢复
        if (_isRecording && _currentRecordingPath != null && _recordingStartTime != null) {
          print('But singleton has state, trying to restore from singleton...');
          return await _restoreFromSingleton();
        }
        return false;
      }
      
      print('Found saved state in SharedPreferences: path=$savedPath, startTime=$savedStartTimeStr');
      
      // 检查文件是否存在
      final file = File(savedPath);
      if (!await file.exists()) {
        print('Recording file does not exist: $savedPath');
        await _clearRecordingState();
        await ForegroundService.stop();
        return false;
      }
      
      // 检查原生录音器是否还在录音
      bool isRecording = false;
      String? nativePath;
      try {
        isRecording = await NativeRecorderService.isRecording();
        nativePath = await NativeRecorderService.getOutputPath();
        print('Native isRecording() returned: $isRecording');
        print('Native output path: $nativePath');
      } catch (e) {
        print('Error checking native recording status: $e');
      }
      
      // 如果原生录音器还在录音，直接恢复状态
      if (isRecording) {
        // 使用原生录音器的路径（如果可用），否则使用保存的路径
        final pathToUse = nativePath ?? savedPath;
        print('Native recording is still active! Restoring state...');
        print('Using path: $pathToUse');
        
        _currentRecordingPath = pathToUse;
        _recordingStartTime = DateTime.parse(savedStartTimeStr);
        _isRecording = true;
        
        // 如果路径不同，更新 SharedPreferences
        if (nativePath != null && nativePath != savedPath) {
          await _saveRecordingState();
        }
        
        // 重新启动计时器和流
        _durationController?.close();
        _durationController = StreamController<Duration>();
        _startDurationTimer();
        
        // 确保前台服务正在运行
        await ForegroundService.start();
        
        print('Recording state restored successfully from native recorder');
        return true;
      }
      
      // 如果原生录音器不在录音，检查文件是否还在增长（备用检查）
      final initialSize = await file.length();
      print('Initial file size: $initialSize bytes');
      await Future.delayed(const Duration(milliseconds: 2000));
      final laterSize = await file.length();
      print('File size after 2s: $laterSize bytes');
      final isFileGrowing = laterSize > initialSize;
      
      if (isFileGrowing) {
        // 文件还在增长，说明录音可能还在进行（但原生录音器状态丢失）
        print('File is growing, recording may still be active. Restoring state...');
        _currentRecordingPath = savedPath;
        _recordingStartTime = DateTime.parse(savedStartTimeStr);
        _isRecording = true;
        
        _durationController?.close();
        _durationController = StreamController<Duration>();
        _startDurationTimer();
        
        await ForegroundService.start();
        
        print('Recording state restored (file is growing)');
        return true;
      }
      
      // 录音已经停止
      print('Recording has stopped and been saved.');
      print('File size: $initialSize -> $laterSize bytes (no growth)');
      
      await _clearRecordingState();
      await ForegroundService.stop();
      return false;
      
    } catch (e) {
      print('Error restoring recording state: $e');
      await _clearRecordingState();
      await ForegroundService.stop();
      return false;
    }
  }
  
  /// 从单例状态恢复（备用方法）
  Future<bool> _restoreFromSingleton() async {
    if (!_isRecording || _currentRecordingPath == null || _recordingStartTime == null) {
      return false;
    }
    
    try {
      bool isActuallyRecording = false;
      try {
        isActuallyRecording = await NativeRecorderService.isRecording();
        print('Native isRecording() returned: $isActuallyRecording');
      } catch (e) {
        print('Error checking native isRecording(): $e');
      }
      
      if (isActuallyRecording) {
        print('Recording is confirmed active from singleton! Restoring UI state...');
        if (_durationController == null || _durationController!.isClosed) {
          _durationController = StreamController<Duration>();
          _startDurationTimer();
        }
        await ForegroundService.start();
        return true;
      }
      
      return false;
    } catch (e) {
      print('Error restoring from singleton: $e');
      return false;
    }
  }

  void _startDurationTimer() {
    if (_recordingStartTime == null) return;

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_recordingStartTime != null) {
        final duration = DateTime.now().difference(_recordingStartTime!);
        _durationController?.add(duration);
      }
    });
  }

  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    try {
      // 使用原生录音停止
      final path = await NativeRecorderService.stopRecording();
      
      // 清除保存的状态
      await _clearRecordingState();
      
      // 停止前台服务
      await ForegroundService.stop();
      
      _isRecording = false;
      _durationTimer?.cancel();
      _durationController?.close();
      _durationController = null;
      print('Native recording stopped: $path');
      return path;
    } catch (e) {
      print('Error stopping recording: $e');
      // 即使出错也要尝试清除状态和停止前台服务
      await _clearRecordingState();
      await ForegroundService.stop();
      return null;
    }
  }

  Future<void> pauseRecording() async {
    // 原生录音不支持暂停，如果需要可以停止并重新开始
    if (_isRecording) {
      print('Native recording does not support pause');
      _durationTimer?.cancel();
    }
  }

  Future<void> resumeRecording() async {
    // 原生录音不支持暂停，如果需要可以停止并重新开始
    if (_isRecording) {
      print('Native recording does not support resume');
      _startDurationTimer();
    }
  }

  Future<List<String>> getRecordedFiles() async {
    final directory = await getApplicationDocumentsDirectory();
    final dir = Directory(directory.path);
    final files = dir.listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.m4a'))
        .map((file) => file.path)
        .toList();
    files.sort((a, b) => b.compareTo(a)); // 最新的在前
    return files;
  }

  Future<bool> deleteRecording(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      print('Error deleting recording: $e');
      return false;
    }
  }

  void dispose() {
    // 注意：不要在录音进行时调用 dispose，否则会停止录音
    // 只有在确定不再需要录音时才调用
    _durationTimer?.cancel();
    _durationController?.close();
    // 不调用 _recorder.dispose()，因为这会停止正在进行的录音
    // 只有在真正停止录音时才应该调用 stop()
  }
}

