#pragma once
#include <algorithm>
#include <cmath>
#include <iomanip>
#include <map>
#include <locale>
#include <stdexcept>
#include <sstream>
#include <string>
#include <vector>

namespace halo {
struct Settings {
    bool enabled = true;
    int style = 0;
    int color = 0;
    double diameter = 56;
    double opacity = .85;
    double stroke = 3;
    bool clicks = true;
    int shortcut = 0;
};
inline double finiteClamp(double value, double low, double high, double fallback) {
    return std::isfinite(value) ? std::clamp(value, low, high) : fallback;
}
inline Settings sanitize(Settings s) {
    s.style = s.style >= 0 && s.style < 2 ? s.style : 0;
    s.color = s.color >= 0 && s.color < 5 ? s.color : 0;
    s.shortcut = s.shortcut >= 0 && s.shortcut < 3 ? s.shortcut : 0;
    s.diameter = finiteClamp(s.diameter, 28, 120, 56);
    s.opacity = finiteClamp(s.opacity, .2, 1, .85);
    s.stroke = finiteClamp(s.stroke, 1, 8, 3);
    return s;
}
inline double number(const std::string &text, double fallback) {
    if (text.empty() || text.find_first_of(" \t\r\n") != std::string::npos) return fallback;
    std::istringstream input(text); input.imbue(std::locale::classic());
    double value = 0; input >> std::noskipws >> value;
    return input && input.peek() == std::char_traits<char>::eof() && std::isfinite(value) ? value : fallback;
}
inline int option(const std::string &text, const std::vector<std::string> &values) {
    auto it = std::find(values.begin(), values.end(), text);
    return it == values.end() ? 0 : static_cast<int>(it - values.begin());
}
inline const std::vector<std::string> styles {"ring", "disc"};
inline const std::vector<std::string> colors {"amber", "mint", "blue", "pink", "white"};
inline const std::vector<std::string> shortcuts {"ctrl-alt-h", "ctrl-alt-c", "ctrl-shift-h"};
inline Settings parse(const std::string &text) {
    Settings s;
    if (text.size() > 16384 || text.find('\0') != std::string::npos) return s;
    std::map<std::string, std::string> items;
    std::istringstream input(text); std::string line;
    while (std::getline(input, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        auto separator = line.find('=');
        if (separator != std::string::npos) items[line.substr(0, separator)] = line.substr(separator + 1);
    }
    auto boolean = [&](const char *key, bool fallback) {
        auto it = items.find(key); return it == items.end() ? fallback : it->second == "true" ? true : it->second == "false" ? false : fallback;
    };
    s.enabled = boolean("enabled", true); s.clicks = boolean("clicks", true);
    s.style = option(items["style"], styles); s.color = option(items["color"], colors);
    s.shortcut = option(items["shortcut"], shortcuts);
    s.diameter = number(items["diameter"], 56); s.opacity = number(items["opacity"], .85); s.stroke = number(items["stroke"], 3);
    return sanitize(s);
}
inline std::string serialize(Settings s) {
    s = sanitize(s); std::ostringstream out; out.imbue(std::locale::classic());
    out << std::setprecision(8) << "enabled=" << (s.enabled ? "true" : "false")
        << "\nstyle=" << styles[s.style] << "\ncolor=" << colors[s.color]
        << "\ndiameter=" << s.diameter << "\nopacity=" << s.opacity << "\nstroke=" << s.stroke
        << "\nclicks=" << (s.clicks ? "true" : "false") << "\nshortcut=" << shortcuts[s.shortcut] << '\n';
    return out.str();
}
inline std::string desktopExec(const std::string &path) {
    if (path.empty() || path.front() != '/' || path.find_first_of("\r\n=") != std::string::npos || path.find('\0') != std::string::npos)
        throw std::runtime_error("The application path cannot be represented safely in a login entry. Move it to a simple local path.");
    std::string result = "/usr/bin/env -- \"";
    for (char c : path) {
        if (c == '%' ) result += '%';
        if (c == '\\' || c == '"' || c == '`' || c == '$') result += '\\';
        result += c;
    }
    return result + "\" --background";
}
struct Frame { int x, y, side; };
inline Frame frame(int x, int y, double diameter, int scale, bool pulse = false) {
    scale = std::clamp(scale, 1, 8);
    int side = static_cast<int>(std::ceil(finiteClamp(diameter, 28, 120, 56) * (pulse ? 2 : 1) + 20));
    return {static_cast<int>(std::floor(static_cast<double>(x) / scale)) - side / 2,
            static_cast<int>(std::floor(static_cast<double>(y) / scale)) - side / 2, side};
}
} // namespace halo
