//
//  VideoLayer.m
//  DemoX
//
//  Created by Pujun Lun on 25/12/2017.
//  Copyright © 2017 Lun. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "VideoLayer.h"

@interface VideoLayer() <AVCaptureVideoDataOutputSampleBufferDelegate>

@end

@implementation VideoLayer {
    AVCaptureSession *_session;
    AVCaptureDevicePosition _currentCameraPosition;
    id<VideoCaptureDelegate> _capturerDelegate;
}

- (instancetype)init {
    [self setupSession];
    if (self = [super initWithSession:_session]) {
        self.videoGravity = kCAGravityResizeAspectFill;
    }
    return self;
}

- (void)videoLayerLog:(NSString *)content {
    NSLog(@"%@", [NSString stringWithFormat:@"[VideoLayer] %@", content]);
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
        if (error)
            [self videoLayerLog:[NSString stringWithFormat:@"Cannot init device input: %@", error.localizedDescription]];
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
        [self videoLayerLog:@"Session setup failed!"];
    }
}

- (void)setFrameRect:(CGRect)rect {
    self.frame = rect;
}

- (void)setCapturerDelegate:(id<VideoCaptureDelegate> _Nonnull)delegate {
    _capturerDelegate = delegate;
}

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate);
    
    CIImage *ciImage = [CIImage imageWithCVImageBuffer:pixelBuffer
                                               options:(__bridge NSDictionary *)attachments];
    if (_currentCameraPosition == AVCaptureDevicePositionBack)
        ciImage = [ciImage imageByApplyingOrientation:UIImageOrientationUpMirrored];
    
    if (_capturerDelegate) [_capturerDelegate didCaptureFrame:[ciImage imageByApplyingOrientation:UIImageOrientationLeftMirrored]];
}

- (void)start {
    [_session startRunning];
}

- (void)stop {
    [_session stopRunning];
}

- (void)switchCamera {
    if (_session) {
        [_session beginConfiguration];
        
        AVCaptureInput *currentInput = _session.inputs[0];
        AVCaptureDevice *newCamera = [self cameraWithPreviousPosition:((AVCaptureDeviceInput *)currentInput).device.position];
        
        [_session removeInput:currentInput];
        NSError *error;
        AVCaptureDeviceInput *newInput = [[AVCaptureDeviceInput alloc] initWithDevice:newCamera
                                                                                error:&error];
        if (error)
            [self videoLayerLog:[NSString stringWithFormat:@"Cannot init device input: %@", error.localizedDescription]];
        _currentCameraPosition = newCamera.position;
        if ([_session canAddInput:newInput]) [_session addInput:newInput];
        
        [_session commitConfiguration];
    } else {
        [self videoLayerLog:@"No session!"];
    }
}

- (AVCaptureDevicePosition)getCameraPosition {
    return _currentCameraPosition;
}

- (AVCaptureDevice *)cameraWithPreviousPosition:(const AVCaptureDevicePosition)previousPosition {
    switch (previousPosition) {
        case AVCaptureDevicePositionFront:
        case AVCaptureDevicePositionBack:
            return [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                      mediaType:AVMediaTypeVideo
                                                       position:previousPosition == AVCaptureDevicePositionFront? AVCaptureDevicePositionBack: AVCaptureDevicePositionFront];
        default:
            [self videoLayerLog:@"Previous position of camera not specified!"];
            return nil;
    }
}

@end
