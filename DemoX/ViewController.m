//
//  ViewController.m
//  DemoX
//
//  Created by Lun on 2017/9/19.
//  Copyright © 2017年 Lun. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>
#import "LocalDetector.h"
#import "PEAServer.h"
#import "DMXError.h"
#import "ViewController.h"

static const NSString *kDefaultServerAddress = @"192.168.0.7:8080";
static const float kTrackingConfidenceThreshold = 0.8f;
static const float kLandmarksDotsRadius = 6.0f;

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate, UITextFieldDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate> {
    AVCaptureSession *_session;
    CAShapeLayer *_shapeLayer;
    AVCaptureVideoPreviewLayer *_previewLayer;
    AVCaptureDevicePosition _currentCameraPosition;
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
    
    [self requestServerAddress];
    
    _willTransfer = NO;
    _viewBoundsSize = self.view.bounds.size;
    _detector = [[LocalDetector alloc] init];
    
    [self setupSession];
    [self setupVisibles];
    [self setupButtons];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    _shapeLayer.frame = self.view.frame;
    _previewLayer.frame = self.view.frame;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    [self.view.layer insertSublayer:_previewLayer atIndex:0];
    
    _shapeLayer.strokeColor = UIColor.redColor.CGColor;
    _shapeLayer.lineWidth = 2.0f;
    [_shapeLayer setAffineTransform:CGAffineTransformMakeScale(-1, -1)];
    
    [self.view.layer insertSublayer:_shapeLayer above:_previewLayer];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewControllerLog:(NSString *)content {
    NSLog(@"%@", [NSString stringWithFormat:@"[ViewController] %@", content]);
}

#pragma mark - Setup

- (void)requestServerAddress {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Please input server address"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = [NSString stringWithFormat:@"Default %@", kDefaultServerAddress.copy];
        textField.delegate = self;
        textField.textAlignment = NSTextAlignmentCenter;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Confirm"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                _server = [PEAServer serverWithAddress:[NSString stringWithFormat:@"http://%@", alert.textFields[0].text]];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Use default address"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                _server = [PEAServer serverWithAddress:[NSString stringWithFormat:@"http://%@", kDefaultServerAddress.copy]];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Search in LAN"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                _server = [PEAServer serverWithAddress:nil];
                                            }]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)setupVisibles {
    _shapeLayer = [[CAShapeLayer alloc] init];
    
    _previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:_session];
    _previewLayer.videoGravity = kCAGravityResizeAspectFill;
    
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
                                                [_session stopRunning];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Take a photo"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                [self showImagePickerForSourceType:UIImagePickerControllerSourceTypeCamera];
                                                [_session stopRunning];
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
    if (_session) {
        [_session beginConfiguration];
        
        AVCaptureInput *currentInput = _session.inputs[0];
        AVCaptureDevice *newCamera = [self cameraWithPreviousPosition:((AVCaptureDeviceInput *)currentInput).device.position];
        
        [_session removeInput:currentInput];
        NSError *error;
        AVCaptureDeviceInput *newInput = [[AVCaptureDeviceInput alloc] initWithDevice:newCamera
                                                                                error:&error];
        if (error)
            [self viewControllerLog:[NSString stringWithFormat:@"Cannot init device input: %@", error.localizedDescription]];
        _currentCameraPosition = newCamera.position;
        if ([_session canAddInput:newInput]) [_session addInput:newInput];
        
        [_session commitConfiguration];
    } else {
        [self viewControllerLog:@"No session!"];
    }
}

- (void)setButton:(UIButton *)button
        withTitle:(NSString *)title
        newTarget:(SEL)sel {
    [button setTitle:title forState:UIControlStateNormal];
    [button removeTarget:self action:nil forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:sel forControlEvents:UIControlEventTouchDown];
}

#pragma mark - AVCaptureSession

