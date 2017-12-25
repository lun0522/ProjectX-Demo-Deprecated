//
//  ViewController.m
//  DemoX
//
//  Created by Lun on 2017/9/19.
//  Copyright © 2017年 Lun. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>
#import "VideoLayer.h"
#import "LocalDetector.h"
#import "PEAServer.h"
#import "DMXError.h"
#import "ViewController.h"

static const NSString *kDefaultServerAddress = @"192.168.0.7:8080";
static const float kLandmarksDotsRadius = 6.0f;

@interface ViewController () <UITextFieldDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, VideoCaptureDelegate> {
    VideoLayer *_videoLayer;
    CAShapeLayer *_shapeLayer;
    UIImagePickerController *_imagePickerController;
    UIVisualEffectView *_blurEffectView;
    UIActivityIndicatorView *_transferIndicator;
    
    BOOL _willTransfer;
    CGSize _viewBoundsSize;
    LocalDetector *_detector;
    PEAServer *_server;
    UIImage *_selectedPhoto;
    NSString *_photoTimestamp;
}

@property (weak, nonatomic) IBOutlet UIButton *selectPhotoButton;
@property (weak, nonatomic) IBOutlet UIButton *captureFaceButton;
@property (weak, nonatomic) IBOutlet UIButton *switchCameraButton;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _willTransfer = NO;
    _viewBoundsSize = self.view.bounds.size;
    _detector = [[LocalDetector alloc] init];
    _server = [[PEAServer alloc] init];
    
    [self setupVisibles];
    [self setupButtons];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    [_videoLayer setFrameRect:self.view.frame];
    _shapeLayer.frame = self.view.frame;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    [self.view.layer insertSublayer:_videoLayer atIndex:0];
    
    _shapeLayer.strokeColor = UIColor.redColor.CGColor;
    _shapeLayer.lineWidth = 2.0f;
    [_shapeLayer setAffineTransform:CGAffineTransformMakeScale(-1, -1)];
    
    [self.view.layer insertSublayer:_shapeLayer above:_videoLayer];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewControllerLog:(NSString *)content {
    NSLog(@"%@", [NSString stringWithFormat:@"[ViewController] %@", content]);
}

#pragma mark - Setup

- (void)setupVisibles {
    _shapeLayer = [[CAShapeLayer alloc] init];
    _videoLayer = [[VideoLayer alloc] init];
    [_videoLayer setCapturerDelegate:self];
    
    _blurEffectView = [[UIVisualEffectView alloc] init];
    _blurEffectView.frame = self.view.frame;
    
    _transferIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _transferIndicator.center = CGPointMake(self.view.center.x, self.view.center.y);
    _transferIndicator.hidesWhenStopped = YES;
}

- (void)setupButtons {
    _selectPhotoButton.layer.cornerRadius = 8.0f;
    _selectPhotoButton.layer.borderWidth = 1.0f;
    _selectPhotoButton.layer.borderColor = _switchCameraButton.tintColor.CGColor;
    [_selectPhotoButton addTarget:self
                           action:@selector(tapSelectPhoto)
                 forControlEvents:UIControlEventTouchDown];
    
    _switchCameraButton.layer.cornerRadius = 8.0f;
    _switchCameraButton.layer.borderWidth = 1.0f;
    _switchCameraButton.layer.borderColor = _switchCameraButton.tintColor.CGColor;
    [_switchCameraButton addTarget:self
                            action:@selector(tapSwitchCamera)
                  forControlEvents:UIControlEventTouchDown];
    
    _captureFaceButton.layer.cornerRadius = 8.0f;
    _captureFaceButton.layer.borderWidth = 1.0f;
    _captureFaceButton.layer.borderColor = _captureFaceButton.tintColor.CGColor;
    [_captureFaceButton addTarget:self
                           action:@selector(tapCaptureFace)
                 forControlEvents:UIControlEventTouchDown];
}

#pragma mark - Buttons methods

- (void)tapSelectPhoto {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"From album"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                [self showImagePickerForSourceType:UIImagePickerControllerSourceTypePhotoLibrary];
                                                [_videoLayer stop];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Take a photo"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                [self showImagePickerForSourceType:UIImagePickerControllerSourceTypeCamera];
                                                [_videoLayer stop];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)tapCaptureFace {
    _willTransfer = YES;
}

- (void)tapSwitchCamera {
    [_videoLayer switchCamera];
}

#pragma mark - Image picker

- (void)showImagePickerForSourceType:(UIImagePickerControllerSourceType)sourceType {
    _imagePickerController = [[UIImagePickerController alloc] init];
    _imagePickerController.sourceType = sourceType;
    _imagePickerController.delegate = self;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:_imagePickerController animated:YES completion:nil];
    });
}

- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
    [self dismissViewControllerAnimated:YES completion:nil];
    _imagePickerController = nil;
    [_videoLayer start];
    
    if (_photoTimestamp) [self deleteLastUploadedPhoto];
    _selectedPhoto = info[UIImagePickerControllerOriginalImage];
    
    // rotate the retrieved image
    UIGraphicsBeginImageContextWithOptions(_selectedPhoto.size, NO, _selectedPhoto.scale);
    [_selectedPhoto drawInRect:(CGRect){0, 0, _selectedPhoto.size}];
    _selectedPhoto = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    _photoTimestamp = [NSString stringWithFormat:@"%lu", (NSUInteger)([[NSDate date] timeIntervalSince1970] * 1000)];
    [self uploadSelectedPhoto];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [self dismissViewControllerAnimated:YES completion:nil];
    _imagePickerController = nil;
    [_videoLayer start];
}

#pragma mark - Video capture

- (void)didCaptureFrame:(CIImage *)frame {
    if (_willTransfer) [_videoLayer stop];
    BOOL doTransfer = _willTransfer;
    
    __weak ViewController *weakSelf = self;
    [_detector detectFaceLandmarksInCIImage:frame
                        didFindFaceCallback:^(LDRFaceDetectionEvent event, CGRect faceBoundingBox) {
                            if (event == LDRFaceNotFound) {
                                [weakSelf clearShapeLayer];
                            } else if (event == LDRFaceFoundByDetection) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [weakSelf drawRectangle:[weakSelf scaleRect:faceBoundingBox toSize:_viewBoundsSize]];
                                });
                            }
                            
                            if (doTransfer) {
                                if (event == LDRFaceNotFound) [weakSelf presentError:@"No face found"];
                                else if (!_selectedPhoto) [weakSelf presentError:@"Please select a photo"];
                                else [weakSelf transferWithCIImage:frame inBoundingBox:[weakSelf scaleRect:faceBoundingBox toSize:frame.extent.size]];
                                
                                _willTransfer = NO;
                                if (event == LDRFaceNotFound || !_selectedPhoto) [_videoLayer start];
                            }
                        }
                              resultHandler:^(NSArray * _Nullable points, NSError * _Nullable error) {
                                  if (error) {
                                      [weakSelf presentError:error.localizedDescription];
                                  } else {
                                      [weakSelf clearShapeLayer];
                                      [weakSelf drawPoints:points
                                                 withColor:UIColor.redColor.CGColor];
                                  }
                              }];
}

#pragma mark - Upload

- (void)uploadSelectedPhoto {
    __weak ViewController *weakSelf = self;
    [_server sendData:UIImageJPEGRepresentation(_selectedPhoto, 1.0)
      withHeaderField:@{@"Timestamp": _photoTimestamp}
            operation:PEAServerStore
              timeout:30
      responseHandler:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
          if (error) [weakSelf presentError:error.localizedDescription];
          else [weakSelf viewControllerLog:@"Uploaded selected photo"];
      }];
}

- (void)deleteLastUploadedPhoto {
    // the request will be cancelled immediately if no body data is appended,
    // so pass an empty NSData here
    __weak ViewController *weakSelf = self;
    [_server sendData:[[NSData alloc] init]
      withHeaderField:@{@"Timestamp": _photoTimestamp}
            operation:PEAServerDelete
              timeout:10
      responseHandler:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
          if (error) [weakSelf presentError:error.localizedDescription];
          else [weakSelf viewControllerLog:@"Deleted the last uploaded photo"];
      }];
}

- (void)transferWithCIImage:(CIImage *)ciImage
              inBoundingBox:(CGRect)boundingBox {
    [self onProcessingAnimation];
    
    // the face part should be cropped down and mirrored
    CIImage *faceImage = [ciImage imageByCroppingToRect:boundingBox];
    CIImage *faceImageMirrored = [faceImage imageByApplyingTransform:CGAffineTransformMakeScale(-1, 1)];
    
    // should convert CIImage to CGImage, and then to UIImage
    // otherwise UIImageJPEGRepresentation() will return nil
    CIContext *context = [[CIContext alloc] initWithOptions:nil];
    CGImageRef cgImage = [context createCGImage:faceImageMirrored
                                       fromRect:faceImageMirrored.extent];
    
    __weak ViewController *weakSelf = self;
    [_server sendData:UIImageJPEGRepresentation([UIImage imageWithCGImage:cgImage], 1.0)
      withHeaderField:@{@"Timestamp": _photoTimestamp}
            operation:PEAServerTransfer
              timeout:120
      responseHandler:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
          [self endProcessingAnimationWithCompletionHandler:^{
              if (error) {
                  [weakSelf presentError:error.localizedDescription];
                  [_videoLayer start];
              } else if (response) {
                  [weakSelf viewControllerLog:@"Received stylized image"];
                  [weakSelf displayStylizedImage:[UIImage imageWithData:response[@"binaryData"]]
                                       WithTitle:response[@"title"]
                                             URL:response[@"url"]];
              } else {
                  [weakSelf presentError:@"No data received"];
                  [_videoLayer start];
              }
          }];
      }];
}

