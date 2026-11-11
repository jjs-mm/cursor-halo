#include "core.hpp"
#include <gtk/gtk.h>
#include <glib-unix.h>
#include <gio/gdesktopappinfo.h>
#include <gdk/gdkx.h>
#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <X11/XKBlib.h>
#include <X11/extensions/XInput2.h>
#include <X11/extensions/Xfixes.h>
#include <X11/extensions/shape.h>
#include <X11/extensions/XTest.h>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <vector>
#include <unistd.h>

#ifndef CURSOR_HALO_VERSION
#define CURSOR_HALO_VERSION "0.4.0"
#endif
namespace fs = std::filesystem;
using halo::Settings;

static std::string readFile(const fs::path &path) {
    if (!fs::exists(path)) return {};
    if (fs::is_symlink(fs::symlink_status(path)) || !fs::is_regular_file(path) || fs::file_size(path) > 16384)
        throw std::runtime_error("Settings file is not a regular file or is too large.");
    std::ifstream input(path); if (!input) throw std::runtime_error("Cannot read settings file.");
    return {std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
}
static void atomicWrite(const fs::path &path, const std::string &value) {
    if (fs::is_symlink(fs::symlink_status(path))) throw std::runtime_error("Refusing to replace a symbolic link.");
    fs::create_directories(path.parent_path());
    GError *error = nullptr;
    if (!g_file_set_contents_full(path.c_str(), value.c_str(), static_cast<gssize>(value.size()),
        static_cast<GFileSetContentsFlags>(G_FILE_SET_CONTENTS_CONSISTENT | G_FILE_SET_CONTENTS_DURABLE), 0600, &error)) {
        std::string message = error->message; g_error_free(error); throw std::runtime_error(message);
    }
}
static std::string executablePath() {
    std::vector<char> buffer(4096); ssize_t length = readlink("/proc/self/exe", buffer.data(), buffer.size());
    if (length < 1 || static_cast<size_t>(length) >= buffer.size()) throw std::runtime_error("Cannot resolve the installed application path.");
    return std::string(buffer.data(), static_cast<size_t>(length));
}
class Startup {
    fs::path path;
    static bool owned(GKeyFile *file) {
        return g_key_file_get_boolean(file, "Desktop Entry", "X-CursorHalo-Owned", nullptr);
    }
    GKeyFile *load() const {
        if (fs::is_symlink(fs::symlink_status(path))) throw std::runtime_error("The login entry is a symbolic link; it was left unchanged.");
        GKeyFile *file = g_key_file_new();
        if (!fs::exists(path)) return file;
        if (!fs::is_regular_file(path) || fs::file_size(path) > 16384 || !g_key_file_load_from_file(file, path.c_str(), G_KEY_FILE_NONE, nullptr) || !owned(file)) {
            g_key_file_free(file); throw std::runtime_error("A different application owns this login entry; it was left unchanged.");
        }
        return file;
    }
public:
    explicit Startup(fs::path location) : path(std::move(location)) {}
    bool enabled() const {
        GKeyFile *file = load();
        bool enabled = owned(file) && !g_key_file_get_boolean(file, "Desktop Entry", "Hidden", nullptr);
        if (g_key_file_has_key(file, "Desktop Entry", "X-GNOME-Autostart-enabled", nullptr))
            enabled = enabled && g_key_file_get_boolean(file, "Desktop Entry", "X-GNOME-Autostart-enabled", nullptr);
        if (enabled) {
            char *type = g_key_file_get_string(file, "Desktop Entry", "Type", nullptr);
            char *command = g_key_file_get_string(file, "Desktop Entry", "Exec", nullptr);
            bool valid = type && std::string(type) == "Application" && command && std::string(command) == halo::desktopExec(executablePath());
            g_free(type); g_free(command); g_key_file_free(file);
            if (!valid) throw std::runtime_error("The login entry points to a different installation. Enable launch at login again to update it.");
        } else g_key_file_free(file);
        return enabled;
    }
    void set(bool enabled) {
        GKeyFile *file = load(); g_key_file_free(file); // Validate ownership even when disabling.
        if (!enabled) { if (fs::exists(path)) fs::remove(path); return; }
        file = g_key_file_new();
        g_key_file_set_string(file, "Desktop Entry", "Type", "Application");
        g_key_file_set_string(file, "Desktop Entry", "Name", "Cursor Halo");
        g_key_file_set_string(file, "Desktop Entry", "Comment", "Make your pointer easy to follow");
        g_key_file_set_string(file, "Desktop Entry", "Exec", halo::desktopExec(executablePath()).c_str());
        g_key_file_set_string(file, "Desktop Entry", "Icon", "input-mouse");
        g_key_file_set_boolean(file, "Desktop Entry", "Terminal", false);
        g_key_file_set_boolean(file, "Desktop Entry", "X-CursorHalo-Owned", true);
        g_key_file_set_string(file, "Desktop Entry", "X-GNOME-Autostart-enabled", "true");
        gsize length = 0; char *data = g_key_file_to_data(file, &length, nullptr);
        std::string value(data, length); g_free(data); g_key_file_free(file); atomicWrite(path, value);
    }
};

class Input {
    Display *display = nullptr;
    Window root = 0;
    int opcode = 0;
    guint source = 0;
    struct EventSource { GSource source; GPollFD poll; Input *owner; };
    bool observing = false;
    bool shortcutDown = false;
    int activeShortcut = -1;
    unsigned int numLock = 0;
    unsigned int keycode = 0, modifiers = 0;
    static inline Display *trapDisplay = nullptr;
    static inline int trappedError = 0;
    static inline XErrorHandler previousHandler = nullptr;
    static int errorHandler(Display *display, XErrorEvent *error) {
        if (display == trapDisplay) { trappedError = error->error_code; return 0; }
        return previousHandler ? previousHandler(display, error) : 0;
    }
    void beginTrap() {
        XSync(display, False); trapDisplay = display; trappedError = 0; previousHandler = XSetErrorHandler(errorHandler);
    }
    int endTrap() {
        XSync(display, False); XSetErrorHandler(previousHandler); trapDisplay = nullptr; return trappedError;
    }
    std::vector<unsigned int> locks() const {
        std::vector<unsigned int> result {0, LockMask, numLock, LockMask | numLock};
        std::sort(result.begin(), result.end()); result.erase(std::unique(result.begin(), result.end()), result.end()); return result;
    }
    void release(unsigned int code, unsigned int mods) {
        for (auto lock : locks()) XUngrabKey(display, static_cast<int>(code), mods | lock, root);
        XSync(display, False);
    }
    void drain() {
        bool moved = false;
        for (int count = 0; count < 512 && XPending(display); ++count) {
            XEvent event; XNextEvent(display, &event);
            if (event.type == KeyPress && event.xkey.keycode == keycode &&
                (event.xkey.state & ~(LockMask | numLock)) == modifiers) {
                if (!shortcutDown) { shortcutDown = true; if (onShortcut) onShortcut(); }
            } else if (event.type == KeyRelease && event.xkey.keycode == keycode) {
                bool repeat = false;
                if (XPending(display)) { XEvent next; XPeekEvent(display, &next); repeat = next.type == KeyPress && next.xkey.keycode == keycode && next.xkey.time == event.xkey.time; }
                if (!repeat) shortcutDown = false;
            } else if (event.type == GenericEvent && event.xcookie.extension == opcode && XGetEventData(display, &event.xcookie)) {
                if (observing) {
                    if (event.xcookie.evtype == XI_RawMotion) moved = true;
                    else if (event.xcookie.evtype == XI_RawButtonPress) {
                        int detail = static_cast<XIRawEvent *>(event.xcookie.data)->detail;
                        if (detail >= 1 && detail <= 3 && onButton) onButton(detail);
                    }
                }
                XFreeEventData(display, &event.xcookie);
            }
        }
        if (moved && onMotion) onMotion();
    }
public:
    std::function<void()> onMotion, onShortcut;
    std::function<void(int)> onButton;
    Input() {
        display = XOpenDisplay(nullptr); if (!display) throw std::runtime_error("Cannot connect to the X11 display.");
        root = DefaultRootWindow(display);
        Bool detectable = False; XkbSetDetectableAutoRepeat(display, True, &detectable);
        int event, error;
        if (!XQueryExtension(display, "XInputExtension", &opcode, &event, &error)) {
            XCloseDisplay(display); display = nullptr; throw std::runtime_error("XInput2 is required for global pointer observation.");
        }
        int major = 2, minor = 1;
        if (XIQueryVersion(display, &major, &minor) != Success) {
            XCloseDisplay(display); display = nullptr; throw std::runtime_error("The X server does not support XInput2.");
        }
        XModifierKeymap *map = XGetModifierMapping(display); KeyCode code = XKeysymToKeycode(display, XK_Num_Lock);
        for (int mod = 0; mod < 8; ++mod) for (int key = 0; key < map->max_keypermod; ++key)
            if (map->modifiermap[mod * map->max_keypermod + key] == code) numLock |= (1u << mod);
        XFreeModifiermap(map);
        static GSourceFuncs functions {
            +[](GSource *base, gint *timeout) -> gboolean { auto *s = reinterpret_cast<EventSource *>(base); *timeout = -1; return XPending(s->owner->display) > 0; },
            +[](GSource *base) -> gboolean { auto *s = reinterpret_cast<EventSource *>(base); return s->poll.revents != 0 || XPending(s->owner->display) > 0; },
            +[](GSource *base, GSourceFunc, gpointer) -> gboolean {
                auto *s = reinterpret_cast<EventSource *>(base);
                if (s->poll.revents & (G_IO_HUP | G_IO_ERR)) { s->owner->source = 0; return G_SOURCE_REMOVE; }
                s->owner->drain(); return G_SOURCE_CONTINUE;
            }, nullptr, nullptr, nullptr
        };
        auto *eventSource = reinterpret_cast<EventSource *>(g_source_new(&functions, sizeof(EventSource)));
        eventSource->owner = this;
        eventSource->poll = {ConnectionNumber(display), static_cast<gushort>(G_IO_IN | G_IO_HUP | G_IO_ERR), 0};
        g_source_add_poll(&eventSource->source, &eventSource->poll); source = g_source_attach(&eventSource->source, nullptr); g_source_unref(&eventSource->source);
    }
    ~Input() {
        if (source) g_source_remove(source);
        if (display) { if (activeShortcut >= 0) release(keycode, modifiers); XCloseDisplay(display); }
    }
    bool setShortcut(int choice) {
        if (choice == activeShortcut) return true;
        auto code = XKeysymToKeycode(display, choice == 1 ? XK_c : XK_h);
        unsigned int mods = ControlMask | (choice == 2 ? ShiftMask : Mod1Mask);
        if (!code) return false;
        beginTrap();
        for (auto lock : locks()) XGrabKey(display, code, mods | lock, root, False, GrabModeAsync, GrabModeAsync);
        if (endTrap()) { release(code, mods); return false; }
        if (activeShortcut >= 0) release(keycode, modifiers);
        activeShortcut = choice; keycode = code; modifiers = mods; shortcutDown = false; return true;
    }
    bool observe(bool enabled) {
        if (observing == enabled) return true;
        unsigned char mask[XIMaskLen(XI_LASTEVENT)] = {};
        if (enabled) { XISetMask(mask, XI_RawMotion); XISetMask(mask, XI_RawButtonPress); }
        XIEventMask selection {XIAllMasterDevices, static_cast<int>(sizeof(mask)), mask};
        beginTrap(); XISelectEvents(display, root, &selection, 1); int error = endTrap();
        if (!error) observing = enabled;
        return error == 0;
    }
    bool pointer(int &x, int &y) const {
        Window rootReturn, child; int wx, wy; unsigned int mask;
        return XQueryPointer(display, root, &rootReturn, &child, &x, &y, &wx, &wy, &mask);
    }
    bool isObserving() const { return observing; }
    int shortcut() const { return activeShortcut; }
    Display *connection() const { return display; }
};

struct Overlay {
    GtkWidget *window = nullptr;
    Settings settings;
    bool pulse = false;
    bool secondary = false;
    bool animate = true;
    double progress = 0;
    gint64 started = 0;
    int x = 0, y = 0;
    explicit Overlay(bool isPulse = false) : pulse(isPulse) {
        window = gtk_window_new(GTK_WINDOW_POPUP);
        gtk_window_set_title(GTK_WINDOW(window), pulse ? "Cursor Halo click" : "Cursor Halo overlay");
        gtk_window_set_decorated(GTK_WINDOW(window), false);
        gtk_window_set_accept_focus(GTK_WINDOW(window), false);
        gtk_window_set_focus_on_map(GTK_WINDOW(window), false);
        gtk_window_set_keep_above(GTK_WINDOW(window), true);
        gtk_window_set_skip_taskbar_hint(GTK_WINDOW(window), true);
        gtk_window_set_skip_pager_hint(GTK_WINDOW(window), true);
        gtk_window_set_type_hint(GTK_WINDOW(window), GDK_WINDOW_TYPE_HINT_NOTIFICATION);
        gtk_window_stick(GTK_WINDOW(window)); gtk_widget_set_app_paintable(window, true);
        auto *screen = gtk_widget_get_screen(window);
        auto *visual = gdk_screen_get_rgba_visual(screen);
        if (!visual) { gtk_widget_destroy(window); window = nullptr; throw std::runtime_error("The X11 display has no RGBA visual for transparent overlays."); }
        gtk_widget_set_visual(window, visual);
        g_signal_connect(window, "draw", G_CALLBACK((+[](GtkWidget *widget, cairo_t *cr, gpointer data) -> gboolean {
            auto *self = static_cast<Overlay *>(data);
            cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE); cairo_set_source_rgba(cr, 0, 0, 0, 0); cairo_paint(cr);
            cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
            double center = gtk_widget_get_allocated_width(widget) / 2.0;
            double radius = self->settings.diameter / 2.0;
            double alpha = self->settings.opacity;
            static constexpr double colors[5][3] {{1, .74, .13}, {.22, .9, .7}, {.23, .63, 1}, {1, .35, .67}, {1, 1, 1}};
            int color = self->secondary ? (self->settings.color == 3 ? 2 : 3) : self->settings.color;
            if (self->pulse) { if (self->animate) { radius += self->progress * 22; alpha *= 1 - self->progress; } }
            if (self->settings.style == 1 && !self->pulse) {
                cairo_arc(cr, center, center, radius, 0, 2 * G_PI);
                cairo_set_source_rgba(cr, colors[color][0], colors[color][1], colors[color][2], alpha * .2); cairo_fill(cr);
            }
            cairo_arc(cr, center, center, radius, 0, 2 * G_PI); cairo_set_line_width(cr, self->settings.stroke + 2);
            cairo_set_source_rgba(cr, .08, .08, .1, alpha * .7); cairo_stroke(cr);
            cairo_arc(cr, center, center, radius, 0, 2 * G_PI); cairo_set_line_width(cr, self->settings.stroke);
            cairo_set_source_rgba(cr, colors[color][0], colors[color][1], colors[color][2], alpha); cairo_stroke(cr);
            return true;
        })), this);
        gtk_widget_realize(window);
        auto *native = gtk_widget_get_window(window);
        cairo_region_t *empty = cairo_region_create(); gdk_window_input_shape_combine_region(native, empty, 0, 0);
        cairo_region_destroy(empty); gdk_window_set_pass_through(native, true);
    }
    ~Overlay() { if (window) gtk_widget_destroy(window); }
    void place(int px, int py, const Settings &value) {
        x = px; y = py; settings = halo::sanitize(value);
        int scale = gtk_widget_get_scale_factor(window);
        auto frame = halo::frame(px, py, settings.diameter, scale, pulse);
        gtk_window_resize(GTK_WINDOW(window), frame.side, frame.side); gtk_window_move(GTK_WINDOW(window), frame.x, frame.y);
        gtk_widget_show(window); gtk_widget_queue_draw(window);
    }
    void hide() { gtk_widget_hide(window); }
};

