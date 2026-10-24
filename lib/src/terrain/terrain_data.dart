import 'dart:math' as math;
import 'dart:typed_data';

import 'package:just_deflate/just_deflate.dart';

/// A terrain's ground: a square grid of [resolution] × [resolution]
/// samples — heights in metres (up: +Y is down, so they are subtracted),
/// how much of each of four layers shows (0–255, red to alpha), and holes —
/// with a revision for each block of [blockSamples]² samples, so what
/// draws it builds only what changed. A `.jterrain` file.
///
/// Sample (i, j) is column i along X, row j along Z: `j * resolution + i`.
final class TerrainData {
  /// A flat terrain of [resolution] samples a side, all of layer 0.
  TerrainData(this.resolution)
    : heights = Float32List(resolution * resolution),
      weights = Uint8List(resolution * resolution * 4),
      holes = Uint8List((resolution * resolution + 7) >> 3),
      _blockRevisions = Uint32List(_blocks(resolution) * _blocks(resolution)) {
    if (resolution < 2 || resolution > 4097) throw ArgumentError.value(resolution, 'resolution');
    for (var k = 0; k < resolution * resolution; k++) {
      weights[k * 4] = 255;
    }
  }

  TerrainData._(this.resolution, this.heights, this.weights, this.holes)
    : _blockRevisions = Uint32List(_blocks(resolution) * _blocks(resolution));

  /// What its files end with.
  static const String ending = '.jterrain';

  /// The resolutions offered for a new terrain.
  static const List<int> resolutions = [65, 129, 257, 513];

  /// Samples a side of a block, the unit what changed is counted in.
  static const int blockSamples = 16;

  static const int _version = 1;
  static const List<int> _magic = [0x4A, 0x54, 0x52, 0x4E]; // JTRN
  static const ZlibCodec _zlib = ZlibCodec(level: 3);

  static int _blocks(int resolution) => (resolution + blockSamples - 1) ~/ blockSamples;

  /// Samples a side.
  final int resolution;

  /// How far up the ground is at each sample (metres).
  final Float32List heights;

  /// Four layers' weights per sample, 0–255.
  final Uint8List weights;

  /// A bit per sample: set where there is a hole.
  final Uint8List holes;

  final Uint32List _blockRevisions;

  /// Equal only to itself: what keys made from this ground hold, instead
  /// of the ground and its arrays.
  final Object identity = Object();

  /// Bumped on every change: what draws it.
  int revision = 0;

  /// Bumped when a change is done — a stroke ended — so what collides with
  /// it is built again then, not at every dab.
  int solidRevision = 0;

  /// Blocks a side.
  int get blocksPerSide => _blocks(resolution);

  /// Block (bx, bz)'s revision.
  int blockRevision(int bx, int bz) => _blockRevisions[bz * blocksPerSide + bx];

  int index(int i, int j) => j * resolution + i;

  double height(int i, int j) => heights[index(i.clamp(0, resolution - 1), j.clamp(0, resolution - 1))];

  bool isHole(int i, int j) {
    final k = index(i, j);
    return holes[k >> 3] & (1 << (k & 7)) != 0;
  }

  void setHole(int i, int j, bool hole) {
    final k = index(i, j);
    if (hole) {
      holes[k >> 3] |= 1 << (k & 7);
    } else {
      holes[k >> 3] &= ~(1 << (k & 7)) & 0xFF;
    }
  }

  /// Whether it has a hole anywhere.
  bool get hasHoles => holes.any((b) => b != 0);

  /// Marks the samples from ([i0], [j0]) to ([i1], [j1]) changed — and the
  /// samples next to them, whose slopes they change.
  void touch(int i0, int j0, int i1, int j1) {
    for (final (bx, bz) in blocksIn(i0 - 1, j0 - 1, i1 + 1, j1 + 1)) {
      _blockRevisions[bz * blocksPerSide + bx]++;
    }
    revision++;
  }

  /// Marks a change done: what collides with it is built again.
  void settle() => solidRevision++;

  (int, double, double)? _range;

  /// Its lowest and highest ground (metres up), worked out again only
  /// after a change.
  (double, double) get heightRange {
    final known = _range;
    if (known != null && known.$1 == revision) return (known.$2, known.$3);
    var low = double.infinity, high = double.negativeInfinity;
    for (final h in heights) {
      if (h < low) low = h;
      if (h > high) high = h;
    }
    if (heights.isEmpty) low = high = 0;
    _range = (revision, low, high);
    return (low, high);
  }

  /// The height at ([x], [z]) samples in, between samples.
  double heightAt(double x, double z) {
    final last = resolution - 1;
    final cx = x.clamp(0.0, last.toDouble()), cz = z.clamp(0.0, last.toDouble());
    final i = math.min(cx.floor(), last - 1), j = math.min(cz.floor(), last - 1);
    final fx = cx - i, fz = cz - j;
    final a = height(i, j), b = height(i + 1, j), c = height(i, j + 1), d = height(i + 1, j + 1);
    return (a * (1 - fx) + b * fx) * (1 - fz) + (c * (1 - fx) + d * fx) * fz;
  }

