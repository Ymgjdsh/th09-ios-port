#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#include <cstdio>
#include <cstdint>

extern "C" {
void th09_native_paths(const char*,const char*);
SDL_Window* th09_native_window();
void th09_native_viewport(float,float,float,float);
unsigned th09_game_open(unsigned);
unsigned th09_native_frame(double);
void th09_loop_start();
void th09_loop_pause(unsigned);
unsigned th09_save_snapshot();
void th09_key(unsigned,unsigned);
void th09_keys_clear();
void th09_touch(unsigned,int,float,float);
void th09_touch_cancel();
void th09_touch_controls(unsigned,unsigned,unsigned,unsigned,unsigned);
void th09_touch_options(unsigned,unsigned,float,unsigned,unsigned);
unsigned th09_cheat_code(const char*);
const int* th09_touch_state();
const int* th09_title_status();
const int* th09_session_status();
const unsigned* th09_game_metrics();
const double* th09_native_performance();
const char* th09_error();
#if defined(TH09_IOS_SMOKE) && TH09_IOS_SMOKE
const char* th09_smoke_export_diagnostics();
#endif
}
#include "Smoke.hpp"
#include "Diagnostics.hpp"
#include "Joystick.hpp"

@interface TH09Joystick : UIView
@property(nonatomic,strong) UIView* thumb;
@property(nonatomic,strong) UITouch* primaryTouch;
@property(nonatomic) unsigned directions;
- (void)clearInput;
- (void)updateTouch:(UITouch*)touch;
@end

@implementation TH09Joystick
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])){
        self.multipleTouchEnabled=YES;self.exclusiveTouch=NO;
        self.backgroundColor=[UIColor colorWithWhite:.08 alpha:.24];
        self.layer.borderWidth=1.5;self.layer.borderColor=[UIColor colorWithWhite:1 alpha:.36].CGColor;
        self.thumb=[[UIView alloc]init];self.thumb.userInteractionEnabled=NO;
        self.thumb.backgroundColor=[UIColor colorWithWhite:1 alpha:.24];
        self.thumb.layer.borderWidth=1.5;self.thumb.layer.borderColor=[UIColor colorWithWhite:1 alpha:.64].CGColor;
        [self addSubview:self.thumb];
        self.isAccessibilityElement=YES;self.accessibilityLabel=@"移动摇杆";
        self.accessibilityHint=@"按住并拖动，松开停止移动";
    }return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    const CGFloat diameter=MIN(self.bounds.size.width,self.bounds.size.height);
    self.layer.cornerRadius=diameter/2;
    self.thumb.bounds=CGRectMake(0,0,diameter*.42,diameter*.42);
    self.thumb.layer.cornerRadius=diameter*.21;
    if(self.primaryTouch)[self updateTouch:self.primaryTouch];
    else self.thumb.center=CGPointMake(CGRectGetMidX(self.bounds),CGRectGetMidY(self.bounds));
}
- (void)setDirectionKeys:(unsigned)directions {
    const unsigned changed=self.directions^directions;
    const unsigned scans[]={203,200,208,205};
    for(unsigned i=0;i<4;++i)if(changed&(1u<<i))th09_key(scans[i],(directions&(1u<<i))!=0);
    self.directions=directions;
}
- (void)updateTouch:(UITouch*)touch {
    const CGPoint center=CGPointMake(CGRectGetMidX(self.bounds),CGRectGetMidY(self.bounds));
    const CGPoint point=[touch locationInView:self];
    const CGFloat x=point.x-center.x,y=point.y-center.y;
    const CGFloat travel=MIN(self.bounds.size.width,self.bounds.size.height)*.29;
    [self setDirectionKeys:TH09JoystickDirections(x,y,travel*.22)];
    const CGFloat distance=std::hypot(x,y),scale=distance>travel?travel/distance:1;
    self.thumb.center=CGPointMake(center.x+x*scale,center.y+y*scale);
}
- (void)clearInput {
    [self setDirectionKeys:0];self.primaryTouch=nil;
    self.thumb.center=CGPointMake(CGRectGetMidX(self.bounds),CGRectGetMidY(self.bounds));
    self.thumb.backgroundColor=[UIColor colorWithWhite:1 alpha:.24];
}
- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    if(self.primaryTouch)return;
    self.primaryTouch=touches.anyObject;
    self.thumb.backgroundColor=[UIColor colorWithWhite:1 alpha:.40];
    [self updateTouch:self.primaryTouch];
}
- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    if(self.primaryTouch&&[touches containsObject:self.primaryTouch])[self updateTouch:self.primaryTouch];
}
- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    if(self.primaryTouch&&[touches containsObject:self.primaryTouch])[self clearInput];
}
- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    if(self.primaryTouch&&[touches containsObject:self.primaryTouch])[self clearInput];
}
@end

