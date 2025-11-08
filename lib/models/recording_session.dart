import '../services/audio_analyzer_service.dart';

class RecordingSession {
  final String id;
  final String filePath;
  final DateTime startTime;
  final DateTime? endTime;
  final Duration duration;
  final List<double>? waveform;
  final List<AnomalySegment> anomalies;

  RecordingSession({
    required this.id,
    required this.filePath,
    required this.startTime,
    this.endTime,
    required this.duration,
    this.waveform,
    this.anomalies = const [],
  });

  bool get isCompleted => endTime != null;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'filePath': filePath,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'duration': duration.inSeconds,
      'anomalies': anomalies.map((a) => {
        'startTime': a.startTime.inSeconds,
        'endTime': a.endTime.inSeconds,
        'amplitude': a.amplitude,
        'type': a.type.toString(),
      }).toList(),
    };
  }

  factory RecordingSession.fromJson(Map<String, dynamic> json) {
    return RecordingSession(
      id: json['id'] as String,
      filePath: json['filePath'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] != null 
          ? DateTime.parse(json['endTime'] as String) 
          : null,
      duration: Duration(seconds: json['duration'] as int),
      anomalies: (json['anomalies'] as List?)
          ?.map((a) => AnomalySegment(
                startTime: Duration(seconds: a['startTime'] as int),
                endTime: Duration(seconds: a['endTime'] as int),
                amplitude: a['amplitude'] as double,
                type: AnomalyType.values.firstWhere(
                  (e) => e.toString() == a['type'],
                  orElse: () => AnomalyType.unknown,
                ),
              ))
          .toList() ?? [],
    );
  }
}

