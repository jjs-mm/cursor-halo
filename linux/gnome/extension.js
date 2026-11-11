// SPDX-License-Identifier: MIT
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';
import Cairo from 'cairo';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {appearance, clickColor, COLORS, finitePoint, MAX_PULSES, PULSE_MS, SHORTCUTS} from './model.js';

export default class CursorHalo extends Extension {
    enable() {
        this._pulses = new Set();
        this._pulseTimeouts = new Map();
        this._settings = this.getSettings();
        this._interface = new Gio.Settings({schema_id: 'org.gnome.desktop.interface'});
        this._tracker = Meta.CursorTracker.get_for_display(global.display);
        this._activeShortcut = null;
        this._action = 0;
        this._button = new PanelMenu.Button(0.0, 'Cursor Halo');
        this._button.add_child(new St.Icon({icon_name: 'find-location-symbolic', style_class: 'system-status-icon'}));
        this._toggle = new PopupMenu.PopupSwitchMenuItem('Highlight pointer', this._settings.get_boolean('enabled'));
        this._toggle.connect('toggled', (_item, enabled) => this._settings.set_boolean('enabled', enabled));
        this._button.menu.addMenuItem(this._toggle);
        this._errorItem = new PopupMenu.PopupMenuItem('', {reactive: false});
        this._button.menu.addMenuItem(this._errorItem);
        this._button.menu.addAction('Settings…', () => this.openPreferences());
        this._button.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this._button.menu.addAction('Turn off extension', () => Main.extensionManager.disableExtension(this.uuid));
        Main.panel.addToStatusArea(this.uuid, this._button);
        this._acceleratorId = global.display.connect('accelerator-activated', (_display, action) => {
            if (action === this._action)
                this._settings.set_boolean('enabled', !this._settings.get_boolean('enabled'));
        });
        this._settingsId = this._settings.connect('changed', (_settings, key) => {
            if (key === 'shortcut') this._registerShortcut();
            else if (key !== 'shortcut-error') this._sync();
        });
        this._registerShortcut();
        this._sync();
    }

    _registerShortcut() {
        const chosen = this._settings.get_int('shortcut');
        if (chosen === this._activeShortcut && this._action) return;
        const action = global.display.grab_accelerator(SHORTCUTS[chosen] ?? SHORTCUTS[0], Meta.KeyBindingFlags.NONE);
        if (!action) {
            const message = 'Shortcut is in use. Choose another in Settings.';
            this._settings.set_string('shortcut-error', message);
            this._errorItem.label.text = message;
            this._errorItem.show();
            if (this._activeShortcut !== null)
                this._settings.set_int('shortcut', this._activeShortcut);
            return;
        }
        Main.wm.allowKeybinding(Meta.external_binding_name_for_action(action), Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW);
        this._releaseShortcut();
        this._action = action;
        this._activeShortcut = chosen;
        this._settings.set_string('shortcut-error', '');
        this._errorItem.hide();
    }

    _releaseShortcut() {
        if (!this._action) return;
        Main.wm.allowKeybinding(Meta.external_binding_name_for_action(this._action), Shell.ActionMode.NONE);
        global.display.ungrab_accelerator(this._action);
        this._action = 0;
    }

    _readAppearance() {
        return appearance(Object.fromEntries(['style', 'color', 'diameter', 'opacity', 'stroke']
            .map(key => [key, this._settings.get_int(key)])));
    }

    _makeActor(config, color, pulse = false) {
        const side = config.diameter + config.stroke * 2 + 6;
        const actor = new St.DrawingArea({width: side, height: side, reactive: false, can_focus: false, track_hover: false});
        actor.connect('repaint', area => {
            const cr = area.get_context();
            const [width, height] = area.get_surface_size();
            cr.setOperator(Cairo.Operator.CLEAR);
            cr.paint();
            cr.setOperator(Cairo.Operator.OVER);
            const radius = config.diameter / 2;
            const alpha = config.opacity / 100;
            cr.arc(width / 2, height / 2, radius, 0, Math.PI * 2);
            if (!pulse && config.style === 1) {
                cr.setSourceRGBA(...color, alpha * 0.22);
                cr.fillPreserve();
            }
            cr.setSourceRGBA(0.05, 0.05, 0.05, alpha * 0.8);
            cr.setLineWidth(config.stroke + 2);
            cr.strokePreserve();
            cr.setSourceRGBA(...color, alpha);
            cr.setLineWidth(config.stroke);
            cr.stroke();
            cr.$dispose();
        });
        Main.layoutManager.addTopChrome(actor, {affectsInputRegion: false, trackFullscreen: false});
        return actor;
    }

