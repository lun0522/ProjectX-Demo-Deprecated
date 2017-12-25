//
//  LocalDetector.h
//  DemoX
//
//  Created by Lun on 2017/9/29.
//  Copyright © 2017年 Lun. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, LDRFaceDetectionEvent) {
    LDRFaceNotFound = 0,
    LDRFaceFoundByDetection,
    LDRFaceFoundByTracking,
};

typedef void (^LocalDetectorDidFindFaceCallback)(LDRFaceDetectionEvent event, CGRect faceBoundingBox);
typedef void (^FaceLandmarksDetectionResultHandler)(NSArray * _Nullable points, NSError * _Nullable error);

@interface LocalDetector : NSObject

- (void)detectFaceLandmarksInCIImage:(CIImage * _Nonnull)image
                 didFindFaceCallback:(LocalDetectorDidFindFaceCallback _Nullable)callback
                       resultHandler:(FaceLandmarksDetectionResultHandler _Nullable)handler;

@end
