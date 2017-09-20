//
//  ViewController.m
//  DemoX
//
//  Created by Lun on 2017/9/19.
//  Copyright © 2017年 Lun. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>
#import "ViewController.h"

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate> {
    AVCaptureSession *session;
    CAShapeLayer *shapeLayer;
    AVCaptureVideoPreviewLayer *previewLayer;
    
    VNDetectFaceRectanglesRequest *faceDetection;
    VNDetectFaceLandmarksRequest  *faceLandmarks;
    VNSequenceRequestHandler *faceDetectionRequest;
    VNSequenceRequestHandler *faceLandmarksRequest;
    
    CGSize viewBoundsSize;
    AVCaptureDevicePosition currentCameraPosition;
}

@property (weak, nonatomic) IBOutlet UIButton *switchCameraButton;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [[UIApplication sharedApplication] setIdleTimerDisabled: YES];
    
    faceDetection = [[VNDetectFaceRectanglesRequest alloc] init];
    faceLandmarks = [[VNDetectFaceLandmarksRequest alloc] init];
    faceDetectionRequest = [[VNSequenceRequestHandler alloc] init];
    faceLandmarksRequest = [[VNSequenceRequestHandler alloc] init];
    
    [self setupSession];
    shapeLayer = [[CAShapeLayer alloc] init];
    previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:session];
    previewLayer.videoGravity = kCAGravityResizeAspectFill;
    
    viewBoundsSize = self.view.bounds.size;
    _switchCameraButton.layer.cornerRadius = 8.0f;
    _switchCameraButton.layer.borderWidth = 1.0f;
    _switchCameraButton.layer.borderColor = _switchCameraButton.tintColor.CGColor;
    [_switchCameraButton addTarget:self
                            action:@selector(switchCamera)
                  forControlEvents:UIControlEventTouchDown];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    shapeLayer.frame = self.view.frame;
    previewLayer.frame = self.view.frame;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    [self.view.layer insertSublayer:previewLayer atIndex:0];
    
    shapeLayer.strokeColor = UIColor.redColor.CGColor;
    shapeLayer.lineWidth = 2.0f;
    [shapeLayer setAffineTransform:CGAffineTransformMakeScale(-1, -1)];
    
    [self.view.layer insertSublayer:shapeLayer above:previewLayer];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)setupSession {
    session = [[AVCaptureSession alloc] init];
    AVCaptureDevice *defaultCamera = [AVCaptureDevice
                                      defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                      mediaType:AVMediaTypeVideo
                                      position:AVCaptureDevicePositionFront];
    
    @try {
        [session beginConfiguration];
        
        NSError *error;
        AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:defaultCamera
                                                                                  error:&error];
        if (error) NSLog(@"Cannot init device input: %@", error.localizedDescription);
        currentCameraPosition = AVCaptureDevicePositionFront;
        if ([session canAddInput:deviceInput]) [session addInput:deviceInput];
        
        AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];
        videoOutput.videoSettings = @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)};
        videoOutput.alwaysDiscardsLateVideoFrames = YES;
        [videoOutput setSampleBufferDelegate:self
                                       queue:dispatch_queue_create("com.lun.demox.videooutput.queue", NULL)];
        if ([session canAddOutput:videoOutput]) [session addOutput:videoOutput];
        
        [session commitConfiguration];
        [session startRunning];
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
    if (currentCameraPosition == AVCaptureDevicePositionBack) ciImage = [ciImage imageByApplyingOrientation:UIImageOrientationUpMirrored];
    [self detectFaceInCIImage:[ciImage imageByApplyingOrientation:UIImageOrientationLeftMirrored]];
}

- (void)detectFaceInCIImage:(CIImage *)image {
    NSError *error;
    [faceDetectionRequest performRequests:@[faceDetection] onCIImage:image error:&error];
    if (error) NSLog(@"Error in face detection: %@", error.localizedDescription);
    
    NSArray *results = faceDetection.results;
    if (results.count) {
        dispatch_async(dispatch_get_main_queue(), ^{
            for (CAShapeLayer *layer in [shapeLayer.sublayers copy]) [layer removeFromSuperlayer];
        });
        faceLandmarks.inputFaceObservations = results;
        [self detectLandmarksInCIImage:image];
    }
}

- (void)detectLandmarksInCIImage:(CIImage *)image {
    NSError *error;
    [faceLandmarksRequest performRequests:@[faceLandmarks] onCIImage:image error:&error];
    if (error) NSLog(@"Error in landmarks detection: %@", error.localizedDescription);
    
    NSArray<VNFaceObservation *> *results = faceLandmarks.results;
    [results enumerateObjectsUsingBlock:^(VNFaceObservation * _Nonnull face,
                                          NSUInteger idx,
                                          BOOL * _Nonnull stop) {
        CGRect boundingBox = ((VNFaceObservation *)faceLandmarks.inputFaceObservations[idx]).boundingBox;
        CGRect faceBoundingBox = [self scaleRect:boundingBox ToSize:viewBoundsSize];
        
        VNFaceLandmarks2D *landmarks = face.landmarks;
        NSArray<VNFaceLandmarkRegion2D *> *requiredLandmarks = @[landmarks.faceContour,
                                                                 landmarks.leftEyebrow,
                                                                 landmarks.rightEyebrow,
                                                                 landmarks.leftEye,
                                                                 landmarks.rightEye,
                                                                 landmarks.nose,
                                                                 landmarks.noseCrest,
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

- (CGRect)scaleRect:(CGRect)rect ToSize:(CGSize)size {
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
    
    [self drawPoints:points];
}

- (void)drawPoints:(NSArray<NSValue *> *)points {
    CAShapeLayer *newLayer = [[CAShapeLayer alloc] init];
    newLayer.strokeColor = UIColor.redColor.CGColor;
    newLayer.lineWidth = 2.0f;
    newLayer.fillColor = UIColor.clearColor.CGColor;
    
    UIBezierPath *path = [[UIBezierPath alloc] init];
    [path moveToPoint:points[0].CGPointValue];
    
    [points enumerateObjectsUsingBlock:^(NSValue * _Nonnull point, NSUInteger idx, BOOL * _Nonnull stop) {
        [path addLineToPoint:point.CGPointValue];
    }];
    newLayer.path = path.CGPath;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [shapeLayer addSublayer:newLayer];
    });
}

- (void)switchCamera {
    if (session) {
        [session beginConfiguration];
        
        AVCaptureInput *currentInput = session.inputs[0];
        AVCaptureDevice *newCamera = [self cameraWithPreviousPosition:((AVCaptureDeviceInput *)currentInput).device.position];
        
        [session removeInput:currentInput];
        NSError *error;
        AVCaptureDeviceInput *newInput = [[AVCaptureDeviceInput alloc] initWithDevice:newCamera
                                                                                   error:&error];
        if (error) NSLog(@"Cannot init device input: %@", error.localizedDescription);
        currentCameraPosition = newCamera.position;
        if ([session canAddInput:newInput]) [session addInput:newInput];
        
        [session commitConfiguration];
    } else {
        NSLog(@"No session!");
    }
}

- (AVCaptureDevice *)cameraWithPreviousPosition:(AVCaptureDevicePosition)previousPosition {
    switch (previousPosition) {
        case AVCaptureDevicePositionFront:
        case AVCaptureDevicePositionBack:
            return [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                      mediaType:AVMediaTypeVideo
                                                       position:previousPosition == AVCaptureDevicePositionFront? AVCaptureDevicePositionBack: AVCaptureDevicePositionFront];
        default:
            NSLog(@"Previous position of camera not specified!");
            return NULL;
    }
}

@end
