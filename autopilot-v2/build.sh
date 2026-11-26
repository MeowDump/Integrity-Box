#!/bin/sh
# Builds the shipped engine and writes its PROVENANCE.
#
#   sh autopilot-v2/build.sh            tests, vet, reproducible arm64 build, provenance file
#   ALLOW_DIRTY=1 sh autopilot-v2/build.sh   development build: no provenance is written (never commit its output)
#
# The binary is tracked in git because the module package is assembled from `git ls-files`. To keep that honest:
#   * it is built only from COMMITTED sources (the provenance records the git tree of autopilot-v2),
#   * the build is reproducible (-trimpath, -buildvcs=false: Go would otherwise stamp the git revision INTO the binary, so a build
#     inside the repository and one from `git archive` could never match; no CGO), so anybody can rebuild and compare (verify_binary.sh),
#   * it is committed in its own commit, after the sources (the pre-commit guard enforces both).
set -eu
cd "$(dirname "$0")"
go test -race ./...
go vet ./...
OUT=../webroot/common_scripts/bin
mkdir -p "$OUT"
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -trimpath -buildvcs=false -ldflags='-s -w' -o "$OUT/box-autopilot" .
if [ "${ALLOW_DIRTY:-0}" = 1 ]; then
    echo "development build: provenance NOT written; do not commit this binary"
    exit 0
fi
if [ -n "$(git status --porcelain -- . 2>/dev/null)" ]; then
    echo "REFUSED to write provenance: autopilot-v2 has uncommitted changes. Commit the sources first, then run build.sh again." >&2
    echo "(the binary was built, but it must not be committed)" >&2
    exit 1
fi
SUM=$(shasum -a 256 "$OUT/box-autopilot" | cut -d' ' -f1)
TREE=$(git rev-parse HEAD:autopilot-v2)
{
    printf '%s  box-autopilot\n' "$SUM"
    printf '# toolchain: %s\n' "$(go version)"
    printf '# build: GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -trimpath -buildvcs=false -ldflags="-s -w" .\n'
    printf '# source: git tree of autopilot-v2 at the build commit = %s\n' "$TREE"
    printf '# verify: sh autopilot-v2/verify_binary.sh\n'
} > "$OUT/box-autopilot.sha256"
echo "built $OUT/box-autopilot ($SUM) and wrote $OUT/box-autopilot.sha256"
