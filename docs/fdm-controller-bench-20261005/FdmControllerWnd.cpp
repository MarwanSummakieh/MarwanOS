#include "stdafx.h"
#include "FdmApp.h"
#include "MainFrm.h"
#include "DownloadsWnd.h"
#include "FdmControllerWnd.h"
#include "FdmControllerInput.h"
#include <Xinput.h>
#include <algorithm>
#include <memory>
#include <cmath>

namespace {
const COLORREF BG=RGB(20,24,23), SURFACE=RGB(32,39,36), LINE=RGB(61,72,65);
const COLORREF INK=RGB(240,244,240), MUTED=RGB(175,187,178), ACCENT=RGB(188,219,199);
enum Page { Queue, Details, TorrentBrowser, FolderBrowser, Keyboard, Review };
enum Command { SelectDownload=1, Toggle, ShowDetails, AddTorrent, AddLink,
    FilterAll, FilterActive, FilterComplete, PreviousPage, NextPage, GoBack, EnterFolder,
    ChooseTorrent, Drives, UseFolder, ChangeFolder, StartNew, AddPaused, TypeKey,
    EraseKey, PasteKey, ShiftKey, FinishText, OpenFolder, FilePriority, ToggleSeeding, UpFolder };
struct Item { CString text,argument; CRect rect; int command; UINT download; };
struct Entry { CString name,path; bool folder; };
CString sizeText(UINT64 value) {
    CString s; double v=double(value); const TCHAR*unit=_T("B");
    if(v>=1073741824){v/=1073741824;unit=_T("GB");}
    else if(v>=1048576){v/=1048576;unit=_T("MB");}
    else if(v>=1024){v/=1024;unit=_T("KB");}
    s.Format(v>=100?_T("%.0f %s"):_T("%.1f %s"),v,unit);return s;
}
CString leaf(CString s){s.TrimRight(_T("\\/"));int p=max(s.ReverseFind('\\'),s.ReverseFind('/'));return s.Mid(p+1);}
CString parent(CString s){s.TrimRight(_T("\\/"));int p=max(s.ReverseFind('\\'),s.ReverseFind('/'));return p<0?CString():s.Left(p+1);}
CString downloadName(vmsDownloadSmartPtr d){if(d->pMgr->IsBittorrent())return CString(d->pMgr->GetBtDownloadMgr()->get_TorrentName());return leaf(CString(d->pMgr->get_OutputFilePathName()));}
CString statusText(vmsDownloadSmartPtr d){
    if(d->pMgr->IsBittorrent()){
        auto b=d->pMgr->GetBtDownloadMgr();
        if(b->isSeeding())return _T("Seeding");
        if(b->get_State()==BTDSE_DOWNLOADING_METADATA)return _T("Fetching metadata");
        if(b->get_State()==BTDSE_CHECKING_FILES||b->get_State()==BTDSE_CHECKING_RESUME_DATA)return _T("Checking files");
    }
    if(d->pMgr->IsDone())return _T("Complete");
    if(d->pMgr->IsRunning())return _T("Downloading");
    return d->bAutoStart?_T("Queued"):_T("Paused");
}
bool running(vmsDownloadSmartPtr d){return d->pMgr->IsRunning()||(d->pMgr->IsBittorrent()&&d->pMgr->GetBtDownloadMgr()->isSeeding());}

class ControllerWindow : public CWnd {
    CWnd*m_legacy;
    Page m_page=Queue;
    std::vector<Item> m_items;
    std::vector<std::unique_ptr<CButton>> m_buttons;
    DLDS_LIST m_downloads;
    std::vector<Entry> m_entries;
    int m_focus=0,m_offset=0,m_filter=0,m_filesOffset=0;
    UINT m_selected=UINT_MAX;
    CString m_folder,m_output,m_pending,m_edit,m_notice;
    DWORD m_noticeUntil=0;
    bool m_upper=false,m_fullscreen=false,m_oldDialog=false;
    double m_scale=1; int m_ox=0,m_oy=0;
    CFont m_title,m_body,m_small;
    HMODULE m_xinput=nullptr;
    typedef DWORD(WINAPI*GetState)(DWORD,XINPUT_STATE*);
    GetState m_getState=nullptr;
    fdm_controller::Input m_input;
    int m_pad=-1; bool m_padConnected=false;
    CRect m_normalRect;
    CString m_lastScene;
    bool m_layoutDirty=true;
public:
    ControllerWindow(CWnd*w):m_legacy(w){
        m_oldDialog=_App.DownloadDialog_Use();
        TCHAR home[MAX_PATH]={0};SHGetFolderPath(NULL,CSIDL_PROFILE,NULL,0,home);
        m_output=CString(home)+_T("\\Downloads\\");m_folder=m_output;
        TCHAR downloads[MY_MAX_PATH]={0};
        if(GetEnvironmentVariable(_T("FDM_DOWNLOAD_DIR"),downloads,MY_MAX_PATH)){m_output=downloads;m_folder=m_output;}
        if(GetEnvironmentVariable(_T("FDM_LOCAL_TEST"),NULL,0)){
            m_folder=((CFdmApp*)AfxGetApp())->m_strAppPath+_T("..\\torrent-test\\");
            m_output=m_folder+_T("controller-download\\");
        }
        TCHAR system[MAX_PATH];GetSystemDirectory(system,MAX_PATH);
        m_xinput=LoadLibrary(CString(system)+_T("\\xinput1_4.dll"));
        if(!m_xinput)m_xinput=LoadLibrary(CString(system)+_T("\\xinput9_1_0.dll"));
        if(m_xinput)m_getState=(GetState)GetProcAddress(m_xinput,"XInputGetState");
    }
    ~ControllerWindow(){_App.DownloadDialog_Use(m_oldDialog);if(m_xinput)FreeLibrary(m_xinput);}
    bool Open(){
        CString cls=AfxRegisterWndClass(CS_HREDRAW|CS_VREDRAW,LoadCursor(NULL,IDC_ARROW),NULL,AfxGetApp()->LoadIcon(IDR_MAINFRAME));
        if(!CreateEx(0,cls,_T("Free Download Manager - Controller"),WS_OVERLAPPEDWINDOW|WS_CLIPCHILDREN,CRect(0,0,1280,800),NULL,0))return false;
        m_oldDialog=_App.DownloadDialog_Use();_App.DownloadDialog_Use(FALSE);
        if(_App.View_FloatingWindow())m_legacy->SendMessage(WM_COMMAND,ID_DROPBOX);
        if(_App.View_FloatingInfoWindow())m_legacy->SendMessage(WM_COMMAND,ID_DLINFOBOX);
        SetTimer(1,33,NULL);SetTimer(2,500,NULL);
        Resize();Refresh();m_legacy->ShowWindow(SW_HIDE);ShowWindow(SW_SHOWMAXIMIZED);SetForegroundWindow();Focus(0);return true;
    }
    void ShowAgain(){_App.DownloadDialog_Use(FALSE);m_legacy->ShowWindow(SW_HIDE);ShowWindow(SW_SHOWMAXIMIZED);SetForegroundWindow();Refresh();Focus(m_focus);}
    BOOL PreTranslateMessage(MSG*msg) override {
        if(msg->message==WM_SYSKEYDOWN&&msg->wParam==VK_F10)return TRUE;
        if(msg->message==WM_KEYDOWN){
            UINT k=UINT(msg->wParam);
            if(k==VK_F11){Fullscreen();return TRUE;}
            if(k==VK_F10)return TRUE;
            if(k==VK_ESCAPE){Back();return TRUE;}
            if(k==VK_RETURN){Activate();return TRUE;}
            if(k==VK_TAB){Focus((m_focus+((GetKeyState(VK_SHIFT)&0x8000)?-1:1)+int(m_items.size()))%max(1,int(m_items.size())));return TRUE;}
            if(k>=VK_LEFT&&k<=VK_DOWN){Move(k);return TRUE;}
            if(k==VK_F5){Browse(TorrentBrowser);return TRUE;}
            if(k==VK_F6){NewLink();return TRUE;}
            if(k==VK_PRIOR||k==VK_NEXT){if(m_page==Queue)Filter((m_filter+(k==VK_NEXT?1:2))%3);else PageBy(k==VK_NEXT?1:-1);return TRUE;}
            if(m_page==Keyboard&&k==VK_BACK){if(!m_edit.IsEmpty())m_edit.Delete(m_edit.GetLength()-1);Refresh();return TRUE;}
            if(m_page==Keyboard&&k=='V'&&(GetKeyState(VK_CONTROL)&0x8000)){Paste();return TRUE;}
        }
        if(msg->message==WM_CHAR&&m_page==Keyboard){TCHAR c=TCHAR(msg->wParam);if(c>=32&&c!=127&&m_edit.GetLength()<8192){m_edit+=c;Refresh();}return TRUE;}
        return CWnd::PreTranslateMessage(msg);
    }
protected:
    DECLARE_MESSAGE_MAP()
    afx_msg void OnPaint(){
        CPaintDC screen(this);CRect r;GetClientRect(r);CDC dc;dc.CreateCompatibleDC(&screen);CBitmap bitmap;bitmap.CreateCompatibleBitmap(&screen,r.Width(),r.Height());auto old=dc.SelectObject(&bitmap);
        dc.FillSolidRect(r,BG);dc.SetBkMode(TRANSPARENT);
        Text(dc,_T("Free Download Manager"),40,20,800,35,m_small,MUTED);
        CString title=m_page==Queue?_T("Downloads"):m_page==Details?_T("Download"):m_page==TorrentBrowser?_T("Add torrent"):m_page==FolderBrowser?_T("Save folder"):m_page==Keyboard?_T("Add link"):_T("Add download");
        Text(dc,title,40,57,970,50,m_title,INK);
        Text(dc,m_padConnected?_T("Controller connected"):_T("Keyboard / controller"),960,28,280,36,m_small,MUTED,DT_RIGHT);
        if(m_page==Queue){
            auto d=Selected();if(d){
                Text(dc,downloadName(d),850,229,390,82,m_body,INK,DT_WORDBREAK);
                CString progress;progress.Format(_T("%.0f%%"),max(0.0f,min(100.0f,d->pMgr->GetPercentDone())));
                Text(dc,progress,850,325,390,58,m_title,INK);
                CRect bar=Px(CRect(850,398,1240,406));dc.FillSolidRect(bar,LINE);bar.right=bar.left+int(bar.Width()*max(0.0f,min(100.0f,d->pMgr->GetPercentDone()))/100);dc.FillSolidRect(bar,ACCENT);
                Text(dc,statusText(d),850,426,390,35,m_body,INK);
                Text(dc,sizeText(d->pMgr->GetDownloadedBytesCount())+_T(" of ")+sizeText(d->pMgr->GetLDFileSize()),850,467,390,35,m_small,MUTED);
                Text(dc,sizeText(d->pMgr->GetSpeed())+_T("/s down"),850,509,390,35,m_small,MUTED);
            }else {Text(dc,_T("No downloads"),60,287,700,55,m_body,INK);}
        }else if(m_page==TorrentBrowser||m_page==FolderBrowser){Text(dc,m_folder.IsEmpty()?_T("This PC"):m_folder,40,119,1200,48,m_small,MUTED,DT_END_ELLIPSIS);if(m_entries.empty())Text(dc,m_page==TorrentBrowser?_T("No torrent files in this folder"):_T("No subfolders"),40,290,1150,48,m_body,MUTED);}
        else if(m_page==Keyboard){
            dc.FillSolidRect(Px(CRect(40,124,1240,240)),SURFACE);
            Text(dc,m_edit.IsEmpty()?_T("Magnet link or download URL"):m_edit.Right(180),60,143,1160,82,m_body,m_edit.IsEmpty()?MUTED:INK,DT_WORDBREAK);
        }else if(m_page==Review){
            Text(dc,_T("Source"),40,141,1150,32,m_small,MUTED);Text(dc,m_pending,40,183,1200,150,m_body,INK,DT_WORDBREAK);
            Text(dc,_T("Save to"),40,349,1150,32,m_small,MUTED);Text(dc,m_output,40,395,1150,72,m_body,INK,DT_WORDBREAK);
        }else if(m_page==Details){auto d=Selected();if(d){Text(dc,downloadName(d),40,119,1200,54,m_body,INK);Text(dc,statusText(d)+_T("  /  ")+sizeText(d->pMgr->GetDownloadedBytesCount()),40,177,1200,34,m_small,MUTED);Text(dc,CString(d->pMgr->get_OutputPath()),40,222,1200,40,m_small,MUTED);}}
        if(GetTickCount()<m_noticeUntil)Text(dc,m_notice,40,688,1200,40,m_small,ACCENT);
        dc.FillSolidRect(Px(CRect(40,740,1240,741)),LINE);
        CString hints=m_page==Keyboard?_T("A Select    B Back    X Backspace    Y Paste    LB/RB Shift"):(m_page==TorrentBrowser||m_page==FolderBrowser||m_page==Details)?_T("D-pad / stick Navigate    A Select    B Back    LB/RB Page"):_T("D-pad / stick Navigate    A Select    B Back    X Torrent    Y Link    LB/RB Filter");
        Text(dc,hints,40,756,1200,34,m_small,MUTED);
        screen.BitBlt(0,0,r.Width(),r.Height(),&dc,0,0,SRCCOPY);dc.SelectObject(old);
    }
    afx_msg BOOL OnEraseBkgnd(CDC*){return TRUE;}
    afx_msg void OnSize(UINT,int,int){if(GetSafeHwnd()){Resize();Refresh();}}
    afx_msg void OnGetMinMaxInfo(MINMAXINFO*i){i->ptMinTrackSize=CPoint(960,660);CWnd::OnGetMinMaxInfo(i);}
    afx_msg void OnClose(){m_legacy->PostMessage(WM_CLOSE);}
    afx_msg void OnTimer(UINT_PTR id){
        if(!IsWindowVisible())return;
        if(id==2){Refresh();return;}
        XINPUT_STATE state={0};int pad=m_pad;
        if(!m_getState)return;
        if(pad<0||m_getState(pad,&state)!=ERROR_SUCCESS){pad=-1;for(DWORD i=0;i<4;i++)if(m_getState(i,&state)==ERROR_SUCCESS){pad=int(i);break;}}
        if(pad!=m_pad){m_input=fdm_controller::Input();m_pad=pad;}m_padConnected=pad>=0;
        fdm_controller::Sample s;WORD b=state.Gamepad.wButtons;
        using namespace fdm_controller;
        if(b&XINPUT_GAMEPAD_A)s.buttons|=A;if(b&XINPUT_GAMEPAD_B)s.buttons|=B;if(b&XINPUT_GAMEPAD_X)s.buttons|=X;if(b&XINPUT_GAMEPAD_Y)s.buttons|=Y;
        if(b&XINPUT_GAMEPAD_LEFT_SHOULDER)s.buttons|=LB;if(b&XINPUT_GAMEPAD_RIGHT_SHOULDER)s.buttons|=RB;if(b&XINPUT_GAMEPAD_START)s.buttons|=Menu;
        if(b&XINPUT_GAMEPAD_DPAD_UP)s.buttons|=DUp;if(b&XINPUT_GAMEPAD_DPAD_DOWN)s.buttons|=DDown;if(b&XINPUT_GAMEPAD_DPAD_LEFT)s.buttons|=DLeft;if(b&XINPUT_GAMEPAD_DPAD_RIGHT)s.buttons|=DRight;
        s.x=state.Gamepad.sThumbLX;s.y=state.Gamepad.sThumbLY;
        auto actions=m_input.Update(s,m_padConnected,::GetForegroundWindow()==m_hWnd,GetTickCount());
        for(auto a:actions){if(a==Up)Move(VK_UP);else if(a==Down)Move(VK_DOWN);else if(a==Left)Move(VK_LEFT);else if(a==Right)Move(VK_RIGHT);else if(a==Accept)Activate();else if(a==fdm_controller::Back)Back();
            else if(m_page==Keyboard){if(a==Torrent)Erase();else if(a==Link)Paste();else if(a==PreviousFilter||a==NextFilter){m_upper=!m_upper;Refresh();}}
            else if(a==Torrent)Browse(TorrentBrowser);else if(a==Link)NewLink();else if(a==PreviousFilter){if(m_page==Queue)Filter((m_filter+2)%3);else PageBy(-1);}else if(a==NextFilter){if(m_page==Queue)Filter((m_filter+1)%3);else PageBy(1);}}
    }
    afx_msg void OnDrawItem(int id,LPDRAWITEMSTRUCT d){
        int index=id-10000;if(index<0||index>=int(m_items.size()))return;
        CDC target;target.Attach(d->hDC);CRect r(d->rcItem);CDC dc;dc.CreateCompatibleDC(&target);CBitmap bitmap;bitmap.CreateCompatibleBitmap(&target,r.Width(),r.Height());auto oldBitmap=dc.SelectObject(&bitmap);bool focus=index==m_focus;dc.FillSolidRect(r,focus?ACCENT:SURFACE);dc.SetBkMode(TRANSPARENT);COLORREF ink=focus?BG:INK;
        if(focus){dc.Draw3dRect(r,INK,INK);CRect inner=r;inner.DeflateRect(2,2);dc.Draw3dRect(inner,ACCENT,ACCENT);}
        CString label=m_items[index].text;int split=label.Find('\n');CRect text=r;text.DeflateRect(int(18*m_scale),int(9*m_scale));
        auto old=dc.SelectObject(&m_body);dc.SetTextColor(ink);
        if(split>=0){CRect top=text;top.bottom=top.top+int(34*m_scale);dc.DrawText(label.Left(split),top,DT_SINGLELINE|DT_END_ELLIPSIS|DT_VCENTER|DT_NOPREFIX);dc.SelectObject(&m_small);text.top+=int(35*m_scale);dc.SetTextColor(focus?BG:MUTED);dc.DrawText(label.Mid(split+1),text,DT_SINGLELINE|DT_END_ELLIPSIS|DT_VCENTER|DT_NOPREFIX);}
        else dc.DrawText(label,text,DT_SINGLELINE|DT_END_ELLIPSIS|DT_VCENTER|DT_CENTER|DT_NOPREFIX);
        dc.SelectObject(old);target.BitBlt(r.left,r.top,r.Width(),r.Height(),&dc,0,0,SRCCOPY);dc.SelectObject(oldBitmap);target.Detach();
    }
    BOOL OnCommand(WPARAM w,LPARAM) override {if(HIWORD(w)==BN_CLICKED&&LOWORD(w)>=10000&&LOWORD(w)<10000+m_items.size()){Focus(LOWORD(w)-10000);Activate();return TRUE;}return FALSE;}
private:
    CRect Px(CRect r){return CRect(m_ox+int(r.left*m_scale),m_oy+int(r.top*m_scale),m_ox+int(r.right*m_scale),m_oy+int(r.bottom*m_scale));}
    void Text(CDC&dc,CString s,int x,int y,int w,int h,CFont&font,COLORREF c,UINT flags=DT_SINGLELINE|DT_END_ELLIPSIS){auto old=dc.SelectObject(&font);dc.SetTextColor(c);CRect r=Px(CRect(x,y,x+w,y+h));dc.DrawText(s,r,flags|DT_NOPREFIX);dc.SelectObject(old);}
    void Resize(){CRect r;GetClientRect(r);m_scale=min(r.Width()/1280.0,r.Height()/800.0);m_ox=int((r.Width()-1280*m_scale)/2);m_oy=int((r.Height()-800*m_scale)/2);m_title.DeleteObject();m_body.DeleteObject();m_small.DeleteObject();m_title.CreateFont(-int(40*m_scale),0,0,0,FW_SEMIBOLD,FALSE,FALSE,0,DEFAULT_CHARSET,0,0,CLEARTYPE_QUALITY,0,_T("Arial"));m_body.CreateFont(-int(25*m_scale),0,0,0,FW_NORMAL,FALSE,FALSE,0,DEFAULT_CHARSET,0,0,CLEARTYPE_QUALITY,0,_T("Arial"));m_small.CreateFont(-int(19*m_scale),0,0,0,FW_NORMAL,FALSE,FALSE,0,DEFAULT_CHARSET,0,0,CLEARTYPE_QUALITY,0,_T("Arial"));m_layoutDirty=true;m_lastScene.Empty();}
    void Add(CString label,int x,int y,int w,int h,int command,CString arg=_T(""),UINT id=UINT_MAX){Item i;i.text=label;i.rect=CRect(x,y,x+w,y+h);i.command=command;i.argument=arg;i.download=id;m_items.push_back(i);}
    vmsDownloadSmartPtr Selected(){return m_selected==UINT_MAX?vmsDownloadSmartPtr():_DldsMgr.GetDownloadByID(m_selected);}
    void Refresh(){
        if(!GetSafeHwnd())return;
        m_items.clear();
        if(m_page==Queue){
            Add(_T("Add torrent"),40,123,245,60,AddTorrent);Add(_T("Add link"),301,123,245,60,AddLink);
            Add(m_filter==0?_T("All  [selected]"):_T("All"),40,194,240,52,FilterAll);Add(m_filter==1?_T("Active  [selected]"):_T("Active"),295,194,240,52,FilterActive);Add(m_filter==2?_T("Complete  [selected]"):_T("Complete"),550,194,240,52,FilterComplete);
            DLDS_LIST all;_DldsMgr.LockList(true);for(size_t i=0;i<_DldsMgr.GetCount();i++)all.push_back(_DldsMgr.GetDownload(i));_DldsMgr.UnlockList(true);
            m_downloads.clear();for(auto d:all)if(m_filter==0||(m_filter==1&&!d->pMgr->IsDone())||(m_filter==2&&d->pMgr->IsDone()))m_downloads.push_back(d);
            if(m_selected==UINT_MAX&&!m_downloads.empty())m_selected=m_downloads[0]->nID;
            m_offset=max(0,min(m_offset,max(0,int(m_downloads.size())-4)));
            for(int i=m_offset;i<min(m_offset+4,int(m_downloads.size()));i++){auto d=m_downloads[i];CString stats;stats.Format(_T("%s   %.0f%%   %s/s"),(LPCTSTR)statusText(d),max(0.0f,min(100.0f,d->pMgr->GetPercentDone())),(LPCTSTR)sizeText(d->pMgr->GetSpeed()));Add(downloadName(d)+_T("\n")+stats,40,268+(i-m_offset)*94,750,82,SelectDownload,_T(""),d->nID);}
            if(m_downloads.size()>4){Add(_T("Previous page"),40,653,365,50,PreviousPage);Add(_T("Next page"),425,653,365,50,NextPage);}
            auto d=Selected();if(d){Add(running(d)?_T("Pause download"):d->pMgr->IsDone()?_T("Open folder"):_T("Resume download"),850,563,390,60,Toggle);Add(_T("Files and details"),850,637,390,60,ShowDetails);}
        }else if(m_page==TorrentBrowser||m_page==FolderBrowser){
            Add(_T("Up one folder"),40,177,230,58,UpFolder);Add(_T("This PC"),287,177,180,58,Drives);Add(_T("Back"),484,177,180,58,GoBack);if(m_page==FolderBrowser&&!m_folder.IsEmpty())Add(_T("Use this folder"),850,177,390,58,UseFolder);
            m_offset=max(0,min(m_offset,max(0,int(m_entries.size())-4)));
            for(int i=m_offset;i<min(m_offset+4,int(m_entries.size()));i++){auto&e=m_entries[i];Add((e.folder?_T("Folder   "):_T("Torrent   "))+e.name,40,257+(i-m_offset)*86,1200,72,e.folder?EnterFolder:ChooseTorrent,e.path);}
            if(m_entries.size()>4){Add(_T("Previous page"),40,616,580,56,PreviousPage);Add(_T("Next page"),660,616,580,56,NextPage);}
        }else if(m_page==Keyboard){
            CString chars=m_upper?_T("1234567890QWERTYUIOPASDFGHJKL:ZXCVBNM./?&=_%+-@#[]"):_T("1234567890qwertyuiopasdfghjkl:zxcvbnm./?&=_%+-@#[]");
            for(int i=0;i<chars.GetLength();i++){CString c(chars.Mid(i,1));Add(c,40+(i%10)*121,260+(i/10)*70,109,58,TypeKey,c);}
            Add(_T("Shift"),40,621,225,56,ShiftKey);Add(_T("Backspace"),281,621,225,56,EraseKey);Add(_T("Paste"),522,621,225,56,PasteKey);Add(_T("Next"),763,621,225,56,FinishText);Add(_T("Back"),1004,621,236,56,GoBack);
        }else if(m_page==Review){Add(_T("Change folder"),40,494,400,62,ChangeFolder);Add(_T("Start download"),40,590,385,70,StartNew);Add(_T("Add paused"),447,590,385,70,AddPaused);Add(_T("Back"),854,590,386,70,GoBack);}
        else if(m_page==Details){auto d=Selected();if(!d){m_page=Queue;Refresh();return;}
            Add(running(d)?_T("Pause"):(d->pMgr->IsDone()?_T("Open folder"):_T("Resume")),40,281,260,60,Toggle);Add(_T("Open folder"),318,281,260,60,OpenFolder);Add(_T("Back"),980,281,260,60,GoBack);
            if(d->pMgr->IsBittorrent()){
                auto b=d->pMgr->GetBtDownloadMgr();Add(b->isSeedingEnabled()?_T("Seeding on"):_T("Seeding off"),597,281,360,60,ToggleSeeding);
                int count=b->get_FileCount();m_filesOffset=max(0,min(m_filesOffset,max(0,count-3)));
                for(int i=m_filesOffset;i<min(m_filesOffset+3,count);i++){CString info;info.Format(_T("%s   %s   %d%%"),b->getFilePriority(i)>0?_T("Included"):_T("Skipped"),(LPCTSTR)sizeText(b->get_FileSize(i)),b->get_FilePercentDone(i));CString index;index.Format(_T("%d"),i);Add(CString(b->get_FileName(i))+_T("\n")+info,40,367+(i-m_filesOffset)*94,1200,82,FilePriority,index);}
                if(count>3){Add(_T("Previous files"),40,653,580,50,PreviousPage);Add(_T("Next files"),660,653,580,50,NextPage);}
            }
        }
        while(m_buttons.size()>m_items.size()){m_buttons.back()->DestroyWindow();m_buttons.pop_back();}
        while(m_buttons.size()<m_items.size()){auto b=std::make_unique<CButton>();b->Create(_T(""),WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_OWNERDRAW,CRect(),this,10000+UINT(m_buttons.size()));m_buttons.push_back(std::move(b));}
        m_focus=max(0,min(m_focus,int(m_items.size())-1));
        CString scene;scene.Format(_T("%d|%u|%d|"),int(m_page),m_selected,int(m_padConnected));scene+=m_edit+_T("|")+m_pending+_T("|")+m_output+_T("|")+m_folder;
        if(GetTickCount()<m_noticeUntil)scene+=m_notice;
        auto selected=Selected();if(selected){CString stats;stats.Format(_T("|%.3f|%I64u|%I64u|%u|"),double(selected->pMgr->GetPercentDone()),selected->pMgr->GetDownloadedBytesCount(),selected->pMgr->GetLDFileSize(),selected->pMgr->GetSpeed());scene+=stats+statusText(selected);}
        for(size_t i=0;i<m_items.size();i++){
            CString old,label=m_items[i].text;label.Replace(_T("&"),_T("&&"));m_buttons[i]->GetWindowText(old);bool changed=old!=label||m_layoutDirty;
            if(old!=label)m_buttons[i]->SetWindowText(label);
            CRect current;m_buttons[i]->GetWindowRect(current);ScreenToClient(current);CRect desired=Px(m_items[i].rect);
            if(current!=desired){m_buttons[i]->MoveWindow(desired,FALSE);changed=true;}
            if(m_layoutDirty||!m_buttons[i]->GetFont()||m_buttons[i]->GetFont()->GetSafeHandle()!=m_body.GetSafeHandle())m_buttons[i]->SetFont(&m_body,FALSE);
            if(changed)m_buttons[i]->Invalidate(FALSE);
            scene+=_T("|")+m_items[i].text;
        }
        if(scene!=m_lastScene||m_layoutDirty){Invalidate(FALSE);m_lastScene=scene;}m_layoutDirty=false;
    }
    void Focus(int i){if(m_items.empty())return;int previous=m_focus;m_focus=max(0,min(i,int(m_items.size())-1));if(m_items[m_focus].command==SelectDownload){m_selected=m_items[m_focus].download;Invalidate(FALSE);}m_buttons[m_focus]->SetFocus();if(previous>=0&&previous<int(m_buttons.size()))m_buttons[previous]->Invalidate(FALSE);m_buttons[m_focus]->Invalidate(FALSE);}
    void Move(UINT k){if(m_items.empty())return;CPoint c=m_items[m_focus].rect.CenterPoint();double best=1e20;int dest=-1;for(size_t i=0;i<m_items.size();i++){if(int(i)==m_focus)continue;auto p=m_items[i].rect.CenterPoint();int dx=p.x-c.x,dy=p.y-c.y;int along=(k==VK_UP?-dy:k==VK_DOWN?dy:k==VK_LEFT?-dx:dx);if(along<=0)continue;int cross=(k==VK_LEFT||k==VK_RIGHT)?abs(dy):abs(dx);double score=along+cross*5.0;if(score<best){best=score;dest=int(i);}}if(dest>=0)Focus(dest);}
    void Notice(CString s){m_notice=s;m_noticeUntil=GetTickCount()+6000;Invalidate(FALSE);}
    void PageBy(int dir){if(m_page==Details)m_filesOffset+=dir*3;else m_offset+=dir*4;Refresh();Focus(m_page==Queue?min(5,int(m_items.size())-1):m_page==Details?4:2);}
    void Filter(int n){if(m_page!=Queue)return;m_filter=n;m_offset=0;m_focus=2+n;Refresh();Focus(m_focus);}
    void Browse(Page page){m_page=page;m_offset=0;m_focus=0;Scan();Refresh();Focus(0);}
    void Scan(){m_entries.clear();
        if(m_folder.IsEmpty()){TCHAR drives[512];DWORD size=GetLogicalDriveStrings(511,drives);if(size&&size<512)for(TCHAR*p=drives;*p;p+=_tcslen(p)+1){Entry e;e.name=e.path=p;e.folder=true;m_entries.push_back(e);}return;}
        if(m_folder.Right(1)!=_T("\\"))m_folder+=_T("\\");WIN32_FIND_DATA data;HANDLE h=FindFirstFile(m_folder+_T("*"),&data);if(h==INVALID_HANDLE_VALUE){Notice(_T("This folder could not be opened"));return;}
        do{CString n=data.cFileName;if(n==_T(".")||n==_T(".."))continue;bool folder=(data.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY)!=0;if(!folder&&(m_page==FolderBrowser||n.Right(8).CompareNoCase(_T(".torrent"))!=0))continue;Entry e;e.name=n;e.path=m_folder+n;e.folder=folder;m_entries.push_back(e);}while(FindNextFile(h,&data));FindClose(h);
        std::sort(m_entries.begin(),m_entries.end(),[](const Entry&a,const Entry&b){return a.folder!=b.folder?a.folder>b.folder:a.name.CompareNoCase(b.name)<0;});
    }
    void NewLink(){m_page=Keyboard;m_edit.Empty();m_focus=0;Refresh();Focus(0);}
    void Erase(){if(!m_edit.IsEmpty())m_edit.Delete(m_edit.GetLength()-1);Refresh();}
    void Paste(){if(!OpenClipboard())return;HGLOBAL data=GetClipboardData(CF_UNICODETEXT);if(data){auto p=(LPCWSTR)GlobalLock(data);if(p){m_edit=CString(p).Left(8192);GlobalUnlock(data);}}CloseClipboard();Refresh();}
    void Back(){if(m_page==TorrentBrowser||m_page==FolderBrowser){if(m_page==FolderBrowser)m_page=Review;else m_page=Queue;}
        else if(m_page==Review)m_page=m_pending.Left(7).CompareNoCase(_T("magnet:"))==0||m_pending.Find(_T("://"))>=0?Keyboard:TorrentBrowser;
        else m_page=Queue;m_focus=0;m_offset=0;Refresh();Focus(0);}
    void Fullscreen(){if(!m_fullscreen){GetWindowRect(m_normalRect);MONITORINFO mi={sizeof(mi)};GetMonitorInfo(MonitorFromWindow(m_hWnd,MONITOR_DEFAULTTONEAREST),&mi);ModifyStyle(WS_OVERLAPPEDWINDOW,0);SetWindowPos(NULL,mi.rcMonitor.left,mi.rcMonitor.top,mi.rcMonitor.right-mi.rcMonitor.left,mi.rcMonitor.bottom-mi.rcMonitor.top,SWP_FRAMECHANGED);}
        else {ModifyStyle(0,WS_OVERLAPPEDWINDOW);SetWindowPos(NULL,m_normalRect.left,m_normalRect.top,m_normalRect.Width(),m_normalRect.Height(),SWP_FRAMECHANGED);}m_fullscreen=!m_fullscreen;}
    void CreateDownload(bool start){
        bool bt=m_pending.Left(7).CompareNoCase(_T("magnet:"))==0||(m_pending.Find(_T("://"))<0&&m_pending.Right(8).CompareNoCase(_T(".torrent"))==0);
        if(bt){vmsBtFile*f=_BT.CreateTorrentFileObject();if(!f){Notice(_T("Torrent support is unavailable"));return;}
            BOOL valid=m_pending.Left(7).CompareNoCase(_T("magnet:"))==0?f->LoadFromMagnetLink(CT2A(m_pending,CP_UTF8)):f->LoadFromFile(m_pending);
            BYTE hash[20];DWORD size=20;bool duplicate=valid&&f->getInfoHash2(hash,&size)&&_DldsMgr.findBtDownloadByHash(hash,size)!=NULL;f->Release();
            if(!valid){Notice(_T("The torrent file or magnet link is invalid"));return;}if(duplicate){Notice(_T("This torrent is already in Downloads"));return;}
        }
        int folderResult=SHCreateDirectoryEx(NULL,m_output,NULL);
        if(folderResult!=ERROR_SUCCESS&&folderResult!=ERROR_ALREADY_EXISTS&&folderResult!=ERROR_FILE_EXISTS){Notice(_T("The save folder could not be created"));return;}
        BOOL old=_App.NewDL_AutoStart();_App.NewDL_AutoStart(start);UINT id=UINT_MAX;BOOL ok=FALSE;
        try{if(bt)ok=_pwndDownloads->CreateBtDownload(m_pending,NULL,TRUE,FALSE,m_output,NULL,NULL,NULL,NULL,&id);
            else{vmsNewDownloadInfo info;info.strUrl=m_pending;info.bAddSilent=TRUE;info.bAutoStart=start;info.dwWhatIsValid=NDIV_AUTOSTART|NDIV_AP;info.ap.dwMask=DWCDAP_FLAGS;info.ap.dwFlags=DWDCDAP_F_NO_UI|DWDCDAP_F_DISABLEMALICIOUSCHECK;info.ap.strDstFolder=m_output;id=_pwndDownloads->CreateDownload(&info);ok=id!=UINT_MAX;}
        }catch(...){ok=FALSE;}_App.NewDL_AutoStart(old);
        if(!ok){Notice(_T("The download could not be added. Check the source and folder."));return;}
        auto d=_DldsMgr.GetDownloadByID(id);if(d){d->dwFlags|=DLD_DONTSHOWDIALOG|DLD_NOAUTOLAUNCH;d->setDirty();}
        m_selected=id;m_page=Queue;m_filter=0;m_focus=6;m_offset=0;Refresh();for(size_t n=0;n<m_downloads.size();n++)if(m_downloads[n]->nID==id){m_offset=int(n/4)*4;break;}Refresh();for(size_t n=0;n<m_items.size();n++)if(m_items[n].command==SelectDownload&&m_items[n].download==id){m_focus=int(n);break;}Focus(m_focus);Notice(start?_T("Download added"):_T("Download added paused"));
    }
    void Activate(){if(m_items.empty())return;Item i=m_items[m_focus];auto d=Selected();
        switch(i.command){
        case SelectDownload:m_selected=i.download;m_page=Details;m_focus=0;m_filesOffset=0;break;
        case Toggle:if(d){if(d->pMgr->IsDone()&&!running(d))d->pMgr->Do_OpenFolder();else{DLDS_LIST v;v.push_back(d);if(running(d))_DldsMgr.StopDownloads(v,TRUE);else _DldsMgr.StartDownloads(v,TRUE);}}break;
        case ShowDetails:m_page=Details;m_focus=0;m_filesOffset=0;break;
        case AddTorrent:Browse(TorrentBrowser);return;case AddLink:NewLink();return;
        case FilterAll:Filter(0);return;case FilterActive:Filter(1);return;case FilterComplete:Filter(2);return;
        case PreviousPage:PageBy(-1);return;case NextPage:PageBy(1);return;case GoBack:Back();return;
        case EnterFolder:m_folder=i.argument;m_offset=0;m_focus=m_page==FolderBrowser?2:2;Scan();break;
        case Drives:m_folder.Empty();m_offset=0;Scan();break;
        case UpFolder:{CString p=parent(m_folder);m_folder=p==m_folder?CString():p;m_offset=0;Scan();break;}
        case ChooseTorrent:m_pending=i.argument;m_page=Review;m_focus=1;break;
        case UseFolder:m_output=m_folder;m_page=Review;m_focus=1;break;
        case ChangeFolder:m_folder=m_output;Browse(FolderBrowser);return;
        case StartNew:CreateDownload(true);return;case AddPaused:CreateDownload(false);return;
        case TypeKey:if(m_edit.GetLength()<8192)m_edit+=i.argument;break;
        case EraseKey:Erase();return;case PasteKey:Paste();return;case ShiftKey:m_upper=!m_upper;break;
        case FinishText:m_pending=m_edit;m_pending.Trim();if(m_pending.Left(7).CompareNoCase(_T("magnet:"))!=0&&m_pending.Left(7).CompareNoCase(_T("http://"))!=0&&m_pending.Left(8).CompareNoCase(_T("https://"))!=0){Notice(_T("Enter a magnet link or an http:// or https:// URL"));return;}m_page=Review;m_focus=1;break;
        case OpenFolder:if(d)d->pMgr->Do_OpenFolder();break;
        case ToggleSeeding:if(d&&d->pMgr->IsBittorrent())d->pMgr->GetBtDownloadMgr()->EnableSeeding(!d->pMgr->GetBtDownloadMgr()->isSeedingEnabled());break;
        case FilePriority:if(d&&d->pMgr->IsBittorrent()){auto b=d->pMgr->GetBtDownloadMgr();int file=_ttoi(i.argument);int included=0;for(int n=0;n<b->get_FileCount();n++)if(b->getFilePriority(n)>0)included++;if(included<=1&&b->getFilePriority(file)>0){Notice(_T("Keep at least one file included"));return;}b->setFilePriority(file,b->getFilePriority(file)>0?0:1);d->setDirty();}break;
        }
        Refresh();Focus(m_focus);
    }
};
BEGIN_MESSAGE_MAP(ControllerWindow,CWnd)
 ON_WM_PAINT()
 ON_WM_ERASEBKGND()
 ON_WM_SIZE()
 ON_WM_GETMINMAXINFO()
 ON_WM_CLOSE()
 ON_WM_TIMER()
 ON_WM_DRAWITEM()
END_MESSAGE_MAP()
ControllerWindow *controller=nullptr;
}
void FdmShowController(CWnd *legacyWindow){if(controller&&::IsWindow(controller->GetSafeHwnd())){controller->ShowAgain();return;}controller=new ControllerWindow(legacyWindow);if(!controller->Open()){delete controller;controller=nullptr;}}
void FdmCloseController(){if(controller){if(::IsWindow(controller->GetSafeHwnd()))controller->DestroyWindow();delete controller;controller=nullptr;}}
namespace {
std::string jsonString(LPCTSTR text){
    CW2A utf8(CStringW(text),CP_UTF8);std::string result="\"";
    for(const unsigned char c:std::string(utf8)){
        if(c=='"'||c=='\\'){result+='\\';result+=char(c);}
        else if(c<32){char escape[7];sprintf_s(escape,"\\u%04x",unsigned(c));result+=escape;}
        else result+=char(c);
    }
    return result+'"';
}
}
void FdmControllerNotify(LPCTSTR title,LPCTSTR body){
    TCHAR directory[MY_MAX_PATH]={0};
    if(!GetEnvironmentVariable(_T("FDM_NOTIFICATION_DIR"),directory,MY_MAX_PATH))return;
    static LONG counter=0;CString filename;
    filename.Format(_T("%s\\fdm-%lu-%lu-%ld.json"),directory,GetCurrentProcessId(),GetTickCount(),InterlockedIncrement(&counter));
    CString temporary=filename+_T(".tmp");
    std::string event="{\"app\":\"FDM Controller\",\"summary\":"+jsonString(title)+",\"body\":"+jsonString(body)+"}";
    HANDLE file=CreateFile(temporary,GENERIC_WRITE,0,NULL,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,NULL);
    if(file==INVALID_HANDLE_VALUE)return;
    DWORD written=0;BOOL ok=WriteFile(file,event.data(),DWORD(event.size()),&written,NULL);CloseHandle(file);
    if(ok&&written==event.size())MoveFileEx(temporary,filename,MOVEFILE_WRITE_THROUGH);
    else DeleteFile(temporary);
}
