#include "mowser_client.h"

#include <cstdio>

namespace mowser {

void Client::GetViewRect(CefRefPtr<CefBrowser> browser, CefRect &rect) {
    int width = 0;
    int height = 0;
    if (sink_ != nullptr) {
        sink_->sink_view_size(width, height);
    }
    // NEVER ZERO. CEF treats an empty view rect as a programming error and
    // stops painting the browser entirely -- permanently, not until the next
    // resize -- and a Control legitimately reports zero size for a frame or
    // two between being added to the tree and being laid out. Falling back to
    // the design surface means the first paint may be the wrong size, which
    // the next OnPaint corrects; the alternative is a page that never draws
    // and no error anywhere explaining why.
    rect.x = 0;
    rect.y = 0;
    rect.width = width > 0 ? width : 1920;
    rect.height = height > 0 ? height : 1080;
}

void Client::OnPaint(CefRefPtr<CefBrowser> browser, PaintElementType type,
                     const RectList &dirtyRects, const void *buffer, int width,
                     int height) {
    // PET_POPUP is the little surface a <select> dropdown draws into, composited
    // by the embedder on top of the page. Ignored deliberately for now: this
    // renders as a select that appears not to open, which is honest and narrow,
    // and the alternative -- compositing it wrongly -- puts a menu at the wrong
    // place on the screen. It is the first thing to add when a real form needs
    // it; see the header for where it would go.
    if (type != PET_VIEW || sink_ == nullptr) {
        return;
    }
    (void)dirtyRects;  // The whole buffer arrives every time; see sink_paint.
    // SAID ONCE, and it is the single most useful line in this file when
    // something is wrong. "The page is blank" has two completely different
    // causes -- the engine never painted, or it painted and the texture never
    // reached the screen -- and they are indistinguishable from a screenshot.
    // One line at the boundary tells them apart.
    if (!painted_once_) {
        painted_once_ = true;
        std::fprintf(stderr, "<6>mowser: first paint %dx%d\n", width, height);
    }
    sink_->sink_paint(buffer, width, height);
}

void Client::OnAfterCreated(CefRefPtr<CefBrowser> browser) {
    // Held so the view can reach the host for navigation and input. This is
    // the only reference the browser process keeps to the page besides CEF's
    // own, which is why OnBeforeClose has to clear it.
    browser_ = browser;
    std::fprintf(stderr, "<6>mowser: browser created\n");
    if (sink_ != nullptr) {
        sink_->sink_browser_ready();
    }
}

void Client::OnBeforeClose(CefRefPtr<CefBrowser> browser) { browser_ = nullptr; }

bool Client::OnBeforePopup(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                           int popup_id, const CefString &target_url,
                           const CefString &target_frame_name,
                           WindowOpenDisposition target_disposition, bool user_gesture,
                           const CefPopupFeatures &popupFeatures, CefWindowInfo &windowInfo,
                           CefRefPtr<CefClient> &client, CefBrowserSettings &settings,
                           CefRefPtr<CefDictionaryValue> &extra_info,
                           bool *no_javascript_access) {
    // A NEW WINDOW IS NOT A THING THAT EXISTS HERE. Rather than drop the
    // navigation on the floor -- which is what cancelling alone would do, and
    // reads as a dead link on a checkout -- the target is loaded in THIS page.
    // A store's "open in new tab" therefore behaves like a normal link, which
    // is the only behaviour a single-surface machine can offer honestly.
    if (sink_ != nullptr && !target_url.empty() && browser && browser->GetMainFrame()) {
        browser->GetMainFrame()->LoadURL(target_url);
    }
    return true;  // true CANCELS the popup
}

void Client::OnLoadStart(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                         TransitionType transition_type) {
    // MAIN FRAME ONLY, here and in every handler below. A modern store page is
    // dozens of iframes -- adverts, video embeds, payment widgets -- and each
    // one starting and finishing would have the shell's status line flickering
    // through a dozen "loading" states for one navigation a person made.
    if (!frame->IsMain() || sink_ == nullptr) {
        return;
    }
    sink_->sink_load_started(frame->GetURL().ToString());
}

void Client::OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                       int httpStatusCode) {
    if (!frame->IsMain() || sink_ == nullptr) {
        return;
    }
    sink_->sink_load_finished(frame->GetURL().ToString(), httpStatusCode);
}

void Client::OnLoadError(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                         ErrorCode errorCode, const CefString &errorText,
                         const CefString &failedUrl) {
    if (!frame->IsMain() || sink_ == nullptr) {
        return;
    }
    // ERR_ABORTED is what a navigation that was replaced by another one
    // reports, which happens on every redirect and every time somebody presses
    // back quickly. It is not a failure and must not put an error on the TV.
    if (errorCode == ERR_ABORTED) {
        return;
    }
    std::string reason = errorText.ToString();
    if (reason.empty()) {
        reason = "the page could not be loaded";
    }
    sink_->sink_load_failed(failedUrl.ToString(), reason);
}

void Client::OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString &title) {
    if (sink_ != nullptr) {
        sink_->sink_title(title.ToString());
    }
}

void Client::OnAddressChange(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                             const CefString &url) {
    if (!frame->IsMain() || sink_ == nullptr) {
        return;
    }
    sink_->sink_url(url.ToString());
}

bool Client::OnProcessMessageReceived(CefRefPtr<CefBrowser> browser,
    CefRefPtr<CefFrame> frame, CefProcessId source_process,
    CefRefPtr<CefProcessMessage> message) {
    if (source_process != PID_RENDERER || message->GetName() != "mowser.keyboard_context")
        return false;
    auto args = message->GetArgumentList();
    if (sink_ && args->GetSize() == 5) {
        sink_->sink_keyboard_context(args->GetBool(0), args->GetString(1).ToString(),
            args->GetString(2).ToString(), args->GetString(3).ToString(),
            args->GetString(4).ToString());
    }
    return true;
}

}  // namespace mowser