// GtkStatusIcon is retained deliberately for XEmbed-based X11 desktops; settings remain available without a tray.
G_GNUC_BEGIN_IGNORE_DEPRECATIONS
class App {
    GtkApplication *application = nullptr;
    fs::path preferencePath;
    Startup startup;
    bool isolated = false;
    bool updating = false;
    std::string inputError, saveError, startupError;
    GtkWidget *settingsWindow = nullptr, *status = nullptr, *enabledControl = nullptr, *styleControl = nullptr,
        *colorControl = nullptr, *diameterControl = nullptr, *opacityControl = nullptr, *strokeControl = nullptr,
        *clickControl = nullptr, *shortcutControl = nullptr, *startupControl = nullptr, *trayMenu = nullptr, *trayToggle = nullptr;
    GtkStatusIcon *tray = nullptr;
    std::unique_ptr<Input> input;
    std::unique_ptr<Overlay> haloWindow;
    std::vector<std::unique_ptr<Overlay>> pulses;
    guint animationSource = 0;
    gulong compositorSignal = 0, monitorSignal = 0;
    void showStatus() {
        std::string message;
        for (const auto &error : {inputError, startupError, saveError}) if (!error.empty()) message += (message.empty() ? "" : "\n") + error;
        if (message.empty()) message = "Ctrl+Alt+H toggles highlighting by default. Settings stay on this computer.";
        gtk_label_set_text(GTK_LABEL(status), message.c_str());
    }
    void save() {
        if (isolated) return;
        try { atomicWrite(preferencePath, halo::serialize(settings)); saveError.clear(); }
        catch (const std::exception &error) { saveError = std::string("Cannot save settings: ") + error.what(); }
        showStatus();
    }
    void clearPulses() {
        if (animationSource) { g_source_remove(animationSource); animationSource = 0; }
        pulses.clear();
    }
    void refreshRunning() {
        bool composited = gdk_screen_is_composited(gdk_screen_get_default());
        bool run = settings.enabled && composited;
        if (!composited) inputError = "Enable desktop compositing to show transparent overlays. Highlighting is paused.";
        else if (inputError.find("compositing") != std::string::npos) inputError.clear();
        if (input && !input->observe(run)) inputError = "Pointer observation failed. Pause and re-enable highlighting to retry.";
        if (run && input && input->isObserving() && haloWindow) moveHalo();
        else { if (haloWindow) haloWindow->hide(); clearPulses(); }
        showStatus();
    }
    void moveHalo() {
        int x, y; if (input && input->isObserving() && haloWindow && input->pointer(x, y)) haloWindow->place(x, y, settings);
    }
    void click(int button) {
        ++buttonEvents;
        if (!settings.enabled || !settings.clicks || !input->isObserving()) return;
        int x, y; if (!input->pointer(x, y)) return;
        auto pulse = std::make_unique<Overlay>(true); pulse->secondary = button == 3; pulse->started = g_get_monotonic_time();
        gboolean animations = true; g_object_get(gtk_settings_get_default(), "gtk-enable-animations", &animations, nullptr);
        pulse->animate = animations; pulse->place(x, y, settings);
        if (pulses.size() >= 12) pulses.erase(pulses.begin());
        pulses.push_back(std::move(pulse));
        if (!animationSource) animationSource = g_timeout_add(16, +[](gpointer data) -> gboolean {
            auto *self = static_cast<App *>(data); gint64 now = g_get_monotonic_time();
            for (auto &pulse : self->pulses) {
                pulse->progress = std::clamp((now - pulse->started) / (pulse->animate ? 420000.0 : 160000.0), 0.0, 1.0);
                if (pulse->animate) gtk_widget_queue_draw(pulse->window);
            }
            self->pulses.erase(std::remove_if(self->pulses.begin(), self->pulses.end(), [](const auto &pulse) { return pulse->progress >= 1; }), self->pulses.end());
            if (self->pulses.empty()) { self->animationSource = 0; return G_SOURCE_REMOVE; }
            return G_SOURCE_CONTINUE;
        }, this);
    }
    static GtkWidget *row(GtkWidget *box, const char *labelText, GtkWidget *control) {
        GtkWidget *row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 16);
        GtkWidget *label = gtk_label_new(labelText); gtk_label_set_xalign(GTK_LABEL(label), 0);
        gtk_box_pack_start(GTK_BOX(row), label, true, true, 0); gtk_box_pack_end(GTK_BOX(row), control, false, false, 0);
        gtk_box_pack_start(GTK_BOX(box), row, false, false, 0); return control;
    }
    GtkWidget *combo(GtkWidget *box, const char *label, std::initializer_list<const char *> choices) {
        GtkWidget *control = gtk_combo_box_text_new();
        for (const auto *choice : choices) gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(control), choice);
        row(box, label, control); g_signal_connect(control, "changed", G_CALLBACK(+[](GtkWidget *, gpointer data) { static_cast<App *>(data)->changed(); }), this); return control;
    }
    GtkWidget *spin(GtkWidget *box, const char *label, double low, double high, double step) {
        GtkWidget *control = gtk_spin_button_new_with_range(low, high, step); row(box, label, control);
        g_signal_connect(control, "value-changed", G_CALLBACK(+[](GtkWidget *, gpointer data) { static_cast<App *>(data)->changed(); }), this); return control;
    }
    void changed() {
        if (updating) return;
        Settings next = settings;
        next.enabled = gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(enabledControl));
        next.style = gtk_combo_box_get_active(GTK_COMBO_BOX(styleControl)); next.color = gtk_combo_box_get_active(GTK_COMBO_BOX(colorControl));
        next.diameter = gtk_spin_button_get_value(GTK_SPIN_BUTTON(diameterControl));
        next.opacity = gtk_spin_button_get_value(GTK_SPIN_BUTTON(opacityControl)) / 100.0;
        next.stroke = gtk_spin_button_get_value(GTK_SPIN_BUTTON(strokeControl)); next.clicks = gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(clickControl));
        next.shortcut = gtk_combo_box_get_active(GTK_COMBO_BOX(shortcutControl)); next = halo::sanitize(next);
        if (next.shortcut != settings.shortcut || (input && input->shortcut() < 0)) {
            if (!input || !input->setShortcut(next.shortcut)) {
                next.shortcut = settings.shortcut; inputError = "That shortcut is already in use. The previous shortcut remains active; choose another combination.";
            } else inputError.clear();
        }
        settings = next; updateControls(); refreshRunning(); save();
    }
    void updateControls() {
        updating = true;
        gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(enabledControl), settings.enabled);
        gtk_combo_box_set_active(GTK_COMBO_BOX(styleControl), settings.style); gtk_combo_box_set_active(GTK_COMBO_BOX(colorControl), settings.color);
        gtk_spin_button_set_value(GTK_SPIN_BUTTON(diameterControl), settings.diameter);
        gtk_spin_button_set_value(GTK_SPIN_BUTTON(opacityControl), settings.opacity * 100); gtk_spin_button_set_value(GTK_SPIN_BUTTON(strokeControl), settings.stroke);
        gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(clickControl), settings.clicks); gtk_combo_box_set_active(GTK_COMBO_BOX(shortcutControl), settings.shortcut);
        if (trayToggle) gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(trayToggle), settings.enabled);
        updating = false;
    }
    void refreshStartup() {
        updating = true;
        try {
            gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(startupControl), isolated ? false : startup.enabled()); startupError.clear();
        } catch (const std::exception &error) {
            gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(startupControl), false); startupError = error.what();
        }
        updating = false; showStatus();
    }
    void buildSettings() {
        settingsWindow = gtk_window_new(GTK_WINDOW_TOPLEVEL); gtk_window_set_title(GTK_WINDOW(settingsWindow), "Cursor Halo");
        gtk_window_set_default_size(GTK_WINDOW(settingsWindow), 440, 650); gtk_window_set_resizable(GTK_WINDOW(settingsWindow), true);
        gtk_window_set_icon_name(GTK_WINDOW(settingsWindow), "input-mouse");
        if (application) gtk_application_add_window(application, GTK_WINDOW(settingsWindow));
        g_signal_connect(settingsWindow, "delete-event", G_CALLBACK(+[](GtkWidget *widget, GdkEvent *, gpointer data) -> gboolean {
            auto *self = static_cast<App *>(data);
            if (self->tray && gtk_status_icon_is_embedded(self->tray)) gtk_widget_hide(widget); else self->quit();
            return true;
        }), this);
        auto *scroll = gtk_scrolled_window_new(nullptr, nullptr); gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll), GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
        gtk_container_add(GTK_CONTAINER(settingsWindow), scroll);
        auto *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 14); gtk_container_set_border_width(GTK_CONTAINER(box), 22); gtk_container_add(GTK_CONTAINER(scroll), box);
        auto *heading = gtk_label_new(nullptr); gtk_label_set_markup(GTK_LABEL(heading), "<b><big>Cursor Halo</big></b>"); gtk_label_set_xalign(GTK_LABEL(heading), 0);
        gtk_box_pack_start(GTK_BOX(box), heading, false, false, 0);
        auto *description = gtk_label_new("Make your pointer easy to follow."); gtk_label_set_xalign(GTK_LABEL(description), 0); gtk_box_pack_start(GTK_BOX(box), description, false, false, 0);
        enabledControl = gtk_check_button_new_with_label("Highlight pointer"); gtk_box_pack_start(GTK_BOX(box), enabledControl, false, false, 0);
        g_signal_connect(enabledControl, "toggled", G_CALLBACK(+[](GtkWidget *, gpointer data) { static_cast<App *>(data)->changed(); }), this);
        styleControl = combo(box, "Style", {"Ring", "Soft disc"}); colorControl = combo(box, "Color", {"Amber", "Mint", "Blue", "Pink", "White"});
        diameterControl = spin(box, "Diameter", 28, 120, 2); opacityControl = spin(box, "Opacity (%)", 20, 100, 5); strokeControl = spin(box, "Stroke width", 1, 8, 1);
        clickControl = gtk_check_button_new_with_label("Show click feedback"); gtk_box_pack_start(GTK_BOX(box), clickControl, false, false, 0);
        g_signal_connect(clickControl, "toggled", G_CALLBACK(+[](GtkWidget *, gpointer data) { static_cast<App *>(data)->changed(); }), this);
        shortcutControl = combo(box, "Toggle shortcut", {"Ctrl + Alt + H", "Ctrl + Alt + C", "Ctrl + Shift + H"});
        startupControl = gtk_check_button_new_with_label("Launch at login"); gtk_box_pack_start(GTK_BOX(box), startupControl, false, false, 0);
        g_signal_connect(startupControl, "toggled", G_CALLBACK(+[](GtkWidget *widget, gpointer data) {
            auto *self = static_cast<App *>(data); if (self->updating || self->isolated) return;
            try { self->startup.set(gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(widget))); self->refreshStartup(); }
            catch (const std::exception &error) {
                std::string message = std::string("Cannot change launch at login: ") + error.what(); self->refreshStartup(); self->startupError = message; self->showStatus();
            }
        }), this);
        status = gtk_label_new(""); gtk_label_set_line_wrap(GTK_LABEL(status), true); gtk_label_set_xalign(GTK_LABEL(status), 0);
        gtk_label_set_max_width_chars(GTK_LABEL(status), 45); gtk_box_pack_start(GTK_BOX(box), status, false, false, 0);
        auto *buttons = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8); gtk_box_pack_start(GTK_BOX(box), buttons, false, false, 4);
        auto *reset = gtk_button_new_with_label("Reset appearance"); gtk_box_pack_start(GTK_BOX(buttons), reset, true, true, 0);
        g_signal_connect(reset, "clicked", G_CALLBACK(+[](GtkWidget *, gpointer data) {
            auto *self = static_cast<App *>(data); Settings next; next.enabled = self->settings.enabled; next.shortcut = self->settings.shortcut;
            self->settings = next; self->updateControls(); self->refreshRunning(); self->save();
        }), this);
        auto *quitButton = gtk_button_new_with_label("Quit"); gtk_box_pack_end(GTK_BOX(buttons), quitButton, false, false, 0);
        g_signal_connect(quitButton, "clicked", G_CALLBACK(+[](GtkWidget *, gpointer data) { static_cast<App *>(data)->quit(); }), this);
        auto *version = gtk_label_new("Version " CURSOR_HALO_VERSION " · Linux X11 · MIT license"); gtk_box_pack_end(GTK_BOX(box), version, false, false, 0);
        updateControls(); refreshStartup();
    }
    void buildTray() {
        trayMenu = gtk_menu_new(); trayToggle = gtk_check_menu_item_new_with_label("Highlight pointer"); gtk_menu_shell_append(GTK_MENU_SHELL(trayMenu), trayToggle);
        g_signal_connect(trayToggle, "toggled", G_CALLBACK(+[](GtkCheckMenuItem *item, gpointer data) {
            auto *self = static_cast<App *>(data); if (self->updating) return;
            self->settings.enabled = gtk_check_menu_item_get_active(item); self->updateControls(); self->refreshRunning(); self->save();
        }), this);
        auto *settingsItem = gtk_menu_item_new_with_label("Settings…"); gtk_menu_shell_append(GTK_MENU_SHELL(trayMenu), settingsItem);
        g_signal_connect(settingsItem, "activate", G_CALLBACK(+[](GtkMenuItem *, gpointer data) { static_cast<App *>(data)->showSettings(); }), this);
        auto *quitItem = gtk_menu_item_new_with_label("Quit"); gtk_menu_shell_append(GTK_MENU_SHELL(trayMenu), quitItem);
        g_signal_connect(quitItem, "activate", G_CALLBACK(+[](GtkMenuItem *, gpointer data) { static_cast<App *>(data)->quit(); }), this); gtk_widget_show_all(trayMenu);
        tray = gtk_status_icon_new_from_icon_name("input-mouse"); gtk_status_icon_set_title(tray, "Cursor Halo"); gtk_status_icon_set_tooltip_text(tray, "Cursor Halo — pointer highlighting");
        g_signal_connect(tray, "activate", G_CALLBACK(+[](GtkStatusIcon *, gpointer data) { static_cast<App *>(data)->showSettings(); }), this);
        g_signal_connect(tray, "popup-menu", G_CALLBACK(+[](GtkStatusIcon *icon, guint button, guint time, gpointer data) {
            auto *self = static_cast<App *>(data); gtk_menu_popup(GTK_MENU(self->trayMenu), nullptr, nullptr, gtk_status_icon_position_menu, icon, button, time);
        }), this);
        g_signal_connect(tray, "notify::embedded", G_CALLBACK(+[](GObject *, GParamSpec *, gpointer data) {
            auto *self = static_cast<App *>(data); if (!gtk_status_icon_is_embedded(self->tray)) self->showSettings();
        }), this); updateControls();
    }
