/* The on-screen pad. It is an SDL virtual game controller, so the port reads
 * it as it reads any pad (port/src/input.c): every control setting, preset
 * and the options overlay work the same way.
 *
 * The left half of the screen is a floating stick (move and strafe, the left
 * stick): it appears where the thumb lands. The right half turns and aims
 * (the right stick): drag from where the thumb lands. Buttons sit on the
 * right edge (fire, aim, use, reload, weapon) and along the top (start,
 * options, back, crouch).
 *
 * The pad hides itself while a hardware controller is connected and comes
 * back when the last one goes. */
#import <UIKit/UIKit.h>
#import <GameController/GameController.h>
#include <SDL.h>

/* Standard game controller layout of an SDL virtual joystick of type
 * SDL_JOYSTICK_TYPE_GAMECONTROLLER: buttons and axes in SDL's own order. */
static SDL_Joystick *s_pad;

static void ge_pad_button(SDL_GameControllerButton b, BOOL down)
{
    if (s_pad)
        SDL_JoystickSetVirtualButton(s_pad, b, down ? SDL_PRESSED : SDL_RELEASED);
}

static void ge_pad_axis(SDL_GameControllerAxis a, CGFloat v)
{
    if (!s_pad)
        return;
    if (v > 1) v = 1;
    if (v < -1) v = -1;
    SDL_JoystickSetVirtualAxis(s_pad, a, (Sint16)(v * 32767));
}

static BOOL ge_pad_attach(void)
{
    if (s_pad)
        return YES;
    if (!SDL_WasInit(SDL_INIT_JOYSTICK))
        return NO;
    SDL_VirtualJoystickDesc d;
    SDL_zero(d);
    d.version = SDL_VIRTUAL_JOYSTICK_DESC_VERSION;
    d.type = SDL_JOYSTICK_TYPE_GAMECONTROLLER;
    d.naxes = SDL_CONTROLLER_AXIS_MAX;
    d.nbuttons = SDL_CONTROLLER_BUTTON_MAX;
    d.name = "Touch Pad";
    int index = SDL_JoystickAttachVirtualEx(&d);
    if (index < 0) {
        fprintf(stderr, "[ios] touch pad: %s\n", SDL_GetError());
        return NO;
    }
    s_pad = SDL_JoystickOpen(index);
    /* Triggers rest at their minimum. */
    SDL_JoystickSetVirtualAxis(s_pad, SDL_CONTROLLER_AXIS_TRIGGERLEFT, -32768);
    SDL_JoystickSetVirtualAxis(s_pad, SDL_CONTROLLER_AXIS_TRIGGERRIGHT, -32768);
    fprintf(stderr, "[ios] touch pad attached\n");
    return YES;
}

/* A round button. `trigger` buttons drive a trigger axis instead. */
@interface GEPadButton : UIView
@property (nonatomic) SDL_GameControllerButton button;
@property (nonatomic) int trigger;      /* 0 none, else the axis */
@property (nonatomic, strong) UILabel *label;
@end

@implementation GEPadButton
{
    UIImpactFeedbackGenerator *_tap;
}

- (instancetype)initWithTitle:(NSString *)title size:(CGFloat)size
{
    self = [super initWithFrame:CGRectMake(0, 0, size, size)];
    if (!self)
        return nil;
    self.layer.cornerRadius = size / 2;
    self.layer.borderWidth = 1.5;
    self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.45].CGColor;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.22];
    self.multipleTouchEnabled = NO;
    _label = [[UILabel alloc] initWithFrame:self.bounds];
    _label.text = title;
    _label.textAlignment = NSTextAlignmentCenter;
    _label.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    _label.font = [UIFont systemFontOfSize:size > 50 ? 13 : 11 weight:UIFontWeightSemibold];
    _label.adjustsFontSizeToFitWidth = YES;
    _label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_label];
    _tap = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    _trigger = 0;
    _button = SDL_CONTROLLER_BUTTON_INVALID;
    return self;
}

