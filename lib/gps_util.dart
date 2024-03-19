import 'dart:convert';
import 'dart:io';

import 'package:gpx/gpx.dart';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

void generateGpxFile(List<LatLng> waypoints,
    {double speedMph = 15,
    String filePath = "~/Desktop/output.gpx"}) {
  final gpx = Gpx();

  // Set the time for the first waypoint to current time
  gpx.wpts.add(Wpt(
    lat: waypoints[0].latitude,
    lon: waypoints[0].longitude,
    time: DateTime.now(),
  ));

  for (var i = 1; i < waypoints.length; i++) {
    // Calculate distance between waypoints (assuming lat/lon in degrees)
    final prevLat = gpx.wpts[i - 1].lat;
    final prevLon = gpx.wpts[i - 1].lon;
    final currLat = waypoints[i].latitude;
    final currLon = waypoints[i].longitude;
    final distanceMeters =
        calculateDistance(prevLat!, prevLon!, currLat, currLon);

    // Convert MPH to meters per second
    final speedMs = speedMph * 1609.34 / 3600;

    // Estimate time based on distance and speed
    final estimatedTime =
        Duration(microseconds: (distanceMeters / speedMs * 1e6).round());

    // Calculate time for current waypoint by adding estimated time to previous time
    final prevTime = gpx.wpts[i - 1].time;
    var currTime = prevTime?.add(estimatedTime);
    if (i == waypoints.length -1 )
      currTime = currTime?.add(Duration(days: 1));
    gpx.wpts.add(Wpt(
      lat: waypoints[i].latitude,
      lon: waypoints[i].longitude,
      time: currTime,
    ));
  }
  writeGpxToFile(gpx, filePath);
}

// Haversine formula to calculate distance between two points on Earth (in meters)
double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  final R = 6371e3; // Earth radius in meters
  final dLat = toRadians(lat2 - lat1);
  final dLon = toRadians(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(toRadians(lat1)) *
          math.cos(toRadians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return R * c;
}

double toRadians(double degrees) {
  return degrees * math.pi / 180;
}

Future<void> writeGpxToFile(Gpx gpx, String filePath) async {
  final file = File(filePath);
  var content = GpxWriter().asString(gpx, pretty: true);

  await file.writeAsString(removeMilliseconds(content));
}

String removeMilliseconds(String gpxContent) {
  final document = XmlDocument.parse(gpxContent);

  // Find all 'time' elements within 'wpt' elements
  final timeElements = document.findAllElements('time');

  // Loop through each 'time' element
  for (final element in timeElements) {
    // Extract the time string
    final timeStr = element.text;

    // Split the time string at the decimal point
    final parts = timeStr.split('.');

    // Join back the parts with '.'
    element.innerText = '${parts[0]}Z';
  }

  return document.toString();
}