public:
    Settings settings;
    uint64_t motionEvents = 0, buttonEvents = 0, shortcutEvents = 0;
    App(GtkApplication *app, bool test = false) : application(app), preferencePath(fs::path(g_get_user_config_dir()) / "cursor-halo/settings.conf"),
        startup(fs::path(g_get_user_config_dir()) / "autostart/io.github.jjs_mm.CursorHalo.desktop"), isolated(test) {
        if (!isolated) try { settings = halo::parse(readFile(preferencePath)); } catch (const std::exception &error) { saveError = error.what(); }
        buildSettings();
        try {
            input = std::make_unique<Input>(); haloWindow = std::make_unique<Overlay>();
            input->onMotion = [this] { ++motionEvents; moveHalo(); }; input->onButton = [this](int button) { click(button); };
            input->onShortcut = [this] { ++shortcutEvents; toggle(); };
            if (!input->setShortcut(settings.shortcut)) inputError = "The toggle shortcut is already in use. Choose another combination.";
        } catch (const std::exception &error) { inputError = error.what(); }
        auto *screen = gdk_screen_get_default();
        compositorSignal = g_signal_connect(screen, "composited-changed", G_CALLBACK(+[](GdkScreen *, gpointer data) { static_cast<App *>(data)->refreshRunning(); }), this);
        monitorSignal = g_signal_connect(screen, "monitors-changed", G_CALLBACK(+[](GdkScreen *, gpointer data) { static_cast<App *>(data)->moveHalo(); }), this);
        if (!isolated) buildTray();
        refreshRunning();
    }
    ~App() {
        clearPulses(); input.reset(); haloWindow.reset();
        auto *screen = gdk_screen_get_default(); if (compositorSignal) g_signal_handler_disconnect(screen, compositorSignal); if (monitorSignal) g_signal_handler_disconnect(screen, monitorSignal);
        if (tray) { g_signal_handlers_disconnect_by_data(tray, this); gtk_status_icon_set_visible(tray, false); g_object_unref(tray); }
        if (trayMenu) gtk_widget_destroy(trayMenu);
        if (settingsWindow) gtk_widget_destroy(settingsWindow);
    }
    void showSettings() { refreshStartup(); gtk_widget_show_all(settingsWindow); gtk_window_present(GTK_WINDOW(settingsWindow)); }
    void start(bool background) { if (!background || !tray || !gtk_status_icon_is_embedded(tray)) showSettings(); }
    void quit() { if (application) g_application_quit(G_APPLICATION(application)); }
    void toggle() { settings.enabled = !settings.enabled; updateControls(); refreshRunning(); save(); }
    void pause() { settings.enabled = false; updateControls(); refreshRunning(); }
    GtkWidget *window() const { return settingsWindow; }
    Overlay *overlay() const { return haloWindow.get(); }
    Input *eventSource() const { return input.get(); }
    size_t pulseCount() const { return pulses.size(); }
    bool animating() const { return animationSource != 0; }
};

