#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string>
#include <vector>
#include <fstream>
#include <iostream>
#include <iterator>
#include <utility>
#include "source/trunc/Bittorrent/fdmbtsupp/vmsBtSession.h"
int main(int argc,char**argv){
 if(argc<5){std::cerr<<"usage: probe seed|partial|resume|magnet torrent-or-magnet output resume-file\n";return 2;}
 std::string mode=argv[1];
 SetEnvironmentVariableA("FDM_LOCAL_TEST","1");
 HMODULE dll=LoadLibraryA("fdmbtsupp.dll");if(!dll){std::cerr<<"LoadLibrary error "<<GetLastError()<<"\n";return 3;}
 auto create=(vmsBtSession*(WINAPI*)())GetProcAddress(dll,"vmsBt_createSession");
 auto fileCreate=(vmsBtFile*(WINAPI*)())GetProcAddress(dll,"vmsBt_CreateTorrentFileObject");
 auto shutdown=(void(WINAPI*)())GetProcAddress(dll,"vmsBt_Shutdown");
 if(!create||!fileCreate||!shutdown)return 4;
 vmsBtSession*s=create();if(!s){std::cerr<<"session creation failed\n";return 5;}
 s->DHT_stop();s->LocalPeers_stop();s->UPNP_stop();s->NATPMP_stop();
 s->ListenOn(mode=="seed"?18974:18975,mode=="seed"?18974:18975);s->SetUploadLimit(mode=="seed"?512*1024:-1);
 vmsBtFile*f=fileCreate();std::wstring tf;for(char*c=argv[2];*c;c++)tf+=(unsigned char)*c;
 if(!(mode=="magnet"?f->LoadFromMagnetLink(argv[2]):f->LoadFromFile(tf.c_str()))){std::cerr<<"torrent load failed\n";return 6;}
 std::vector<unsigned char> resume;
 if(mode=="resume"){std::ifstream r(argv[4],std::ios::binary);resume.assign(std::istreambuf_iterator<char>(r),{});if(resume.empty())return 7;}
 vmsBtDownload*d=s->CreateDownload(f,argv[3],resume.empty()?nullptr:resume.data(),(DWORD)resume.size(),BTSM_SPARSE,0);if(!d){std::cerr<<"CreateDownload failed\n";return 8;}
 d->Resume();bool metadata=mode!="magnet";DWORD start=GetTickCount();
 for(int tick=0;GetTickCount()-start<(mode=="seed"?900000:180000);tick++){
  Sleep(250);
  if(!metadata&&d->SetMagnetMetadata(f)){metadata=true;std::cout<<"MAGNET_METADATA_RECEIVED files="<<f->get_FileCount()<<"\n"<<std::flush;}
  int state=d->GetState(), completed=0;d->get_PiecesProgressMap(nullptr,&completed);
  if(tick%4==0)std::cout<<"state="<<state<<" pieces="<<completed<<" bytes="<<d->get_TotalDownloadedBytesCount()<<" peers="<<d->get_ConnectionCount()<<"\n"<<std::flush;
  if(mode=="partial"&&completed>=8){
   d->Pause();Sleep(2000);auto b=d->get_TotalDownloadedBytesCount();Sleep(2000);auto a=d->get_TotalDownloadedBytesCount();
   std::cout<<"PAUSE paused="<<d->IsPaused()<<" stable="<<(a==b)<<" before="<<b<<" after="<<a<<"\n";
   if(!d->IsPaused()||a!=b)return 9;d->Resume();Sleep(250);d->Pause();Sleep(1000);
   DWORD size=0;if(!d->get_FastResumeData(nullptr,0,&size)||!size)return 10;resume.resize(size);if(!d->get_FastResumeData(resume.data(),size,&size))return 11;
   std::ofstream out(argv[4],std::ios::binary);out.write((char*)resume.data(),size);out.close();std::cout<<"RESUME_SAVED bytes="<<size<<" pieces="<<completed<<"\n"<<std::flush;shutdown();return 0;
  }
  if(mode!="seed"&&metadata&&(state==BTDS_SEEDING||state==BTDS_FINISHED)){std::cout<<"COMPLETE\n"<<std::flush;d->Pause();shutdown();return 0;}
 }
 if(mode=="seed"){shutdown();return 0;}std::cerr<<"TIMEOUT\n";shutdown();return 12;
}
