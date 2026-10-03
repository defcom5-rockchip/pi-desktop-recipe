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
cycle(){ rfkill block bluetooth; sleep 2; rfkill unblock bluetooth; sleep 1; }
cycle; attach
for i in $(seq 1 15); do sleep 1; ok && break; done
if ! ok; then
	log "hci0 wedged (null address) — power-cycling and re-attaching once"
	kill "$HCI" 2>/dev/null; sleep 1; cycle; attach
	for i in $(seq 1 15); do sleep 1; ok && break; done
fi
if ok; then log "hci0 up: $(hciconfig hci0 | awk '/BD Address/{print $3}')"; else log "hci0 STILL wedged after retry — bt-sentinel will keep trying"; fi
wait "$HCI"