G_GNUC_END_IGNORE_DEPRECATIONS

static void pump(int milliseconds = 100) {
    gint64 until = g_get_monotonic_time() + milliseconds * 1000;
    while (g_get_monotonic_time() < until) { while (g_main_context_iteration(nullptr, false)) {} g_usleep(1000); }
}
static void require(bool condition, const char *message) { if (!condition) throw std::runtime_error(message); }
static int smoke(const fs::path &output) {
    std::vector<std::string> checks;
    std::string failure;
    try {
        require(gdk_screen_is_composited(gdk_screen_get_default()), "Smoke test requires an X11 compositor.");
        Display *display = GDK_DISPLAY_XDISPLAY(gdk_display_get_default());
        int eventBase, errorBase, major, minor;
        require(XTestQueryExtension(display, &eventBase, &errorBase, &major, &minor), "XTest is required for native smoke input.");
        auto key = [&](KeySym symbol, bool press) { XTestFakeKeyEvent(display, XKeysymToKeycode(display, symbol), press, CurrentTime); };
        auto shortcut = [&] { key(XK_Control_L, true); key(XK_Alt_L, true); key(XK_h, true); key(XK_h, false); key(XK_Alt_L, false); key(XK_Control_L, false); XFlush(display); pump(); };
        {
            App app(nullptr, true);
            require(app.eventSource() && app.overlay() && app.eventSource()->isObserving(), "Native event source and overlay must initialize.");
            app.showSettings(); pump(); require(gtk_widget_get_visible(app.window()), "Settings window must render.");
            if (!output.empty()) {
                fs::create_directories(output.parent_path().empty() ? "." : output.parent_path());
                auto *native = gtk_widget_get_window(app.window());
                GdkPixbuf *capture = gdk_pixbuf_get_from_window(native, 0, 0, gdk_window_get_width(native), gdk_window_get_height(native));
                require(capture != nullptr, "Rendered settings must be capturable.");
                fs::path screenshot = output.parent_path() / "settings.png";
                bool saved = gdk_pixbuf_save(capture, screenshot.c_str(), "png", nullptr, nullptr); g_object_unref(capture);
                require(saved, "Rendered settings screenshot must save.");
            }
            gtk_widget_hide(app.window()); pump(); checks.push_back("Native settings rendered with isolated state");
            GtkWidget *target = gtk_window_new(GTK_WINDOW_TOPLEVEL); gtk_window_set_default_size(GTK_WINDOW(target), 600, 400);
            gtk_window_move(GTK_WINDOW(target), 100, 100); gtk_widget_add_events(target, GDK_BUTTON_PRESS_MASK);
            int targetClicks = 0;
            g_signal_connect(target, "button-press-event", G_CALLBACK(+[](GtkWidget *, GdkEventButton *, gpointer data) -> gboolean { ++*static_cast<int *>(data); return true; }), &targetClicks);
            gtk_widget_show_all(target); gtk_window_present(GTK_WINDOW(target)); pump(150);
            Window focusBefore; int revert; XGetInputFocus(display, &focusBefore, &revert);
            int originX, originY; gdk_window_get_origin(gtk_widget_get_window(target), &originX, &originY);
            int scale = gtk_widget_get_scale_factor(target); int px = (originX + 150) * scale, py = (originY + 150) * scale;
            XTestFakeMotionEvent(display, -1, px, py, CurrentTime); XFlush(display); pump();
            require(app.motionEvents > 0, "XInput2 must receive actual simulated pointer movement.");
            Window focusAfter; XGetInputFocus(display, &focusAfter, &revert);
            require(focusBefore == focusAfter, "Overlay must not steal keyboard focus.");
            require(!gtk_window_get_accept_focus(GTK_WINDOW(app.overlay()->window)), "Overlay must not accept focus.");
            int rectangleCount = -1, ordering = 0;
            XRectangle *rectangles = XShapeGetRectangles(display, GDK_WINDOW_XID(gtk_widget_get_window(app.overlay()->window)), ShapeInput, &rectangleCount, &ordering);
            if (rectangles) XFree(rectangles);
            require(rectangleCount == 0, "Overlay input region must be empty.");
            checks.push_back("XInput2 movement drives a transparent non-focusing overlay with empty input region");
            XTestFakeButtonEvent(display, 1, true, CurrentTime); XTestFakeButtonEvent(display, 1, false, CurrentTime); XFlush(display); pump(80);
            require(targetClicks == 1 && app.buttonEvents >= 1 && app.pulseCount() >= 1, "Clicks must pass through the halo while generating feedback.");
            checks.push_back("Pointer clicks reach the underlying window and create bounded feedback");
            pump(500); require(app.pulseCount() == 0 && !app.animating(), "Animation timer must stop after feedback expires.");
            checks.push_back("Click feedback expires and leaves no idle animation timer");
            {
                Input competitor; require(competitor.setShortcut(1), "Competing shortcut should register.");
                require(!app.eventSource()->setShortcut(1) && app.eventSource()->shortcut() == 0, "A shortcut conflict must preserve the active shortcut.");
                shortcut(); require(!app.settings.enabled && app.shortcutEvents == 1 && !app.eventSource()->isObserving(), "Original hotkey must pause highlighting and pointer observation after conflict.");
                require(!gtk_widget_get_visible(app.overlay()->window), "Paused halo must be hidden.");
                shortcut(); require(app.settings.enabled && app.shortcutEvents == 2, "Global hotkey must resume highlighting.");
            }
            checks.push_back("Global shortcut conflict preserves the working key; pause removes observation");
            app.pause(); gtk_widget_destroy(target); pump();
        }
        {
            Input next; require(next.setShortcut(0), "Quit must release the hotkey for another instance.");
        }
        checks.push_back("Disposal releases native hotkey and observation resources");
        GError *error = nullptr; char *directory = g_dir_make_tmp("cursor-halo-smoke-XXXXXX", &error);
        require(directory != nullptr, "Cannot create isolated startup test directory."); fs::path temporary(directory); g_free(directory);
        try {
            fs::path entry = temporary / "autostart/io.github.jjs_mm.CursorHalo.desktop"; Startup startup(entry);
            require(!startup.enabled(), "Startup must be off by default."); startup.set(true); require(startup.enabled(), "Startup registration must be readable.");
            atomicWrite(entry, readFile(entry) + "X-GNOME-Autostart-enabled=false\n");
            require(!startup.enabled(), "Desktop startup manager disablement must be reflected.");
            startup.set(true);
            atomicWrite(entry, readFile(entry) + "Exec=/bin/true\n");
            bool stale = false; try { startup.enabled(); } catch (...) { stale = true; }
            require(stale, "Startup pointing to a different installation must be reported.");
            startup.set(false); require(!fs::exists(entry), "Disabling startup removes only the owned file.");
            atomicWrite(entry, "[Desktop Entry]\nType=Application\nName=Another app\nExec=/bin/true\n");
            bool rejected = false; try { startup.set(false); } catch (...) { rejected = true; }
            require(rejected && fs::exists(entry), "Foreign startup entries must be preserved.");
            checks.push_back("Startup opt-in, manager disablement, stale paths and foreign-entry preservation use temporary files");
            fs::path script = temporary / "space \\\"$%` runner";
            atomicWrite(script, "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$0.result\"\n"); fs::permissions(script, fs::perms::owner_all);
            GKeyFile *file = g_key_file_new();
            g_key_file_set_string(file, "Desktop Entry", "Type", "Application"); g_key_file_set_string(file, "Desktop Entry", "Name", "Cursor Halo smoke");
            g_key_file_set_string(file, "Desktop Entry", "Exec", halo::desktopExec(script.string()).c_str());
            gsize length; char *serialized = g_key_file_to_data(file, &length, nullptr);
            GKeyFile *parsed = g_key_file_new(); require(g_key_file_load_from_data(parsed, serialized, length, G_KEY_FILE_NONE, nullptr), "Desktop entry must parse.");
            g_free(serialized); g_key_file_free(file);
            GDesktopAppInfo *info = g_desktop_app_info_new_from_keyfile(parsed); g_key_file_free(parsed);
            require(info != nullptr, "Escaped executable must parse through GDesktopAppInfo.");
            bool launched = g_app_info_launch(G_APP_INFO(info), nullptr, nullptr, &error); g_object_unref(info);
            require(launched, "Escaped executable must launch through desktop APIs.");
            pump(200); require(readFile(script.string() + ".result") == "--background\n", "Spaces, percent and shell punctuation must round-trip without command injection.");
            checks.push_back("Desktop Exec escaping round-trips unusual paths through real GIO launch");
            fs::path settings = temporary / "preferences/settings.conf";
            atomicWrite(settings, halo::serialize(Settings{})); require(halo::serialize(halo::parse(readFile(settings))) == halo::serialize(Settings{}), "Preferences must persist atomically.");
            fs::remove(settings); fs::create_symlink(script, settings); rejected = false;
            try { atomicWrite(settings, "unsafe"); } catch (...) { rejected = true; }
            require(rejected && readFile(script).find("#!/bin/sh") == 0, "Preference writes must not overwrite symlink targets.");
            checks.push_back("Atomic preference persistence rejects symbolic-link replacement");
        } catch (...) { fs::remove_all(temporary); throw; }
        fs::remove_all(temporary);
    } catch (const std::exception &error) { failure = error.what(); }
    auto quote = [](const std::string &text) { std::string value = "\""; for (char c : text) { if (c == '"' || c == '\\') value += '\\'; if (c == '\n') value += "\\n"; else value += c; } return value + '"'; };
    std::ostringstream json; json << "{\n  \"success\": " << (failure.empty() ? "true" : "false") << ",\n  \"version\": \"" CURSOR_HALO_VERSION "\",\n  \"checks\": [";
    for (size_t i = 0; i < checks.size(); ++i) json << (i ? ", " : "") << quote(checks[i]);
    json << "],\n  \"error\": " << quote(failure) << "\n}\n";
    if (!output.empty()) { fs::create_directories(output.parent_path().empty() ? "." : output.parent_path()); std::ofstream stream(output); stream << json.str(); }
    std::cout << json.str(); return failure.empty() ? 0 : 1;
}

