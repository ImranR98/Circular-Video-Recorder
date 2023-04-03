import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:keep_screen_on/keep_screen_on.dart';
import 'package:dhttpd/dhttpd.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

late List<CameraDescription> _cameras;
Directory? saveDir;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  saveDir = await getRecordingDir();
  runApp(const MyApp());
}

Future<Directory?> getRecordingDir() async {
  Directory? exportDir;
  if (Platform.isAndroid &&
      (await DeviceInfoPlugin().androidInfo).version.sdkInt <= 29) {
    while (await Permission.storage.isDenied) {
      await Permission.storage.request();
    }
  }
  if (Platform.isAndroid) {
    exportDir = Directory('/storage/emulated/0/Documents');
    try {
      exportDir.existsSync();
    } catch (e) {
      exportDir = null;
    }
  }
  if (exportDir == null) {
    if (Platform.isAndroid) {
      exportDir = await getExternalStorageDirectory();
    } else if (Platform.isIOS) {
      exportDir = await getApplicationDocumentsDirectory();
    } else {
      exportDir = await getDownloadsDirectory();
    }
  }
  exportDir =
      exportDir != null ? Directory('${exportDir.path}/CVR_Clips') : null;
  exportDir?.createSync(recursive: true);
  return exportDir;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Circular Video Recorder',
      theme: ThemeData(
          useMaterial3: true,
          colorScheme: const ColorScheme.light(
              primary: Colors.red, secondary: Colors.amber)),
      darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: const ColorScheme.dark(
              primary: Colors.redAccent, secondary: Colors.amberAccent)),
      home: const MyHomePage(title: 'Circular Video Recorder'),
    );
  }
}

