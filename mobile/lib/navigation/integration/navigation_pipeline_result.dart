import 'package:latlong2/latlong.dart';
import 'package:mobile/models/navigation_output.dart';
import 'package:mobile/navigation/map_matching/map_match_result.dart';

class NavigationPipelineResult {
  final NavigationOutput raw;
  final MapMatchResult? mapMatch;

  const NavigationPipelineResult({required this.raw, this.mapMatch});

  LatLng get displayPosition => mapMatch?.matched == true
      ? mapMatch!.matchedPosition
      : LatLng(raw.latitude, raw.longitude);
}
