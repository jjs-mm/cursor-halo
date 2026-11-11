// Test-only native Wayland client. Its event handler proves overlay input passes through.
import Gtk from 'gi://Gtk?version=3.0';
import Gdk from 'gi://Gdk?version=3.0';
import GLib from 'gi://GLib';

Gtk.init(null);
const window = new Gtk.Window({title: 'Cursor Halo Wayland smoke client', default_width: 640, default_height: 480});
window.add_events(Gdk.EventMask.BUTTON_PRESS_MASK);
window.connect('button-press-event', () => {
    GLib.file_set_contents(ARGV[0], 'clicked');
    return false;
});
window.add(new Gtk.Label({label: 'Cursor Halo input pass-through test'}));
window.connect('destroy', () => Gtk.main_quit());
window.show_all();
Gtk.main();
