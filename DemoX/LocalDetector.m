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
    VNSequenceRequestHandler *_faceDetectionRequest;
    VNSequenceRequestHandler *_faceLandmarksRequest;
    LocalDetectorDidFindFaceCallback _didFindFaceCallback;
    FaceLandmarksDetectionResultHandler _resultHandler;
}

@end

@implementation LocalDetector

- (instancetype)init {
    if (self = [super init]) {
        _faceDetection = [[VNDetectFaceRectanglesRequest alloc] init];
        _faceLandmarksDetection = [[VNDetectFaceLandmarksRequest alloc] init];
        _faceDetectionRequest = [[VNSequenceRequestHandler alloc] init];
        _faceLandmarksRequest = [[VNSequenceRequestHandler alloc] init];
    }
    return self;
}

- (void)detectionErrorWithDescription:(NSString *)description {
    NSLog(@"%@", [NSString stringWithFormat:@"[Detector] %@", description]);
    if (_resultHandler) {
        _resultHandler(nil, [NSError errorWithDomain:DMXErrorDomain
                                                code:DMXDetectionError
                                            userInfo:@{NSLocalizedDescriptionKey: description}]);
        _resultHandler = nil;
    }
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
        [self detectionErrorWithDescription:[NSString stringWithFormat:@"Error in face detection: %@", error.localizedDescription]];
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
        
        // face bounding box is expanded for 25% vertically
        CGRect expandedFaceRect = faceObservation.boundingBox;
        expandedFaceRect.origin.y = MAX(expandedFaceRect.origin.y - expandedFaceRect.size.height * 0.25, 0);
        expandedFaceRect.size.height *= MIN(1.25, (image.extent.size.height - expandedFaceRect.origin.y) / expandedFaceRect.size.height);
        _didFindFaceCallback(YES, [self scaleRect:expandedFaceRect toSize:image.extent.size]);
        
        CGRect faceBoundingBox = expandedFaceRect;
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
        if (_resultHandler) _resultHandler(points, nil);
        
        VNFaceObservation *expandedFaceObservation = [VNFaceObservation observationWithBoundingBox:expandedFaceRect];
        _faceLandmarksDetection.inputFaceObservations = @[expandedFaceObservation];
        [self detectLandmarksInCIImage:image];
    } else {
        _didFindFaceCallback(NO, (CGRect){});
    }
}

- (void)detectLandmarksInCIImage:(CIImage *)image {
    NSError *error;
    [_faceLandmarksRequest performRequests:@[_faceLandmarksDetection] onCIImage:image error:&error];
    if (error) {
        [self detectionErrorWithDescription:[NSString stringWithFormat:@"Error in landmarks detection: %@", error.localizedDescription]];
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
