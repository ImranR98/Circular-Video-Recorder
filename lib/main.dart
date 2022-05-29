import 'dart:async';
import 'dart:html';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

late List<CameraDescription> _cameras;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Circular Video Recorder',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Circular Video Recorder'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late CameraController controller;

  @override
  void initState() {
    super.initState();
    controller = CameraController(_cameras[0], ResolutionPreset.max);
    controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    }).catchError((Object e) {
      if (e is CameraException) {
        switch (e.code) {
          case 'CameraAccessDenied':
            print('User denied camera access.');
            break;
          default:
            print('Handle other errors.');
            break;
        }
      }
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void showInSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
          child: controller.value.isInitialized
              ? CameraPreview(controller)
              : const Text("Could not Access Camera")),
      floatingActionButton: FloatingActionButton(
        onPressed: controller.value.isRecordingVideo
            ? stopRecording
            : recordRecursively,
        tooltip: controller.value.isRecordingVideo
            ? 'Stop Recording'
            : 'Start Recording',
        child: controller.value.isRecordingVideo
            ? const Icon(Icons.stop)
            : const Icon(Icons.videocam),
      ),
    );
  }

  void recordRecursively() {
    controller.startVideoRecording().then((_) {
      setState(() {});
      Timer(const Duration(milliseconds: 1 * 10 * 1000), () {
        if (controller.value.isRecordingVideo) {
          stopRecording().then((_) {
            recordRecursively();
          });
        }
      });
    });
  }

  Future<void> stopRecording() async {
    XFile file = await controller.stopVideoRecording();
    setState(() {});
    showInSnackBar('Video recorded to ${file.path}');
    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      final uri = Uri.dataFromBytes(bytes, mimeType: 'video/webm;codecs=vp8');

      final link = AnchorElement(href: uri.toString());
      link.download =
          'recording-${DateTime.now().millisecondsSinceEpoch.toString()}.webm';
      link.click();
      link.remove();
    }
  }
}
