#!/bin/zsh
# Lenovo Legion Pro 34WD-10 light strip effects over DDC/CI (prototype).
# The strip features sit behind VCP 0xF8 (feature index) + 0xF7 (value):
#   0x1D effect   0x51D speed   0x61D brightness (0-100)
# Needs the `ddc` binary next to this script: swiftc -O ddc.swift -o ddc
cd "$(dirname "$0")"

typeset -A MODES=(off 0 breathing 1 flashing 2 marquee 3 fireworks 5 starry 6 rhythm 7)

sel() { ./ddc set F8 $(($1)) >/dev/null; sleep 0.15; }
put() { sel $1; ./ddc set F7 $(($2)) >/dev/null; sleep 0.2; }
val() { sel $1; ./ddc get F7 | sed -E 's/.*cur=([0-9]+).*/\1/'; }

case $1 in
  status)
    m=$(val 0x1D)
    for k v in ${(kv)MODES}; do [[ $v == $m ]] && m="$k ($v)"; done
    echo "effect:     $m"
    echo "speed:      $(val 0x51D)"
    echo "brightness: $(val 0x61D)" ;;
  mode)
    [[ -n ${MODES[$2]} ]] || { echo "effects: ${(k)MODES}"; exit 1; }
    put 0x1D ${MODES[$2]} ;;
  off)        put 0x1D 0 ;;
  brightness) put 0x61D $2 ;;
  speed)      put 0x51D $2 ;;
  *) echo "usage: light.sh status | mode <${(kj:|:)MODES}> | off | brightness 0-100 | speed N" ;;
esac
