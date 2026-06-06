#!/usr/bin/env bash
# Apply patches, build firmware for Pico 2 W and Pico W, copy UF2s to Windows side.
# Run from WSL.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MPY_DIR="${MPY_DIR:-$HOME/micropython}"

# 1. Apply our patches
"$HERE/apply.sh"

cd "$MPY_DIR/ports/rp2"

# 2. Build RPI_PICO2_W
BOARD2="RPI_PICO2_W"
echo "==> Building $BOARD2"
rm -rf "build-$BOARD2"
PATH=/usr/local/bin:/usr/bin:/bin \
PICOTOOL_FORCE_FETCH_FROM_GIT=1 \
    make BOARD="$BOARD2" submodules

PATH=/usr/local/bin:/usr/bin:/bin \
PICOTOOL_FORCE_FETCH_FROM_GIT=1 \
    make -j"$(nproc)" BOARD="$BOARD2"

UF2_SRC2="$MPY_DIR/ports/rp2/build-$BOARD2/firmware.uf2"
UF2_DST2="$HERE/firmware_pico2_w.uf2"
cp "$UF2_SRC2" "$UF2_DST2"

# 3. Build RPI_PICO_W
BOARD1="RPI_PICO_W"
echo "==> Building $BOARD1"
rm -rf "build-$BOARD1"
PATH=/usr/local/bin:/usr/bin:/bin \
PICOTOOL_FORCE_FETCH_FROM_GIT=1 \
    make BOARD="$BOARD1" submodules

PATH=/usr/local/bin:/usr/bin:/bin \
PICOTOOL_FORCE_FETCH_FROM_GIT=1 \
    make -j"$(nproc)" BOARD="$BOARD1"

UF2_SRC1="$MPY_DIR/ports/rp2/build-$BOARD1/firmware.uf2"
UF2_DST1="$HERE/firmware_pico_w.uf2"
cp "$UF2_SRC1" "$UF2_DST1"

# 4. Build RPI_PICO2 (non-Wi-Fi)
BOARD3="RPI_PICO2"
echo "==> Building $BOARD3"
rm -rf "build-$BOARD3"
PATH=/usr/local/bin:/usr/bin:/bin \
PICOTOOL_FORCE_FETCH_FROM_GIT=1 \
    make BOARD="$BOARD3" submodules

PATH=/usr/local/bin:/usr/bin:/bin \
PICOTOOL_FORCE_FETCH_FROM_GIT=1 \
    make -j"$(nproc)" BOARD="$BOARD3"

UF2_SRC3="$MPY_DIR/ports/rp2/build-$BOARD3/firmware.uf2"
UF2_DST3="$HERE/firmware_pico2.uf2"
cp "$UF2_SRC3" "$UF2_DST3"

# 5. Build RPI_PICO (non-Wi-Fi)
BOARD4="RPI_PICO"
echo "==> Building $BOARD4"
rm -rf "build-$BOARD4"
PATH=/usr/local/bin:/usr/bin:/bin \
PICOTOOL_FORCE_FETCH_FROM_GIT=1 \
    make BOARD="$BOARD4" submodules

PATH=/usr/local/bin:/usr/bin:/bin \
PICOTOOL_FORCE_FETCH_FROM_GIT=1 \
    make -j"$(nproc)" BOARD="$BOARD4"

UF2_SRC4="$MPY_DIR/ports/rp2/build-$BOARD4/firmware.uf2"
UF2_DST4="$HERE/firmware_pico.uf2"
cp "$UF2_SRC4" "$UF2_DST4"

echo "==> Done"
echo "    Pico 2 W:       $UF2_DST2"
echo "    Pico W:         $UF2_DST1"
echo "    Pico 2 (non-W): $UF2_DST3"
echo "    Pico (non-W):   $UF2_DST4"
echo "    Flash: hold BOOTSEL, plug USB, drag appropriate UF2 onto board drive."