#pragma mark - UI

- (void)clearShapeLayer {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (CAShapeLayer *layer in [_shapeLayer.sublayers copy])
            [layer removeFromSuperlayer];
    });
}

- (void)drawPoints:(const NSArray<NSValue *> *)points
         withColor:(const CGColorRef)color {
    dispatch_async(dispatch_get_main_queue(), ^{
        [points enumerateObjectsUsingBlock:^(NSValue * _Nonnull point,
                                             NSUInteger idx,
                                             BOOL * _Nonnull stop) {
            CAShapeLayer *pointLayer = [[CAShapeLayer alloc] init];
            [pointLayer setFillColor:UIColor.redColor.CGColor];
            CGRect dotRect = CGRectMake(point.CGPointValue.x * _viewBoundsSize.width - kLandmarksDotsRadius / 2,
                                        point.CGPointValue.y * _viewBoundsSize.height - kLandmarksDotsRadius / 2,
                                        kLandmarksDotsRadius, kLandmarksDotsRadius);
            pointLayer.path = [UIBezierPath bezierPathWithOvalInRect:dotRect].CGPath;
            [_shapeLayer addSublayer:pointLayer];
        }];
    });
}

- (void)drawRectangle:(CGRect)rect {
    dispatch_async(dispatch_get_main_queue(), ^{
        CAShapeLayer *rectLayer = [[CAShapeLayer alloc] init];
        [rectLayer setFillColor:UIColor.clearColor.CGColor];
        [rectLayer setStrokeColor:UIColor.redColor.CGColor];
        rectLayer.path = [UIBezierPath bezierPathWithRect:rect].CGPath;
        [_shapeLayer addSublayer:rectLayer];
    });
}

- (CGRect)scaleRect:(CGRect)rect toSize:(CGSize)size {
    return CGRectMake(rect.origin.x * size.width,
                      rect.origin.y * size.height,
                      rect.size.width * size.width,
                      rect.size.height * size.height);
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

- (void)endProcessingAnimationWithCompletionHandler:(void (^)(void))handler {
    dispatch_async(dispatch_get_main_queue(), ^{
        [_transferIndicator stopAnimating];
        [_transferIndicator removeFromSuperview];
        
        [UIView animateWithDuration:0.3 animations:^{
            _blurEffectView.effect = nil;
        } completion:^(BOOL finished) {
            [_blurEffectView removeFromSuperview];
            handler();
        }];
    });
}

- (void)image:(UIImage *)image
didFinishSavingWithError:(NSError *)error
  contextInfo:(void *)contextInfo {
    if (error) {
        [self presentError:error.localizedDescription];
        [_videoLayer start];
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Success!"
                                                                       message:@"Please view your artwork in the album."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Great"
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentViewController:alert animated:YES completion:nil];
            [_videoLayer start];
        });
    }
}

- (void)displayStylizedImage:(UIImage *)image
                   WithTitle:(NSString *)title
                         URL:(NSString *)url {
    CGSize newSize = CGSizeMake(245.0, 245.0 * image.size.height / image.size.width);
    UIGraphicsBeginImageContextWithOptions(newSize, NO, 0.0);
    [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *imagePlaceholder = [UIAlertAction actionWithTitle:@"placeholder"
                                                               style:UIAlertActionStyleDefault
                                                             handler:nil];
    [imagePlaceholder setValue:[resizedImage imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    [imagePlaceholder setEnabled:NO];
    [alert addAction:imagePlaceholder];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save to album"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                UIImageWriteToSavedPhotosAlbum(image, self, @selector(image:didFinishSavingWithError:contextInfo:), nil);
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"View painting"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]
                                                                                   options:@{}
                                                                         completionHandler:^(BOOL success) {
                                                                             [_videoLayer start];
                                                                         }];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Return"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                [alert dismissViewControllerAnimated:YES completion:nil];
                                                [_videoLayer start];
                                            }]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alert animated:YES completion:nil];
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
