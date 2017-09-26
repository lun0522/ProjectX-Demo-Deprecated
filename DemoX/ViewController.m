//
//  ViewController.m
//  DemoX
//
//  Created by Lun on 2017/9/19.
//  Copyright © 2017年 Lun. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>
#import "BonjourUtility.h"
#import "ViewController.h"

static const NSString *kAuthenticationString = @"PortableEmotionAnalysis";
static const NSString *kServerAddress = @"http://192.168.0.7:8080";
static const NSString *kUploadPhotoButtonTitle = @"Upload Photo";
static const NSString *kContinueNuttonTitle = @"Continue";
static NSDictionary *kDlibLandmarksMap = nil;

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate, UITextFieldDelegate> {
    AVCaptureSession *_session;
    CAShapeLayer *_shapeLayer;
    AVCaptureVideoPreviewLayer *_previewLayer;
    AVCaptureDevicePosition _currentCameraPosition;
    
    VNDetectFaceRectanglesRequest *_faceDetection;
    VNDetectFaceLandmarksRequest  *_faceLandmarks;
    VNSequenceRequestHandler *_faceDetectionRequest;
    VNSequenceRequestHandler *_faceLandmarksRequest;
    
    CGSize _viewBoundsSize;
    BOOL _shouldStopToUpload;
    NSString *_serverAddress;
    BonjourUtility *_multicast;
}

@property (weak, nonatomic) IBOutlet UIButton *switchCameraButton;
@property (weak, nonatomic) IBOutlet UIButton *uploadPhotoButton;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _multicast = [[BonjourUtility alloc] init];
    [_multicast searchServerWithCompletionHandler:^{
        NSLog(@"Completion block executed");
    }];
    
    // disable locking screen
    [[UIApplication sharedApplication] setIdleTimerDisabled: YES];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Please input server address"
                                                                   message:@""
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Default 192.168.0.7:8080";
        textField.delegate = self;
        textField.textAlignment = NSTextAlignmentCenter;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Confirm"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                _serverAddress = [NSString stringWithFormat:@"http://%@", alert.textFields[0].text];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Use default address"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                _serverAddress = kServerAddress.copy;
                                            }]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alert animated:YES completion:nil];;
    });
    
    _faceDetection = [[VNDetectFaceRectanglesRequest alloc] init];
    _faceLandmarks = [[VNDetectFaceLandmarksRequest alloc] init];
    _faceDetectionRequest = [[VNSequenceRequestHandler alloc] init];
    _faceLandmarksRequest = [[VNSequenceRequestHandler alloc] init];
    
    [self setupSession];
    _shapeLayer = [[CAShapeLayer alloc] init];
    _previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:_session];
    _previewLayer.videoGravity = kCAGravityResizeAspectFill;
    
    _viewBoundsSize = self.view.bounds.size;
    _shouldStopToUpload = NO;
    
    _switchCameraButton.layer.cornerRadius = 8.0f;
    _switchCameraButton.layer.borderWidth = 1.0f;
    _switchCameraButton.layer.borderColor = _switchCameraButton.tintColor.CGColor;
    [_switchCameraButton addTarget:self
                            action:@selector(tapSwitchCamera)
                  forControlEvents:UIControlEventTouchDown];
    
    _uploadPhotoButton.layer.cornerRadius = 8.0f;
    _uploadPhotoButton.layer.borderWidth = 1.0f;
    _uploadPhotoButton.layer.borderColor = _uploadPhotoButton.tintColor.CGColor;
    [_uploadPhotoButton addTarget:self
                           action:@selector(tapUploadPhoto)
                 forControlEvents:UIControlEventTouchDown];
    
    kDlibLandmarksMap = @{
                          @"faceContour" : [NSValue valueWithRange:NSMakeRange(0, 17)],
                          @"leftEyebrow" : [NSValue valueWithRange:NSMakeRange(17, 5)],
                          @"rightEyebrow": [NSValue valueWithRange:NSMakeRange(22, 5)],
                          @"noseCrest"   : [NSValue valueWithRange:NSMakeRange(27, 4)],
                          @"nose"        : [NSValue valueWithRange:NSMakeRange(31, 5)],
                          @"leftEye"     : [NSValue valueWithRange:NSMakeRange(36, 6)],
                          @"rightEye"    : [NSValue valueWithRange:NSMakeRange(42, 6)],
                          @"outerLips"   : [NSValue valueWithRange:NSMakeRange(48,12)],
                          @"innerLips"   : [NSValue valueWithRange:NSMakeRange(60, 8)],
                          };
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
        if (error) NSLog(@"Cannot init device input: %@", error.localizedDescription);
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
        NSLog(@"Session setup failed!");
    }
}

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate);
    
    CIImage *ciImage = [CIImage imageWithCVImageBuffer:pixelBuffer
                                               options:(__bridge NSDictionary *)attachments];
    if (_currentCameraPosition == AVCaptureDevicePositionBack) ciImage = [ciImage imageByApplyingOrientation:UIImageOrientationUpMirrored];
    
    if (_shouldStopToUpload) {
        _shouldStopToUpload = NO;
        [self sessionPauseRunning];
        
        // should convert CIImage to CGImage, and then to UIImage
        // otherwise UIImageJPEGRepresentation() will return nil
        CIContext *context = [[CIContext alloc] initWithOptions:nil];
        CGImageRef cgImage = [context createCGImage:ciImage fromRect:ciImage.extent];
        [self uploadImage:[UIImage imageWithCGImage:cgImage]];
    }
    
    [self detectFaceInCIImage:[ciImage imageByApplyingOrientation:UIImageOrientationLeftMirrored]];
}

