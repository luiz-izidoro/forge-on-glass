// AppShell.m — Objective-C + UIKit shell for an iOS app built on-device.
//
// This is the UI layer. UIKit compiles 100% here via clang + the iOS 26.5 SDK.
// It declares the Swift @_cdecl functions as `extern` and calls them.
// Architecture: iOS 26 UIScene (UIWindowSceneDelegate + SceneManifest).
//
// Build with scripts/build-ipa.sh <App> <BundleID> AppLogic.swift AppShell.m

#import <UIKit/UIKit.h>

// ---- Swift functions (from AppLogic.swift) ----
extern int32_t swift_fibonacci(int32_t n);
extern int32_t swift_sum_of_squares(int32_t n);
extern void    swift_describe(int32_t n, char *out, int32_t cap);

// ======================= UI =======================
@interface RootViewController : UIViewController
@property (strong, nonatomic) UILabel *resultLabel;
@property (strong, nonatomic) UISlider *slider;
@end

@implementation RootViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    UIView *card = [UIView new];
    card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    card.layer.cornerRadius = 28; card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.shadowColor = [UIColor.blackColor colorWithAlphaComponent:0.12].CGColor;
    card.layer.shadowOffset = CGSizeMake(0, 8); card.layer.shadowRadius = 24; card.layer.shadowOpacity = 1;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:card];

    UILabel *title = [UILabel new];
    title.text = @"Swift on iSH";
    title.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    title.textColor = [UIColor labelColor]; title.textAlignment = NSTextAlignmentCenter;

    UILabel *subtitle = [UILabel new];
    subtitle.text = @"Swift logic + UIKit, compiled on-device";
    subtitle.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    subtitle.textColor = [UIColor secondaryLabelColor];
    subtitle.textAlignment = NSTextAlignmentCenter; subtitle.numberOfLines = 0;

    self.resultLabel = [UILabel new];
    self.resultLabel.font = [UIFont monospacedSystemFontOfSize:20 weight:UIFontWeightSemibold];
    self.resultLabel.textColor = [UIColor systemBlueColor];
    self.resultLabel.textAlignment = NSTextAlignmentCenter; self.resultLabel.numberOfLines = 0;

    self.slider = [UISlider new];
    self.slider.minimumValue = 1; self.slider.maximumValue = 30; self.slider.value = 12;
    [self.slider addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, subtitle, self.resultLabel, self.slider]];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 20;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [card.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [card.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:36],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-36],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:28],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-28],
    ]];
    [self update];
}
- (void)changed:(UISlider *)s { [self update]; }
- (void)update {
    int32_t n = (int32_t)roundf(self.slider.value);
    char buf[160]; swift_describe(n, buf, sizeof(buf));   // ← string from Swift
    self.resultLabel.text = [NSString stringWithUTF8String:buf];
}
@end

// ================= Scene + App delegates (iOS 26 UIScene) =================
@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow *window;
@end
@implementation SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session
      options:(UISceneConnectionOptions *)opts {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [RootViewController new];
    [self.window makeKeyAndVisible];
}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)a didFinishLaunchingWithOptions:(NSDictionary *)o { return YES; }
- (UISceneConfiguration *)application:(UIApplication *)a
        configurationForConnectingSceneSession:(UISceneSession *)s
                                       options:(UISceneConnectionOptions *)o {
    UISceneConfiguration *c = [[UISceneConfiguration alloc]
        initWithName:@"Default Configuration" sessionRole:s.role];
    c.delegateClass = [SceneDelegate class];
    return c;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class])); }
}
