import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:map_fake_gps/config.dart';
import 'package:map_fake_gps/gps_util.dart';
import 'package:map_fake_gps/painter.dart';
import 'package:numberpicker/numberpicker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
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
  final _mapController = MapController();
  bool _isRefresh = false;
  final PublishSubject<bool?> _refreshMark = PublishSubject<bool?>();
  Stream<bool?> get refreshMarkSubjectStream => _refreshMark.stream;
  final BehaviorSubject<Icon> _startIconSubject =
      BehaviorSubject<Icon>.seeded(const Icon(Icons.start));
  Stream<Icon> get startSubjectStream => _startIconSubject.stream;
  Position? _personMarkPosition;
  Position? _lastPersonMarkPosition;
  int _speedValue = 8;
  @override
  void initState() {
    super.initState();
    _getPath().then((value) {
      if (Config.path == "") {
        getApplicationDocumentsDirectory().then((value) {
          setState(() {
            Config.path = value.path;
          });
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        endDrawer: _buildSettingDrawer(context),
        key: _scaffoldKey,
        floatingActionButton: _buildToolBar(),
        body: Stack(
          children: [
            _buildMap(context),
            _buildSpeedPicker(context),
            _buildSettingButton()
          ],
        ));
  }

  Future<void> _getPath() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? path = prefs.getString('path');
    setState(() {
      Config.path = path ?? "";
    });
  }

  Future<void> _moveToCurrentLocation() async {
    Location location = Location();

    bool serviceEnabled;
    PermissionStatus permissionGranted;
    LocationData locationData;

    serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        return;
      }
    }

    permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        return;
      }
    }

    locationData = await location.getLocation();
    _mapController.move(
        LatLng(locationData.latitude!, locationData.longitude!), 18.0);
  }

  Point _latLngConvertScreen(MapPosition map, LatLng goalLatLng) {
    var northWestPoint =
        const Epsg3857().latLngToPoint(map.bounds!.northWest, map.zoom!);
    var markerPoint = const Epsg3857().latLngToPoint(goalLatLng, map.zoom!);
    double x = markerPoint.x - northWestPoint.x;
    double y = markerPoint.y - northWestPoint.y;
    return Point(x, y);
  }

  void _markRefresh() {
    _refreshMark.add(!_isRefresh);
    _isRefresh = !_isRefresh;
  }

  StreamBuilder<bool?> _buildToolBar() {
    return StreamBuilder<bool?>(
        stream: refreshMarkSubjectStream,
        builder: (context, snapshot) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_lastPersonMarkPosition != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: FloatingActionButton(
                      onPressed: () async {
                        generateGpxFile([
                          _lastPersonMarkPosition!.mapPosition,
                          _personMarkPosition!.mapPosition,
                          _personMarkPosition!.mapPosition.round(),
                        ],
                            speedMph: _speedValue.toDouble(),
                            filePath: Config.path);
                        _startIconSubject
                            .add(const Icon(Icons.check, color: Colors.green));
                        Future.delayed(const Duration(seconds: 2))
                            .then((value) {
                          _startIconSubject.add(const Icon(Icons.start));
                        });
                      },
                      child: StreamBuilder<Icon>(
                          stream: startSubjectStream,
                          builder: (context, startSnapshot) {
                            return (startSnapshot.data ??
                                const Icon(Icons.start));
                          })),
                ),
              if (_personMarkPosition != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: FloatingActionButton(
                      onPressed: () async {
                        _mapController.move(
                            _personMarkPosition!.mapPosition, 18.0);
                      },
                      child: const Icon(Icons.man)),
                ),
              FloatingActionButton(
                  onPressed: () async {
                    _moveToCurrentLocation();
                  },
                  child: const Icon(Icons.location_on)),
              if (_personMarkPosition != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: FloatingActionButton(
                      onPressed: () async {
                        setState(() {
                          _lastPersonMarkPosition = null;
                          _personMarkPosition = null;
                        });
                      },
                      child: const Icon(
                        Icons.delete,
                        color: Colors.red,
                      )),
                ),
            ],
          );
        });
  }

  Drawer _buildSettingDrawer(BuildContext context) {
    return Drawer(
      child: Column(children: <Widget>[
        ListTile(
          leading: const Icon(Icons.download),
          title: const Text('Gpx file path : '),
          subtitle: Text(Config.path),
          onTap: () {
            _showEditPathDialog(context);
          },
        ),
        const Spacer(),
        ListTile(
          titleAlignment: ListTileTitleAlignment.center,
          title: const Center(
              child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.close),
              Text('Close'),
            ],
          )),
          onTap: () {
            Navigator.pop(context);
          },
        ),
      ]),
    );
  }

  Future<dynamic> _showEditPathDialog(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) {
        var textCtr = TextEditingController(text: Config.path);
        return AlertDialog(
          title: Text("The path of gpx file",
              style: Theme.of(context).textTheme.titleLarge),
          content: TextField(controller: textCtr),
          actions: [
            OutlinedButton(
                onPressed: () async {
                  String? selectedDirectory =
                      await FilePicker.platform.getDirectoryPath();

                  if (selectedDirectory == null) {
                    // User canceled the picker
                  } else {
                    setState(() {
                      Config.path = selectedDirectory;
                    });
                    final SharedPreferences prefs =
                        await SharedPreferences.getInstance();
                    prefs.setString("path", selectedDirectory);
                    Navigator.pop(context);
                  }
                },
                child: const Text("Broswer...")),
            OutlinedButton(
                onPressed: () async {
                  setState(() {
                    Config.path = textCtr.text;
                  });
                  // Obtain shared preferences.
                  final SharedPreferences prefs =
                      await SharedPreferences.getInstance();
                  prefs.setString("path", textCtr.text);
                  Navigator.pop(context);
                },
                child: const Text("Confirm"))
          ],
        );
      },
    );
  }

  Positioned _buildSettingButton() {
    return Positioned.fill(
        top: 12,
        right: 12,
        child: Align(
          alignment: Alignment.topRight,
          child: IconButton(
              iconSize: 30,
              onPressed: () {
                _scaffoldKey.currentState!.openEndDrawer();
              },
              icon: const Icon(Icons.settings)),
        ));
  }

  Positioned _buildSpeedPicker(BuildContext context) {
    return Positioned(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20.0),
          child: IntrinsicHeight(
            child: Container(
              decoration: BoxDecoration(
                  color: Colors.white.withAlpha(120),
                  borderRadius: const BorderRadius.all(Radius.circular(12))),
              margin: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  NumberPicker(
                    textStyle: Theme.of(context)
                        .textTheme
                        .titleSmall!
                        .copyWith(color: Colors.blueGrey),
                    selectedTextStyle: Theme.of(context)
                        .textTheme
                        .titleLarge!
                        .copyWith(color: Colors.redAccent),
                    value: _speedValue,
                    axis: Axis.horizontal,
                    minValue: 3,
                    maxValue: 20,
                    onChanged: (value) => setState(() => _speedValue = value),
                  ),
                  Text(
                    'Speed value: $_speedValue MPH',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium!
                        .copyWith(color: const Color.fromARGB(255, 69, 87, 96)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Container _buildMap(BuildContext context) {
    const LatLng initialCenter =  LatLng(24.84138065785531, 121.01890140704562);

    return Container(
      height: MediaQuery.of(context).size.height,
      width: MediaQuery.of(context).size.width,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter:initialCenter,
              initialZoom: 18.0,
              onTap: (tapPosition, point) {
                var p = Point(tapPosition.global.dx, tapPosition.global.dy);
                if (_personMarkPosition != null) {
                  _lastPersonMarkPosition = _personMarkPosition!.copy();
                }
                _personMarkPosition =
                    Position(mapPosition: point, screenPosition: p);
                _markRefresh();
              },
              onPositionChanged: (position, hasGesture) {
                if (_lastPersonMarkPosition != null) {
                  var mapP = _latLngConvertScreen(
                      position, _lastPersonMarkPosition!.mapPosition);
                  _lastPersonMarkPosition!.copyWithScreenPosition(mapP);
                }
                if (_personMarkPosition != null) {
                  var mapP = _latLngConvertScreen(
                      position, _personMarkPosition!.mapPosition);
                  _personMarkPosition!.copyWithScreenPosition(mapP);
                  _markRefresh();
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.app',
              ),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                    onTap: () => launchUrl(
                        Uri.parse('https://openstreetmap.org/copyright')),
                  ),
                ],
              ),
            ],
          ),
          StreamBuilder<bool?>(
              stream: refreshMarkSubjectStream,
              builder: (context, refreshSnapshot) {
                if (refreshSnapshot.data != null &&
                    _personMarkPosition != null) {
                  return Stack(
                    children: [
                      Positioned(
                          left: _personMarkPosition!.screenPosition.x -
                              20.toDouble(),
                          top: _personMarkPosition!.screenPosition.y -
                              20.toDouble(),
                          child: const Icon(
                              size: 40, color: Colors.red, Icons.man)),
                      if (_lastPersonMarkPosition != null)
                        Positioned(
                            left: _lastPersonMarkPosition!.screenPosition.x -
                                20.toDouble(),
                            top: _lastPersonMarkPosition!.screenPosition.y -
                                20.toDouble(),
                            child: Icon(
                                size: 40,
                                color: Colors.grey.shade400,
                                Icons.man)),
                      if (_lastPersonMarkPosition != null)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: LinePainter(
                                startPoint: Offset(
                                    _lastPersonMarkPosition!.screenPosition.x
                                        .toDouble(),
                                    _lastPersonMarkPosition!.screenPosition.y
                                        .toDouble()),
                                endPoint: Offset(
                                    _personMarkPosition!.screenPosition.x
                                        .toDouble(),
                                    _personMarkPosition!.screenPosition.y
                                        .toDouble()),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                }
                return const SizedBox.shrink();
              })
        ],
      ),
    );
  }
}

class Position {
  LatLng mapPosition;
  Point screenPosition;
  Position({required this.mapPosition, required this.screenPosition});

  void copyWithMapPosition(LatLng newPostion) {
    mapPosition = newPostion;
  }

  void copyWithScreenPosition(Point newPostion) {
    screenPosition = newPostion;
  }

  Position copy() {
    return Position(mapPosition: mapPosition, screenPosition: screenPosition);
  }
}
