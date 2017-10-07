//
//  LocalDetector.h
//  DemoX
//
//  Created by Lun on 2017/9/29.
//  Copyright © 2017年 Lun. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void (^LocalDetectorDidFindFaceCallback)(void);
typedef void (^FaceLandmarksDetectionResultHandler)(NSArray * _Nullable points, NSError * _Nullable error);

@interface LocalDetector : NSObject

- (instancetype _Nonnull)init __attribute__((unavailable("use detectorWithFrameSize:")));

+ (LocalDetector * _Nonnull)detectorWithFrameSize:(CGSize)frameSize;
- (void)detectFaceLandmarksInCIImage:(CIImage * _Nonnull)image
                 didFindFaceCallback:(LocalDetectorDidFindFaceCallback _Nullable)callback
                       resultHandler:(FaceLandmarksDetectionResultHandler _Nullable)handler;

@end
