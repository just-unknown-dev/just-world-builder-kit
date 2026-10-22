# just_world_builder_kit

World building for [just_game_engine](https://engine.justunknown.com/) in 3D:
the pieces a level is built from — and, in the editor, the Level Designer
tools that make them. The kit owns its pieces whole: their components, what
draws them, what makes them solid and the files they keep.

| Piece | Component | Drawn | Solid |
| --- | --- | --- | --- |
| Blockout | the engine's 3-D shapes | as shapes | as shapes |
| Splines | `Spline3D`, `SplineSweep3D`, `SplineInstances3D`, `PathFollower3D` | a swept mesh; copies in one batch | the swept mesh |
| Grid tiles | `GridTiles3D` + a mesh library (`.meshlib.json`) | batches per piece and block of cells | boxes merged along rows, or each piece's shape |
| Terrain | `Terrain3D` + a `.jterrain` file | in chunks, rebuilt only where it changed | a height field, holes and all |
| Scatter | `Scatter3D` | batches per layer and square, not drawn far off | opt-in boxes or capsules per layer |

Every piece is solid through a `Collider3D` set to **Match shape** on a static
body (a platform on a route: a kinematic one). +Y is down in the engine:
heights are measured up, towards −Y.

## The pieces

- **Blockout.** Draw a box on any surface and pull it up to its height,
  outline a floor, drag a ramp or a flight of stairs from its foot to its
  top. Blockout makes the engine's own 3-D shapes, so a blocked-out level
  plays at once and can be dressed later.
- **Splines.** A `Spline3D` is a path of points (Catmull–Rom, Bézier or
  straight; open or closed; each point with a roll). Lay a road, a wall, a
  pipe or a rail along it (`SplineSweep3D`), copies of a model every few
  metres (`SplineInstances3D`, which the editor can bake into entities), or
  move an entity along it with `PathFollower3D` — loop, back and forth, or
  once, resting at the ends. A kinematic body on a route carries whoever
  stands on it.
- **Grid tiles.** A mesh library lists pieces — a model, or one of the
  engine's shapes — sized to its cells, each solid as its cell, as its own
  shape, or not at all. A `GridTiles3D` holds which piece is in each cell and
  how it is turned (any of the 24 quarter turns of a cube), packed small in
  the scene.
- **Terrain.** A `Terrain3D` is ground shaped by hand: heights, four layers'
  weights and holes, kept in a `.jterrain` file beside the scene. It shows the
  four layers of a layered material file, or four colours. Its collision is
  rebuilt when a stroke ends, not at every dab.
- **Scatter.** A `Scatter3D` holds layers — grass, rocks, trees, each a
  model or one of the engine's shapes in its colour — and the pieces
  painted of each, kept a layer's spacing apart.

## Use

Give the engine the kit's extension and its systems (the Asset Store's
generated `storeExtensions` and the setup snippet do this for an installed
kit):

```dart
final engine = Engine(config: EngineConfig(
  extensions: [WorldBuilderKit.extension],
  graphics3D: Graphics3D(),
  physics3D: Physics3D(),
));
await engine.initialize();
WorldBuilderKit.registerSystems(engine.world);
```

The systems tie sweeps, tiles and terrains to their splines and files before
physics runs — so they are solid even where nothing draws them — and move
path followers.

List the folders the kit's files live in among the game's assets, as a
scene uses them: `assets/tiles/`, `assets/terrain/<scene>/`.

## In the editor

Add `WorldBuilderModule()` from `package:just_world_builder_kit/editor.dart`
to the editor's modules (the generated `storeModules()` does this). It
appears as **World Builder** in the Level Designer's switch in 3-D scenes:

- **BLOCKOUT**: Block, Floor, Ramp.
- **SPLINES**: Spline — click points along any surface; Enter, a double-click
  or the first point finishes. It makes a path, a road, a wall, a pipe, a
  rail, posts, or a platform with its route. Drag a selected spline's points,
  raise them on their diamonds, add points on the "+"s, Alt-click to remove.
  The inspector lays the rest of the selection along a spline, and bakes
  copies into entities.
- **TILES**: Tiles — paint, erase, fill a box; on the floor level (Page Up /
  Page Down) or stacked on what is under the pointer; Z turns the piece, X
  and C tip it, Shift the other way; Alt-click picks one up. The Tiles panel
  chooses the library and the piece and makes a new library; a library opens
  in its own workspace.
- **TERRAIN**: Terrain — raise, lower, smooth, flatten, roughen, paint a
  layer, cut holes; Shift the other way, `[` `]` the brush's size. The
  Terrain panel names the terrain being shaped, holds the brush (what it
  does, its size and strength, the layer it paints), makes a new terrain
  (its size, and its detail: coarse, medium or fine) and gives a shared one
  a file of its own. Terrain files are written when the scene is saved.
- **SCATTER**: Scatter — drag over the ground (terrain, tiles, shapes,
  models) for the chosen layer's pieces, each set down on what is under it;
  Shift erases. The Scatter panel names the scatter being painted, holds the
  brush, lists the layers with their pieces and edits the chosen one; the
  inspector edits every setting of every layer.

The side panel's TILES, TERRAIN and SCATTER sections open with their own
tools.

Each stroke is one undo step.

`lib/just_world_builder_kit.dart` never imports the editor: a release build
ships the runtime only.