@interface TH09Controls : UIView<UIPopoverPresentationControllerDelegate>
@property(nonatomic) CGRect gameRect;
@property(nonatomic) CGRect lastBounds;
@property(nonatomic) UIEdgeInsets lastInsets;
@property(nonatomic,strong) NSMutableArray<UIButton*>* buttons;
@property(nonatomic,strong) NSMapTable<UITouch*,NSNumber*>* touchIDs;
@property(nonatomic) int nextTouchID;
@property(nonatomic) BOOL autoShot;
@property(nonatomic) NSInteger movementMode;
@property(nonatomic) BOOL twoFingerSlow;
@property(nonatomic) BOOL doubleTapBomb;
@property(nonatomic) BOOL developerMode;
@property(nonatomic,strong) TH09Joystick* joystick;
@property(nonatomic,strong) UIButton* shotButton;
@property(nonatomic,strong) UIButton* bombButton;
@property(nonatomic,strong) UIButton* slowButton;
@property(nonatomic,strong) UIButton* pauseButton;
@property(nonatomic,strong) UIButton* settingsButton;
- (void)clearInput;
@end
static TH09Controls* controls;
static UIViewController* settingsController;
static BOOL stopped=NO, backgrounded=NO, audioInterrupted=NO, noticeVisible=NO, settingsVisible=NO, loopPaused=NO;
static NSUserDefaults* prefs(){return NSUserDefaults.standardUserDefaults;}
static double lastReport=0;
static unsigned callbacks=0;
static double perfPrevious[16]{},perfWindowStart=0;
static NSString* performanceSummary=@"Performance: waiting for the first sample.\n";
static void logLine(const char* message){
    TH09Diagnostics::write(message);
}
static BOOL inputBlocked(){return stopped||backgrounded||audioInterrupted||noticeVisible||settingsVisible;}
static void resetPerformanceWindow(){
    const double* p=th09_native_performance();for(unsigned i=0;i<16;++i)perfPrevious[i]=p[i];
    perfWindowStart=SDL_GetTicksNS()/1000000.;
}
static void reportPerformance(double now){
    const double* p=th09_native_performance();double d[16];for(unsigned i=0;i<16;++i)d[i]=p[i]-perfPrevious[i];
    const double seconds=(now-perfWindowStart)/1000.,calls=MAX(1.,d[0]),draws=MAX(1.,d[9]);
    if(seconds<=0)return;
    performanceSummary=[NSString stringWithFormat:@"Performance: fps=%.1f logicHz=%.1f callbackMs=%.2f logicMs=%.2f drawMs=%.2f audioMs=%.2f submitMs=%.2f uploadMs=%.2f presentMs=%.2f batchesPerFrame=%.1f genericBatches=%.0f framebufferBinds=%.0f vertexKiB=%.1f replacements=%.0f subUpdates=%.0f\n",d[9]/seconds,d[1]/seconds,d[2]/calls,d[3]/calls,d[4]/draws,d[5]/calls,d[7]/draws,d[6]/draws,d[8]/draws,d[10]/draws,d[11],d[12],d[13]/1024.,d[14],d[15]];
    logLine(performanceSummary.UTF8String);resetPerformanceWindow();
}
static void updatePauseState(){
    const BOOL paused=inputBlocked();
    if(paused!=loopPaused){
        loopPaused=paused;[controls clearInput];th09_loop_pause(paused);resetPerformanceWindow();
    }
    // Retain the Auto preference, but never inject shots while suspended.
    th09_touch_controls(1,!paused&&controls.autoShot,0,0,0);
    th09_touch_options(!paused,(unsigned)controls.movementMode,1.0f,controls.twoFingerSlow,controls.doubleTapBomb);
    controls.joystick.userInteractionEnabled=!paused;
    for(UIButton* button in controls.buttons)button.enabled=button==controls.settingsButton?(!backgrounded&&!noticeVisible&&!settingsVisible):!paused;
}
static NSURL* diagnosticExport(NSError** error){
    const int* title=th09_title_status();const int* session=th09_session_status();
    const unsigned* metrics=th09_game_metrics();const int* touch=th09_touch_state();
    NSString* failure=[NSString stringWithUTF8String:th09_error()?th09_error():""]?:@"";
    NSString* runtime=[NSString stringWithFormat:@"--- Runtime snapshot ---\nDisplay callbacks: %u\nUptime seconds: %.3f\nStopped: %d; background: %d; audio interruption: %d; notice: %d; settings/share: %d; loop paused: %d\nAuto shot: %d\nTitle: frames=%d active=%d screen=%d state=%d selection=%d loadFrame=%d leaving=%d transition=%d\nSession: phase=%d frames=%d replayFrame=%d replayLength=%d continues=%d stage=%d replay=%d recordable=%d\nTouch: context=%d ready=%d dragging=%d title=%d\nGraphics: batches=%u uploadBytes=%u readBytes=%u vertexUploadBytes=%u programCompiles=%u bufferReplacements=%u bufferSubUpdates=%u frames=%u resamples=%u presentations=%u\nError: %@\n",callbacks,SDL_GetTicks()/1000.,stopped,backgrounded,audioInterrupted,noticeVisible,settingsVisible,loopPaused,controls.autoShot,title[0],title[1],title[2],title[3],title[4],title[5],title[6],title[7],session[0],session[1],session[2],session[3],session[4],session[5],session[6],session[7],touch[0],touch[1],touch[2],touch[3],metrics[0],metrics[1],metrics[2],metrics[3],metrics[4],metrics[5],metrics[6],metrics[7],metrics[8],metrics[9],failure.length?failure:@"(none)"];
    runtime=[runtime stringByAppendingString:performanceSummary];
    runtime=[runtime stringByAppendingFormat:@"Controls: overlay joystick/Z/X/S; full 4:3 image; viewport=%.0fx%.0f points\nRender stream: fresh storage per batch on iOS\n",controls.gameRect.size.width,controls.gameRect.size.height];
    return TH09Diagnostics::exportLog(runtime,error);
}
#if defined(TH09_IOS_SMOKE) && TH09_IOS_SMOKE
extern "C" const char* th09_smoke_export_diagnostics(){
    static NSString* exported;NSError* error=nil;NSURL* url=diagnosticExport(&error);
    exported=url.path;return exported.fileSystemRepresentation;
}
#endif
static void finishSettings(UIViewController* controller){
    // UIKit can deliver both a dismissal delegate and an activity completion.
    // A callback from the previous sheet must not resume a replacement sheet.
    if(settingsController!=controller)return;
    settingsController=nil;settingsVisible=NO;updatePauseState();
}
static void closeSettings(UIViewController* controller){
    if(!controller||settingsController!=controller)return;
    if(controller.isBeingDismissed&&controller.transitionCoordinator){
        [controller.transitionCoordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context){finishSettings(controller);}];
    }else if(controller.presentingViewController){
        [controller dismissViewControllerAnimated:YES completion:^{finishSettings(controller);}];
    }else finishSettings(controller);
}
static void anchorPopover(UIViewController* controller){
    UIPopoverPresentationController* popover=controller.popoverPresentationController;
    popover.sourceView=controls.settingsButton;popover.sourceRect=controls.settingsButton.bounds;
    popover.permittedArrowDirections=UIPopoverArrowDirectionAny;
    popover.delegate=controls;
    controller.presentationController.delegate=controls;
}
static void presentSettingsController(UIViewController* presenter,UIViewController* controller){
    settingsController=controller;anchorPopover(controller);
    [presenter presentViewController:controller animated:YES completion:^{
        // On iPhone the adaptive presentation controller may be created during
        // presentation, so attach the swipe-dismiss delegate again afterward.
        controller.presentationController.delegate=controls;
    }];
}
static void showDiagnosticShare(UIViewController* presenter){
    if(backgrounded||!presenter.view.window){finishSettings(nil);return;}
    NSError* error=nil;NSURL* url=diagnosticExport(&error);
    if(!url){
        logLine("Diagnostic export failed");
        UIAlertController* alert=[UIAlertController alertControllerWithTitle:@"无法导出诊断日志" message:@"请检查设备剩余空间后重试。" preferredStyle:UIAlertControllerStyleAlert];
        __weak UIAlertController* weakAlert=alert;
        [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleDefault handler:^(UIAlertAction*){closeSettings(weakAlert);}]];
        presentSettingsController(presenter,alert);return;
    }
    logLine("Diagnostic log exported locally; awaiting the user's share choice");
    UIActivityViewController* share=[[UIActivityViewController alloc]initWithActivityItems:@[url] applicationActivities:nil];
    __weak UIActivityViewController* weakShare=share;
    share.completionWithItemsHandler=^(UIActivityType activity,BOOL completed,NSArray* items,NSError* shareError){
        if(shareError)logLine("System share sheet reported an error");
        closeSettings(weakShare);
    };
    presentSettingsController(presenter,share);
}
static void activateAudio(){
    NSError* error=nil;
    if(![[AVAudioSession sharedInstance]setActive:YES error:&error])logLine([[NSString stringWithFormat:@"Audio resume failed: %@",error.localizedDescription]UTF8String]);
}
static UIViewController* gameController(){
    SDL_Window* window=th09_native_window();if(!window)return nil;
    UIWindow* native=(__bridge UIWindow*)SDL_GetPointerProperty(SDL_GetWindowProperties(window),SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER,nullptr);
    return native.rootViewController;
}
extern "C" void th09_native_notice(const char* message){
    NSString* text=[NSString stringWithUTF8String:message?message:"Unknown error"];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController* vc=gameController();if(!vc||vc.presentedViewController)return;
        noticeVisible=YES;updatePauseState();
        UIAlertController* alert=[UIAlertController alertControllerWithTitle:@"TH09" message:text preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction*){noticeVisible=NO;updatePauseState();}]];
        [vc presentViewController:alert animated:YES completion:nil];
    });
}

