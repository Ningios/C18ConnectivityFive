#import <UIKit/UIKit.h>
typedef UIContextMenuConfiguration *(^C18PressMenuFactory)(UIContextMenuInteraction *,CGPoint);
FOUNDATION_EXPORT UILongPressGestureRecognizer *C18PressAttach(UIView *view,BOOL(^canBegin)(void),void(^action)(void));
FOUNDATION_EXPORT void C18PressUpdate(UIView *view,BOOL enabled);
FOUNDATION_EXPORT BOOL C18PressPresentMenu(UIView *view,C18PressMenuFactory factory);
