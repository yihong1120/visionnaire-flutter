#import "HCaptchaFlutterPlugin.h"

NSString * const HFlutterMethodCallBadRequest = @"HFlutterMethodCallBadRequest";

@interface HCaptchaFlutterPlugin ()

@property(strong, nonatomic) HCaptcha *hCaptcha;
@property(strong, nonatomic) UIView *overlayView;
@property(weak, nonatomic) WKWebView *webView;
@property(copy, nonatomic) FlutterResult pendingResult;
@property(assign, nonatomic) NSUInteger challengeGeneration;

- (void)finishChallengeForGeneration:(NSUInteger)generation
                               token:(NSString *)token
                        errorMessage:(NSString *)errorMessage;
- (void)cancelPendingChallenge;
- (void)tearDownChallenge;

@end

@implementation HCaptchaFlutterPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"plugins.kjxbyz.com/hcaptcha_flutter_plugin"
            binaryMessenger:[registrar messenger]];
  HCaptchaFlutterPlugin* instance = [[HCaptchaFlutterPlugin alloc] init];
  [registrar addApplicationDelegate:instance];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"dismiss" isEqualToString:call.method]) {
    [self cancelPendingChallenge];
    result(nil);
  } else if ([@"show" isEqualToString:call.method]) {
    if (self.pendingResult != nil) {
      result([FlutterError errorWithCode:@"challenge_in_progress"
                                 message:@"An hCaptcha challenge is already open."
                                 details:nil]);
      return;
    }

    id arguments = call.arguments;
    if (![arguments isKindOfClass:NSDictionary.class]) {
      result([FlutterError errorWithCode:HFlutterMethodCallBadRequest
                                 message:@"hCaptcha configuration must be a dictionary."
                                 details:nil]);
      return;
    }

    NSDictionary *config = (NSDictionary *) arguments;
    id siteKeyValue = [config objectForKey:@"siteKey"];
    id languageValue = [config objectForKey:@"language"];
    if (![siteKeyValue isKindOfClass:NSString.class] ||
        ![languageValue isKindOfClass:NSString.class]) {
      result([FlutterError errorWithCode:HFlutterMethodCallBadRequest
                                 message:@"hCaptcha siteKey and language must be strings."
                                 details:nil]);
      return;
    }

    NSCharacterSet *whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSString *siteKey = [(NSString *)siteKeyValue stringByTrimmingCharactersInSet:whitespace];
    NSString *language = [(NSString *)languageValue stringByTrimmingCharactersInSet:whitespace];
    if (siteKey.length == 0 || language.length == 0) {
      result([FlutterError errorWithCode:HFlutterMethodCallBadRequest
                                 message:@"hCaptcha siteKey and language must not be empty."
                                 details:nil]);
      return;
    }

    NSError *initializationError = nil;
    self.hCaptcha = [[HCaptcha alloc] initWithApiKey: siteKey
                                           baseURL: [NSURL URLWithString: @"http://localhost"]
                                           locale: [NSLocale localeWithLocaleIdentifier: language]
                                           size: HCaptchaSizeInvisible
                                           error: &initializationError];
    if (self.hCaptcha == nil || initializationError != nil) {
      result([FlutterError errorWithCode:@"challenge_initialization_failed"
                                 message:initializationError.localizedDescription ?: @"hCaptcha could not be initialized."
                                 details:nil]);
      self.hCaptcha = nil;
      return;
    }

    UIViewController* viewController = [self topViewController];
    if (viewController == nil || viewController.view == nil) {
      result([FlutterError errorWithCode:@"presentation_unavailable"
                                 message:@"No active view controller is available for hCaptcha."
                                 details:nil]);
      self.hCaptcha = nil;
      return;
    }
    UIView* view = viewController.view;
    NSUInteger generation = ++self.challengeGeneration;
    self.pendingResult = [result copy];

    // overlay
    self.overlayView = [[UIView alloc] init];
    self.overlayView.frame = view.bounds;
    self.overlayView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.overlayView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    [view addSubview:self.overlayView];

    // loading view
    UIView* loadingView = [[UIView alloc] init];
    loadingView.frame = CGRectMake(0, 0, 80, 80);
    loadingView.center = self.overlayView.center;
    loadingView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
    loadingView.clipsToBounds = true;
    loadingView.layer.cornerRadius = 10;

    // loading indicator
    UIActivityIndicatorView *activityIndicator = [[UIActivityIndicatorView alloc] init];
    activityIndicator.frame = CGRectMake(0, 0, 40, 40);
    activityIndicator.center = CGPointMake(loadingView.frame.size.width / 2,
                                           loadingView.frame.size.height / 2);
    activityIndicator.hidesWhenStopped = YES;
    activityIndicator.activityIndicatorViewStyle = UIActivityIndicatorViewStyleLarge;
    activityIndicator.color = UIColor.whiteColor;

    [loadingView addSubview:activityIndicator];
    [self.overlayView addSubview:loadingView];
    [activityIndicator startAnimating];

    __weak typeof(self) weakSelf = self;
    [self.hCaptcha configureWebView:^(WKWebView * _Nonnull webView) {
      HCaptchaFlutterPlugin *strongSelf = weakSelf;
      if (strongSelf == nil ||
          strongSelf.pendingResult == nil ||
          strongSelf.challengeGeneration != generation) {
        return;
      }
      const CGFloat horizontalInset = 24;
      const CGFloat verticalInset = 32;
      CGFloat width = CGRectGetWidth(view.bounds) - (horizontalInset * 2);
      CGFloat height = CGRectGetHeight(view.bounds) - (verticalInset * 2);
      CGFloat webviewWidth = MIN(325, MAX(0, width));
      CGFloat webviewHeight = MIN(490, MAX(0, height));
      webView.bounds = CGRectMake(0, 0, webviewWidth, webviewHeight);
      webView.center = CGPointMake(CGRectGetMidX(view.bounds), CGRectGetMidY(view.bounds));
      strongSelf.webView = webView;
    }];

    [self.hCaptcha onEvent:^(enum HCaptchaEvent event, id _Nullable _) {
      dispatch_async(dispatch_get_main_queue(), ^{
        HCaptchaFlutterPlugin *strongSelf = weakSelf;
        if (strongSelf == nil ||
            strongSelf.pendingResult == nil ||
            strongSelf.challengeGeneration != generation) {
          return;
        }
        if (event == HCaptchaEventOpen) {
          [activityIndicator stopAnimating];
        } else if (event == HCaptchaEventError) {
          // The event callback is diagnostic. The validate completion below is
          // the single authoritative success/error result.
          [activityIndicator stopAnimating];
        }
      });
    }];

    [self.hCaptcha validateOn:view resetOnError:NO completion:^(HCaptchaResult *result) {
      NSError *error = nil;
      NSString *token = [result dematerializeAndReturnError: &error];
      NSString *errorMessage = error.localizedDescription;
      dispatch_async(dispatch_get_main_queue(), ^{
        HCaptchaFlutterPlugin *strongSelf = weakSelf;
        [strongSelf finishChallengeForGeneration:generation
                                           token:token
                                    errorMessage:errorMessage];
      });
    }];
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (UIViewController *)topViewController {
  UIWindow *window = [self activeWindow];
  if (window == nil) {
    return nil;
  }
  return [self topViewControllerFromViewController:window.rootViewController];
}

- (UIWindow *)activeWindow {
  for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
    if (![scene isKindOfClass:UIWindowScene.class] ||
        scene.activationState != UISceneActivationStateForegroundActive) {
      continue;
    }

    UIWindowScene *windowScene = (UIWindowScene *)scene;
    for (UIWindow *window in windowScene.windows) {
      if (window.isKeyWindow) {
        return window;
      }
    }
    for (UIWindow *window in windowScene.windows) {
      if (!window.hidden) {
        return window;
      }
    }
  }
  return nil;
}