@implementation TH09Controls
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])){
        self.multipleTouchEnabled=YES;self.backgroundColor=UIColor.clearColor;
        self.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        self.buttons=[NSMutableArray array];self.touchIDs=[NSMapTable strongToStrongObjectsMapTable];self.nextTouchID=1;
        self.autoShot=[prefs() boolForKey:@"autoShot"];
        self.movementMode=[prefs() objectForKey:@"movementMode"]?[prefs() integerForKey:@"movementMode"]:0;
        self.twoFingerSlow=[prefs() boolForKey:@"twoFingerSlow"];
        self.doubleTapBomb=[prefs() boolForKey:@"doubleTapBomb"];
        self.developerMode=[prefs() boolForKey:@"developerMode"];
        self.joystick=[[TH09Joystick alloc]initWithFrame:CGRectZero];[self addSubview:self.joystick];
        NSArray* titles=@[@"Z",@"X",@"S",@"",@""];
        NSArray* labels=@[@"Z 发射与蓄力",@"X 炸弹",@"S 减速",@"暂停",@"设置"];
        const int scans[]={44,45,42,1,0};
        for(NSUInteger n=0;n<titles.count;++n){
            UIButton* b=[UIButton buttonWithType:UIButtonTypeCustom];b.tag=scans[n];
            [b setTitle:titles[n] forState:UIControlStateNormal];b.titleLabel.font=[UIFont systemFontOfSize:25 weight:UIFontWeightSemibold];
            [b setTitleColor:[UIColor colorWithWhite:1 alpha:.9] forState:UIControlStateNormal];b.tintColor=[UIColor colorWithWhite:1 alpha:.9];
            [b setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold] forImageInState:UIControlStateNormal];
            b.backgroundColor=[UIColor colorWithWhite:.08 alpha:.24];b.layer.borderWidth=1.5;b.layer.borderColor=[UIColor colorWithWhite:1 alpha:.44].CGColor;
            b.accessibilityLabel=labels[n];b.exclusiveTouch=NO;b.multipleTouchEnabled=NO;
            if(n==0)self.shotButton=b;
            else if(n==1)self.bombButton=b;
            else if(n==2)self.slowButton=b;
            else if(n==3){self.pauseButton=b;[b setImage:[UIImage systemImageNamed:@"pause.fill"] forState:UIControlStateNormal];}
            if(n==4){self.settingsButton=b;[b setImage:[UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];[b addTarget:self action:@selector(showSettings:) forControlEvents:UIControlEventTouchUpInside];}
            else {[b addTarget:self action:@selector(buttonDown:) forControlEvents:UIControlEventTouchDown];[b addTarget:self action:@selector(buttonUp:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];}
            [self.buttons addObject:b];[self addSubview:b];
        }
    }return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if(!CGRectEqualToRect(self.lastBounds,self.bounds)||!UIEdgeInsetsEqualToEdgeInsets(self.lastInsets,self.safeAreaInsets))[self clearInput];
    self.lastBounds=self.bounds;self.lastInsets=self.safeAreaInsets;
    // The complete 4:3 game image fills an iPad mini. Wider screens retain the
    // original aspect ratio; safe areas affect controls, never the game scale.
    const CGRect area=self.bounds;
    CGFloat scale=MIN(area.size.width/640.,area.size.height/480.);
    self.gameRect=CGRectMake(CGRectGetMidX(area)-320*scale,CGRectGetMidY(area)-240*scale,640*scale,480*scale);
    const CGFloat width=self.bounds.size.width,height=self.bounds.size.height;
    if(width>0&&height>0)th09_native_viewport(self.gameRect.origin.x/width,self.gameRect.origin.y/height,self.gameRect.size.width/width,self.gameRect.size.height/height);
    const CGRect safe=CGRectIntersection(self.gameRect,UIEdgeInsetsInsetRect(self.bounds,self.safeAreaInsets));
    const CGFloat unit=MIN(1.2,MAX(.70,self.gameRect.size.height/768.));
    const CGFloat margin=24*unit,stick=156*unit,shot=80*unit,action=64*unit,utility=44;
    self.joystick.frame=CGRectMake(CGRectGetMinX(safe)+margin,CGRectGetMaxY(safe)-margin-stick,stick,stick);
    const CGPoint shotCenter=CGPointMake(CGRectGetMaxX(safe)-margin-shot/2,CGRectGetMaxY(safe)-margin-shot/2);
    self.shotButton.bounds=CGRectMake(0,0,shot,shot);self.shotButton.center=shotCenter;
    self.bombButton.bounds=CGRectMake(0,0,action,action);self.bombButton.center=CGPointMake(shotCenter.x-90*unit,shotCenter.y-16*unit);
    self.slowButton.bounds=CGRectMake(0,0,action,action);self.slowButton.center=CGPointMake(shotCenter.x-16*unit,shotCenter.y-96*unit);
    self.settingsButton.frame=CGRectMake(CGRectGetMaxX(safe)-margin-utility,CGRectGetMinY(safe)+12*unit,utility,utility);
    self.pauseButton.frame=CGRectMake(CGRectGetMinX(self.settingsButton.frame)-utility-12*unit,CGRectGetMinY(self.settingsButton.frame),utility,utility);
    for(UIButton* button in self.buttons){button.layer.cornerRadius=button.bounds.size.width/2;button.titleLabel.font=[UIFont systemFontOfSize:25*unit weight:UIFontWeightSemibold];}
}
- (void)buttonDown:(UIButton*)button {if(inputBlocked())return;th09_key((unsigned)button.tag,1);button.backgroundColor=[UIColor colorWithWhite:1 alpha:.36];}
- (void)buttonUp:(UIButton*)button {th09_key((unsigned)button.tag,0);button.backgroundColor=[UIColor colorWithWhite:.08 alpha:.24];}
- (void)showSettings:(UIButton*)button {
    UIViewController* presenter=gameController();if(backgrounded||settingsVisible||noticeVisible||!presenter||presenter.presentedViewController)return;
    settingsVisible=YES;updatePauseState();
    UIAlertController* settings=[UIAlertController alertControllerWithTitle:@"设置" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak UIAlertController* weakSettings=settings;
    [settings addAction:[UIAlertAction actionWithTitle:self.autoShot?@"自动射击：开（点击关闭）":@"自动射击：关（点击开启）" style:UIAlertActionStyleDefault handler:^(UIAlertAction*){
        self.autoShot=!self.autoShot;[prefs() setBool:self.autoShot forKey:@"autoShot"];[prefs() synchronize];logLine(self.autoShot?"Auto shot enabled":"Auto shot disabled");
        closeSettings(weakSettings);
    }]];
    [settings addAction:[UIAlertAction actionWithTitle:self.movementMode==0?@"移动：混合（拖动＋摇杆）":self.movementMode==1?@"移动：拖动":@"移动：摇杆" style:UIAlertActionStyleDefault handler:^(UIAlertAction*){
        self.movementMode=(self.movementMode+1)%3;[prefs() setInteger:self.movementMode forKey:@"movementMode"];[prefs() synchronize];updatePauseState();closeSettings(weakSettings);
    }]];
    [settings addAction:[UIAlertAction actionWithTitle:self.twoFingerSlow?@"双指减速：开（点击关闭）":@"双指减速：关（点击开启）" style:UIAlertActionStyleDefault handler:^(UIAlertAction*){
        self.twoFingerSlow=!self.twoFingerSlow;[prefs() setBool:self.twoFingerSlow forKey:@"twoFingerSlow"];[prefs() synchronize];updatePauseState();closeSettings(weakSettings);
    }]];
    [settings addAction:[UIAlertAction actionWithTitle:self.doubleTapBomb?@"双击 Bomb：开（点击关闭）":@"双击 Bomb：关（点击开启）" style:UIAlertActionStyleDefault handler:^(UIAlertAction*){
        self.doubleTapBomb=!self.doubleTapBomb;[prefs() setBool:self.doubleTapBomb forKey:@"doubleTapBomb"];[prefs() synchronize];updatePauseState();closeSettings(weakSettings);
    }]];
    [settings addAction:[UIAlertAction actionWithTitle:self.developerMode?@"开发者模式：开（点击关闭）":@"开发者模式：关（点击开启）" style:UIAlertActionStyleDefault handler:^(UIAlertAction*){
        self.developerMode=!self.developerMode;[prefs() setBool:self.developerMode forKey:@"developerMode"];[prefs() synchronize];
        logLine(self.developerMode?"Developer mode enabled":"Developer mode disabled");closeSettings(weakSettings);
    }]];
    [settings addAction:[UIAlertAction actionWithTitle:@"Cheat Code：输入 ymgjdsh" style:UIAlertActionStyleDefault handler:^(UIAlertAction*){
        UIAlertController* code=[UIAlertController alertControllerWithTitle:@"Cheat Code" message:@"输入 ymgjdsh 解锁全部内容并保存。" preferredStyle:UIAlertControllerStyleAlert];
        [code addTextFieldWithConfigurationHandler:^(UITextField* field){field.placeholder=@"Cheat Code";field.autocapitalizationType=UITextAutocapitalizationTypeNone;field.autocorrectionType=UITextAutocorrectionTypeNo;}];
        __weak UIAlertController* weakCode=code;
        [code addAction:[UIAlertAction actionWithTitle:@"应用" style:UIAlertActionStyleDefault handler:^(UIAlertAction*){BOOL ok=th09_cheat_code((weakCode.textFields.firstObject.text?:@"").UTF8String)!=0;logLine(ok?"Cheat code accepted":"Cheat code rejected");closeSettings(weakCode);}]];
        [code addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction*){closeSettings(weakCode);}]];
        [settings dismissViewControllerAnimated:YES completion:^{presentSettingsController(presenter,code);}];
    }]];
    [settings addAction:[UIAlertAction actionWithTitle:@"导出诊断日志" style:UIAlertActionStyleDefault handler:^(UIAlertAction*){
        // Keep the pause reason set across dismissal and the following share UI.
        UIAlertController* sheet=weakSettings;if(settingsController!=sheet)return;
        settingsController=nil;
        [sheet dismissViewControllerAnimated:YES completion:^{showDiagnosticShare(presenter);}];
    }]];
    [settings addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:^(UIAlertAction*){
        closeSettings(weakSettings);
    }]];
    presentSettingsController(presenter,settings);
}
- (void)presentationControllerDidDismiss:(UIPresentationController*)presentationController {finishSettings(presentationController.presentedViewController);}
- (void)popoverPresentationControllerDidDismissPopover:(UIPopoverPresentationController*)popoverPresentationController {finishSettings(popoverPresentationController.presentedViewController);}
- (void)clearInput {
    [self.joystick clearInput];th09_keys_clear();th09_touch_cancel();[self.touchIDs removeAllObjects];
    for(UIButton* b in self.buttons){[b cancelTrackingWithEvent:nil];b.highlighted=NO;b.backgroundColor=[UIColor colorWithWhite:.08 alpha:.24];}
    th09_touch_controls(1,!inputBlocked()&&self.autoShot,0,0,0);
    th09_touch_options(!inputBlocked(),(unsigned)self.movementMode,1.0f,self.twoFingerSlow,self.doubleTapBomb);
}
- (void)sendTouches:(NSSet<UITouch*>*)touches type:(unsigned)type {
    if(inputBlocked()||self.gameRect.size.width<=0||self.gameRect.size.height<=0)return;
    for(UITouch* touch in touches){
        CGPoint p=[touch locationInView:self];NSNumber* ident=[self.touchIDs objectForKey:touch];
        // Menu taps, dialogue taps and battle dragging all start here; the
        // joystick tracks its own touch separately.
        if(type==0){if(!CGRectContainsPoint(self.gameRect,p))continue;ident=@(self.nextTouchID++);[self.touchIDs setObject:ident forKey:touch];}
        if(!ident)continue;
        th09_touch(type,ident.intValue,(p.x-self.gameRect.origin.x)/self.gameRect.size.width,(p.y-self.gameRect.origin.y)/self.gameRect.size.height);
        if(type>=2)[self.touchIDs removeObjectForKey:touch];
    }
}
- (void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event {[self sendTouches:touches type:0];}
- (void)touchesMoved:(NSSet*)touches withEvent:(UIEvent*)event {[self sendTouches:touches type:1];}
- (void)touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event {[self sendTouches:touches type:2];}
- (void)touchesCancelled:(NSSet*)touches withEvent:(UIEvent*)event {[self sendTouches:touches type:3];}
@end

static void SDLCALL frame(void*) {
    @autoreleasepool {
        if(inputBlocked())return;
        const double now=SDL_GetTicksNS()/1000000.;
        if(!th09_native_frame(now)){
#if defined(TH09_IOS_SMOKE) && TH09_IOS_SMOKE
            th09SmokeAfterFrame();
#endif
            stopped=YES;updatePauseState();logLine(th09_error());th09_native_notice(th09_error());return;
        }
#if defined(TH09_IOS_SMOKE) && TH09_IOS_SMOKE
        th09SmokeAfterFrame();
#endif
        ++callbacks;
        if(now-lastReport>=5000){
            const int* title=th09_title_status();const int* session=th09_session_status();
            char line[400];std::snprintf(line,sizeof(line),"frames=%u title=%d screen=%d selection=%d phase=%d sessionFrames=%d replay=%d stage=%d",callbacks,title[1],title[2],title[4],session[0],session[1],session[6],session[5]);logLine(line);lastReport=now;
            reportPerformance(SDL_GetTicksNS()/1000000.);
        }
    }
}

int main(int argc,char** argv){
    @autoreleasepool {
        NSString* documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
        NSString* saves=[documents stringByAppendingPathComponent:@"TH09"];
        NSError* ioError=nil;
        if(![[NSFileManager defaultManager]createDirectoryAtPath:[saves stringByAppendingPathComponent:@"replay"] withIntermediateDirectories:YES attributes:nil error:&ioError]){NSLog(@"TH09 save folder failed: %@",ioError);return 1;}
        TH09Diagnostics::begin(documents);
        NSString* assets=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"assets"];
        th09_native_paths(assets.fileSystemRepresentation,saves.fileSystemRepresentation);
        logLine("Starting native SDL3 TH09 / Japanese 1.50a / offline / minimum iOS 14");
        NSError* audioError=nil;
        [[AVAudioSession sharedInstance]setCategory:AVAudioSessionCategoryPlayback error:&audioError];
        [[AVAudioSession sharedInstance]setActive:YES error:&audioError];
        if(audioError)logLine([[NSString stringWithFormat:@"Audio session failed: %@",audioError.localizedDescription]UTF8String]);
        SDL_SetHint(SDL_HINT_ORIENTATIONS,"LandscapeLeft LandscapeRight");
        SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS,"0");
        if(!th09_game_open(0x7531)){logLine(th09_error());SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR,"TH09 startup failed",th09_error(),th09_native_window());return 1;}
        SDL_Window* window=th09_native_window();SDL_SetWindowTitle(window,"Touhou 09 - Phantasmagoria of Flower View");
        UIViewController* vc=gameController();
        if(!vc){logLine("SDL did not supply an iOS view controller");return 1;}
        controls=[[TH09Controls alloc]initWithFrame:vc.view.bounds];[vc.view addSubview:controls];[controls setNeedsLayout];[controls layoutIfNeeded];
        NSNotificationCenter* center=NSNotificationCenter.defaultCenter;
        [center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*){
            backgrounded=YES;updatePauseState();if(!th09_save_snapshot())logLine("Save snapshot failed on background");logLine("Suspended");
        }];
        [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*){
            backgrounded=NO;if(!audioInterrupted&&!stopped)activateAudio();updatePauseState();logLine(inputBlocked()?"Active; still paused":"Resumed");
        }];
        [center addObserverForName:AVAudioSessionInterruptionNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification* note){
            const BOOL begin=[note.userInfo[AVAudioSessionInterruptionTypeKey]unsignedIntegerValue]==AVAudioSessionInterruptionTypeBegan;
            audioInterrupted=begin;
            if(!begin&&!backgrounded&&!stopped)activateAudio();
            updatePauseState();
        }];
        th09_touch_controls(1,0,0,0,0);th09_touch_options(1,(unsigned)controls.movementMode,1.0f,controls.twoFingerSlow,controls.doubleTapBomb);th09_loop_start();resetPerformanceWindow();
        backgrounded=UIApplication.sharedApplication.applicationState!=UIApplicationStateActive;updatePauseState();
        if(!SDL_SetiOSAnimationCallback(window,1,frame,nullptr)){logLine(SDL_GetError());return 1;}
        logLine("Game title ready; iOS display callback installed");
    }
    return 0;
}
