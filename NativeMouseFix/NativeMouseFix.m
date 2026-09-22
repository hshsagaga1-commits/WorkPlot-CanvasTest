#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <GameController/GameController.h>
#import <objc/runtime.h>
#import <objc/message.h>

static UILabel *gStatusLabel;
static BOOL gLastHandleMouseTouch = NO;
static NSInteger gLastTouchType = -1;
static BOOL gAssistiveTouchBlocksMouse = NO;
static BOOL gSupportsMouseHandling = NO;
static BOOL gPrefersPointerLocked = NO;
static BOOL gFixEnabled = YES;

static BOOL readBoolIvar(id obj, const char *name, BOOL fallback) {
    Ivar iv = class_getInstanceVariable([obj class], name);
    if (!iv) return fallback;
    ptrdiff_t off = ivar_getOffset(iv);
    return *((BOOL *)((uint8_t *)(__bridge void *)obj + off));
}
static void writeBoolIvar(id obj, const char *name, BOOL value) {
    Ivar iv = class_getInstanceVariable([obj class], name);
    if (!iv) return;
    ptrdiff_t off = ivar_getOffset(iv);
    *((BOOL *)((uint8_t *)(__bridge void *)obj + off)) = value;
}
static id findInputCapture(void) {
    Class cls = NSClassFromString(@"InputCapture");
    if (!cls) return nil;
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        NSMutableArray<UIView *> *queue = [NSMutableArray array];
        if (window) [queue addObject:window];
        while (queue.count) {
            UIView *v = queue.firstObject; [queue removeObjectAtIndex:0];
            if ([v isKindOfClass:cls]) return v;
            [queue addObjectsFromArray:v.subviews];
        }
    }
    return nil;
}
static NSString *touchTypeName(NSInteger type) {
    switch (type) {
        case 0: return @"Direct (dedo)";
        case 1: return @"Indirect";
        case 2: return @"Pencil";
        case 3: return @"IndirectPointer (mouse)";
        default: return [NSString stringWithFormat:@"%ld", (long)type];
    }
}
static NSString *mouseSummary(void) {
    if (@available(iOS 14.0, *)) {
        NSArray<GCMouse *> *mice = GCMouse.mice;
        GCMouse *mouse = GCMouse.current;
        if (!mouse && mice.count) mouse = mice.firstObject;
        if (!mouse) return @"GCMouse: NAO detectado";
        GCMouseInput *in = mouse.mouseInput;
        return [NSString stringWithFormat:@"GCMouse: SIM (%lu) L:%@ R:%@ M:%@",
          (unsigned long)mice.count,
          in.leftButton.isPressed?@"1":@"0",
          in.rightButton.isPressed?@"1":@"0",
          in.middleButton.isPressed?@"1":@"0"];
    }
    return @"GCMouse: iOS antigo";
}
static void refreshHUD(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        id cap = findInputCapture();
        if (cap) {
            gAssistiveTouchBlocksMouse = readBoolIvar(cap, "assistiveTouchDisablesMouseInput", gAssistiveTouchBlocksMouse);
            if ([cap respondsToSelector:NSSelectorFromString(@"supportsMouseHandling")])
                gSupportsMouseHandling = ((BOOL(*)(id,SEL))objc_msgSend)(cap,NSSelectorFromString(@"supportsMouseHandling"));
            if ([cap respondsToSelector:NSSelectorFromString(@"prefersPointerLocked")])
                gPrefersPointerLocked = ((BOOL(*)(id,SEL))objc_msgSend)(cap,NSSelectorFromString(@"prefersPointerLocked"));
        }
        gStatusLabel.text = [NSString stringWithFormat:
          @"NativeMouseFix V0.2%@\n%@\nInputCapture: %@\nsupportsMouseHandling: %@\nAssistiveTouch bloqueia mouse: %@\nprefersPointerLocked: %@\nultimo touch: %@\nhandleMouseTouch aceitou: %@",
          gFixEnabled?@" [FIX ON]":@" [DIAG]", mouseSummary(), cap?@"SIM":@"NAO",
          gSupportsMouseHandling?@"SIM":@"NAO", gAssistiveTouchBlocksMouse?@"SIM":@"NAO",
          gPrefersPointerLocked?@"SIM":@"NAO", touchTypeName(gLastTouchType),
          gLastHandleMouseTouch?@"SIM":@"NAO"];
    });
}
static void installHUD(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
        for (UIWindow *w in UIApplication.sharedApplication.windows) if (w.isKeyWindow) { window=w; break; }
        if (!window || gStatusLabel) return;
        UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(10,55,MIN(window.bounds.size.width-20,390),190)];
        label.numberOfLines=0;
        label.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightMedium];
        label.textColor=UIColor.whiteColor;
        label.backgroundColor=[UIColor colorWithWhite:0 alpha:0.78];
        label.layer.cornerRadius=10; label.layer.masksToBounds=YES;
        label.accessibilityIdentifier=@"NativeMouseFixHUD";
        [window addSubview:label]; gStatusLabel=label; refreshHUD();
        [NSTimer scheduledTimerWithTimeInterval:0.15 repeats:YES block:^(__unused NSTimer *t){ refreshHUD(); }];
    });
}
static BOOL (*orig_handleMouseTouch)(id,SEL,UITouch *,UIEvent *);
static BOOL hook_handleMouseTouch(id self, SEL cmd, UITouch *touch, UIEvent *event) {
    if (touch) gLastTouchType=touch.type;
    BOOL ret=orig_handleMouseTouch?orig_handleMouseTouch(self,cmd,touch,event):NO;
    gLastHandleMouseTouch=ret; return ret;
}
static void (*orig_updateAssistiveTouchState)(id,SEL);
static void hook_updateAssistiveTouchState(id self, SEL cmd) {
    if (orig_updateAssistiveTouchState) orig_updateAssistiveTouchState(self,cmd);
    gAssistiveTouchBlocksMouse=readBoolIvar(self,"assistiveTouchDisablesMouseInput",NO);
    if (gFixEnabled && GCMouse.current) {
        writeBoolIvar(self,"assistiveTouchDisablesMouseInput",NO);
        SEL update=NSSelectorFromString(@"updateMouseEnabled");
        if ([self respondsToSelector:update]) ((void(*)(id,SEL))objc_msgSend)(self,update);
    }
}
static void swizzleInstance(Class cls, SEL sel, IMP replacement, IMP *originalOut) {
    Method m=class_getInstanceMethod(cls,sel); if(!m)return;
    if(originalOut)*originalOut=method_getImplementation(m);
    method_setImplementation(m,replacement);
}
static void installRobloxHooks(void) {
    Class cls=NSClassFromString(@"InputCapture"); if(!cls)return;
    swizzleInstance(cls,NSSelectorFromString(@"handleMouseTouch:withEvent:"),(IMP)hook_handleMouseTouch,(IMP*)&orig_handleMouseTouch);
    swizzleInstance(cls,NSSelectorFromString(@"updateAssistiveTouchState"),(IMP)hook_updateAssistiveTouchState,(IMP*)&orig_updateAssistiveTouchState);
}
static void mouseConnected(NSNotification *n) {
    NSLog(@"[NativeMouseFix] GCMouse connected: %@",n.object);
    if(gFixEnabled){
        id cap=findInputCapture();
        if(cap){ writeBoolIvar(cap,"assistiveTouchDisablesMouseInput",NO);
            SEL update=NSSelectorFromString(@"updateMouseEnabled");
            if([cap respondsToSelector:update])((void(*)(id,SEL))objc_msgSend)(cap,update);
        }
    }
    refreshHUD();
}
__attribute__((constructor)) static void NativeMouseFixInit(void) {
    @autoreleasepool {
        NSLog(@"[NativeMouseFix] loaded");
        if(@available(iOS 14.0,*)){
            [NSNotificationCenter.defaultCenter addObserverForName:GCMouseDidConnectNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*n){mouseConnected(n);}];
            [NSNotificationCenter.defaultCenter addObserverForName:GCMouseDidDisconnectNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification*n){refreshHUD();}];
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{installRobloxHooks();installHUD();});
    }
}
