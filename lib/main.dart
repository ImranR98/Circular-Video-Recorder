import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:keep_screen_on/keep_screen_on.dart';

late List<CameraDescription> _cameras;
TextEditingController recordMinsController = TextEditingController(text: '60');
TextEditingController recordCountController = TextEditingController(text: '12');
ResolutionPreset resolutionPreset = ResolutionPreset.medium;
late Directory saveDir;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _cameras = await availableCameras();
  saveDir = await getRecordingDir();
  runApp(const MyApp());
}

Future<Directory> getRecordingDir() async {
  Directory? saveDir;
  while (saveDir == null) {
    if (Platform.isAndroid) {
      saveDir = await getExternalStorageDirectory();
    } else if (Platform.isIOS) {
      saveDir = await getApplicationDocumentsDirectory();
    } else {
      saveDir = await getDownloadsDirectory();
    }
  }
  return saveDir;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Circular Video Recorder',
      theme:
          ThemeData(colorScheme: const ColorScheme.light(primary: Colors.red)),
      darkTheme:
          ThemeData(colorScheme: const ColorScheme.dark(primary: Colors.red)),
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
  late CameraController cameraController;

  @override
  void initState() {
    super.initState();
    initCam();
    KeepScreenOn.turnOn();
  }

  Future<void> initCam() async {
    cameraController = CameraController(_cameras[0], resolutionPreset);
    try {
      await cameraController.initialize();
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (e) {
      if (e is CameraException) {
        switch (e.code) {
          case 'CameraAccessDenied':
            showInSnackBar('User denied camera access');
            break;
          default:
            showInSnackBar('Unknown error');
            break;
        }
      }
    }
  }

  @override
  void dispose() {
    cameraController.dispose();
    recordMinsController.dispose();
    recordCountController.dispose();
    KeepScreenOn.turnOff();
    super.dispose();
  }

  void showInSnackBar(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Column(children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(
                color: cameraController.value.isRecordingVideo
                    ? Colors.red
                    : Colors.black87,
                width: 5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(1.0),
              child: Center(
                child: cameraController.value.isInitialized
                    ? CameraPreview(cameraController)
                    : const Text("Could not Access Camera"),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(15.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Expanded(
                  child: TextField(
                controller: recordMinsController,
                enabled: !cameraController.value.isRecordingVideo,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Clip Length (Min)',
                ),
              )),
              const SizedBox(width: 15),
              Expanded(
                  child: TextField(
                      controller: recordCountController,
                      enabled: !cameraController.value.isRecordingVideo,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Clip Count Limit',
                      ))),
              const SizedBox(width: 15),
              Expanded(
                  child: DropdownButtonFormField(
                      value: resolutionPreset,
                      items: ResolutionPreset.values
                          .map((e) => DropdownMenuItem<ResolutionPreset>(
                              value: e, child: Text(e.name)))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            resolutionPreset = value;
                          });
                          initCam();
                        }
                      },
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Video Quality',
                      ))),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(15.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Expanded(
                  child: IconButton(
                onPressed: cameraController.value.isRecordingVideo
                    ? stopRecording
                    : recordRecursively,
                icon: cameraController.value.isRecordingVideo
                    ? const Icon(Icons.stop_outlined)
                    : const Icon(Icons.videocam_outlined),
                tooltip: cameraController.value.isRecordingVideo
                    ? 'Stop Recording'
                    : 'Start Recording',
              ))
            ],
          ),
        ),
      ]),
    );
  }

  void recordRecursively() async {
    double recordMins = recordMinsController.text == ''
        ? 0
        : double.parse(recordMinsController.text);
    int recordCount = recordCountController.text == ''
        ? 0
        : int.parse(recordCountController.text);
    if (recordMins <= 0) {
      showInSnackBar('Enter a valid clip duration');
    } else if (recordCount <= 0) {
      showInSnackBar('Enter a valid maximum clip count');
    } else {
      await cameraController.startVideoRecording();
      setState(() {});
      await Future.delayed(
          Duration(milliseconds: (recordMins * 60 * 1000).toInt()));
      if (cameraController.value.isRecordingVideo) {
        await stopRecording();
        recordRecursively();
      }
    }
  }

  Future<void> stopRecording() async {
    if (cameraController.value.isRecordingVideo) {
      XFile tempFile = await cameraController.stopVideoRecording();
      setState(() {});
      String appDocPath = saveDir.path;
      String filePath =
          '$appDocPath/CVR-${DateTime.now().millisecondsSinceEpoch.toString()}.mp4';
      // Once clip is recorded, copying it over to the final dir and cleaning up old ones can be done asynchronously
      tempFile.readAsBytes().then((bytes) async {
        await File(filePath).writeAsBytes(bytes);
        File(tempFile.path).delete();
        String message = '[NEW CLIP RECORDED: $filePath]';
        if (await deleteOldRecordings()) {
          message += '\n\n[CLIP LIMIT REACHED - OLDER CLIP(S) DELETED]';
        }
        showInSnackBar(message);
      });
    }
  }

  Future<bool> deleteOldRecordings() async {
    bool ret = false;
    int recordCount = recordCountController.text == ''
        ? 0
        : int.parse(recordCountController.text);
    if (recordCount > 0) {
      List<FileSystemEntity> existingFiles = await saveDir.list().toList();
      if (existingFiles.length >= recordCount) {
        ret = true;
        existingFiles.sublist(recordCount).forEach((eF) {
          eF.delete();
        });
      }
    }
    return ret;
  }
}
