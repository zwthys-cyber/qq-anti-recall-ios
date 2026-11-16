#import <UIKit/UIKit.h>

// QQ may style its views dark while leaving UIKit's inherited traits light.
// Follow an explicitly dark window, device screen, or host surface in that case.
static inline BOOL QARSurfaceIsDark(UIColor *color, UITraitCollection *traits) {
    if (!color) return NO;
    CGFloat red=0, green=0, blue=0, alpha=0;
    if (![[color resolvedColorWithTraitCollection:traits] getRed:&red green:&green blue:&blue alpha:&alpha]) return NO;
    return alpha > 0.9 && (0.2126*red + 0.7152*green + 0.0722*blue) < 0.25;
}
static inline UIUserInterfaceStyle QARHostStyle(UIView *host) {
    if (host.window.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ||
        host.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ||
        host.window.windowScene.screen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark)
        return UIUserInterfaceStyleDark;
    for (UIView *view = host; view; view = view.superview) {
        if (QARSurfaceIsDark(view.backgroundColor, view.traitCollection)) return UIUserInterfaceStyleDark;
    }
    return UIUserInterfaceStyleLight;
}
static inline UIColor *QARAccent(void) { return UIColor.systemIndigoColor; }
