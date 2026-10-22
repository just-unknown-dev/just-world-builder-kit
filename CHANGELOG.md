# Changelog

## 0.1.0-dev

First version: world building for just_game_engine in 3D.

- `WorldBuilderKit.extension`: the kit's components, field types and render providers; `WorldBuilderKit.systems()`: what ties sweeps, tiles and terrains to their splines and files before physics, and moves path followers.
- `package:just_world_builder_kit/editor.dart` (design-time): `WorldBuilderModule`, a Level Designer kit for 3-D scenes ("World Builder" in its switch).
- Blockout: draw a box on any surface and pull it up to its height, outline a floor, drag a ramp or a flight of stairs from its foot to its top. Each makes the engine's own 3-D shapes, one undo step.
- Splines: `Spline3D` (Catmull-Rom, Bezier or straight; open or closed; roll), `SplinePath` (length, rotation-minimising frames, nearest point), `SplineSweep3D` (road, wall, pipe, rail; solid as its mesh), `SplineInstances3D` (copies in one batch), `PathFollower3D` (loop, back and forth or once, resting at the ends). Editor: the Spline tool, point handles, a splines overlay, laying the selection along a spline, baking copies into entities.
- Grid tiles: mesh libraries (`.meshlib.json`) and their workspace, `GridTiles3D` (24 turns; cells packed with zlib), batches per piece and block of cells, collision merged along rows. Editor: the Tiles tool (paint, erase, fill, pick; floors; turns) and the Tiles panel.
- Terrain: `Terrain3D` and `.jterrain` files (heights, four layers' weights, holes), chunks rebuilt only where they changed, a height field with holes for collision. Editor: the Terrain tool (raise, lower, smooth, flatten, noise, paint, holes), the Terrain panel; files written as the scene is saved.
- Scatter: `Scatter3D` layers (each a model, or one of the engine's shapes in its colour) and pieces (packed with zlib), batches per layer and square with a reach, opt-in box or capsule collision. Editor: the Scatter brush and panel, and inspector editors for the layers and pieces.
- The editor picks the kit's pieces exactly: tiles by cell, swept roads by triangle, terrain by its ground.
- The brush and preview overlays (blockout, grid tiles, terrain, scatter) are what a tool in use draws, not gizmos (`gizmoKind` null): they stay with the editor's gizmos hidden.
- `just_store.json`: a kit; its editor part editor-only.