- (void)press:(BOOL)down
{
    [UIView animateWithDuration:0.08 animations:^{
        self.transform = down ? CGAffineTransformMakeScale(0.9, 0.9) : CGAffineTransformIdentity;
        self.backgroundColor = [UIColor colorWithWhite:down ? 1 : 0 alpha:down ? 0.35 : 0.22];
    }];
    if (down)
        [_tap impactOccurred];
    if (self.trigger)
        ge_pad_axis((SDL_GameControllerAxis)self.trigger, down ? 1 : -1);
    else
        ge_pad_button(self.button, down);
}

- (void)touchesBegan:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e { [self press:YES]; }
- (void)touchesEnded:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e { [self press:NO]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e { [self press:NO]; }

@end

/* The full-screen layer: two floating sticks under the buttons. */
@interface GETouchPad : UIView
@end

@implementation GETouchPad
{
    UITouch *_moveTouch, *_lookTouch;
    CGPoint _moveStart, _lookStart;
    UIView *_moveRing, *_moveKnob;
    NSArray<GEPadButton *> *_buttons;
}

static const CGFloat kStickRadius = 56;

- (UIView *)ring:(CGFloat)d alpha:(CGFloat)a
{
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, d, d)];
    v.layer.cornerRadius = d / 2;
    v.layer.borderWidth = 1.5;
    v.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.4].CGColor;
    v.backgroundColor = [UIColor colorWithWhite:1 alpha:a];
    v.userInteractionEnabled = NO;
    v.alpha = 0;
    return v;
}

- (GEPadButton *)button:(NSString *)title size:(CGFloat)size sdl:(SDL_GameControllerButton)b
{
    GEPadButton *v = [[GEPadButton alloc] initWithTitle:title size:size];
    v.button = b;
    [self addSubview:v];
    return v;
}

