#!/bin/bash
# Publishes the data-only "GS - Trails" pack (content/gs-trails: images, trails.json, provides.json, licence.json) to the dot-cloud CDN.
# No addon code ships: dot_trail is the host's. Load trails.json with DotTrailRegistry.load_index, by path.
#   tools/publish_trails.sh VERSION [extra publish_pack.sh flags, e.g. --asset ID --site URL --token-file F --dry-run]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V=${1:?usage: tools/publish_trails.sh VERSION [flags]}; shift
CLOUD="${DOT_CLOUD_DIR:-$HERE/../dot-cloud}"
exec "$CLOUD/tools/publish_pack.sh" publish --source "$HERE/content/gs-trails" --id gs-trails --kind pack --name "GS - Trails" \
    --version "$V" --no-import --lock-optional --lock "$HERE/content/gs-trails.lock.json" "$@"
