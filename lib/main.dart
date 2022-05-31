import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:keep_screen_on/keep_screen_on.dart';

late List<CameraDescription> _cameras;
int recordMins = 0;
int recordCount = -1;
ResolutionPreset resolutionPreset = ResolutionPreset.medium;
DateTime currentClipStart = DateTime.now();
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
              border: Border(
                  left: BorderSide(
                      color: cameraController.value.isRecordingVideo
                          ? Colors.red
                          : Colors.black87,
                      width: 5),
                  right: BorderSide(
                      color: cameraController.value.isRecordingVideo
                          ? Colors.red
                          : Colors.black87,
                      width: 5),
                  top: BorderSide(
                      color: cameraController.value.isRecordingVideo
                          ? Colors.red
                          : Colors.black87,
                      width: 5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(1.0),
              child: Center(
                child: cameraController.value.isInitialized
                    ? CameraPreview(cameraController)
                    : const Text('Could not Access Camera'),
              ),
            ),
          ),
        ),
        // if (cameraController.value.isRecordingVideo)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            decoration: BoxDecoration(
              color: cameraController.value.isRecordingVideo
                  ? Colors.red
                  : Colors.black,
              border: Border.all(
                color: cameraController.value.isRecordingVideo
                    ? Colors.red
                    : Colors.black,
                width: cameraController.value.isRecordingVideo ? 5 : 2.5,
              ),
            ),
            child: cameraController.value.isRecordingVideo
                ? Text(
                    'Current clip started at ${currentClipStart.hour <= 9 ? '0${currentClipStart.hour}' : currentClipStart.hour}:${currentClipStart.minute <= 9 ? '0${currentClipStart.minute}' : currentClipStart.minute}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.white))
                : null,
          ),
        ]),
        if (cameraController.value.isRecordingVideo)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(5, 0, 5, 5),
              decoration: const BoxDecoration(
                color: Colors.red,
              ),
              child: Text('${saveDir.path}/${latestFileName()}',
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(letterSpacing: 1, color: Colors.white)),
            ),
          ]),
        Padding(
          padding: const EdgeInsets.all(10.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Expanded(
                  child: TextField(
                onChanged: (value) {
                  setState(() {
                    recordMins = value.trim() == '' ? 0 : int.parse(value);
                  });
                },
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
                      onChanged: (value) {
                        setState(() {
                          recordCount =
                              value.trim() == '' ? -1 : int.parse(value);
                        });
                      },
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
                      onChanged: cameraController.value.isRecordingVideo
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() {
                                  resolutionPreset = value as ResolutionPreset;
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
          padding: const EdgeInsets.fromLTRB(5.0, 0, 5, 0),
          child: Text(getStatusText(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        Padding(
          padding: const EdgeInsets.all(5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Expanded(
                  child: IconButton(
                onPressed: cameraController.value.isRecordingVideo
                    ? () => stopRecording(false)
                    : recordMins > 0 && recordCount >= 0
                        ? recordRecursively
                        : null,
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

  String getStatusText() {
    if (recordMins <= 0 || recordCount < 0) {
      String res = '';
      if (recordMins <= 0) res += 'Length must be above 0.';
      if (recordCount < 0) {
        if (res.isNotEmpty) {
          res += ' ';
        }
        res += 'Count must be 0 (infinite) or more.';
      }
      return res;
    }
    String status1 = cameraController.value.isRecordingVideo
        ? 'Now recording'
        : 'Set to record';
    int totalMins = recordMins * recordCount;
    String status2 =
        '$recordMins min clips ${recordCount == 0 ? '(until space runs out)' : '(keeping the latest ${totalMins < 60 ? '$totalMins minutes' : '${totalMins / 60} hours'})'}.';
    if (!cameraController.value.isRecordingVideo && recordMins > 15) {
      status1 = 'Warning: Long clip lengths (above 15) may cause crashes.\n\n'
          '$status1';
    }
    return '$status1 $status2';
  }

  void recordRecursively() async {
    if (recordMins > 0 && recordCount >= 0) {
      await cameraController.startVideoRecording();
      setState(() {
        currentClipStart = DateTime.now();
      });
      await Future.delayed(
          Duration(milliseconds: (recordMins * 60 * 1000).toInt()));
      if (cameraController.value.isRecordingVideo) {
        await stopRecording(true);
        recordRecursively();
      }
    }
  }

  String latestFileName() {
    return 'CVR-${currentClipStart.millisecondsSinceEpoch.toString()}.mp4';
  }

  Future<void> stopRecording(bool cleanup) async {
    if (cameraController.value.isRecordingVideo) {
      XFile tempFile = await cameraController.stopVideoRecording();
      setState(() {});
      String appDocPath = saveDir.path;
      String filePath = '$appDocPath/${latestFileName()}';
      // Once clip is saved, deleting cached copy and cleaning up old clips can be done asynchronously
      tempFile.saveTo(filePath).then((_) {
        File(tempFile.path).delete();
        if (cleanup) {
          deleteOldRecordings();
        }
      });
    }
  }

  Future<bool> deleteOldRecordings() async {
    bool ret = false;
    if (recordCount > 0) {
      List<FileSystemEntity> existingFiles = await saveDir.list().toList();
      if (existingFiles.length >= recordCount) {
        ret = true;
        existingFiles.sublist(recordCount).forEach((eF) {
          showInSnackBar(
              'Clip limit reached. Deleting: ${eF.uri.pathSegments.last}');
          eF.delete();
        });
      }
    }
    return ret;
  }
}