- (instancetype)initWithFrame:(CGRect)f
{
    self = [super initWithFrame:f];
    if (!self)
        return nil;
    self.multipleTouchEnabled = YES;
    self.backgroundColor = UIColor.clearColor;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _moveRing = [self ring:kStickRadius * 2 alpha:0.06];
    _moveKnob = [self ring:48 alpha:0.3];
    [self addSubview:_moveRing];
    [self addSubview:_moveKnob];

    GEPadButton *fire = [self button:@"FIRE" size:76 sdl:SDL_CONTROLLER_BUTTON_INVALID];
    fire.trigger = SDL_CONTROLLER_AXIS_TRIGGERRIGHT;
    GEPadButton *aim = [self button:@"AIM" size:56 sdl:SDL_CONTROLLER_BUTTON_INVALID];
    aim.trigger = SDL_CONTROLLER_AXIS_TRIGGERLEFT;
    _buttons = @[
        fire, aim,
        [self button:@"USE" size:56 sdl:SDL_CONTROLLER_BUTTON_A],
        [self button:@"RELOAD" size:48 sdl:SDL_CONTROLLER_BUTTON_X],
        [self button:@"WEAPON" size:48 sdl:SDL_CONTROLLER_BUTTON_Y],
        [self button:@"CROUCH" size:44 sdl:SDL_CONTROLLER_BUTTON_RIGHTSTICK],
        [self button:@"BACK" size:40 sdl:SDL_CONTROLLER_BUTTON_B],
        [self button:@"START" size:40 sdl:SDL_CONTROLLER_BUTTON_START],
        [self button:@"OPTIONS" size:40 sdl:SDL_CONTROLLER_BUTTON_BACK],
    ];
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    UIEdgeInsets in = self.safeAreaInsets;
    CGFloat right = self.bounds.size.width - MAX(in.right, 16);
    CGFloat bottom = self.bounds.size.height - MAX(in.bottom, 16);
    CGFloat top = MAX(in.top, 12);
    CGFloat left = MAX(in.left, 16);
    /* fire bottom right; aim, use, reload, weapon around it */
    _buttons[0].center = CGPointMake(right - 46, bottom - 46);
    _buttons[1].center = CGPointMake(right - 130, bottom - 30);
    _buttons[2].center = CGPointMake(right - 40, bottom - 140);
    _buttons[3].center = CGPointMake(right - 110, bottom - 108);
    _buttons[4].center = CGPointMake(right - 40, bottom - 220);
    _buttons[5].center = CGPointMake(right - 200, bottom - 26);
    /* menus: back, start, options along the top */
    _buttons[6].center = CGPointMake(left + 24, top + 24);
    _buttons[7].center = CGPointMake(right - 24, top + 24);
    _buttons[8].center = CGPointMake(right - 76, top + 24);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)e
{
    for (UITouch *t in touches) {
        CGPoint p = [t locationInView:self];
        if (p.x < self.bounds.size.width / 2 && !_moveTouch) {
            _moveTouch = t;
            _moveStart = p;
            _moveRing.center = p;
            _moveKnob.center = p;
            [UIView animateWithDuration:0.12 animations:^{ self->_moveRing.alpha = 1; self->_moveKnob.alpha = 1; }];
        } else if (p.x >= self.bounds.size.width / 2 && !_lookTouch) {
            _lookTouch = t;
            _lookStart = p;
        }
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)e
{
    for (UITouch *t in touches) {
        CGPoint p = [t locationInView:self];
        if (t == _moveTouch) {
            CGFloat dx = p.x - _moveStart.x, dy = p.y - _moveStart.y;
            CGFloat len = hypot(dx, dy);
            if (len > kStickRadius) {
                dx *= kStickRadius / len;
                dy *= kStickRadius / len;
            }
            _moveKnob.center = CGPointMake(_moveStart.x + dx, _moveStart.y + dy);
            ge_pad_axis(SDL_CONTROLLER_AXIS_LEFTX, dx / kStickRadius);
            ge_pad_axis(SDL_CONTROLLER_AXIS_LEFTY, dy / kStickRadius);
        } else if (t == _lookTouch) {
            ge_pad_axis(SDL_CONTROLLER_AXIS_RIGHTX, (p.x - _lookStart.x) / kStickRadius);
            ge_pad_axis(SDL_CONTROLLER_AXIS_RIGHTY, (p.y - _lookStart.y) / kStickRadius);
        }
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)e
{
    for (UITouch *t in touches) {
        if (t == _moveTouch) {
            _moveTouch = nil;
            ge_pad_axis(SDL_CONTROLLER_AXIS_LEFTX, 0);
            ge_pad_axis(SDL_CONTROLLER_AXIS_LEFTY, 0);
            [UIView animateWithDuration:0.18 animations:^{ self->_moveRing.alpha = 0; self->_moveKnob.alpha = 0; }];
        } else if (t == _lookTouch) {
            _lookTouch = nil;
            ge_pad_axis(SDL_CONTROLLER_AXIS_RIGHTX, 0);
            ge_pad_axis(SDL_CONTROLLER_AXIS_RIGHTY, 0);
        }
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)e
{
    [self touchesEnded:touches withEvent:e];
}

@end

/* Installed once SDL's GL view exists and SDL's joystick subsystem is up. */
@interface GETouchPadInstaller : NSObject
@end

@implementation GETouchPadInstaller

static GETouchPad *s_overlay;

static void ge_pad_update_visibility(void)
{
    BOOL hw = GCController.controllers.count > 0;
    [UIView animateWithDuration:0.2 animations:^{ s_overlay.alpha = hw ? 0 : 1; }];
    s_overlay.userInteractionEnabled = !hw;
}

static void ge_pad_try_install(void)
{
    if (s_overlay)
        return;
    UIView *gl = nil;
    for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if (![sc isKindOfClass:UIWindowScene.class])
            continue;
        for (UIWindow *w in ((UIWindowScene *)sc).windows) {
            UIView *v = w.rootViewController.view;
            if ([NSStringFromClass(v.class) isEqualToString:@"SDL_uikitopenglview"])
                gl = v;
        }
    }
    if (!gl || !ge_pad_attach()) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
            ge_pad_try_install();
        });
        return;
    }
    s_overlay = [[GETouchPad alloc] initWithFrame:gl.bounds];
    [gl addSubview:s_overlay];
    ge_pad_update_visibility();
    for (NSNotificationName n in @[GCControllerDidConnectNotification, GCControllerDidDisconnectNotification])
        [NSNotificationCenter.defaultCenter addObserverForName:n object:nil queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *note) { ge_pad_update_visibility(); }];
    fprintf(stderr, "[ios] touch pad on screen\n");
}

+ (void)load
{
    dispatch_async(dispatch_get_main_queue(), ^{ ge_pad_try_install(); });
}

@end
