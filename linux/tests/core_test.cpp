#include "../src/core.hpp"
#include <cstdlib>
static int checks = 0;
#define CHECK(condition) do { ++checks; if (!(condition)) { std::cerr << "FAILED: " #condition << " at line " << __LINE__ << "\n"; std::exit(1); } } while (false)
#include <iostream>
#include <limits>
int main() {
    auto defaults = halo::parse("");
    CHECK(defaults.enabled && defaults.clicks && defaults.diameter == 56 && defaults.opacity == .85);
    auto s = halo::parse("diameter=900\nopacity=-4\nstroke=nan\nenabled=FALSE\nclicks=false\nstyle=triangle\ncolor=pink\nshortcut=ctrl-shift-h\n");
    CHECK(s.diameter == 120 && s.opacity == .2 && s.stroke == 3 && s.enabled && !s.clicks && s.style == 0 && s.color == 3 && s.shortcut == 2);
    s = halo::parse("diameter=56oops\nopacity=inf\nstroke= 4\n");
    CHECK(s.diameter == 56 && s.opacity == .85 && s.stroke == 3);
    s.diameter = std::numeric_limits<double>::quiet_NaN(); s.style = -1; s.color = 99;
    auto safe = halo::sanitize(s); CHECK(safe.diameter == 56 && safe.style == 0 && safe.color == 0);
    s = halo::parse("enabled=false\nstyle=disc\ncolor=mint\ndiameter=72.5\nopacity=0.7\nstroke=7\nclicks=false\nshortcut=ctrl-alt-c\n");
    CHECK(halo::serialize(halo::parse(halo::serialize(s))) == halo::serialize(s));
    CHECK(halo::parse(std::string(16385, 'x')).enabled);
    CHECK(halo::parse(std::string("enabled=false\0", 14)).enabled);
    auto f = halo::frame(-15, 43, 56, 2); CHECK(f.x == -46 && f.y == -17 && f.side == 76);
    f = halo::frame(0, 0, std::numeric_limits<double>::infinity(), 0, true); CHECK(f.side == 132);
    CHECK(halo::desktopExec("/home/a b/100%/a\"b$`") == "/usr/bin/env -- \"/home/a b/100%%/a\\\"b\\$\\`\" --background");
    struct Comma : std::numpunct<char> { char do_decimal_point() const override { return ','; } };
    auto previous = std::locale::global(std::locale(std::locale::classic(), new Comma));
    CHECK(halo::parse("opacity=0.7\ndiameter=72.5\n").opacity == .7);
    CHECK(halo::serialize(halo::parse("opacity=0.7\n")).find("opacity=0.7") != std::string::npos);
    std::locale::global(previous);
    bool invalid = false; try { halo::desktopExec("/tmp/bad\npath"); } catch (...) { invalid = true; }
    CHECK(invalid);
    std::cout << checks << " core behavior checks passed\n";
}