int main(int argc, char **argv) {
    bool background = false; fs::path smokeOutput; bool testing = false;
    for (int i = 1; i < argc; ++i) {
        std::string argument(argv[i]);
        if (argument == "--version") { std::cout << "Cursor Halo " CURSOR_HALO_VERSION "\n"; return 0; }
        if (argument == "--background") background = true;
        else if (argument == "--smoke-test") { testing = true; if (i + 1 < argc) smokeOutput = argv[++i]; }
        else if (argument == "--help") { std::cout << "Cursor Halo " CURSOR_HALO_VERSION "\nUsage: cursor-halo [--background | --version | --help]\nLinux X11 desktop with compositing required. Native Wayland is not supported by this build.\n"; return 0; }
        else { std::cerr << "Unknown argument: " << argument << '\n'; return 2; }
    }
    const char *session = g_getenv("XDG_SESSION_TYPE"), *wayland = g_getenv("WAYLAND_DISPLAY");
    if ((session && std::string(session) == "wayland") || (wayland && *wayland)) {
        const char *message = "This Cursor Halo build requires an X11 desktop session with compositing. It cannot highlight native Wayland applications through XWayland. For GNOME Wayland, use the Cursor Halo GNOME extension; see docs/linux.md in the download or repository. Other Wayland desktops are not supported by this build.";
        std::cerr << message << '\n';
        if (!testing && gtk_init_check(nullptr, nullptr)) {
            auto *dialog = gtk_message_dialog_new(nullptr, GTK_DIALOG_MODAL, GTK_MESSAGE_INFO, GTK_BUTTONS_CLOSE, "%s", message);
            gtk_window_set_title(GTK_WINDOW(dialog), "Cursor Halo — unsupported session"); gtk_dialog_run(GTK_DIALOG(dialog)); gtk_widget_destroy(dialog);
        }
        return 2;
    }
    g_setenv("GDK_BACKEND", "x11", true);
    if (!gtk_init_check(nullptr, nullptr)) { std::cerr << "Cannot open an X11 desktop display. Cursor Halo needs a graphical X11 session.\n"; return 2; }
    if (testing) return smoke(smokeOutput);
    GtkApplication *application = gtk_application_new("io.github.jjs_mm.CursorHalo", G_APPLICATION_DEFAULT_FLAGS);
    struct State { std::unique_ptr<App> app; bool background; } state {nullptr, background};
    g_signal_connect(application, "activate", G_CALLBACK(+[](GtkApplication *application, gpointer data) {
        auto *state = static_cast<State *>(data);
        if (state->app) { state->app->showSettings(); return; }
        state->app = std::make_unique<App>(application); g_application_hold(G_APPLICATION(application)); state->app->start(state->background);
    }), &state);
    // GtkApplication's D-Bus identity hands a second launch to the existing settings window.
    char *applicationArgv[] {argv[0], nullptr}; int result = g_application_run(G_APPLICATION(application), 1, applicationArgv);
    state.app.reset(); g_object_unref(application); return result;
}
