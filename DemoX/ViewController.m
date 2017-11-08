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
static const NSString *kUploadPhotoButtonTitle = @"Upload Photo";
static const NSString *kContinueButtonTitle = @"Continue";
static const float kTrackingConfidenceThreshold = 0.8;

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate, UITextFieldDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate> {
    AVCaptureSession *_session;
    CAShapeLayer *_shapeLayer;
    AVCaptureVideoPreviewLayer *_previewLayer;
    AVCaptureDevicePosition _currentCameraPosition;
    UIImagePickerController *_imagePickerController;
    
    BOOL _willTransfer;
    LocalDetector *_detector;
    PEAServer *_server;
    NSDictionary *_serverLandmarksMap;
    CGSize _viewBoundsSize;
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
                                                _serverLandmarksMap = [_server getLandmarksMap];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Use default address"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                _server = [PEAServer serverWithAddress:[NSString stringWithFormat:@"http://%@", kDefaultServerAddress.copy]];
                                                _serverLandmarksMap = [_server getLandmarksMap];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Search in LAN"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                _server = [PEAServer serverWithAddress:nil];
                                                _serverLandmarksMap = [_server getLandmarksMap];
                                            }]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alert animated:YES completion:nil];
        
        _detector = [[LocalDetector alloc] init];
        _viewBoundsSize = self.view.bounds.size;
    });
    
    [self setupSession];
    _shapeLayer = [[CAShapeLayer alloc] init];
    _previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:_session];
    _previewLayer.videoGravity = kCAGravityResizeAspectFill;
    _willTransfer = NO;
    
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

- (void)presentError:(NSString *)description {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                   message:description
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)viewControllerLog:(NSString *)content {
    NSLog(@"%@", [NSString stringWithFormat:@"[ViewController] %@", content]);
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
                                                [self sessionPauseRunning];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Take a photo"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                [self showImagePickerForSourceType:UIImagePickerControllerSourceTypeCamera];
                                                [self sessionPauseRunning];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)tapCaptureFace {
    _willTransfer = YES;
}

- (void)tapContinue {
    _willTransfer = NO;
    [self sessionContinueRunning];
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
    if (_willTransfer) [self sessionPauseRunning];
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
                        didFindFaceCallback:^(BOOL hasFace, CGRect faceBoundingBox) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                for (CAShapeLayer *layer in [_shapeLayer.sublayers copy])
                                    [layer removeFromSuperlayer];
                            });
                            
                            if (doTransfer) {
                                if (!hasFace) [weakSelf presentError:@"No face found"];
                                else if (!_selectedPhoto) [weakSelf presentError:@"Please select a photo"];
                                else [weakSelf transferWithCIImage:ciImage inBoundingBox:faceBoundingBox];
                            }
                        }
                              resultHandler:^(NSArray * _Nullable points, NSError * _Nullable error) {
                                  if (error) [self presentError:error.localizedDescription];
                                  else [weakSelf drawLineFromPoints:points
                                                            inRange:NSMakeRange(0, points.count)
                                                          withColor:UIColor.redColor.CGColor
                                                              scale:_viewBoundsSize];
                        }];
}

- (void)sessionContinueRunning {
    [_session startRunning];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setButton:_captureFaceButton
              withTitle:kUploadPhotoButtonTitle.copy
              newTarget:@selector(tapCaptureFace)];
    });
}

- (void)sessionPauseRunning {
    [_session stopRunning];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setButton:_captureFaceButton
              withTitle:kContinueButtonTitle.copy
              newTarget:@selector(tapContinue)];
    });
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
    [self presentViewController:_imagePickerController animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
    [self dismissViewControllerAnimated:YES completion:nil];
    _imagePickerController = nil;
    [self sessionContinueRunning];
    
    if (_photoTimestamp) [self deleteLastUploadedPhoto];
    _selectedPhoto = info[UIImagePickerControllerOriginalImage];
    _photoTimestamp = [NSString stringWithFormat:@"%lu", (NSUInteger)([[NSDate date] timeIntervalSince1970] * 1000)];
    [self uploadSelectedPhoto];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [self dismissViewControllerAnimated:YES completion:nil];
    _imagePickerController = nil;
    [self sessionContinueRunning];
}

#pragma mark - Upload / Download

- (void)uploadSelectedPhoto {
    [_server sendData:UIImageJPEGRepresentation(_selectedPhoto, 1.0)
      withHeaderField:@{@"Timestamp": _photoTimestamp}
            operation:PEAServerStore
              timeout:30
      responseHandler:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
          if (error) [self presentError:error.localizedDescription];
          else [self viewControllerLog:@"Uploaded selected photo"];
      }];
}