- (void)detectFaceInCIImage:(CIImage *)image {
    NSError *error;
    [_faceDetectionRequest performRequests:@[_faceDetection] onCIImage:image error:&error];
    if (error) NSLog(@"Error in face detection: %@", error.localizedDescription);
    
    NSArray *results = _faceDetection.results;
    if (results.count) {
        dispatch_async(dispatch_get_main_queue(), ^{
            for (CAShapeLayer *layer in [_shapeLayer.sublayers copy]) [layer removeFromSuperlayer];
        });
        _faceLandmarks.inputFaceObservations = results;
        [self detectLandmarksInCIImage:image];
    }
}

- (void)detectLandmarksInCIImage:(CIImage *)image {
    NSError *error;
    [_faceLandmarksRequest performRequests:@[_faceLandmarks] onCIImage:image error:&error];
    if (error) NSLog(@"Error in landmarks detection: %@", error.localizedDescription);
    
    NSArray<VNFaceObservation *> *results = _faceLandmarks.results;
    [results enumerateObjectsUsingBlock:^(VNFaceObservation * _Nonnull face,
                                          NSUInteger idx,
                                          BOOL * _Nonnull stop) {
        CGRect boundingBox = ((VNFaceObservation *)_faceLandmarks.inputFaceObservations[idx]).boundingBox;
        CGRect faceBoundingBox = [self scaleRect:boundingBox toSize:_viewBoundsSize];
        
        VNFaceLandmarks2D *landmarks = face.landmarks;
        NSArray<VNFaceLandmarkRegion2D *> *requiredLandmarks = @[landmarks.faceContour,
                                                                 landmarks.leftEyebrow,
                                                                 landmarks.rightEyebrow,
                                                                 landmarks.noseCrest,
                                                                 landmarks.nose,
                                                                 landmarks.leftEye,
                                                                 landmarks.rightEye,
                                                                 landmarks.outerLips,
                                                                 landmarks.innerLips];
        
        for (VNFaceLandmarkRegion2D *landmarkRegion in requiredLandmarks) {
            if (landmarkRegion.pointCount) {
                [self convertLandmarkPoints:landmarkRegion.normalizedPoints
                             withPointCount:landmarkRegion.pointCount
                       forFaceInBoundingBox:faceBoundingBox];
            }
        }
    }];
}

- (CGRect)scaleRect:(const CGRect)rect
             toSize:(const CGSize)size {
    return CGRectMake(rect.origin.x * size.width,
                      rect.origin.y * size.height,
                      rect.size.width * size.width,
                      rect.size.height * size.height);
}

- (void)convertLandmarkPoints:(const CGPoint *)landmarkPoints
               withPointCount:(NSUInteger)pointCount
         forFaceInBoundingBox:(CGRect)boundingBox {
    NSMutableArray *points = [[NSMutableArray alloc] initWithCapacity:pointCount];
    for (NSUInteger idx = 0; idx < pointCount; ++idx) {
        points[idx] = [NSValue valueWithCGPoint:CGPointMake(landmarkPoints[idx].x * boundingBox.size.width
                                                            + boundingBox.origin.x,
                                                            landmarkPoints[idx].y * boundingBox.size.height
                                                            + boundingBox.origin.y)];
    }
    
    [self drawLineFromPoints:points inRange:NSMakeRange(0, pointCount) withColor:UIColor.redColor.CGColor];
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
        if (error) NSLog(@"Cannot init device input: %@", error.localizedDescription);
        _currentCameraPosition = newCamera.position;
        if ([_session canAddInput:newInput]) [_session addInput:newInput];
        
        [_session commitConfiguration];
    } else {
        NSLog(@"No session!");
    }
}

- (AVCaptureDevice *)cameraWithPreviousPosition:(const AVCaptureDevicePosition)previousPosition {
    switch (previousPosition) {
        case AVCaptureDevicePositionFront:
        case AVCaptureDevicePositionBack:
            return [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                      mediaType:AVMediaTypeVideo
                                                       position:previousPosition == AVCaptureDevicePositionFront? AVCaptureDevicePositionBack: AVCaptureDevicePositionFront];
        default:
            NSLog(@"Previous position of camera not specified!");
            return nil;
    }
}

- (void)tapUploadPhoto {
    _shouldStopToUpload = YES;
}

- (void)sessionPauseRunning {
    [_session stopRunning];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [_uploadPhotoButton removeTarget:self
                                  action:nil
                        forControlEvents:UIControlEventTouchDown];
        [_uploadPhotoButton addTarget:self
                               action:@selector(tapContinue)
                     forControlEvents:UIControlEventTouchDown];
        [_uploadPhotoButton setTitle:kContinueNuttonTitle.copy forState:UIControlStateNormal];
    });
}

