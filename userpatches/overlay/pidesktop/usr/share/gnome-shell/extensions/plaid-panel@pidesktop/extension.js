// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 defcom5-rockchip (Pi-Desktop)
// Plaid Panel: recolours GNOME's top bar to match the Plaid wallpaper. All of it is stylesheet.css, which GNOME Shell
// loads when the extension is enabled and unloads when it is disabled, across theme rebuilds (dark/light, high
// contrast) and the lock screen. So there is nothing to do here: no settings, no D-Bus, no signals.
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

export default class PlaidPanel extends Extension {
    enable() {}
    disable() {}
}