- (void)finishChallengeForGeneration:(NSUInteger)generation
                               token:(NSString *)token
                        errorMessage:(NSString *)errorMessage {
  if (self.pendingResult == nil || self.challengeGeneration != generation) {
    return;
  }

  FlutterResult pendingResult = self.pendingResult;
  self.pendingResult = nil;
  [self tearDownChallenge];

  if (errorMessage == nil && token.length > 0) {
    pendingResult(token);
  } else {
    pendingResult([FlutterError errorWithCode:@"hcaptcha_failed"
                                      message:errorMessage ?: @"hCaptcha challenge failed."
                                      details:nil]);
  }
}

- (void)cancelPendingChallenge {
  FlutterResult pendingResult = self.pendingResult;
  self.pendingResult = nil;
  [self tearDownChallenge];
  if (pendingResult != nil) {
    pendingResult([FlutterError errorWithCode:@"challenge_cancelled"
                                      message:@"hCaptcha challenge was cancelled."
                                      details:nil]);
  }
}

- (void)tearDownChallenge {
  // Invalidate callbacks before releasing the SDK-owned WebView.
  self.challengeGeneration += 1;

  // End any WebKit text session before removing the WKWebView. This avoids
  // leaving UIKit with a stale RTI input session during page transitions.
  [self.webView endEditing:YES];
  [self.hCaptcha stop];

  [self.webView removeFromSuperview];
  self.webView = nil;
  [self.overlayView removeFromSuperview];
  self.overlayView = nil;
  self.hCaptcha = nil;
}

/**
 * This method recursively iterate through the view hierarchy
 * to return the top most view controller.
 *
 * It supports the following scenarios:
 *
 * - The view controller is presenting another view.
 * - The view controller is a UINavigationController.
 * - The view controller is a UITabBarController.
 *
 * @return The top most view controller.
 */
- (UIViewController *)topViewControllerFromViewController:(UIViewController *)viewController {
  if (viewController == nil) {
    return nil;
  }
  if ([viewController isKindOfClass:[UINavigationController class]]) {
    UINavigationController *navigationController = (UINavigationController *)viewController;
    return [self
        topViewControllerFromViewController:[navigationController.viewControllers lastObject]];
  }
  if ([viewController isKindOfClass:[UITabBarController class]]) {
    UITabBarController *tabController = (UITabBarController *)viewController;
    return [self topViewControllerFromViewController:tabController.selectedViewController];
  }
  if (viewController.presentedViewController) {
    return [self topViewControllerFromViewController:viewController.presentedViewController];
  }
  return viewController;
}

@end