- (void)tapContinue {
    [self sessionContinueRunning];
}

- (void)sessionContinueRunning {
    [_session startRunning];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [_uploadPhotoButton removeTarget:self
                                  action:nil
                        forControlEvents:UIControlEventTouchDown];
        [_uploadPhotoButton addTarget:self
                               action:@selector(tapUploadPhoto)
                     forControlEvents:UIControlEventTouchDown];
        [_uploadPhotoButton setTitle:kUploadPhotoButtonTitle.copy forState:UIControlStateNormal];
    });
}

- (void)uploadImage:(UIImage *)image {
    // NSData *data = [[NSData alloc]initWithBase64EncodedString:string options:NSDataBase64DecodingIgnoreUnknownCharacters];
    NSString *imageString = [UIImageJPEGRepresentation(image, 1.0) base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed];
    NSDictionary *requestDict = @{@"image": imageString};
    NSError *error;
    NSData* jsonData = [NSJSONSerialization dataWithJSONObject:requestDict
                                                       options:kNilOptions
                                                         error:&error];
    if (error) NSLog(@"Failed converting dictionary to JSON: %@", error.localizedDescription);
    NSString *dataLength = [NSString stringWithFormat:@"%ld", jsonData.length];
    
    NSMutableURLRequest *request =
    [NSMutableURLRequest requestWithURL:[NSURL URLWithString:_serverAddress]
                            cachePolicy:NSURLRequestReloadIgnoringCacheData
                        timeoutInterval:60];
    
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:jsonData];
    [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request addValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:dataLength forHTTPHeaderField:@"Content-Length"];
    [request setValue:kAuthenticationString.copy forHTTPHeaderField:@"Authentication"];
    
    NSURLSession *urlSession = [NSURLSession sharedSession];
    NSURLSessionTask *task =
    [urlSession uploadTaskWithRequest:request
                             fromData:jsonData
                    completionHandler:^(NSData * _Nullable data,
                                        NSURLResponse * _Nullable response,
                                        NSError * _Nullable error) {
                        if (error) NSLog(@"Failed in uploading: %@", error.localizedDescription);
                        else {
                            NSError *error;
                            NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data
                                                                                         options:kNilOptions
                                                                                           error:&error];
                            if (error) NSLog(@"Failed converting JSON to dictionary: %@", error.localizedDescription);
                            
                            if (responseDict[@"landmarks"]) {
                                NSArray *landmarks = responseDict[@"landmarks"];
                                if (landmarks.class == NSNull.class) {
                                    UIAlertController *alert =
                                    [UIAlertController alertControllerWithTitle:@"Server found no face"
                                                                        message:@""
                                                                 preferredStyle:UIAlertControllerStyleAlert];
                                    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                                              style:UIAlertActionStyleCancel
                                                                            handler:nil]];
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        [self presentViewController:alert animated:YES completion:nil];;
                                    });
                                } else {
                                    CGFloat scaleWidth = _viewBoundsSize.width / image.size.height;
                                    CGFloat scaleHeight = _viewBoundsSize.height / image.size.width;
                                    
                                    for (NSArray<NSArray<NSNumber *> *> *face in landmarks) {
                                        if (face.count == 68) {
                                            NSMutableArray *points = [[NSMutableArray alloc] initWithCapacity:68];
                                            for (NSUInteger idx = 0; idx < 68; ++idx) {
                                                points[idx] = [NSValue valueWithCGPoint:
                                                               CGPointMake(face[idx][0].floatValue * scaleWidth, 
                                                                           _viewBoundsSize.height - face[idx][1].floatValue * scaleHeight)];
                                            }
                                            [kDlibLandmarksMap enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull landmarkName,
                                                                                                   NSValue * _Nonnull range,
                                                                                                   BOOL * _Nonnull stop) {
                                                [self drawLineFromPoints:points
                                                                 inRange:[range rangeValue]
                                                               withColor:UIColor.blueColor.CGColor];
                                            }];
                                        } else {
                                            NSLog(@"Less than 68 points returned by server");
                                        }
                                    }
                                }
                            }
                        }
                    }];
    [task resume];
}

- (void)drawLineFromPoints:(const NSArray<NSValue *> *)points
                   inRange:(const NSRange)range
                 withColor:(const CGColorRef)color {
    CAShapeLayer *newLayer = [[CAShapeLayer alloc] init];
    newLayer.strokeColor = color;
    newLayer.lineWidth = 2.0f;
    newLayer.fillColor = UIColor.clearColor.CGColor;
    
    UIBezierPath *path = [[UIBezierPath alloc] init];
    [path moveToPoint:points[range.location].CGPointValue];
    
    for (NSUInteger idx = range.location; idx < NSMaxRange(range); ++idx) {
        [path addLineToPoint:points[idx].CGPointValue];
    }
    newLayer.path = path.CGPath;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [_shapeLayer addSublayer:newLayer];
    });
}

@end
