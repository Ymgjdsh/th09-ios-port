#pragma once
#if defined(TH09_IOS_SMOKE) && TH09_IOS_SMOKE
// Objective-C++ diagnostic driver, called after th09_native_frame(). It injects
// the public hosted-key API. This is not an XCTest or physical-touch test.
extern "C" {
const int* th09_smoke_state();
unsigned th09_smoke_validate_save();
int th09_smoke_replay_begin();
int th09_smoke_replay_step(unsigned);
const int* th09_smoke_replay_status();
const char* th09_smoke_replay_error();
const char* th09_smoke_export_diagnostics();
}

struct TH09NativeSmoke {
    enum Phase {menu,opening,holdCharge,releaseCharge,play,pauseRequest,pauseHold,resume,afterResume,replay,done};
    Phase phase=menu;int lastFrame=-1,start=0,liveStart=0,pauseFrame=0,nextMenuPulse=0,menuPulseEnd=-1;
    unsigned callbacks=0,keys=0;int maxCharge=0,liveFrames=0;
    bool sawHeld=false,sawRelease=false,pauseStable=false,resumed=false,saved=false;
    double started=0;FILE* log=nullptr;
    NSString* documents(){return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;}
    void message(const char* text){
        if(!log)log=std::fopen([[documents() stringByAppendingPathComponent:@"native-smoke.log"]fileSystemRepresentation],"w");
        NSLog(@"[TH09 smoke] %s",text);if(log){std::fprintf(log,"%.3f %s\n",SDL_GetTicks()/1000.,text);std::fflush(log);}
    }
    void setKeys(unsigned next){
        const unsigned scans[]={44,29,203,205,42,1,200};
        for(unsigned n=0;n<7;++n)if((keys^next)&(1u<<n))th09_key(scans[n],(next>>n)&1u);
        keys=next;
    }
    NSDictionary* exportDiagnostics(){
        const char* exported=th09_smoke_export_diagnostics();
        NSString* path=exported?[NSString stringWithUTF8String:exported]:nil;
        NSError* io=nil;BOOL directory=NO;
        const BOOL exists=path.length&&[[NSFileManager defaultManager]fileExistsAtPath:path isDirectory:&directory]&&!directory;
        NSData* data=exists?[NSData dataWithContentsOfFile:path options:0 error:&io]:nil;
        NSString* text=data?[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding]:nil;
        NSMutableArray<NSString*>* failures=[NSMutableArray array];
        if(!exists)[failures addObject:@"Export did not create a regular file"];
        if(!text.length)[failures addObject:@"Export could not be read as nonempty UTF-8"];
        const BOOL bounded=data.length>0&&data.length<3*1024*1024;
        if(!bounded)[failures addObject:@"Export length is outside the expected bounded range"];
        const auto contains=[&](NSString* needle){return text&&[text rangeOfString:needle].location!=NSNotFound;};
        UIDevice* device=UIDevice.currentDevice;NSBundle* bundle=NSBundle.mainBundle;
        NSString* version=[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        NSString* build=[bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
        const BOOL system=contains([NSString stringWithFormat:@"\nSystem: %@ %@\n",device.systemName,device.systemVersion]);
        const BOOL model=contains([NSString stringWithFormat:@"\nDevice model: %@ (",device.model]);
        const BOOL versionOK=version.length&&contains([NSString stringWithFormat:@"\nVersion: %@\n",version]);
        const BOOL buildOK=build.length&&contains([NSString stringWithFormat:@"\nBuild: %@\n",build]);
        const BOOL runtime=contains(@"--- Runtime snapshot ---")&&contains(@"\nSession: ")&&contains(@"\nGraphics: ");
        const NSRange current=text?[text rangeOfString:@"--- Current launch: startup.log"]:NSMakeRange(NSNotFound,0);
        const NSRange previous=text?[text rangeOfString:@"--- Previous launch: previous-startup.log"]:NSMakeRange(NSNotFound,0);
        NSString* currentLog=@"";
        if(current.location!=NSNotFound){
            const NSUInteger begin=NSMaxRange(current),end=previous.location!=NSNotFound&&previous.location>begin?previous.location:text.length;
            currentLog=[text substringWithRange:NSMakeRange(begin,end-begin)];
        }
        // Check the current section itself: a previous successful launch must
        // not hide a missing or unreadable log from this process.
        const BOOL startup=[currentLog rangeOfString:@"Starting native SDL3 TH09 / Japanese 1.50a"].location!=NSNotFound;
        const BOOL ready=[currentLog rangeOfString:@"Game title ready; iOS display callback installed"].location!=NSNotFound;
        if(!system)[failures addObject:@"System name/version field missing or incorrect"];
        if(!model)[failures addObject:@"Device model field missing or incorrect"];
        if(!versionOK||!buildOK)[failures addObject:@"App version/build field missing or incorrect"];
        if(!runtime)[failures addObject:@"Runtime snapshot fields missing"];
        if(!startup||!ready)[failures addObject:@"Current launch startup/readiness log missing"];
        return @{@"passed":@(failures.count==0),@"file":path.lastPathComponent?:@"",@"bytes":@(data.length),
            @"exists":@(exists),@"bounded":@(bounded),@"systemMatches":@(system),@"deviceModelMatches":@(model),
            @"versionMatches":@(versionOK),@"buildMatches":@(buildOK),@"runtimeSnapshotPresent":@(runtime),
            @"currentLaunchStartupPresent":@(startup),@"currentLaunchReadyPresent":@(ready),
            @"previousLaunchSectionPresent":@(previous.location!=NSNotFound),@"failures":failures,
            @"readError":io.localizedDescription?:@""};
    }
    void finish(bool passed,const char* error){
        phase=done;setKeys(0);th09_loop_pause(1);
        NSString* resultError=[NSString stringWithUTF8String:error?error:""]?:@"Invalid error text";
        NSDictionary* diagnostics=exportDiagnostics();
        if(![diagnostics[@"passed"]boolValue]){
            passed=false;NSString* detail=[diagnostics[@"failures"]componentsJoinedByString:@"; "];
            resultError=[NSString stringWithFormat:@"%@%@Diagnostic export: %@",resultError,resultError.length?@"; ":@"",detail];
        }
        const int* check=th09_smoke_replay_status();
        NSDictionary* report=@{
            @"passed":@(passed),@"error":resultError,@"diagnosticsExport":diagnostics,
            @"scope":@"Native rendered title/story with injected hosted keys; isolated normal two-human simulation recording/playback. No forced wins or invulnerability. Not physical touch or an iOS 14 device result.",
            @"liveStoryFrames":@(liveFrames),@"chargeHeld":@(sawHeld),@"maxCharge":@(maxCharge/1000.),
            @"chargeReleased":@(sawRelease),@"pauseFramesStable":@(pauseStable),@"resumed":@(resumed),
            @"saveReadbackValid":@(saved),@"replayPhase":@(check[0]),@"replayFrames":@(check[1]),
            @"comparedFields":@(check[2]),@"replayBytes":@(check[3]),
            @"mismatchFrame":@(check[4]),@"mismatchField":@(check[5]),@"expected":@(check[6]),@"actual":@(check[7]),
            @"snapshotExclusions":@[@"RNG call counter (field 1)",@"replay flag bit 8 (field 2)"],
            @"systemVersion":UIDevice.currentDevice.systemVersion,@"model":UIDevice.currentDevice.model
        };
        NSError* io=nil;NSData* data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:&io];
        if(!data||![data writeToFile:[documents() stringByAppendingPathComponent:@"native-smoke-result.json"] options:NSDataWritingAtomic error:&io]){
            passed=false;message("FAIL: could not write native-smoke-result.json");if(io)NSLog(@"TH09 smoke report: %@",io);
        }
        message(passed?"PASS: rendered gameplay, charge, pause/resume, save readback, 900-frame replay equivalence, diagnostic export":"FAIL: native smoke");
        if(resultError.length)message(resultError.UTF8String);
    }
    void tick(){
        if(phase==done)return;
        if(!started){started=SDL_GetTicks()/1000.;message("BEGIN: diagnostic input injection; physical touch remains untested");}
        ++callbacks;
        if(SDL_GetTicks()/1000.-started>600){finish(false,"Timed out after 600 seconds");return;}
        if(*th09_error()){finish(false,th09_error());return;}
        if(phase==replay){
            const int result=th09_smoke_replay_step(8);
            if(result==3)finish(true,"");else if(result<0)finish(false,th09_smoke_replay_error());
            return;
        }
        const int* state=th09_smoke_state();const int appFrame=state[0];
        if(appFrame==lastFrame)return;lastFrame=appFrame;
        const int* title=th09_title_status();
        if(phase==menu){
            if(!title[1]){setKeys(0);phase=opening;start=appFrame;message("Title menu launched ordinary Story mode");return;}
            // Use elapsed deadlines: catch-up ticks may skip every exact
            // multiple of 40. Track Up too so all exits release every key.
            if(menuPulseEnd>=0&&appFrame>=menuPulseEnd){setKeys(0);menuPulseEnd=-1;}
            if(menuPulseEnd<0&&appFrame>=nextMenuPulse&&title[3]==1&&title[5]>=12&&title[2]>=1&&title[2]<=3){
                setKeys(title[2]==2&&title[4]!=0?64:1);menuPulseEnd=appFrame+3;nextMenuPulse=appFrame+40;
            }
            return;
        }
        if(title[1]||state[4]!=1){finish(false,"Live story ended before the bounded smoke sequence completed");return;}
        if(phase==opening){
            // Ctrl and repeated Z advance original dialogue using ordinary keys.
            setKeys(2u|(appFrame%6<3?1u:0u));
            if(state[5]<0&&state[5]!=-2&&state[13]>=30&&(state[7]==0||state[7]==3)&&state[8]>0){
                setKeys(1);liveStart=state[3];start=state[3];phase=holdCharge;message("Active story gameplay; holding Z for charge");
            }return;
        }
        liveFrames=state[3]-liveStart;
        if(phase==holdCharge){
            if(state[9]&1)sawHeld=true;if(state[11]>maxCharge)maxCharge=state[11];
            if(state[3]-start>=120){setKeys(0);start=state[3];phase=releaseCharge;message("Released Z; observing charge reset");}
        }else if(phase==releaseCharge){
            if(!(state[9]&1)&&state[11]==0&&maxCharge>0)sawRelease=true;
            if(state[3]-start>=30){
                if(!sawHeld||!sawRelease){finish(false,"Charge press/release was not observed in gameplay state");return;}
                phase=play;
            }
        }else if(phase==play||phase==afterResume){
            const unsigned shot=liveFrames%6<3?1:0,move=liveFrames%240<120?4:8;
            setKeys(shot|move|(liveFrames%80<20?16:0));
            if(phase==play&&liveFrames>=360){setKeys(32);phase=pauseRequest;start=appFrame;message("Requesting ordinary pause menu");}
            else if(phase==afterResume&&liveFrames>=900){
                setKeys(0);saved=th09_save_snapshot()&&th09_smoke_validate_save();
                if(!saved){finish(false,"Save write/readback validation failed");return;}
                message("900 live story frames completed; save reloaded and validated");
                th09_loop_pause(1);
                if(th09_smoke_replay_begin()<0){finish(false,th09_smoke_replay_error());return;}
                phase=replay;message("Recording and replaying 900 ordinary two-human simulation frames");
            }
        }else if(phase==pauseRequest){
            if(appFrame-start>=3)setKeys(0);
            if(state[2]){pauseFrame=state[3];start=appFrame;phase=pauseHold;}
            else if(appFrame-start>90){finish(false,"Pause menu did not open");return;}
        }else if(phase==pauseHold){
            setKeys(0);
            if(state[3]!=pauseFrame){finish(false,"Simulation advanced while pause menu was open");return;}
            if(appFrame-start>=30){pauseStable=true;setKeys(1);start=appFrame;phase=resume;message("Pause held simulation stable; requesting Resume");}
        }else if(phase==resume){
            if(appFrame-start>=3)setKeys(0);
            if(!state[2]&&state[3]>pauseFrame){resumed=true;phase=afterResume;message("Ordinary pause menu resumed simulation");}
            else if(appFrame-start>90){finish(false,"Simulation did not resume");return;}
        }
    }
};
static void th09SmokeAfterFrame(){static TH09NativeSmoke smoke;smoke.tick();}
#endif
