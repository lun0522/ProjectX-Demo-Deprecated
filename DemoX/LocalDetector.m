//
//  LocalDetector.m
//  DemoX
//
//  Created by Lun on 2017/9/29.
//  Copyright © 2017年 Lun. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Vision/Vision.h>
#import "DMXError.h"
#import "LocalDetector.h"

@interface LocalDetector() {
    VNDetectFaceRectanglesRequest *_faceDetection;
    VNDetectFaceLandmarksRequest  *_faceLandmarksDetection;
    VNFaceObservation *_lastObservation;
    VNTrackObjectRequest *_faceTracking;
    VNSequenceRequestHandler *_faceDetectionRequest;
    VNSequenceRequestHandler *_faceLandmarksRequest;
    VNSequenceRequestHandler *_faceTrackingRequest;
    LocalDetectorDidFindFaceCallback _didFindFaceCallback;
    FaceLandmarksDetectionResultHandler _resultHandler;
    BOOL _tracking;
}

@end

@implementation LocalDetector

- (instancetype)init {
    if (self = [super init]) {
        _faceDetection = [[VNDetectFaceRectanglesRequest alloc] init];
        _faceLandmarksDetection = [[VNDetectFaceLandmarksRequest alloc] init];
        _faceDetectionRequest = [[VNSequenceRequestHandler alloc] init];
        _faceLandmarksRequest = [[VNSequenceRequestHandler alloc] init];
        _tracking = NO;
    }
    return self;
}

- (void)detectorErrorWithDescription:(NSString *)description
                                code:(NSUInteger)code {
    NSLog(@"%@", [NSString stringWithFormat:@"[Detector] %@", description]);
    if (_resultHandler) {
        _resultHandler(nil, [NSError errorWithDomain:DMXErrorDomain
                                                code:code
                                            userInfo:@{NSLocalizedDescriptionKey:description}]);
        _resultHandler = nil;
    }
}

- (void)detectFaceLandmarksInCIImage:(CIImage * _Nonnull)image
         trackingConfidenceThreshold:(float)threshold
                 didFindFaceCallback:(LocalDetectorDidFindFaceCallback _Nullable)callback
                       resultHandler:(FaceLandmarksDetectionResultHandler _Nullable)handler {
    _didFindFaceCallback = callback;
    _resultHandler = handler;
    if (_tracking) [self trackFaceInCIImage:image confidenceThreshold:threshold];
    else [self detectFaceInCIImage:image];
}

- (void)detectFaceInCIImage:(CIImage *)image {
    NSError *error;
    [_faceDetectionRequest performRequests:@[_faceDetection] onCIImage:image error:&error];
    if (error) {
        [self detectorErrorWithDescription:[NSString stringWithFormat:@"Error in face detection: %@",
                                            error.localizedDescription]
                                      code:DMXFaceDetectionError];
        return;
    }
    
    if (_faceDetection.results.count) {
        VNFaceObservation *faceObservation;
        
        if (_faceDetection.results.count == 1) faceObservation = _faceDetection.results[0];
        else {
            NSArray *sortedObservations = [_faceDetection.results
                                           sortedArrayUsingComparator:^NSComparisonResult(VNFaceObservation * _Nonnull face1,
                                                                                          VNFaceObservation * _Nonnull face2) {
                                               NSNumber *area1 = @(face1.boundingBox.size.width * face1.boundingBox.size.height);
                                               NSNumber *area2 = @(face2.boundingBox.size.width * face2.boundingBox.size.height);
                                               return [area2 compare:area1];
                                           }];
            faceObservation = sortedObservations[0];
        }
        
        CGRect faceBoundingBox = faceObservation.boundingBox;
        _didFindFaceCallback(YES, [self scaleRect:faceBoundingBox toSize:image.extent.size]);
        
        if (_resultHandler) {
            NSArray *points = [NSArray arrayWithObjects:
                               [NSValue valueWithCGPoint:CGPointMake(faceBoundingBox.origin.x,
                                                                     faceBoundingBox.origin.y)],
                               [NSValue valueWithCGPoint:CGPointMake(faceBoundingBox.origin.x + faceBoundingBox.size.width,
                                                                     faceBoundingBox.origin.y)],
                               [NSValue valueWithCGPoint:CGPointMake(faceBoundingBox.origin.x + faceBoundingBox.size.width,
                                                                     faceBoundingBox.origin.y + faceBoundingBox.size.height)],
                               [NSValue valueWithCGPoint:CGPointMake(faceBoundingBox.origin.x,
                                                                     faceBoundingBox.origin.y + faceBoundingBox.size.height)],
                               [NSValue valueWithCGPoint:CGPointMake(faceBoundingBox.origin.x,
                                                                     faceBoundingBox.origin.y)],
                               nil];
            _resultHandler(points, nil);
        }
        
        // https://stackoverflow.com/a/46355234/7873124
        // Re-instantiate the request handler after the first frame used for tracking changes,
        // to avoid that Vision throws "Exceeded maximum allowed number of Trackers" error
        _faceTrackingRequest = [[VNSequenceRequestHandler alloc] init];
        _lastObservation = faceObservation;
        _tracking = YES;
        
        _faceLandmarksDetection.inputFaceObservations = @[faceObservation];
        [self detectLandmarksInCIImage:image];
    } else {
        _didFindFaceCallback(NO, (CGRect){});
    }
}

