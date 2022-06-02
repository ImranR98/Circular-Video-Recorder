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

late List<CameraDescription> _cameras;
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
      theme: ThemeData(
          colorScheme: const ColorScheme.light(
              primary: Colors.red, secondary: Colors.amber)),
      darkTheme: ThemeData(
          colorScheme: const ColorScheme.dark(
              primary: Colors.redAccent, secondary: Colors.amberAccent)),
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
  int recordMins = 0;
  int recordCount = -1;
  ResolutionPreset resolutionPreset = ResolutionPreset.medium;
  DateTime currentClipStart = DateTime.now();
  String? ip;
  Dhttpd? server;
  bool saving = false;
  bool moving = false;

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
    List<FileSystemEntity> existingFiles = await saveDir.list().toList();
    existingFiles.removeWhere(
        (element) => element.uri.pathSegments.last == 'index.html');
    return existingFiles;
  }

  Future<void> generateHTMLList() async {
    List<FileSystemEntity> existingClips = await getExistingClips();
    String html =
        '<!DOCTYPE html><html lang="en"><head><meta http-equiv="content-type" content="text/html; charset=utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Circular Video Recorder - Clips</title><style>@media (prefers-color-scheme: dark) {html {background-color: #222222; color: white;}} body {font-family: Arial, Helvetica, sans-serif;} a {color: inherit;}</style></head><body><h1>Circular Video Recorder - Clips:</h1>';
    if (existingClips.isNotEmpty) {
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
    File('${saveDir.path}/index.html').writeAsString(html);
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
                          ? Theme.of(context).colorScheme.primary
                          : Colors.black,
                      width: 5),
                  right: BorderSide(
                      color: cameraController.value.isRecordingVideo
                          ? Theme.of(context).colorScheme.primary
                          : Colors.black,
                      width: 5),
                  top: BorderSide(
                      color: cameraController.value.isRecordingVideo
                          ? Theme.of(context).colorScheme.primary
                          : Colors.black,
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
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            decoration: BoxDecoration(
              color: cameraController.value.isRecordingVideo
                  ? Theme.of(context).colorScheme.primary
                  : Colors.black,
              border: Border.all(
                color: cameraController.value.isRecordingVideo
                    ? Theme.of(context).colorScheme.primary
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
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
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
          padding: const EdgeInsets.fromLTRB(5, 0, 5, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: ElevatedButton(
                    onPressed: cameraController.value.isRecordingVideo
                        ? () => stopRecording(false)
                        : recordMins > 0 && recordCount >= 0
                            ? recordRecursively
                            : null,
                    child: Text(cameraController.value.isRecordingVideo
                        ? 'Stop Recording'
                        : 'Start Recording')),
              ),
              const SizedBox(width: 5),
              OutlinedButton(
                onPressed: moveToGallery,
                style: Theme.of(context).brightness == Brightness.light
                    ? ButtonStyle(
                        foregroundColor:
                            MaterialStateProperty.all(Colors.black),
                        overlayColor: MaterialStateProperty.all(
                            const Color.fromARGB(20, 0, 0, 0)))
                    : ButtonStyle(
                        foregroundColor:
                            MaterialStateProperty.all(Colors.white),
                        overlayColor: MaterialStateProperty.all(
                            const Color.fromARGB(20, 255, 255, 255))),
                child: const Text('Move Clips to Gallery'),
              )
            ],
          ),
        ),
        SwitchListTile(
          onChanged: (_) {
            toggleWeb();
          },
          visualDensity: VisualDensity.compact,
          value: server != null,
          activeColor: Theme.of(context).colorScheme.secondary,
          title: const Text('Serve Clips on Web GUI'),
          subtitle: server != null
              ? Text(
                  'Serving on ${ip != null ? 'http://$ip:${server?.port} (LAN)' : 'http://${server?.host}:${server?.port}'}')
              : null,
        ),
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
    if (server == null) {
      try {
        ip = await NetworkInfo().getWifiIP();
        server = await Dhttpd.start(
            path: saveDir.path, address: InternetAddress.anyIPv4);
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

  moveToGallery() async {
    List<FileSystemEntity> existingClips = await getExistingClips();
    if (existingClips.isEmpty) {
      showInSnackBar('You have no recorded Clips!');
    } else if (saving) {
      showInSnackBar('A clip is still being saved - try again later');
    } else {
      showDialog(
          context: context,
          builder: (BuildContext ctx) {
            return AlertDialog(
              title: const Text('Confirmation'),
              content: const Text(
                  'This action will move all Clips in this App\'s internal storage to an external location accessible via a Gallery app.\n\nThese clips will no longer be "owned" by the App, so they will not be accessible via the Web GUI nor affected by the Clip Count Limit.\n\nContinue?'),
              actions: [
                TextButton(
                    onPressed: () async {
                      // Remove the box
                      setState(() {
                        moving = true;
                      });
                      Navigator.of(context).pop();
                      for (var eC in existingClips) {
                        await GallerySaver.saveVideo(eC.path,
                            albumName: 'Circular Video Recorder');
                      }
                      await Future.wait(existingClips.map((eC) => eC.delete()));
                      generateHTMLList();
                      showInSnackBar(
                          '${existingClips.length} Clips moved to Gallery');
                      setState(() {
                        moving = false;
                      });
                    },
                    child: const Text('Yes')),
                TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('No'))
              ],
            );
          });
    }
  }

  @override
  void dispose() {
    cameraController.dispose();
    KeepScreenOn.turnOff();
    super.dispose();
  }
}
