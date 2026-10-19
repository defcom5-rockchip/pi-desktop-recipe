#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 defcom5-rockchip — https://github.com/defcom5-rockchip
# Pi-Desktop: AP6275P Bluetooth bring-up, race-hardened.
# Port of 2.0.x ap6275p-bluetooth.sh (ubuntu-rockchip#1 / 814a50f) onto Armbian's hciattach path.
# Replaces the BSP-generated /usr/local/sbin/bluetooth-hciattach.sh (diverted, not deleted).
#  - unblock Bluetooth by TYPE, never "all": waking WiFi during the BT firmware load wedges the shared chip
#    (hci0 DOWN, null MAC, "HCI Reset 0x1003 failed: -49")
#  - power-cycle BT_REG_ON first, attach, verify hci0 got a real address, retry once
log(){ logger -t pidesktop-bt "$*"; }
ok(){ local m; m=$(hciconfig hci0 2>/dev/null | awk '/BD Address/{print $3}'); [[ -n $m && $m != 00:00:00:00:00:00 ]]; }
attach(){ hciattach -n -s 115200 /dev/ttyS9 bcm43xx 1500000 & HCI=$!; }
cycle(){  # record the window so bt-sentinel can tell this power cycle from a user's switch (it matches event times).
          # One line per cycle, "start end" ("-" while in progress); the last 20 are kept, because the sentinel may only
          # look at an event long after a later cycle has happened.
	local c=/run/pidesktop-bt-cycle s e; s=$(date +%s); { [ -f "$c" ] && tail -n 19 "$c"; echo "$s -"; } > "$c.new"; mv -f "$c.new" "$c"
	rfkill block bluetooth; sleep 2; rfkill unblock bluetooth; sleep 1
	e=$(date +%s); sed -i "s/^$s -\$/$s $e/" "$c"; }
# The module is a Broadcom BCM43752 (AP6275P) on PCIe (pcie@fe190000). An Orange Pi 5 (not B) has no module, only an
# M.2 slot on that lane: there is nothing to attach, so stand down quietly instead of retrying for ever. The marker tells
# bt-sentinel and bt-revive to stand down too. (The bt_default rfkill exists on the 5 as well: it comes from the device
# tree, not from the chip, so it cannot be the test.)
# A 5B whose Wi-Fi link did not train would look the same on PCIe, so the eMMC (every 5B has one, no 5 does) is the
# second witness: Broadcom gone but eMMC present = a 5B with a module problem → still try Bluetooth (it is UART-attached
# and does not need the PCIe side).
PCI=${PD_PCI_SYSFS:-/sys/bus/pci/devices}; MMC=${PD_MMC_SYSFS:-/sys/bus/mmc/devices}; ABSENT=/run/pidesktop-bt-absent
module_present(){ local d; for d in "$PCI"/*; do [ "$(cat "$d/vendor" 2>/dev/null)" = 0x14e4 ] && case "$(cat "$d/class" 2>/dev/null)" in 0x0280*) return 0;; esac; done; return 1; }
emmc_present(){ local d; for d in "$MMC"/*; do [ "$(cat "$d/type" 2>/dev/null)" = MMC ] && return 0; done; return 1; }
rm -f "$ABSENT"
for i in $(seq 1 10); do module_present && break; sleep 1; done
if ! module_present; then
	if emmc_present; then
		log "Broadcom PCIe Wi-Fi/Bluetooth module not found but eMMC present: an Orange Pi 5B whose module did not enumerate — attempting Bluetooth anyway"
	else
		echo "no Broadcom PCIe Wi-Fi/Bluetooth module and no eMMC: an Orange Pi 5 (no onboard Wi-Fi/Bluetooth) — Bluetooth helpers standing down" > "$ABSENT"
		log "$(cat "$ABSENT")"; systemctl stop --no-block bt-sentinel.service 2>/dev/null || true; exit 0
	fi
fi
systemctl start --no-block bt-sentinel.service 2>/dev/null || true   # back in service if an earlier boot phase stood it down
cycle; attach
for i in $(seq 1 15); do sleep 1; ok && break; done
if ! ok; then
	log "hci0 wedged (null address) — power-cycling and re-attaching once"
	kill "$HCI" 2>/dev/null; sleep 1; cycle; attach
	for i in $(seq 1 15); do sleep 1; ok && break; done
fi
if ok; then log "hci0 up: $(hciconfig hci0 | awk '/BD Address/{print $3}')"; else log "hci0 STILL wedged after retry — bt-sentinel will keep trying"; fi
wait "$HCI"
