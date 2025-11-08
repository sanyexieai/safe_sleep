import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  StreamController<Duration>? _durationController;
  Timer? _durationTimer;

  bool get isRecording => _isRecording;
  String? get currentRecordingPath => _currentRecordingPath;
  DateTime? get recordingStartTime => _recordingStartTime;

  Stream<Duration>? get durationStream => _durationController?.stream;

  Future<bool> checkPermissions() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
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

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _currentRecordingPath!,
      );

      _isRecording = true;
      _durationController = StreamController<Duration>();
      _startDurationTimer();
      return true;
    } catch (e) {
      print('Error starting recording: $e');
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
      final path = await _recorder.stop();
      _isRecording = false;
      _durationTimer?.cancel();
      _durationController?.close();
      _durationController = null;
      return path;
    } catch (e) {
      print('Error stopping recording: $e');
      return null;
    }
  }

  Future<void> pauseRecording() async {
    if (_isRecording) {
      await _recorder.pause();
      _durationTimer?.cancel();
    }
  }

  Future<void> resumeRecording() async {
    if (_isRecording) {
      await _recorder.resume();
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
    _durationTimer?.cancel();
    _durationController?.close();
    _recorder.dispose();
  }
}

