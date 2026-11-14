#import "C18Five.h"
#import "C18PressDriver.h"
#import <QuartzCore/QuartzCore.h>
#import <string.h>

static char kPressOwner,kPressMenu,kPressAncestorGate;
static BOOL C18PressEditing(void);
static BOOL C18PressOwnsTouch(UIView *);
static BOOL C18PressIsCompetitor(UIGestureRecognizer *,UIView *);
static void C18PressRemoveCompetitors(UIView *);
static void C18PressPrepareAncestor(UIView *);

// A proxy on a specific ancestor recognizer filters only touches that actually
// start on an enabled custom expandable button. All other touches and delegate
// selectors go to the original delegate. Never remove a module-wide interaction:
// the four-key auxiliary region and native editing still need that interaction.
@interface C18PressAncestorGate : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic,weak) id<UIGestureRecognizerDelegate> original;
@end
@implementation C18PressAncestorGate
- (BOOL)respondsToSelector:(SEL)selector {
    return [super respondsToSelector:selector] || [self.original respondsToSelector:selector];
}
- (id)forwardingTargetForSelector:(SEL)selector {
    id original=self.original;
    return [original respondsToSelector:selector]?original:[super forwardingTargetForSelector:selector];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (C18PressOwnsTouch(touch.view)) return NO;
    id<UIGestureRecognizerDelegate> original=self.original;
    if ([original respondsToSelector:_cmd]) return [original gestureRecognizer:gesture shouldReceiveTouch:touch];
    return YES;
}
@end

@interface C18HoldGesture : UILongPressGestureRecognizer @end
@implementation C18HoldGesture
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)other {
    if (!C18PressEditing() && C18PressIsCompetitor(other,self.view)) return NO;
    return [super canBePreventedByGestureRecognizer:other];
}
- (BOOL)shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)other {
    if (!C18PressEditing() && C18PressIsCompetitor(other,self.view)) return NO;
    return [super shouldRequireFailureOfGestureRecognizer:other];
}
- (BOOL)shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other {
    if (!C18PressEditing() && C18PressIsCompetitor(other,self.view)) return NO;
    return [super shouldBeRequiredToFailByGestureRecognizer:other];
}
@end
@interface C18PressState : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic,weak) UIView *view;
@property(nonatomic,strong) C18HoldGesture *gesture;
@property(nonatomic,copy) BOOL(^canBegin)(void);
@property(nonatomic,copy) void(^action)(void);
@property(nonatomic) BOOL active;
- (void)hold:(UILongPressGestureRecognizer *)gesture;
@end
static id C18PressShell(void) { return C18FiveLiveShell(); }
static BOOL C18PressEditing(void) { return C18FiveBool(C18PressShell(),NSSelectorFromString(@"isEditing")); }
static BOOL C18PressReady(C18PressState *state) {
    UIView *view=state.view;
    if (!C18FiveIsPresented() || !state.active || !view.window || C18PressEditing()) return NO;
    for (UIView *ancestor=view; ancestor; ancestor=ancestor.superview)
        if (ancestor.hidden || ancestor.alpha<.01 || !ancestor.userInteractionEnabled) return NO;
    if ([view isKindOfClass:UIControl.class] && ![(UIControl *)view isEnabled]) return NO;
    return !state.canBegin || state.canBegin();
}
static BOOL C18PressOwnsTouch(UIView *view) {
    for (UIView *candidate=view;candidate;candidate=candidate.superview) {
        C18PressState *state=objc_getAssociatedObject(candidate,&kPressOwner);
        if (state) return C18PressReady(state);
    }
    return NO;
}
@implementation C18PressState
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    (void)touch;
    if (gesture!=self.gesture || !C18PressReady(self)) return NO;
    C18PressPrepareAncestor(self.view);
    if (!objc_getAssociatedObject(self.view,&kPressMenu)) C18PressRemoveCompetitors(self.view);
    return YES;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture { (void)gesture; return C18PressReady(self); }
