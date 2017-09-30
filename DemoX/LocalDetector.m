//
//  LocalDetector.m
//  DemoX
//
//  Created by Lun on 2017/9/29.
//  Copyright © 2017年 Lun. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Vision/Vision.h>
#import "LocalDetector.h"

@interface LocalDetector() {
    VNDetectFaceRectanglesRequest *_faceDetection;
    VNDetectFaceLandmarksRequest  *_faceLandmarksDetection;
    VNSequenceRequestHandler *_faceDetectionRequest;
    VNSequenceRequestHandler *_faceLandmarksRequest;
    LocalDetectorDidFindFaceCallback _didFindFaceCallback;
    FaceLandmarksDetectionResultHandler _resultHandler;
    CGSize _frameSize;
}

@end

@implementation LocalDetector

- (instancetype)initWithFrameSize:(CGSize)frameSize {
    if (self = [super init]) {
        _faceDetection = [[VNDetectFaceRectanglesRequest alloc] init];
        _faceLandmarksDetection = [[VNDetectFaceLandmarksRequest alloc] init];
        _faceDetectionRequest = [[VNSequenceRequestHandler alloc] init];
        _faceLandmarksRequest = [[VNSequenceRequestHandler alloc] init];
        _frameSize = frameSize;
    }
    return self;
}

+ (LocalDetector * _Nonnull)detectorWithFrameSize:(CGSize)frameSize {
    return [[LocalDetector alloc] initWithFrameSize:frameSize];
}

- (void)detectorLog:(NSString *)content {
    NSLog(@"%@", [NSString stringWithFormat:@"[Detector] %@", content]);
}

- (void)detectFaceLandmarksInCIImage:(CIImage * _Nonnull)image
                 didFindFaceCallback:(LocalDetectorDidFindFaceCallback _Nullable)callback
                       resultHandler:(FaceLandmarksDetectionResultHandler _Nullable)handler {
    _didFindFaceCallback = callback;
    _resultHandler = handler;
    [self detectFaceInCIImage:image];
}

- (void)detectFaceInCIImage:(CIImage *)image {
    NSError *error;
    [_faceDetectionRequest performRequests:@[_faceDetection] onCIImage:image error:&error];
    if (error) {
        [self detectorLog:[NSString stringWithFormat:@"Error in face detection: %@", error.localizedDescription]];
        return;
    }
    
    if (_faceDetection.results.count) {
        _didFindFaceCallback();
        _faceLandmarksDetection.inputFaceObservations = _faceDetection.results;
        [self detectLandmarksInCIImage:image];
    }
}

- (void)detectLandmarksInCIImage:(CIImage *)image {
    NSError *error;
    [_faceLandmarksRequest performRequests:@[_faceLandmarksDetection] onCIImage:image error:&error];
    if (error) {
        [self detectorLog:[NSString stringWithFormat:@"Error in landmarks detection: %@", error.localizedDescription]];
        return;
    }
    
    [_faceLandmarksDetection.results enumerateObjectsUsingBlock:^(VNFaceObservation * _Nonnull face,
                                                                  NSUInteger idx,
                                                                  BOOL * _Nonnull stop) {
        CGRect boundingBox = ((VNFaceObservation *)_faceLandmarksDetection.inputFaceObservations[idx]).boundingBox;
        CGRect faceBoundingBox = [self scaleRect:boundingBox toSize:_frameSize];
        
        VNFaceLandmarks2D *landmarks = face.landmarks;
        NSDictionary *requestedLandmarks = @{
                                             @"faceContour" : landmarks.faceContour,
                                             @"leftEyebrow" : landmarks.leftEyebrow,
                                             @"rightEyebrow": landmarks.rightEyebrow,
                                             @"noseCrest"   : landmarks.noseCrest,
                                             @"nose"        : landmarks.nose,
                                             @"leftEye"     : landmarks.leftEye,
                                             @"rightEye"    : landmarks.rightEye,
                                             @"outerLips"   : landmarks.outerLips,
                                             @"innerLips"   : landmarks.innerLips,
                                             };
        [requestedLandmarks enumerateKeysAndObjectsUsingBlock:^(NSString *  _Nonnull landmarkName,
                                                                VNFaceLandmarkRegion2D *  _Nonnull landmarkRegion,
                                                                BOOL * _Nonnull stop) {
            if (landmarkRegion.pointCount) {
                [self convertLandmarkPoints:landmarkRegion.normalizedPoints
                             withPointCount:landmarkRegion.pointCount
                       forFaceInBoundingBox:faceBoundingBox];
            }
        }];
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
    _resultHandler([points copy]);
}

@end