- (void)trackFaceInCIImage:(CIImage *)image
       confidenceThreshold:(float)threshold {
    // The default tracking level of VNTrackObjectRequest is VNRequestTrackingLevelFast,
    // which results that the confidence can only be 0.0 or 1.0.
    // For more precise control, it should be set to VNRequestTrackingLevelAccurate,
    // so that the confidence floats between 0.0 and 1.0
    _faceTracking = [[VNTrackObjectRequest alloc]
                     initWithDetectedObjectObservation:_lastObservation
                     completionHandler:^(VNRequest * _Nonnull request, NSError * _Nullable error) {
                         if (error) [self detectorErrorWithDescription:[NSString stringWithFormat:
                                                                        @"Error in face tracking: %@",
                                                                        error.localizedDescription]
                                                                  code:DMXFaceTrackingError];
                         else _lastObservation = request.results[0];
                     }];
    _faceTracking.trackingLevel = VNRequestTrackingLevelAccurate;
    
    NSError *error;
    [_faceTrackingRequest performRequests:@[_faceTracking] onCIImage:image error:&error];
    if (error) {
        [self detectorErrorWithDescription:[NSString stringWithFormat:@"Error in face tracking: %@",
                                            error.localizedDescription]
                                      code:DMXFaceTrackingError];
        return;
    }
    
    VNDetectedObjectObservation *faceObservation = _faceTracking.results[0];
    if (faceObservation.confidence < threshold) {
        _tracking = NO;
        [self detectFaceInCIImage:image];
    } else {
        CGRect faceBoundingBox = faceObservation.boundingBox;
        _didFindFaceCallback(YES, [self scaleRect:faceBoundingBox toSize:image.extent.size]);
        
        _faceLandmarksDetection.inputFaceObservations = @[[VNFaceObservation observationWithBoundingBox:faceObservation.boundingBox]];
        [self detectLandmarksInCIImage:image];
    }
}

- (void)detectLandmarksInCIImage:(CIImage *)image {
    NSError *error;
    [_faceLandmarksRequest performRequests:@[_faceLandmarksDetection] onCIImage:image error:&error];
    if (error) {
        [self detectorErrorWithDescription:[NSString stringWithFormat:
                                            @"Error in landmarks detection: %@",
                                            error.localizedDescription]
                                      code:DMXFaceLandmarksDetectionError];
        return;
    }
    
    [_faceLandmarksDetection.results enumerateObjectsUsingBlock:^(VNFaceObservation * _Nonnull face,
                                                                  NSUInteger idx,
                                                                  BOOL * _Nonnull stop) {
        CGRect boundingBox = ((VNFaceObservation *)_faceLandmarksDetection.inputFaceObservations[idx]).boundingBox;
        
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
                       forFaceInBoundingBox:boundingBox];
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
    if (_resultHandler) _resultHandler([points copy], nil);
}

@end