- (void)deleteLastUploadedPhoto {
    // the request will be canceled immediately if no body data is appended,
    // so pass an empty NSData here
    [_server sendData:[[NSData alloc] init]
      withHeaderField:@{@"Timestamp": _photoTimestamp}
            operation:PEAServerDelete
              timeout:10
      responseHandler:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
          if (error) [self presentError:error.localizedDescription];
          else [self viewControllerLog:@"Deleted the last uploaded photo"];
      }];
}

- (void)transferWithCIImage:(CIImage *)ciImage
              inBoundingBox:(CGRect)boundingBox {
    // the face part should be cropped down and mirrored
    CIImage *faceImage = [ciImage imageByCroppingToRect:boundingBox];
    CIImage *faceImageMirrored = [faceImage imageByApplyingTransform:CGAffineTransformMakeScale(-1, 1)];
    CGSize scaleImageToScreen = CGSizeMake(_viewBoundsSize.width / ciImage.extent.size.width,
                                           _viewBoundsSize.height / ciImage.extent.size.height);
    
    // should convert CIImage to CGImage, and then to UIImage
    // otherwise UIImageJPEGRepresentation() will return nil
    CIContext *context = [[CIContext alloc] initWithOptions:nil];
    CGImageRef cgImage = [context createCGImage:faceImageMirrored
                                       fromRect:faceImageMirrored.extent];
    
    [_server sendData:UIImageJPEGRepresentation([UIImage imageWithCGImage:cgImage], 1.0)
      withHeaderField:@{@"Timestamp": _photoTimestamp}
            operation:PEAServerTransfer
              timeout:120
      responseHandler:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
          if (error) {
              [self presentError:error.localizedDescription];
          } else {
              if (response[@"Stylized"]) {
                  NSData *imageData = [[NSData alloc]initWithBase64EncodedString:response[@"Stylized"]
                                                                         options:NSDataBase64DecodingIgnoreUnknownCharacters];
                  [self displayStylizedImage:[UIImage imageWithData:imageData]];
              } else if (response[@"Landmarks"]) {
                  NSArray<NSArray<NSNumber *> *> *landmarks = response[@"Landmarks"];
                  if (landmarks.class == NSNull.class) [self presentError:@"Server found no face"];
                  else {
                      if (landmarks.count == 68) {
                          NSMutableArray *points = [[NSMutableArray alloc] initWithCapacity:68];
                          for (NSUInteger idx = 0; idx < 68; ++idx) {
                              points[idx] = [NSValue valueWithCGPoint:
                                             CGPointMake(boundingBox.size.width - landmarks[idx][0].floatValue
                                                         + boundingBox.origin.x,
                                                         boundingBox.size.height - landmarks[idx][1].floatValue
                                                         + boundingBox.origin.y)];
                          }
                          [_serverLandmarksMap enumerateKeysAndObjectsUsingBlock:
                           ^(NSString * _Nonnull landmarkName,
                             NSValue * _Nonnull range,
                             BOOL * _Nonnull stop) {
                               [self drawLineFromPoints:points
                                                inRange:[range rangeValue]
                                              withColor:UIColor.blueColor.CGColor
                                                  scale:scaleImageToScreen];
                           }];
                      } else {
                          [self viewControllerLog:@"Less than 68 points returned by server"];
                      }
                  }
              }
          }
      }];
}

#pragma mark - UI

- (void)displayStylizedImage:(UIImage *)image {
    [self viewControllerLog:@"Received stylized image"];
}

- (void)drawLineFromPoints:(const NSArray<NSValue *> *)points
                   inRange:(const NSRange)range
                 withColor:(const CGColorRef)color
                     scale:(CGSize)scale {
    CAShapeLayer *newLayer = [[CAShapeLayer alloc] init];
    newLayer.strokeColor = color;
    newLayer.lineWidth = 2.0f;
    newLayer.fillColor = UIColor.clearColor.CGColor;
    
    UIBezierPath *path = [[UIBezierPath alloc] init];
    [path moveToPoint:CGPointMake(points[range.location].CGPointValue.x * scale.width,
                                  points[range.location].CGPointValue.y * scale.height)];
    
    for (NSUInteger idx = range.location; idx < NSMaxRange(range); ++idx) {
        [path addLineToPoint:CGPointMake(points[idx].CGPointValue.x * scale.width,
                                         points[idx].CGPointValue.y * scale.height)];
    }
    newLayer.path = path.CGPath;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [_shapeLayer addSublayer:newLayer];
    });
}

@end