- (void)setupSession {
    _session = [[AVCaptureSession alloc] init];
    AVCaptureDevice *defaultCamera = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                                        mediaType:AVMediaTypeVideo
                                                                         position:AVCaptureDevicePositionFront];
    
    @try {
        [_session beginConfiguration];
        
        NSError *error;
        AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:defaultCamera
                                                                                  error:&error];
        if (error)
            [self viewControllerLog:[NSString stringWithFormat:@"Cannot init device input: %@", error.localizedDescription]];
        _currentCameraPosition = AVCaptureDevicePositionFront;
        if ([_session canAddInput:deviceInput]) [_session addInput:deviceInput];
        
        AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];
        videoOutput.videoSettings = @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)};
        videoOutput.alwaysDiscardsLateVideoFrames = YES;
        [videoOutput setSampleBufferDelegate:self
                                       queue:dispatch_queue_create("com.lun.demox.videooutput.queue", NULL)];
        if ([_session canAddOutput:videoOutput]) [_session addOutput:videoOutput];
        
        [_session commitConfiguration];
        [_session startRunning];
    }
    @catch (NSException *exception) {
        [self viewControllerLog:@"Session setup failed!"];
    }
}

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    if (_willTransfer) [_session stopRunning];
    BOOL doTransfer = _willTransfer;
    
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate);
    
    CIImage *ciImage = [CIImage imageWithCVImageBuffer:pixelBuffer
                                               options:(__bridge NSDictionary *)attachments];
    if (_currentCameraPosition == AVCaptureDevicePositionBack) 
        ciImage = [ciImage imageByApplyingOrientation:UIImageOrientationUpMirrored];
    ciImage = [ciImage imageByApplyingOrientation:UIImageOrientationLeftMirrored];
    
    __weak ViewController *weakSelf = self;
    [_detector detectFaceLandmarksInCIImage:ciImage
                trackingConfidenceThreshold:kTrackingConfidenceThreshold
                        didFindFaceCallback:^(LDRFaceDetectionEvent event, CGRect faceBoundingBox) {
                            if (event == LDRFaceNotFound) {
                                [weakSelf clearShapeLayer];
                            } else if (event == LDRFaceFoundByDetection) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [weakSelf drawRectangle:[weakSelf scaleRect:faceBoundingBox toSize:_viewBoundsSize]];
                                });
                            }
                            
                            if (doTransfer) {
                                if (!event) [weakSelf presentError:@"No face found"];
                                else if (!_selectedPhoto) [weakSelf presentError:@"Please select a photo"];
                                else [weakSelf transferWithCIImage:ciImage inBoundingBox:[weakSelf scaleRect:faceBoundingBox toSize:ciImage.extent.size]];
                                
                                _willTransfer = NO;
                                if (!event || !_selectedPhoto) [_session startRunning];
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

- (AVCaptureDevice *)cameraWithPreviousPosition:(const AVCaptureDevicePosition)previousPosition {
    switch (previousPosition) {
        case AVCaptureDevicePositionFront:
        case AVCaptureDevicePositionBack:
            return [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                      mediaType:AVMediaTypeVideo
                                                       position:previousPosition == AVCaptureDevicePositionFront? AVCaptureDevicePositionBack: AVCaptureDevicePositionFront];
        default:
            [self viewControllerLog:@"Previous position of camera not specified!"];
            return nil;
    }
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
    [_session startRunning];
    
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
    [_session startRunning];
}

#pragma mark - Upload / Download

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
                  [_session startRunning];
              } else if (response) {
                  [weakSelf viewControllerLog:@"Received stylized image"];
                  [weakSelf displayStylizedImage:[UIImage imageWithData:response[@"binaryData"]]
                                       WithTitle:response[@"title"]
                                             URL:response[@"url"]];
              } else {
                  [weakSelf presentError:@"No data received"];
                  [_session startRunning];
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
        [_session startRunning];
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Success!"
                                                                       message:@"Please view your artwork in the album."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Great"
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentViewController:alert animated:YES completion:nil];
            [_session startRunning];
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
                                                                             [_session startRunning];
                                                                         }];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Return"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                [alert dismissViewControllerAnimated:YES completion:nil];
                                                [_session startRunning];
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
