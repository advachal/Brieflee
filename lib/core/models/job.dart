import 'enums.dart';

/// A long-running backend operation (analysis or matching). The API returns
/// a job id immediately and the app polls or subscribes for progress.
class Job {
  const Job({
    required this.id,
    required this.status,
    required this.progress,
    required this.step,
    this.resultId,
    this.error,
  });

  final String id;
  final JobStatus status;

  /// 0..1
  final double progress;
  final String step;
  final String? resultId;
  final String? error;

  bool get isDone =>
      status == JobStatus.succeeded || status == JobStatus.failed;

  factory Job.fromJson(Map<String, dynamic> j) => Job(
    id: j['id'] as String,
    status: enumByName(JobStatus.values, j['status'], JobStatus.queued),
    progress: (j['progress'] as num).toDouble(),
    step: j['step'] as String,
    resultId: j['result_id'] as String?,
    error: j['error'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status.name,
    'progress': progress,
    'step': step,
    'result_id': resultId,
    'error': error,
  };
}
