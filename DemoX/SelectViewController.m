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
    NSMutableArray<NSNumber *> *_paintingsId;
    UIImage *_stylizedImage;
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
    
    [_paintingView setContentMode:UIViewContentModeScaleAspectFit];
    self.view.backgroundColor = UIColor.blackColor;
    
    _portraits = [NSMutableArray arrayWithCapacity:3];
    _paintings = [NSMutableArray arrayWithCapacity:3];
    _paintingsId = [NSMutableArray arrayWithCapacity:3];
    
    UIBarButtonItem *rightBarItem = [[UIBarButtonItem alloc] initWithTitle:@"Use It!"
                                                                     style:UIBarButtonItemStylePlain
                                                                    target:self
                                                                    action:@selector(pushStylized)];
    self.navigationItem.rightBarButtonItem = rightBarItem;
    
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
                  
                  NSArray *infoArray = [NSJSONSerialization JSONObjectWithData:[response[@"info"] dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:nil];
                  for (NSDictionary *info in infoArray) {
                      [_paintingsId addObject:info[@"Painting-Id"]];
                      
                      NSUInteger paintingDataLength = ((NSNumber *)info[@"Painting-Length"]).unsignedIntegerValue;
                      NSData *paintingData = [NSData dataWithBytesNoCopy:(char *)data.bytes + offset
                                                                  length:paintingDataLength
                                                            freeWhenDone:NO];
                      [_paintings addObject:[UIImage imageWithData:paintingData]];
                      offset += paintingDataLength;
                      
                      NSUInteger portraitDataLength = ((NSNumber *)info[@"Portrait-Length"]).unsignedIntegerValue;
                      NSData *portraitData = [NSData dataWithBytesNoCopy:(char *)data.bytes + offset
                                                                  length:portraitDataLength
                                                            freeWhenDone:NO];
                      [_portraits addObject:[UIImage imageWithData:portraitData]];
                      offset += portraitDataLength;
                  }
                  
                  _portraitView0.image = _portraits[0];
                  _portraitView1.image = _portraits[1];
                  _portraitView2.image = _portraits[2];
                  _paintingView.image = _paintings[0];
                  _selectedPainting = 0;
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

- (void)pushStylized {
    [self onProcessingAnimation];
    __weak typeof(self) weakSelf = self;
    [_server sendData:[NSData data]
     withHeaderFields:@{@"Photo-Timestamp": _photoTimestamp,
                        @"Style-Id": _paintingsId[_selectedPainting].stringValue}
            operation:PEAServerTransfer
              timeout:300
      responseHandler:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
          [weakSelf endProcessingAnimationWithBlock:^{
              _stylizedImage = [UIImage imageWithData:response[@"data"]];
              [weakSelf performSegueWithIdentifier:@"ShowStylized" sender:self];
          }];
      }];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    ((StylizedViewController *)segue.destinationViewController).stylizedImage = _stylizedImage;
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
