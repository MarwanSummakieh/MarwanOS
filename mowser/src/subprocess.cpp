// mowser-helper -- every Chromium process that is not the browser process.
//
// THIS FILE IS SHORT AND IT IS NOT OPTIONAL. Chromium is multi-process: the
// renderer that runs a page's JavaScript, the GPU process, and the utility
// processes are separate programs, and CEF starts them by executing a binary
// with a --type= argument. Ordinarily that binary is the application itself,
// which requires CefExecuteProcess to be the FIRST thing main() does -- before
// any library has initialised anything, because a renderer process must not
// inherit a half-built browser.
//
// The shell's main() belongs to Godot. So this exists instead: a binary whose
// entire job is to be re-executed by CEF, named to CefSettings::
// browser_subprocess_path. It links libcef and NOTHING ELSE -- no godot-cpp,
// no shell code -- both because it needs none of it and because everything
// linked here is loaded into every renderer Chromium spawns.
//
// It must never print. Its stdout and stderr belong to Chromium's own IPC and
// logging, and a stray line here surfaces as a corrupt message on a channel
// somebody else is parsing.

#include "include/cef_app.h"

int main(int argc, char *argv[]) {
    CefMainArgs main_args(argc, argv);
    // A null CefApp: the switches that matter were set by the browser process
    // and arrive on this process's command line already. Returning whatever
    // CefExecuteProcess returns is the contract -- it is the process's exit
    // code, and CEF reads it.
    return CefExecuteProcess(main_args, nullptr, nullptr);
}
