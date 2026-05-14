// Tiny exec stub that replaces the symlink-to-/bin/zsh inside each
// "<BUNDLE_NAME_PREFIX> <Cmd>.app" bundle. The symlink approach broke the
// Login Items icon: macOS resolves the symlink to /bin/zsh before looking
// up the icon, so it never sees the enclosing bundle and falls back to the
// generic "exec" icon. A real Mach-O binary inside Contents/MacOS keeps
// Launch Services anchored to the bundle, so CFBundleIconFile / icon.icns
// is used.
//
// Behavior matches the symlink: launchd invokes us with our binary as
// argv[0] and the rest of the launchd ProgramArguments after; we rewrite
// argv[0] to "/bin/zsh" and execv into zsh, which then runs the wrapper
// script that was passed as argv[1].
#include <unistd.h>

int main(int argc, char **argv) {
    (void)argc;
    argv[0] = "/bin/zsh";
    execv("/bin/zsh", argv);
    return 127;
}
