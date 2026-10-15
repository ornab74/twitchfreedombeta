import 'dart:io';

import 'package:flutter/material.dart';
import '../restoration/restoration_runner.dart';

/// An honest, local FFmpeg restoration entry point; generative AI is not wired yet.
Future<void> showRestorationStudio(BuildContext context) async {
  if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Restoration Studio is desktop-only for now.')),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => const _RestorationStudio(),
  );
}

class _RestorationStudio extends StatefulWidget {
  const _RestorationStudio();
  @override
  State<_RestorationStudio> createState() => _RestorationStudioState();
}

class _RestorationStudioState extends State<_RestorationStudio> {
  final _source = TextEditingController();
  final _destination = TextEditingController();
  final _runner = RestorationRunner();
  int _width = 1920;
  double _denoise = 2;
  bool _deinterlace = true;
  bool _grayscale = false;
  bool _busy = false;
  String _status = 'Requires FFmpeg installed on your desktop.';
  @override
  void dispose() {
    _runner.cancel();
    _source.dispose();
    _destination.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy) return;
    if (_source.text.trim().isEmpty || _destination.text.trim().isEmpty) {
      setState(() => _status = 'Enter an input path and a different output MP4 path.');
      return;
    }
    setState(() { _busy = true; _status = 'Running FFmpeg restoration…'; });
    try {
      final code = await _runner.run(
        RestorationJob(
          inputPath: _source.text.trim(),
          outputPath: _destination.text.trim(),
          width: _width,
          denoise: _denoise,
          deinterlace: _deinterlace,
          keepGrayscale: _grayscale,
        ),
        onLog: (line) {
          if (mounted && (line.contains('time=') || line.toLowerCase().contains('error'))) {
            setState(() => _status = line);
          }
        },
      );
      if (mounted) setState(() => _status = code == 0
          ? 'Complete: ${_destination.text.trim()}'
          : 'FFmpeg failed or was cancelled (exit code $code).');
    } catch (e) {
      if (mounted) setState(() => _status = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Restoration Studio · Desktop Preview'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Classical VHS cleanup and upscale. This stage does not use LTX, colorize monochrome video, or produce true HDR.'),
            const SizedBox(height: 16),
            TextField(controller: _source, enabled: !_busy, decoration: const InputDecoration(labelText: 'Source video path', hintText: '/videos/vhs_capture.mkv')),
            TextField(controller: _destination, enabled: !_busy, decoration: const InputDecoration(labelText: 'Output MP4 path', hintText: '/videos/restored.mp4')),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _width,
              decoration: const InputDecoration(labelText: 'Output width'),
              items: const [
                DropdownMenuItem(value: 1280, child: Text('720p-class (1280 wide)')),
                DropdownMenuItem(value: 1920, child: Text('1080p-class (1920 wide)')),
                DropdownMenuItem(value: 3840, child: Text('4K-class (3840 wide)')),
              ],
              onChanged: _busy ? null : (v) => setState(() => _width = v ?? 1920),
            ),
            SwitchListTile(title: const Text('Deinterlace'), value: _deinterlace, onChanged: _busy ? null : (v) => setState(() => _deinterlace = v)),
            SwitchListTile(title: const Text('Keep black-and-white'), value: _grayscale, onChanged: _busy ? null : (v) => setState(() => _grayscale = v)),
            Text('Denoise strength: ${_denoise.toStringAsFixed(1)}'),
            Slider(value: _denoise, min: 0, max: 10, onChanged: _busy ? null : (v) => setState(() => _denoise = v)),
            SelectableText(_status),
          ],
        ),
      ),
    ),
    actions: [
      if (_busy) TextButton(onPressed: _runner.cancel, child: const Text('Cancel job')),
      TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Close')),
      FilledButton(onPressed: _busy ? null : _start, child: const Text('Restore video')),
    ],
  );
}