    _sync() {
        this._clearOverlay();
        const enabled = this._settings.get_boolean('enabled');
        this._toggle.setToggleState(enabled);
        if (!enabled) return;
        this._config = this._readAppearance();
        this._halo = this._makeActor(this._config, COLORS[this._config.color]);
        this._positionId = this._tracker.connect('position-invalidated', () => this._updatePointer());
        // Mutter consumes native client button events before stage signals. Sample
        // only button state while the user is active; never capture typed keys.
        // Like Shell's PointerWatcher, observation stops after one idle second.
        if (this._settings.get_boolean('click-feedback')) {
            this._lastButtons = global.get_pointer()[2];
            this._idleMonitor = global.backend.get_core_idle_monitor();
            this._idleWatchId = this._idleMonitor.add_idle_watch(1000, () => this._waitForActivity());
            if (this._idleMonitor.get_idletime() >= 1000) this._waitForActivity();
            else this._startButtonSampling();
        }
        this._updatePointer();
    }

    _startButtonSampling() {
        if (this._buttonPollId) return;
        this._sampleButtons();
        this._buttonPollId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 16, () => {
            this._sampleButtons();
            return GLib.SOURCE_CONTINUE;
        });
    }

    _waitForActivity() {
        if (this._buttonPollId) GLib.source_remove(this._buttonPollId);
        this._buttonPollId = 0;
        if (!this._userWatchId) {
            this._userWatchId = this._idleMonitor.add_user_active_watch(() => {
                this._userWatchId = 0;
                this._startButtonSampling();
            });
        }
    }

    _sampleButtons() {
        const [x, y, state] = global.get_pointer();
        const buttons = [Clutter.ModifierType.BUTTON1_MASK, Clutter.ModifierType.BUTTON2_MASK, Clutter.ModifierType.BUTTON3_MASK];
        for (let i = 0; i < buttons.length; i++) {
            if ((state & buttons[i]) && !(this._lastButtons & buttons[i])) this._pulse(x, y, i + 1);
        }
        this._lastButtons = state;
    }

    _updatePointer() {
        if (!this._halo) return;
        const [x, y] = global.get_pointer();
        if (!finitePoint(x, y)) { this._halo.hide(); return; }
        this._halo.set_position(x - this._halo.width / 2, y - this._halo.height / 2);
        this._halo.show();
        if (this._idleMonitor) this._sampleButtons();
    }

    _pulse(x, y, button) {
        if (!finitePoint(x, y)) return;
        while (this._pulses.size >= MAX_PULSES)
            this._destroyActor(this._pulses.values().next().value);
        const actor = this._makeActor(this._config, clickColor(this._config.color, button), true);
        actor.set_position(x - actor.width / 2, y - actor.height / 2);
        actor.set_pivot_point(0.5, 0.5);
        this._pulses.add(actor);
        if (this._interface.get_boolean('enable-animations') && St.Settings.get().enable_animations) {
            actor.ease({opacity: 0, scale_x: 1.65, scale_y: 1.65, duration: PULSE_MS,
                mode: Clutter.AnimationMode.EASE_OUT_QUAD, onComplete: () => this._destroyActor(actor)});
        } else {
            const id = GLib.timeout_add(GLib.PRIORITY_DEFAULT, PULSE_MS, () => {
                this._pulseTimeouts.delete(actor);
                this._destroyActor(actor);
                return GLib.SOURCE_REMOVE;
            });
            this._pulseTimeouts.set(actor, id);
        }
    }

    _destroyActor(actor) {
        if (!actor) return;
        const timeout = this._pulseTimeouts.get(actor);
        if (timeout) {
            GLib.source_remove(timeout);
            this._pulseTimeouts.delete(actor);
        }
        this._pulses.delete(actor);
        actor.remove_all_transitions();
        Main.layoutManager.removeChrome(actor);
        actor.destroy();
    }

    _clearOverlay() {
        if (this._positionId) this._tracker.disconnect(this._positionId);
        if (this._buttonPollId) GLib.source_remove(this._buttonPollId);
        if (this._idleWatchId) this._idleMonitor.remove_watch(this._idleWatchId);
        if (this._userWatchId) this._idleMonitor.remove_watch(this._userWatchId);
        this._positionId = this._buttonPollId = this._idleWatchId = this._userWatchId = 0;
        this._idleMonitor = null;
        for (const id of this._pulseTimeouts.values()) GLib.source_remove(id);
        this._pulseTimeouts.clear();
        for (const actor of [...this._pulses]) this._destroyActor(actor);
        if (this._halo) this._destroyActor(this._halo);
        this._halo = null;
    }

    disable() {
        this._clearOverlay();
        this._releaseShortcut();
        if (this._acceleratorId) global.display.disconnect(this._acceleratorId);
        if (this._settingsId) this._settings.disconnect(this._settingsId);
        this._button?.destroy();
        this._button = this._toggle = this._errorItem = null;
        this._settings = this._interface = this._tracker = null;
        this._acceleratorId = this._settingsId = 0;
    }
}
