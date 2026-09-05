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
#include "include/cef_dom.h"
#include "include/cef_process_message.h"
#include "include/cef_render_process_handler.h"

// Only field metadata crosses IPC. Never copy a field value, selection or
// password into the shell; Chromium remains the owner of the live editor.
class KeyboardContextApp : public CefApp, public CefRenderProcessHandler {
public:
    CefRefPtr<CefRenderProcessHandler> GetRenderProcessHandler() override { return this; }
    void OnFocusedNodeChanged(CefRefPtr<CefBrowser> browser,
                              CefRefPtr<CefFrame> frame,
                              CefRefPtr<CefDOMNode> node) override {
        if (!frame) return;
        auto message = CefProcessMessage::Create("mowser.keyboard_context");
        auto args = message->GetArgumentList();
        const bool editable = node && node->IsElement() && node->IsEditable() &&
            !node->HasElementAttribute("readonly") && !node->HasElementAttribute("disabled");
        args->SetBool(0, editable);
        for (int i = 1; i <= 4; ++i) args->SetString(i, "");
        if (editable) {
            auto type = node->GetElementAttribute("type");
            if (node->GetElementTagName() == "TEXTAREA") type = "multiline";
            args->SetString(1, type);
            args->SetString(2, node->GetElementAttribute("inputmode"));
            std::string label = node->GetElementAttribute("aria-label").ToString();
            if (label.empty()) label = node->GetElementAttribute("placeholder").ToString();
            args->SetString(3, label.substr(0, 160));
            args->SetString(4, node->GetElementAttribute("enterkeyhint"));
        }
        frame->SendProcessMessage(PID_BROWSER, message);
    }
private:
    IMPLEMENT_REFCOUNTING(KeyboardContextApp);
};

int main(int argc, char *argv[]) {
    CefMainArgs main_args(argc, argv);
    return CefExecuteProcess(main_args, new KeyboardContextApp(), nullptr);
}
