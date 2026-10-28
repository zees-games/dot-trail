# dot-trail

Players equip a trail, an image ribbon that follows them as they move. Operators upload trails and choose who may wear them: everyone, or only some groups (donators, say). The server decides what a player may wear; clients download every trail as one pack before joining. See [docs/design.md](docs/design.md).

**Licensing: this addon provides upload and display only. It ships no art; whoever uploads an image is responsible for having the right to distribute it.**

```gdscript
var trails := DotTrailRegistry.new()
trails.install()                                   # DotRegistry, no autoload
trails.load_index(index_json, files)               # the downloaded pack
var equip := DotTrailEquip.new(trails)
var res := equip.equip(peer_id, "spark", groups, entitlements)   # DotResult; server only

var emitter := DotTrailEmitter.new()               # child of the player, or set `target`
emitter.registry = trails
player.add_child(emitter)
emitter.set_trail(trails.get_def(equip.worn(peer_id)))
```

Settings are `DotTrailConfig` (`DOT_TRAIL_*` environment, `--trail-*` command line): `enabled`, `min_step`, `max_points`, `equip_cooldown`, `max_upload_bytes`, `max_dimension`, `max_trails`, `cull_distance`.

The self-test is `examples/trail_selftest.tscn`, run headless.