  /// A copy of its own.
  TerrainData copy() => TerrainData._(
    resolution,
    Float32List.fromList(heights),
    Uint8List.fromList(weights),
    Uint8List.fromList(holes),
  );

  /// What block ([bx], [bz]) holds now: to put back with [restore].
  TerrainBlock capture(int bx, int bz) {
    final (i0, j0, i1, j1) = _rectOf(bx, bz);
    final w = i1 - i0 + 1, h = j1 - j0 + 1;
    final hs = Float32List(w * h), ws = Uint8List(w * h * 4), hole = Uint8List(w * h);
    for (var j = 0; j < h; j++) {
      for (var i = 0; i < w; i++) {
        final k = index(i0 + i, j0 + j), o = j * w + i;
        hs[o] = heights[k];
        for (var l = 0; l < 4; l++) {
          ws[o * 4 + l] = weights[k * 4 + l];
        }
        hole[o] = isHole(i0 + i, j0 + j) ? 1 : 0;
      }
    }
    return TerrainBlock(bx, bz, hs, ws, hole);
  }

  /// Puts [block] back as it was captured.
  void restore(TerrainBlock block) {
    final (i0, j0, i1, j1) = _rectOf(block.bx, block.bz);
    final w = i1 - i0 + 1, h = j1 - j0 + 1;
    for (var j = 0; j < h; j++) {
      for (var i = 0; i < w; i++) {
        final k = index(i0 + i, j0 + j), o = j * w + i;
        heights[k] = block.heights[o];
        for (var l = 0; l < 4; l++) {
          weights[k * 4 + l] = block.weights[o * 4 + l];
        }
        setHole(i0 + i, j0 + j, block.holes[o] != 0);
      }
    }
    touch(i0, j0, i1, j1);
  }

  (int, int, int, int) _rectOf(int bx, int bz) {
    final i0 = bx * blockSamples, j0 = bz * blockSamples;
    return (i0, j0, math.min(i0 + blockSamples - 1, resolution - 1), math.min(j0 + blockSamples - 1, resolution - 1));
  }

  /// The blocks the samples from ([i0], [j0]) to ([i1], [j1]) are in.
  Iterable<(int, int)> blocksIn(int i0, int j0, int i1, int j1) sync* {
    final last = resolution - 1;
    for (var bz = j0.clamp(0, last) ~/ blockSamples; bz <= j1.clamp(0, last) ~/ blockSamples; bz++) {
      for (var bx = i0.clamp(0, last) ~/ blockSamples; bx <= i1.clamp(0, last) ~/ blockSamples; bx++) {
        yield (bx, bz);
      }
    }
  }

  /// The file's bytes: `JTRN`, a version, the resolution, then the
  /// heights (32-bit floats), the weights and the holes, packed with zlib.
  Uint8List encode() {
    final n = resolution * resolution;
    final body = BytesBuilder(copy: false)
      ..add(heights.buffer.asUint8List(heights.offsetInBytes, n * 4))
      ..add(weights)
      ..add(holes);
    final packed = _zlib.encode(body.takeBytes());
    final head = ByteData(8)
      ..setUint8(0, _magic[0])
      ..setUint8(1, _magic[1])
      ..setUint8(2, _magic[2])
      ..setUint8(3, _magic[3])
      ..setUint16(4, _version, Endian.little)
      ..setUint16(6, resolution, Endian.little);
    return (BytesBuilder(copy: false)
          ..add(head.buffer.asUint8List())
          ..add(packed))
        .takeBytes();
  }

  /// The terrain [bytes] hold; a [FormatException] when they hold none.
  static TerrainData decode(Uint8List bytes) {
    if (bytes.length < 8) throw const FormatException('Not a terrain: too short');
    for (var k = 0; k < 4; k++) {
      if (bytes[k] != _magic[k]) throw const FormatException('Not a terrain');
    }
    final head = ByteData.sublistView(bytes, 0, 8);
    final version = head.getUint16(4, Endian.little);
    if (version > _version) throw FormatException('Terrain version $version is newer than this engine reads ($_version)');
    final resolution = head.getUint16(6, Endian.little);
    final n = resolution * resolution;
    final holeBytes = (n + 7) >> 3;
    if (resolution < 2) throw const FormatException('A terrain\'s samples do not add up');
    // Never more than the header says: a damaged file fails at once.
    final body = _zlib.decode(Uint8List.sublistView(bytes, 8), maxOutputSize: n * 8 + holeBytes);
    if (body.length != n * 4 + n * 4 + holeBytes) {
      throw const FormatException('A terrain\'s samples do not add up');
    }
    // Copied: a view into the body may not be aligned for floats.
    final heights = Float32List(n);
    heights.buffer.asUint8List().setRange(0, n * 4, body);
    return TerrainData._(
      resolution,
      heights,
      Uint8List.fromList(Uint8List.sublistView(body, n * 4, n * 8)),
      Uint8List.fromList(Uint8List.sublistView(body, n * 8)),
    );
  }
}

/// One block of a [TerrainData] as it was: what undo puts back.
final class TerrainBlock {
  const TerrainBlock(this.bx, this.bz, this.heights, this.weights, this.holes);

  final int bx, bz;
  final Float32List heights;
  final Uint8List weights;
  final Uint8List holes;
}
