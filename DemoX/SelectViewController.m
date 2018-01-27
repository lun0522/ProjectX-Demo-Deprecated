//
//  SelectViewController.m
//  DemoX
//
//  Created by Pujun Lun on 1/26/18.
//  Copyright © 2018 Lun. All rights reserved.
//

#import "PEAServer.h"
#import "StylizedViewController.h"
#import "SelectViewController.h"

@interface SelectViewController () {
    NSUInteger _selectedPainting;
    UIVisualEffectView *_blurEffectView;
    UIActivityIndicatorView *_transferIndicator;
    NSMutableArray<UIImage *> *_portraits;
    NSMutableArray<UIImage *> *_paintings;
    NSMutableArray<NSString *> *_paintingsId;
    NSMutableArray<NSString *> *_paintingsTitle;
}

@property (weak, nonatomic) IBOutlet UIImageView *paintingView;
@property (weak, nonatomic) IBOutlet UIImageView *portraitView0;
@property (weak, nonatomic) IBOutlet UIImageView *portraitView1;
@property (weak, nonatomic) IBOutlet UIImageView *portraitView2;
- (IBAction)tapPortrait0:(id)sender;
- (IBAction)tapPortrait1:(id)sender;
- (IBAction)tapPortrait2:(id)sender;

@end

@implementation SelectViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    _blurEffectView = [[UIVisualEffectView alloc] init];
    _blurEffectView.frame = self.view.frame;

    _transferIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _transferIndicator.center = CGPointMake(self.view.center.x, self.view.center.y);
    _transferIndicator.hidesWhenStopped = YES;
    
    _portraits = [NSMutableArray arrayWithCapacity:3];
    _paintings = [NSMutableArray arrayWithCapacity:3];
    _paintingsId = [NSMutableArray arrayWithCapacity:3];
    _paintingsTitle = [NSMutableArray arrayWithCapacity:3];
    
    [self retrievePainting];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewControllerLog:(NSString *)content {
    NSLog(@"%@", [NSString stringWithFormat:@"[SelectViewController] %@", content]);
}

- (void)retrievePainting {
    [self onProcessingAnimation];
    __weak typeof(self) weakSelf = self;
    [_server sendData:UIImageJPEGRepresentation(_selfie, 1.0)
     withHeaderFields:nil
            operation:PEAServerRetrieve
              timeout:120
      responseHandler:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
          [self endProcessingAnimationWithBlock:^{
              if (error) {
                  [weakSelf presentError:error.localizedDescription];
              } else if (response) {
                  [weakSelf viewControllerLog:@"Retrieved images"];
                  NSData *data = response[@"data"];
                  NSUInteger offset = 0;
                  for (NSDictionary *info in response) {
                      NSUInteger portraitDataLength = ((NSNumber *)info[@"Portrait-Length"]).unsignedIntegerValue;
                      NSData *portraitData = [NSData dataWithBytesNoCopy:(char *)data.bytes + offset
                                                                  length:portraitDataLength
                                                            freeWhenDone:NO];
                      [_portraits addObject:[UIImage imageWithData:portraitData]];
                      offset += portraitDataLength;
                      
                      NSUInteger paintingDataLength = ((NSNumber *)info[@"Painting-Length"]).unsignedIntegerValue;
                      NSData *paintingData = [NSData dataWithBytesNoCopy:(char *)data.bytes + offset
                                                                  length:paintingDataLength
                                                            freeWhenDone:NO];
                      [_paintings addObject:[UIImage imageWithData:paintingData]];
                      offset += paintingDataLength;
                      
                      [_paintingsId addObject:info[@"Painting-Id"]];
                      [_paintingsTitle addObject:info[@"Painting-Title"]];
                  }
              } else {
                  [weakSelf presentError:@"No data received"];
              }
          }];
      }];
}

- (IBAction)tapPortrait0:(id)sender {
    if (_selectedPainting != 0) {
        _selectedPainting = 0;
        _paintingView.image = _paintings[0];
    }
}

- (IBAction)tapPortrait1:(id)sender {
    if (_selectedPainting != 1) {
        _selectedPainting = 1;
        _paintingView.image = _paintings[1];
    }
}

- (IBAction)tapPortrait2:(id)sender {
    if (_selectedPainting != 2) {
        _selectedPainting = 2;
        _paintingView.image = _paintings[2];
    }
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    [self onProcessingAnimation];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __weak typeof(self) weakSelf = self;
    [_server sendData:[NSData data]
     withHeaderFields:@{@"Timestamp": _photoTimestamp}
            operation:PEAServerTransfer
              timeout:300
      responseHandler:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
          [weakSelf endProcessingAnimationWithBlock:^{
              StylizedViewController *svc = ((UINavigationController *)segue.destinationViewController).viewControllers[0];
              svc.stylizedImage = [UIImage imageWithData:response[@"data"]];
              dispatch_semaphore_signal(semaphore);
          }];
      }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)onProcessingAnimation {
    dispatch_async(dispatch_get_main_queue(), ^{
        [_transferIndicator startAnimating];
        [self.view addSubview:_blurEffectView];
        
        [UIView animateWithDuration:0.3 animations:^{
            _blurEffectView.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        } completion:^(BOOL finished) {
            [self.view addSubview:_transferIndicator];
        }];
    });
}

- (void)endProcessingAnimationWithBlock:(void (^)(void))block {
    dispatch_async(dispatch_get_main_queue(), ^{
        [_transferIndicator stopAnimating];
        [_transferIndicator removeFromSuperview];
        block();
        
        [UIView animateWithDuration:0.3 animations:^{
            _blurEffectView.effect = nil;
        } completion:^(BOOL finished) {
            [_blurEffectView removeFromSuperview];
        }];
    });
}

- (void)presentError:(NSString *)description {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                   message:description
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alert animated:YES completion:nil];
    });
}

@end