var initMins = 15;
var initCount = 48;

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late CameraController cameraController;
  int recordMins = initMins;
  int recordCount = initCount;
  ResolutionPreset resolutionPreset = ResolutionPreset.medium;
  DateTime currentClipStart = DateTime.now();
  String? ip;
  Dhttpd? server;
  bool saving = false;
  bool moving = false;
  Directory? exportDir;
  var lenController = TextEditingController(text: initMins.toString());
  var countController = TextEditingController(text: initCount.toString());

  @override
  void initState() {
    super.initState();
    KeepScreenOn.turnOn();
    initCam();
    generateHTMLList();
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

  Future<List<FileSystemEntity>> getExistingClips() async {
    List<FileSystemEntity>? existingFiles = await saveDir?.list().toList();
    existingFiles?.removeWhere(
        (element) => element.uri.pathSegments.last == 'index.html');
    return existingFiles ?? [];
  }

  Future<void> generateHTMLList() async {
    List<FileSystemEntity> existingClips = await getExistingClips();
    String html =
        '<!DOCTYPE html><html lang="en"><head><meta http-equiv="content-type" content="text/html; charset=utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Circular Video Recorder - Clips</title><style>@media (prefers-color-scheme: dark) {html {background-color: #222222; color: white;}} body {font-family: Arial, Helvetica, sans-serif;} a {color: inherit;}</style></head><body><h1>Circular Video Recorder - Clips:</h1>';
    if (saveDir != null && existingClips.isNotEmpty) {
      html += '<ul>';
      for (var element in existingClips) {
        html +=
            '<li><a href="./${element.uri.pathSegments.last}">${element.uri.pathSegments.last}</a></li>';
      }
      html += '</ul>';
    } else {
      html += '<p>No Clips Found!</p>';
    }
    html += '</body></html>';
    File('${saveDir!.path}/index.html').writeAsString(html);
  }

  @override
  Widget build(BuildContext context) {
    var status = getStatusText();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Column(children: [
        Expanded(
          child: Center(
            child: cameraController.value.isInitialized
                ? CameraPreview(cameraController)
                : const Text('Could not Access Camera'),
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            child: cameraController.value.isRecordingVideo
                ? Text(
                    'Current clip started at ${currentClipStart.hour <= 9 ? '0${currentClipStart.hour}' : currentClipStart.hour}:${currentClipStart.minute <= 9 ? '0${currentClipStart.minute}' : currentClipStart.minute}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ))
                : null,
          ),
        ]),
        if (cameraController.value.isRecordingVideo)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(5, 5, 5, 5),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
              ),
              child: Text(latestFilePath(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'monospace', color: Colors.white)),
            ),
          ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 15, 15, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Expanded(
                  child: TextField(
                controller: lenController,
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
                      controller: countController,
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
          padding: const EdgeInsets.fromLTRB(15, 0, 15, 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                  child: Text(
                status ??
                    'A count limit of 0 is infinite.\nLower the length/count in case of crashes.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                overflow: TextOverflow.clip,
              )),
              const SizedBox(
                width: 15,
              ),
              ElevatedButton.icon(
                  label: Text(cameraController.value.isRecordingVideo
                      ? 'Stop'
                      : 'Record'),
                  onPressed: cameraController.value.isRecordingVideo
                      ? () => stopRecording(false)
                      : recordMins > 0 && recordCount >= 0
                          ? () {
                              if (saveDir == null) {
                                showDialog(
                                    context: context,
                                    builder: (BuildContext ctx) {
                                      return const AlertDialog(
                                          title: Text('Storage Error'),
                                          content: Text(
                                              'Could not configure storage directory. This error is unrecoverable.'));
                                    });
                              } else {
                                recordRecursively();
                              }
                            }
                          : null,
                  icon: Icon(cameraController.value.isRecordingVideo
                      ? Icons.stop
                      : Icons.circle)),
            ],
          ),
        ),
        const Divider(
          height: 0,
        ),
        SwitchListTile(
            onChanged: (_) {
              toggleWeb();
            },
            visualDensity: VisualDensity.compact,
            value: server != null,
            activeColor: Theme.of(context).colorScheme.secondary,
            title: const Text('Serve Clips on Web GUI (Insecure)'),
            subtitle: server == null
                ? null
                : Text(
                    'Serving on ${'http://${ip ?? server?.host}:${server?.port}'}',
                  )),
        if (saving || moving)
          Container(
              decoration:
                  BoxDecoration(color: Theme.of(context).colorScheme.primary),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(5, 5, 5, 5),
                child: Row(children: [
                  Text(
                      '${saving && moving ? 'Saving & moving clips' : saving ? 'Saving last clip' : 'Moving clips'} - do not exit...',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.white))
                ]),
              )),
        if (saving || moving) const LinearProgressIndicator(),
      ]),
    );
  }

  void showInSnackBar(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> toggleWeb() async {
    if (server == null && saveDir != null) {
      try {
        ip = await NetworkInfo().getWifiIP();
        server = await Dhttpd.start(
            path: saveDir!.path, address: InternetAddress.anyIPv4);
        setState(() {});
      } catch (e) {
        showInSnackBar('Error - try restarting the app');
        await disableWeb();
      }
    } else {
      await disableWeb();
    }
  }

  Future<void> disableWeb() async {
    await server?.destroy();
    setState(() {
      server = null;
      ip = null;
    });
  }

  String? getStatusText() {
    if (recordMins <= 0 || recordCount < 0) {
      return null;
    }
    String status1 = cameraController.value.isRecordingVideo
        ? 'Now recording'
        : 'Set to record';
    int totalMins = recordMins * recordCount;
    String status2 =
        '$recordMins min clips ${recordCount == 0 ? '(until space runs out)' : '(keeping the latest ${totalMins < 60 ? '$totalMins minutes' : '${totalMins / 60} hours'})'}.';
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

  String latestFilePath() {
    return '${saveDir?.path ?? ''}/CVR-${currentClipStart.millisecondsSinceEpoch.toString()}.mp4';
  }

  Future<void> stopRecording(bool cleanup) async {
    if (cameraController.value.isRecordingVideo) {
      XFile tempFile = await cameraController.stopVideoRecording();
      setState(() {});
      String filePath = latestFilePath();
      // Once clip is saved, deleting cached copy and cleaning up old clips can be done asynchronously
      setState(() {
        saving = true;
      });
      tempFile.saveTo(filePath).then((_) {
        File(tempFile.path).delete();
        generateHTMLList();
        setState(() {
          saving = false;
        });
        if (cleanup) {
          deleteOldRecordings();
        }
      });
    }
  }

  Future<bool> deleteOldRecordings() async {
    bool ret = false;
    if (recordCount > 0) {
      List<FileSystemEntity> existingClips = await getExistingClips();
      if (existingClips.length > recordCount) {
        ret = true;
        await Future.wait(existingClips.sublist(recordCount).map((eC) {
          showInSnackBar(
              'Clip limit reached. Deleting: ${eC.uri.pathSegments.last}');
          return eC.delete();
        }));
        generateHTMLList();
      }
    }
    return ret;
  }

  @override
  void dispose() {
    cameraController.dispose();
    KeepScreenOn.turnOff();
    super.dispose();
  }
}
