import 'dart:async';
import 'dart:io';

/// Desktop-first, non-generative archival restoration using FFmpeg.
///
/// This is deliberately separate from an eventual LTX inference provider.
/// Never claim that a classical FFmpeg pass has recovered missing detail or HDR.
final class RestorationJob {
  RestorationJob({
    required this.inputPath,
    required this.outputPath,
    this.width = 1920,
    this.denoise = 2.0,
    this.deinterlace = true,
    this.keepGrayscale = true,
    this.ffmpegExecutable = 'ffmpeg',
  });

  final String inputPath;
  final String outputPath;
  final int width;
  final double denoise;
  final bool deinterlace;
  final bool keepGrayscale;
  final String ffmpegExecutable;

  List<String> get filters => [
    if (deinterlace) 'bwdif=mode=send_frame:parity=auto:deint=interlaced',
    'hqdn3d=${denoise.toStringAsFixed(1)}:${denoise.toStringAsFixed(1)}:4:4',
    'scale=$width:-2:flags=lanczos',
    'setsar=1',
    if (keepGrayscale) 'format=gray',
    'format=yuv420p',
  ];

  List<String> get arguments => [
    '-hide_banner', '-nostdin', '-y', '-i', inputPath,
    '-map', '0:v:0', '-map', '0:a?', '-vf', filters.join(','),
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '17',
    '-c:a', 'copy', '-movflags', '+faststart', outputPath,
  ];
}

final class RestorationRunner {
  Process? _process;
  bool get running => _process != null;

  Future<int> run(RestorationJob job, {void Function(String)? onLog}) async {
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) {
      throw UnsupportedError('Restoration is currently desktop-only.');
    }
    if (running) throw StateError('A restoration job is already running.');
    if (job.width < 320 || job.width > 3840 || job.width.isOdd) {
      throw ArgumentError.value(job.width, 'width', 'Must be even, 320–3840.');
    }
    if (!job.denoise.isFinite || job.denoise < 0 || job.denoise > 10) {
      throw ArgumentError.value(job.denoise, 'denoise', 'Must be 0–10.');
    }
    final input = File(job.inputPath);
    if (!await input.exists()) throw FileSystemException('Input file missing', job.inputPath);
    if (input.absolute.path == File(job.outputPath).absolute.path) {
      throw ArgumentError('Output must differ from source.');
    }
    try {
      _process = await Process.start(job.ffmpegExecutable, job.arguments,
          runInShell: false);
      final process = _process!;
      final stdoutDone = process.stdout.drain<void>();
      final stderrDone = process.stderr
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .forEach((line) => onLog?.call(line));
      final exit = await process.exitCode;
      await Future.wait([stdoutDone, stderrDone]);
      return exit;
    } finally {
      _process = null;
    }
  }

  void cancel() => _process?.kill(ProcessSignal.sigterm);
}
