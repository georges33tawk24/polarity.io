# assets/

Authored glTF from `tools/blender_export.py`. **Empty by default** — the game
generates equivalent geometry at runtime when these files are absent, so the
project builds and plays with or without this directory being populated.

To populate it:

```bash
blender --background --python tools/blender_export.py
```

The exporter fails loudly if any asset exceeds the §13A tri budget (magnet 800,
scrap 200). `AssetLibrary` picks up whatever is here on the next launch with no
code change, and the boot log prints which assets came from files and which were
generated.