- (void)hold:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state!=UIGestureRecognizerStateBegan || !C18PressReady(self)) return;
    // This fires at the elapsed hold deadline. No Changed/end/move gate.
    if ([self.view isKindOfClass:UIControl.class]) {
        [(UIControl *)self.view cancelTrackingWithEvent:nil];
        [(UIControl *)self.view setHighlighted:NO];
    }
    if (self.action) self.action();
}
@end
static BOOL C18PressIsModuleView(UIView *view) {
    Class module=objc_getClass("C18ModuleView");
    return module && [view isKindOfClass:module];
}
static BOOL C18PressIsCompetitor(UIGestureRecognizer *gesture,UIView *view) {
    UIView *ancestor=gesture.view;
    if (!view || !ancestor || (view!=ancestor && ![view isDescendantOfView:ancestor])) return NO;
    if ([gesture isKindOfClass:UIPanGestureRecognizer.class] || [gesture isKindOfClass:UIScreenEdgePanGestureRecognizer.class]) return NO;
    // Do not depend on private recognizer names: the native click interaction
    // may install non-Click-named recognizers on iOS 16. Only recognizers on
    // the path up to this known module qualify; pan/edge-pan stay untouched.
    for (UIView *p=view;p;p=p.superview) {
        if (p==ancestor) return YES;
        if (C18PressIsModuleView(p)) break;
    }
    return NO;
}
static void C18PressPrepareAncestor(UIView *view) {
    for (UIView *ancestor=view.superview;ancestor;ancestor=ancestor.superview) {
        for (UIGestureRecognizer *gesture in [ancestor.gestureRecognizers copy]) {
            if (!C18PressIsCompetitor(gesture,view)) continue;
            C18PressAncestorGate *gate=objc_getAssociatedObject(gesture,&kPressAncestorGate);
            if (!gate) {
                gate=[C18PressAncestorGate new];
                objc_setAssociatedObject(gesture,&kPressAncestorGate,gate,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (gesture.delegate!=gate) { gate.original=gesture.delegate; gesture.delegate=gate; }
        }
        if (C18PressIsModuleView(ancestor)) break;
    }
}
static void C18PressRemoveCompetitors(UIView *view) {
    if (!view) return;
    Class click=objc_getClass("_UIClickPresentationInteraction");
    for (id interaction in [view.interactions copy]) {
        if ([interaction isKindOfClass:UIContextMenuInteraction.class] || (click && [interaction isKindOfClass:click]))
            [view removeInteraction:interaction];
    }
}
UILongPressGestureRecognizer *C18PressAttach(UIView *view,BOOL(^canBegin)(void),void(^action)(void)) {
    if (!view || !action) return nil;
    C18PressState *state=objc_getAssociatedObject(view,&kPressOwner);
    if (!state) {
        state=[C18PressState new];state.view=view;
        state.gesture=[[C18HoldGesture alloc] initWithTarget:state action:@selector(hold:)];
        state.gesture.minimumPressDuration=.4;
        state.gesture.allowableMovement=12;
        state.gesture.cancelsTouchesInView=YES;
        state.gesture.delaysTouchesBegan=NO;state.gesture.delaysTouchesEnded=NO;
        state.gesture.delegate=state;[view addGestureRecognizer:state.gesture];
        state.active=YES;
        objc_setAssociatedObject(view,&kPressOwner,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Reusing the control must not enable/reset a disabled recognizer before
    // its current primary/auxiliary/editing role is applied by PressUpdate.
    state.canBegin=canBegin;state.action=action;
    if (state.active) C18PressPrepareAncestor(view);
    if (!objc_getAssociatedObject(view,&kPressMenu)) C18PressRemoveCompetitors(view);
    return state.gesture;
}
void C18PressUpdate(UIView *view,BOOL enabled) {
    C18PressState *state=objc_getAssociatedObject(view,&kPressOwner);if (!state) return;
    state.active=enabled;
    // Never reset an active recognizer on a no-op layout pass.
    if (state.gesture.enabled!=enabled) state.gesture.enabled=enabled;
    if (enabled) {
        C18PressPrepareAncestor(view);
        if (!objc_getAssociatedObject(view,&kPressMenu)) C18PressRemoveCompetitors(view);
    }
}
@interface C18PressMenuBridge : NSObject <UIContextMenuInteractionDelegate>
@property(nonatomic,weak) UIView *view;
@property(nonatomic,strong) UIContextMenuInteraction *interaction;
@property(nonatomic,copy) C18PressMenuFactory factory;
@property(nonatomic,strong) UIContextMenuConfiguration *configuration;
@end
@implementation C18PressMenuBridge
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)point {
    (void)interaction;(void)point;return self.configuration;
}
- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)interaction previewForHighlightingMenuWithConfiguration:(UIContextMenuConfiguration *)configuration {
    (void)interaction;(void)configuration;UIView *view=self.view;if (!view.window) return nil;
    UIPreviewParameters *parameters=[UIPreviewParameters new];parameters.backgroundColor=UIColor.clearColor;
    parameters.visiblePath=[UIBezierPath bezierPathWithRoundedRect:view.bounds cornerRadius:MIN(view.bounds.size.width,view.bounds.size.height)*.5];
    return [[UITargetedPreview alloc] initWithView:view parameters:parameters];
}
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willEndForConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionAnimating>)animator {
    (void)configuration;C18PressMenuBridge *bridge=self;
    void(^finish)(void)=^{
        UIView *view=bridge.view;[view removeInteraction:interaction];bridge.factory=nil;bridge.configuration=nil;
        if (objc_getAssociatedObject(view,&kPressMenu)==bridge) objc_setAssociatedObject(view,&kPressMenu,nil,OBJC_ASSOCIATION_ASSIGN);
    };
    if (animator) [animator addCompletion:finish];else finish();
}
@end
BOOL C18PressPresentMenu(UIView *view,C18PressMenuFactory factory) {
    if (!view.window || !factory || C18PressEditing()) return NO;
    if (objc_getAssociatedObject(view,&kPressMenu)) return YES;
    C18PressMenuBridge *bridge=[C18PressMenuBridge new];bridge.view=view;bridge.factory=factory;
    bridge.interaction=[[UIContextMenuInteraction alloc] initWithDelegate:bridge];
    SEL present=NSSelectorFromString(@"_presentMenuAtLocation:");NSMethodSignature *sig=[bridge.interaction methodSignatureForSelector:present];
    if (sig.numberOfArguments!=3 || strcmp(sig.methodReturnType,"v") || strcmp([sig getArgumentTypeAtIndex:2],@encode(CGPoint))) return NO;
    CGPoint point=CGPointMake(CGRectGetMidX(view.bounds),CGRectGetMidY(view.bounds));
    bridge.configuration=factory(bridge.interaction,point);
    if (![bridge.configuration isKindOfClass:UIContextMenuConfiguration.class]) return NO;
    objc_setAssociatedObject(view,&kPressMenu,bridge,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [view addInteraction:bridge.interaction];
    ((void(*)(id,SEL,CGPoint))objc_msgSend)(bridge.interaction,present,point);
    return YES;
}
