// SPDX-License-Identifier: MIT
import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk';
import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

export default class CursorHaloPreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();
        window.set_default_size(560, 650);
        const page = new Adw.PreferencesPage({title: 'Cursor Halo', icon_name: 'find-location-symbolic'});
        const appearance = new Adw.PreferencesGroup({title: 'Appearance'});
        const controls = new Adw.PreferencesGroup({title: 'Controls'});
        page.add(appearance);
        page.add(controls);
        window.add(page);

        const toggle = (group, key, title) => {
            const row = new Adw.SwitchRow({title});
            settings.bind(key, row, 'active', Gio.SettingsBindFlags.DEFAULT);
            group.add(row);
        };
        const choice = (group, key, title, options) => {
            const row = new Adw.ComboRow({title, model: Gtk.StringList.new(options)});
            settings.bind(key, row, 'selected', Gio.SettingsBindFlags.DEFAULT);
            group.add(row);
        };
        const number = (key, title, min, max) => {
            const row = new Adw.SpinRow({title,
                adjustment: new Gtk.Adjustment({lower: min, upper: max, step_increment: 1, page_increment: 5})});
            settings.bind(key, row, 'value', Gio.SettingsBindFlags.DEFAULT);
            appearance.add(row);
        };
        toggle(appearance, 'enabled', 'Highlight pointer');
        choice(appearance, 'style', 'Style', ['Ring', 'Soft disc']);
        choice(appearance, 'color', 'Color', ['Amber', 'Mint', 'Blue', 'Pink', 'White']);
        number('diameter', 'Diameter (logical pixels)', 28, 120);
        number('opacity', 'Opacity (%)', 20, 100);
        number('stroke', 'Outline width', 1, 8);
        toggle(controls, 'click-feedback', 'Click feedback');
        choice(controls, 'shortcut', 'Toggle shortcut', ['Ctrl + Alt + H', 'Ctrl + Alt + C', 'Ctrl + Shift + H']);
        const status = new Adw.ActionRow({title: 'Shortcut status'});
        const updateStatus = () => {
            const error = settings.get_string('shortcut-error');
            status.subtitle = error || 'Available while Cursor Halo is enabled in Extensions.';
        };
        const id = settings.connect('changed::shortcut-error', updateStatus);
        window.connect('close-request', () => { settings.disconnect(id); return false; });
        updateStatus();
        controls.add(status);
        controls.add(new Adw.ActionRow({title: 'Launch at login',
            subtitle: 'GNOME loads enabled extensions at login. Use the Extensions app to enable or disable Cursor Halo.'}));
        const reset = new Gtk.Button({label: 'Reset appearance', halign: Gtk.Align.END, margin_top: 12});
        reset.connect('clicked', () => {
            for (const key of ['style', 'color', 'diameter', 'opacity', 'stroke', 'click-feedback']) settings.reset(key);
        });
        appearance.add(reset);
    }
}
