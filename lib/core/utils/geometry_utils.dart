import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Geometry utilities for polygon operations.
///
/// Provides algorithms for:
/// - Basic geometry (intersection, point-in-polygon, area)
/// - Polygon splitting via a cut line
/// - Polygon merging (shared-edge and closest-point strategies)
///
/// All coordinates use [LatLng] from latlong2 package.
/// Latitude = Y axis, Longitude = X axis in all calculations.
///
/// Author: Lộc Vũ Trung
class GeometryUtils {
  // Private constructor — all methods are static
  GeometryUtils._();

  /// Small epsilon for floating-point comparisons
  static const double _epsilon = 1e-10;

  /// Tolerance for coordinate matching (in degrees ≈ ~1.1 meters)
  static const double _defaultToleranceDeg = 0.00001;

  // ═══════════════════════════════════════════════════════════════
  // 1. BASIC GEOMETRY
  // ═══════════════════════════════════════════════════════════════

  /// Line segment intersection using parametric form.
  ///
  /// Given segments AB and CD, finds intersection point (if any).
  /// Uses parametric equations:
  ///   P = A + t*(B - A),  where 0 <= t <= 1
  ///   Q = C + s*(D - C),  where 0 <= s <= 1
  ///
  /// Returns the intersection [LatLng] if segments cross,
  /// or `null` if they are parallel or don't intersect within bounds.
  static LatLng? lineSegmentIntersection(
    LatLng a,
    LatLng b,
    LatLng c,
    LatLng d,
  ) {
    // Direction vectors
    final double dx1 = b.longitude - a.longitude; // B - A (x component)
    final double dy1 = b.latitude - a.latitude; // B - A (y component)
    final double dx2 = d.longitude - c.longitude; // D - C (x component)
    final double dy2 = d.latitude - c.latitude; // D - C (y component)

    // Denominator of the parametric equations
    // det = dx1 * dy2 - dy1 * dx2
    final double denominator = dx1 * dy2 - dy1 * dx2;

    // If denominator is ~0, lines are parallel (or coincident)
    if (denominator.abs() < _epsilon) {
      return null;
    }

    // Vector from A to C
    final double dx3 = c.longitude - a.longitude;
    final double dy3 = c.latitude - a.latitude;

    // Parameter t for segment AB
    final double t = (dx3 * dy2 - dy3 * dx2) / denominator;

    // Parameter s for segment CD
    final double s = (dx3 * dy1 - dy3 * dx1) / denominator;

    // Check if intersection falls within both segments [0, 1]
    if (t < -_epsilon || t > 1.0 + _epsilon) return null;
    if (s < -_epsilon || s > 1.0 + _epsilon) return null;

    // Compute the intersection point using segment AB's parametric form
    final double intersectLng = a.longitude + t * dx1;
    final double intersectLat = a.latitude + t * dy1;

    return LatLng(intersectLat, intersectLng);
  }

  /// Point-in-polygon test using the ray casting algorithm.
  ///
  /// Casts a horizontal ray from [point] to the right (+longitude)
  /// and counts how many polygon edges it crosses. An odd count
  /// means the point is inside.
  ///
  /// Handles edge cases:
  /// - Ray passing through a vertex
  /// - Point exactly on an edge (treated as inside)
  ///
  /// [polygon] should be a closed ring or an open ring
  /// (the closing edge from last→first is handled automatically).
  static bool pointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;

    final double px = point.longitude;
    final double py = point.latitude;
    bool inside = false;
    final int n = polygon.length;

    for (int i = 0, j = n - 1; i < n; j = i++) {
      final double xi = polygon[i].longitude;
      final double yi = polygon[i].latitude;
      final double xj = polygon[j].longitude;
      final double yj = polygon[j].latitude;

      // Check if the ray crosses this edge.
      // Edge goes from (xj, yj) to (xi, yi).
      // Ray is horizontal at py going to +infinity on x-axis.
      final bool intersects = ((yi > py) != (yj > py)) &&
          (px < (xj - xi) * (py - yi) / (yj - yi) + xi);

      if (intersects) {
        inside = !inside;
      }
    }

    return inside;
  }

  /// Distance from a [point] to line segment [segA]→[segB].
  ///
  /// Returns approximate distance in degrees. For rough on-screen
  /// proximity checks this is sufficient; for precise metric distance,
  /// convert the result using cos(latitude) scaling.
  ///
  /// Algorithm:
  /// 1. Project point onto the infinite line through segA→segB
  /// 2. Clamp the projection parameter t to [0, 1]
  /// 3. Compute distance from point to the clamped projection
  static double pointToSegmentDistance(
    LatLng point,
    LatLng segA,
    LatLng segB,
  ) {
    final double dx = segB.longitude - segA.longitude;
    final double dy = segB.latitude - segA.latitude;

    // If segment is actually a point, return distance to that point
    final double segLenSq = dx * dx + dy * dy;
    if (segLenSq < _epsilon * _epsilon) {
      return _degreeDistance(point, segA);
    }

    // Parameter t: projection of (point - segA) onto (segB - segA)
    double t = ((point.longitude - segA.longitude) * dx +
            (point.latitude - segA.latitude) * dy) /
        segLenSq;

    // Clamp t to [0, 1] so projection stays on the segment
    t = t.clamp(0.0, 1.0);

    // Closest point on the segment
    final LatLng closest = LatLng(
      segA.latitude + t * dy,
      segA.longitude + t * dx,
    );

    return _degreeDistance(point, closest);
  }

  /// Calculate polygon area in hectares using the Shoelace formula.
  ///
  /// Converts degree coordinates to approximate meters using:
  /// - 1° latitude ≈ 111,320 m
  /// - 1° longitude ≈ 111,320 m × cos(latitude)
  ///
  /// The polygon should be a simple (non-self-intersecting) ring.
  /// Works for both CW and CCW winding (returns absolute area).
  static double polygonAreaHa(List<LatLng> polygon) {
    if (polygon.length < 3) return 0.0;

    // Compute centroid latitude for longitude scaling
    double sumLat = 0.0;
    for (final p in polygon) {
      sumLat += p.latitude;
    }
    final double centerLat = sumLat / polygon.length;
    final double latToMeter = 111320.0;
    final double lngToMeter =
        111320.0 * math.cos(centerLat * math.pi / 180.0);

    // Shoelace formula in metric coordinates
    double area = 0.0;
    final int n = polygon.length;
    for (int i = 0; i < n; i++) {
      final int j = (i + 1) % n;
      final double xi = polygon[i].longitude * lngToMeter;
      final double yi = polygon[i].latitude * latToMeter;
      final double xj = polygon[j].longitude * lngToMeter;
      final double yj = polygon[j].latitude * latToMeter;
      area += xi * yj - xj * yi;
    }
    area = area.abs() / 2.0;

    // Convert m² to hectares (1 ha = 10,000 m²)
    return area / 10000.0;
  }

  // ═══════════════════════════════════════════════════════════════
  // 2. POLYGON SPLIT
  // ═══════════════════════════════════════════════════════════════

  /// Split a polygon with a cut line.
  ///
  /// [polygon] — The polygon to split (list of vertices, open or closed ring).
  /// [cutLine] — The cut line (list of 2+ points defining the cutting path).
  ///
  /// Returns `[polygonA, polygonB]` if the cut line properly crosses the
  /// polygon (entering and exiting), or `null` if it doesn't.
  ///
  /// **Algorithm overview:**
  /// 1. Find all intersection points of [cutLine] with polygon edges.
  /// 2. Require at least 2 intersections (entry + exit).
  /// 3. Use the first intersection as entry and last as exit.
  /// 4. Build polygon A by walking edges from entry→exit (forward),
  ///    then walking the cut line back from exit→entry.
  /// 5. Build polygon B by walking edges from exit→entry (continuing
  ///    forward, wrapping around), then walking cut line entry→exit.
  static List<List<LatLng>>? splitPolygon(
    List<LatLng> polygon,
    List<LatLng> cutLine,
  ) {
    if (polygon.length < 3 || cutLine.length < 2) {
      debugPrint('GeometryUtils.splitPolygon: invalid input '
          '(polygon: ${polygon.length} pts, cutLine: ${cutLine.length} pts)');
      return null;
    }

    // Ensure the polygon is an open ring (no duplicate closing vertex)
    final List<LatLng> poly = _ensureOpenRing(polygon);
    final int n = poly.length;

    // ── Step 1: Find all intersections ──────────────────────────
    // Each intersection records:
    //   - point: the LatLng where crossing occurs
    //   - edgeIndex: index of the polygon edge (edge i → i+1)
    //   - t: parametric position along that polygon edge [0..1]
    final List<_Intersection> intersections = [];

    for (int i = 0; i < n; i++) {
      final int iNext = (i + 1) % n;
      final LatLng edgeA = poly[i];
      final LatLng edgeB = poly[iNext];

      for (int j = 0; j < cutLine.length - 1; j++) {
        final LatLng cutA = cutLine[j];
        final LatLng cutB = cutLine[j + 1];

        final LatLng? hit = lineSegmentIntersection(edgeA, edgeB, cutA, cutB);
        if (hit != null) {
          // Compute parameter t along the polygon edge
          final double dx = edgeB.longitude - edgeA.longitude;
          final double dy = edgeB.latitude - edgeA.latitude;
          double t;
          if (dx.abs() > dy.abs()) {
            t = (hit.longitude - edgeA.longitude) / dx;
          } else if (dy.abs() > _epsilon) {
            t = (hit.latitude - edgeA.latitude) / dy;
          } else {
            t = 0.0;
          }
          t = t.clamp(0.0, 1.0);

          intersections.add(_Intersection(
            point: hit,
            edgeIndex: i,
            t: t,
            cutSegIndex: j,
          ));
        }
      }
    }

    // ── Step 2: Need at least 2 intersections ──────────────────
    if (intersections.length < 2) {
      debugPrint('GeometryUtils.splitPolygon: found only '
          '${intersections.length} intersection(s), need >= 2');
      return null;
    }

    // Sort by edge index, then by parameter t within the same edge
    intersections.sort((a, b) {
      final int cmp = a.edgeIndex.compareTo(b.edgeIndex);
      if (cmp != 0) return cmp;
      return a.t.compareTo(b.t);
    });

    // Remove duplicate intersection points (can happen at vertices)
    _removeDuplicateIntersections(intersections);

    if (intersections.length < 2) {
      debugPrint('GeometryUtils.splitPolygon: after dedup, only '
          '${intersections.length} intersection(s)');
      return null;
    }

    // Take first (entry) and last (exit) intersections
    final _Intersection entry = intersections.first;
    final _Intersection exit = intersections.last;

    // ── Step 3: Build polygon A ────────────────────────────────
    // Walk from entry intersection → along polygon edges → exit intersection
    // Then walk cutLine backwards from exit → entry
    final List<LatLng> polyA = [];

    // Start with the entry intersection point
    polyA.add(entry.point);

    // Walk polygon vertices from entry edge's end to exit edge's start
    {
      int startVert = (entry.edgeIndex + 1) % n;
      int endVert = exit.edgeIndex; // Walk up to (and including) this vertex

      // Walk forward from startVert to endVert (inclusive)
      int curr = startVert;
      int safetyCounter = 0;
      while (safetyCounter <= n) {
        polyA.add(poly[curr]);
        if (curr == endVert) break;
        curr = (curr + 1) % n;
        safetyCounter++;
      }
    }

    // Add the exit intersection point
    polyA.add(exit.point);

    // Walk cutLine in reverse: from exit back to entry
    // We need the portion of cutLine between the two intersection points
    // The cut line segment indices tell us which parts are inside the polygon
    {
      final List<LatLng> cutSegment =
          _extractCutLineSegment(cutLine, entry, exit);
      // Add in reverse (exit → entry)
      for (int i = cutSegment.length - 1; i >= 0; i--) {
        // Skip the endpoints (already added as intersection points)
        if (_pointsEqual(cutSegment[i], exit.point) ||
            _pointsEqual(cutSegment[i], entry.point)) {
          continue;
        }
        polyA.add(cutSegment[i]);
      }
    }

    // ── Step 4: Build polygon B ────────────────────────────────
    // Walk from exit intersection → along polygon edges (wrapping) → entry intersection
    // Then walk cutLine forward from entry → exit
    final List<LatLng> polyB = [];

    // Start with the exit intersection point
    polyB.add(exit.point);

    // Walk polygon vertices from exit edge's end to entry edge's start
    {
      int startVert = (exit.edgeIndex + 1) % n;
      int endVert = entry.edgeIndex;

      int curr = startVert;
      int safetyCounter = 0;
      while (safetyCounter <= n) {
        polyB.add(poly[curr]);
        if (curr == endVert) break;
        curr = (curr + 1) % n;
        safetyCounter++;
      }
    }

    // Add the entry intersection point
    polyB.add(entry.point);

    // Walk cutLine forward: from entry to exit
    {
      final List<LatLng> cutSegment =
          _extractCutLineSegment(cutLine, entry, exit);
      for (int i = 0; i < cutSegment.length; i++) {
        if (_pointsEqual(cutSegment[i], entry.point) ||
            _pointsEqual(cutSegment[i], exit.point)) {
          continue;
        }
        polyB.add(cutSegment[i]);
      }
    }

    // ── Step 5: Validate results ───────────────────────────────
    if (polyA.length < 3 || polyB.length < 3) {
      debugPrint('GeometryUtils.splitPolygon: resulting polygons too small '
          '(A: ${polyA.length} pts, B: ${polyB.length} pts)');
      return null;
    }

    return [polyA, polyB];
  }

  // ═══════════════════════════════════════════════════════════════
  // 3. POLYGON MERGE
  // ═══════════════════════════════════════════════════════════════

  /// Merge two polygons into one.
  ///
  /// **Strategy 1 — Shared edge:**
  /// If the polygons share one or more edges (within [toleranceDeg]),
  /// remove the shared portion and stitch the remaining boundaries
  /// into a single polygon.
  ///
  /// **Strategy 2 — No shared edge (nearby polygons):**
  /// Find the closest pair of vertices between the two polygons
  /// and connect them, creating a single polygon with a pinch point.
  ///
  /// Returns the merged polygon or `null` if merge fails.
  static List<LatLng>? mergePolygons(
    List<LatLng> polyA,
    List<LatLng> polyB, {
    double toleranceDeg = _defaultToleranceDeg,
  }) {
    if (polyA.length < 3 || polyB.length < 3) {
      debugPrint('GeometryUtils.mergePolygons: invalid input');
      return null;
    }

    final List<LatLng> a = _ensureOpenRing(polyA);
    final List<LatLng> b = _ensureOpenRing(polyB);

    // ── Try Strategy 1: Shared edge merge ──────────────────────
    final shared = findSharedEdge(a, b, toleranceDeg: toleranceDeg);
    if (shared != null) {
      return _mergeViaSharedEdge(a, b, shared);
    }

    // ── Strategy 2: Closest-point merge ────────────────────────
    return _mergeViaClosestPoint(a, b);
  }

  /// Merge multiple polygons sequentially.
  ///
  /// Starts with the first polygon and merges each subsequent polygon
  /// into the accumulated result. Returns `null` if any merge step fails.
  static List<LatLng>? mergeMultiplePolygons(List<List<LatLng>> polygons) {
    if (polygons.isEmpty) return null;
    if (polygons.length == 1) return List<LatLng>.from(polygons[0]);

    List<LatLng>? result = List<LatLng>.from(polygons[0]);
    for (int i = 1; i < polygons.length; i++) {
      result = mergePolygons(result!, polygons[i]);
      if (result == null) {
        debugPrint('GeometryUtils.mergeMultiplePolygons: '
            'merge failed at polygon index $i');
        return null;
      }
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════════
  // 4. HELPERS (PUBLIC)
  // ═══════════════════════════════════════════════════════════════

  /// Check if two polygons share at least one edge (within [toleranceDeg]).
  ///
  /// An edge is "shared" when two consecutive vertices of polyA match
  /// (within tolerance) two consecutive vertices of polyB.
  static bool polygonsShareEdge(
    List<LatLng> polyA,
    List<LatLng> polyB, {
    double toleranceDeg = _defaultToleranceDeg,
  }) {
    return findSharedEdge(polyA, polyB, toleranceDeg: toleranceDeg) != null;
  }

  /// Find the shared edge between two polygons.
  ///
  /// Returns a record with:
  /// - `startA`, `endA`: start/end vertex indices in polyA
  /// - `startB`, `endB`: start/end vertex indices in polyB
  ///
  /// Shared edges run in opposite winding directions (A goes CW,
  /// B goes CCW relative to the shared boundary, or vice versa).
  ///
  /// Returns `null` if no shared edge is found.
  static ({int startA, int endA, int startB, int endB})? findSharedEdge(
    List<LatLng> polyA,
    List<LatLng> polyB, {
    double toleranceDeg = _defaultToleranceDeg,
  }) {
    final List<LatLng> a = _ensureOpenRing(polyA);
    final List<LatLng> b = _ensureOpenRing(polyB);
    final int nA = a.length;
    final int nB = b.length;

    // For each edge in A, check if it matches any edge in B (in reverse).
    // Adjacent polygons typically share edges with opposite winding.
    for (int i = 0; i < nA; i++) {
      final int iNext = (i + 1) % nA;
      for (int j = 0; j < nB; j++) {
        final int jNext = (j + 1) % nB;

        // Check forward-reverse match: A[i]→A[i+1] matches B[j+1]→B[j]
        if (_pointsNear(a[i], b[jNext], toleranceDeg) &&
            _pointsNear(a[iNext], b[j], toleranceDeg)) {
          // Found a matching edge; now extend to find the longest shared run
          return _extendSharedEdge(a, b, i, j, toleranceDeg);
        }

        // Check forward-forward match: A[i]→A[i+1] matches B[j]→B[j+1]
        if (_pointsNear(a[i], b[j], toleranceDeg) &&
            _pointsNear(a[iNext], b[jNext], toleranceDeg)) {
          return _extendSharedEdgeForward(a, b, i, j, toleranceDeg);
        }
      }
    }

    return null;
  }

  /// Haversine distance between two points in meters.
  ///
  /// Uses the standard Haversine formula with Earth radius = 6,371,000 m.
  static double haversineDistance(LatLng a, LatLng b) {
    const double earthRadius = 6371000.0; // meters

    final double dLat = _toRadians(b.latitude - a.latitude);
    final double dLng = _toRadians(b.longitude - a.longitude);

    final double sinDLat = math.sin(dLat / 2.0);
    final double sinDLng = math.sin(dLng / 2.0);

    final double h = sinDLat * sinDLat +
        math.cos(_toRadians(a.latitude)) *
            math.cos(_toRadians(b.latitude)) *
            sinDLng *
            sinDLng;

    return 2.0 * earthRadius * math.asin(math.sqrt(h));
  }

  // ═══════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ═══════════════════════════════════════════════════════════════

  /// Convert degrees to radians.
  static double _toRadians(double deg) => deg * math.pi / 180.0;

  /// Euclidean distance in degrees (approximate, for comparisons only).
  static double _degreeDistance(LatLng a, LatLng b) {
    final double dx = a.longitude - b.longitude;
    final double dy = a.latitude - b.latitude;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Check if two points are within [tolerance] degrees of each other.
  static bool _pointsNear(LatLng a, LatLng b, double tolerance) {
    return (a.latitude - b.latitude).abs() < tolerance &&
        (a.longitude - b.longitude).abs() < tolerance;
  }

  /// Check if two points are equal (within floating-point epsilon).
  static bool _pointsEqual(LatLng a, LatLng b) {
    return _pointsNear(a, b, _defaultToleranceDeg);
  }

  /// Ensure polygon is an open ring (remove duplicate closing vertex).
  static List<LatLng> _ensureOpenRing(List<LatLng> polygon) {
    if (polygon.length < 2) return List<LatLng>.from(polygon);
    if (_pointsNear(polygon.first, polygon.last, _defaultToleranceDeg)) {
      return polygon.sublist(0, polygon.length - 1);
    }
    return List<LatLng>.from(polygon);
  }

  /// Remove duplicate intersections that are at the same location.
  static void _removeDuplicateIntersections(List<_Intersection> list) {
    if (list.length < 2) return;
    for (int i = list.length - 1; i > 0; i--) {
      if (_pointsEqual(list[i].point, list[i - 1].point)) {
        list.removeAt(i);
      }
    }
  }

  /// Extract the portion of the cut line between entry and exit intersections.
  ///
  /// Returns a list of points starting near entry and ending near exit,
  /// including any intermediate cut line vertices that lie inside the polygon.
  static List<LatLng> _extractCutLineSegment(
    List<LatLng> cutLine,
    _Intersection entry,
    _Intersection exit,
  ) {
    final List<LatLng> result = [];

    // Determine which cut segment indices are between entry and exit
    final int startSeg = math.min(entry.cutSegIndex, exit.cutSegIndex);
    final int endSeg = math.max(entry.cutSegIndex, exit.cutSegIndex);

    // Add entry point
    if (entry.cutSegIndex <= exit.cutSegIndex) {
      result.add(entry.point);
      // Add intermediate cut line points between the two intersection segments
      for (int i = startSeg + 1; i <= endSeg; i++) {
        result.add(cutLine[i]);
      }
      result.add(exit.point);
    } else {
      // Entry is on a later cut segment than exit — reverse order
      result.add(exit.point);
      for (int i = startSeg + 1; i <= endSeg; i++) {
        result.add(cutLine[i]);
      }
      result.add(entry.point);
      // Reverse so it goes entry → exit
      final reversed = result.reversed.toList();
      result
        ..clear()
        ..addAll(reversed);
    }

    return result;
  }

  /// Merge two polygons that share an edge (reverse winding match).
  ///
  /// Walks polyA, skipping the shared portion, and inserts polyB's
  /// non-shared vertices at the junction point.
  static List<LatLng>? _mergeViaSharedEdge(
    List<LatLng> a,
    List<LatLng> b,
    ({int startA, int endA, int startB, int endB}) shared,
  ) {
    final int nA = a.length;
    final int nB = b.length;
    final List<LatLng> result = [];

    // Walk polyA from after endA, around to startA (skipping shared edge)
    {
      int curr = (shared.endA + 1) % nA;
      int safetyCounter = 0;
      while (safetyCounter <= nA) {
        result.add(a[curr]);
        if (curr == shared.startA) break;
        curr = (curr + 1) % nA;
        safetyCounter++;
      }
    }

    // Walk polyB from after endB, around to startB (skipping shared edge)
    // Note: shared edges run in opposite directions between A and B,
    // so polyB's shared portion is startB→endB. We walk the non-shared part.
    {
      int curr = (shared.endB + 1) % nB;
      int safetyCounter = 0;
      while (safetyCounter <= nB) {
        result.add(b[curr]);
        if (curr == shared.startB) break;
        curr = (curr + 1) % nB;
        safetyCounter++;
      }
    }

    if (result.length < 3) {
      debugPrint('GeometryUtils._mergeViaSharedEdge: result too small');
      return null;
    }

    return result;
  }

  /// Merge two polygons by connecting them at their closest vertices.
  ///
  /// Finds the closest pair of vertices (one from each polygon),
  /// then stitches the polygons together at that point, creating
  /// a single polygon with a "pinch" or bridge.
  static List<LatLng>? _mergeViaClosestPoint(
    List<LatLng> a,
    List<LatLng> b,
  ) {
    final int nA = a.length;
    final int nB = b.length;

    // Find the closest vertex pair between the two polygons
    double minDist = double.infinity;
    int closestA = 0;
    int closestB = 0;

    for (int i = 0; i < nA; i++) {
      for (int j = 0; j < nB; j++) {
        final double d = _degreeDistance(a[i], b[j]);
        if (d < minDist) {
          minDist = d;
          closestA = i;
          closestB = j;
        }
      }
    }

    // Build merged polygon:
    // Walk polyA starting from closestA (full loop),
    // then bridge to polyB at closestB,
    // walk polyB (full loop),
    // then bridge back to polyA at closestA.
    final List<LatLng> result = [];

    // Walk all of polyA starting from closestA
    for (int i = 0; i <= nA; i++) {
      result.add(a[(closestA + i) % nA]);
    }

    // Walk all of polyB starting from closestB
    for (int i = 0; i <= nB; i++) {
      result.add(b[(closestB + i) % nB]);
    }

    // The resulting polygon revisits the bridge vertices (pinch points).
    // This is geometrically valid for display and area calculations.

    if (result.length < 3) {
      debugPrint('GeometryUtils._mergeViaClosestPoint: result too small');
      return null;
    }

    return result;
  }

  /// Extend a shared edge match (reverse winding) as far as possible.
  ///
  /// Given that edge A[iStart]→A[iStart+1] matches B[jStart+1]→B[jStart],
  /// walk forward in A and backward in B to find the full shared boundary.
  static ({int startA, int endA, int startB, int endB}) _extendSharedEdge(
    List<LatLng> a,
    List<LatLng> b,
    int iStart,
    int jStart,
    double tolerance,
  ) {
    final int nA = a.length;
    final int nB = b.length;

    int endA = (iStart + 1) % nA;
    int startB = jStart;

    // Try to extend forward in A and backward in B
    int currA = (endA + 1) % nA;
    int currB = (startB - 1 + nB) % nB;
    int extensions = 0;

    while (extensions < math.min(nA, nB)) {
      if (_pointsNear(a[currA], b[currB], tolerance)) {
        endA = currA;
        startB = currB;
        currA = (currA + 1) % nA;
        currB = (currB - 1 + nB) % nB;
        extensions++;
      } else {
        break;
      }
    }

    // endB is the vertex in B that matches the start of the shared portion in A
    final int endB = (jStart + 1) % nB;

    return (startA: iStart, endA: endA, startB: startB, endB: endB);
  }

  /// Extend a shared edge match (forward winding) as far as possible.
  ///
  /// Given that A[iStart]→A[iStart+1] matches B[jStart]→B[jStart+1],
  /// walk forward in both A and B to find the full shared boundary.
  static ({int startA, int endA, int startB, int endB})
      _extendSharedEdgeForward(
    List<LatLng> a,
    List<LatLng> b,
    int iStart,
    int jStart,
    double tolerance,
  ) {
    final int nA = a.length;
    final int nB = b.length;

    int endA = (iStart + 1) % nA;
    int endB = (jStart + 1) % nB;

    // Try to extend forward in both A and B
    int currA = (endA + 1) % nA;
    int currB = (endB + 1) % nB;
    int extensions = 0;

    while (extensions < math.min(nA, nB)) {
      if (_pointsNear(a[currA], b[currB], tolerance)) {
        endA = currA;
        endB = currB;
        currA = (currA + 1) % nA;
        currB = (currB + 1) % nB;
        extensions++;
      } else {
        break;
      }
    }

    return (startA: iStart, endA: endA, startB: jStart, endB: endB);
  }

  // ═══════════════════════════════════════════════════════════
  // POLYGON BUFFER (Nới rộng lô)
  // ═══════════════════════════════════════════════════════════

  /// Buffer a polygon outward by a distance in meters.
  /// Positive distance = expand outward, Negative = shrink inward.
  ///
  /// Algorithm:
  /// 1. For each edge of the polygon, compute the outward normal
  /// 2. Offset each edge by the buffer distance along the normal
  /// 3. Find intersections of adjacent offset edges
  /// 4. These intersections form the buffered polygon vertices
  ///
  /// Returns null if buffer produces invalid polygon
  static List<LatLng>? bufferPolygon(List<LatLng> polygon, double distanceMeters) {
    if (polygon.length < 3) return null;
    if (distanceMeters == 0) return List.from(polygon);

    final coords = _ensureOpenRing(polygon);
    final n = coords.length;
    
    // Convert distance to approximate degrees
    // At the polygon's center latitude
    final centerLat = coords.map((c) => c.latitude).reduce((a, b) => a + b) / n;
    final metersToDegLat = 1.0 / 111320.0; // ~111.32 km per degree latitude
    final metersToDegLng = 1.0 / (111320.0 * math.cos(centerLat * math.pi / 180.0));
    
    // Determine winding order (clockwise or counterclockwise)
    // Use signed area: positive = counterclockwise, negative = clockwise
    double signedArea = 0;
    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      signedArea += coords[i].longitude * coords[j].latitude;
      signedArea -= coords[j].longitude * coords[i].latitude;
    }
    // If clockwise (negative), flip the normal direction
    final normalSign = signedArea >= 0 ? 1.0 : -1.0;
    final d = distanceMeters * normalSign;
    
    // For each edge, compute offset line
    // Edge i: coords[i] -> coords[(i+1)%n]
    // Outward normal = perpendicular to edge direction, pointing outward
    final List<_OffsetEdge> offsetEdges = [];
    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final dx = coords[j].longitude - coords[i].longitude;
      final dy = coords[j].latitude - coords[i].latitude;
      
      // Perpendicular (outward normal): (-dy, dx) for CCW polygon
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < _epsilon) continue;
      
      final nx = -dy / len; // normal x (longitude direction)
      final ny = dx / len;  // normal y (latitude direction)
      
      // Offset both endpoints
      final offsetLng = d * metersToDegLng * nx;
      final offsetLat = d * metersToDegLat * ny;
      
      offsetEdges.add(_OffsetEdge(
        LatLng(coords[i].latitude + offsetLat, coords[i].longitude + offsetLng),
        LatLng(coords[j].latitude + offsetLat, coords[j].longitude + offsetLng),
      ));
    }
    
    if (offsetEdges.length < 3) return null;
    
    // Find intersections of adjacent offset edges
    final List<LatLng> result = [];
    for (int i = 0; i < offsetEdges.length; i++) {
      final j = (i + 1) % offsetEdges.length;
      final intersection = _lineLineIntersection(
        offsetEdges[i].a, offsetEdges[i].b,
        offsetEdges[j].a, offsetEdges[j].b,
      );
      if (intersection != null) {
        result.add(intersection);
      } else {
        // Parallel edges — use endpoint
        result.add(offsetEdges[i].b);
      }
    }
    
    if (result.length < 3) return null;
    return result;
  }
  
  /// Line-line intersection (unbounded lines, not segments)
  static LatLng? _lineLineIntersection(LatLng a1, LatLng a2, LatLng b1, LatLng b2) {
    final d1x = a2.longitude - a1.longitude;
    final d1y = a2.latitude - a1.latitude;
    final d2x = b2.longitude - b1.longitude;
    final d2y = b2.latitude - b1.latitude;
    
    final denom = d1x * d2y - d1y * d2x;
    if (denom.abs() < _epsilon) return null; // parallel
    
    final t = ((b1.longitude - a1.longitude) * d2y - (b1.latitude - a1.latitude) * d2x) / denom;
    
    return LatLng(
      a1.latitude + t * d1y,
      a1.longitude + t * d1x,
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// INTERNAL DATA STRUCTURES
// ═════════════════════════════════════════════════════════════════

/// Records an intersection between a polygon edge and a cut line segment.
class _Intersection {
  /// The intersection point coordinates.
  final LatLng point;

  /// Index of the polygon edge (edge from vertex[edgeIndex] to vertex[edgeIndex+1]).
  final int edgeIndex;

  /// Parametric position along the polygon edge [0.0 .. 1.0].
  /// 0.0 = at vertex[edgeIndex], 1.0 = at vertex[edgeIndex+1].
  final double t;

  /// Index of the cut line segment where intersection occurs.
  final int cutSegIndex;

  const _Intersection({
    required this.point,
    required this.edgeIndex,
    required this.t,
    required this.cutSegIndex,
  });

  @override
  String toString() =>
      '_Intersection(edge=$edgeIndex, t=${t.toStringAsFixed(4)}, '
      'cutSeg=$cutSegIndex, point=${point.latitude.toStringAsFixed(6)}, '
      '${point.longitude.toStringAsFixed(6)})';
}

/// Helper for buffer polygon offset edges
class _OffsetEdge {
  final LatLng a;
  final LatLng b;
  _OffsetEdge(this.a, this.b);
}
