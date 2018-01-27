//
//  VideoLayer.h
//  DemoX
//
//  Created by Pujun Lun on 25/12/2017.
//  Copyright © 2017 Lun. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@protocol VideoCaptureDelegate

- (void)didCaptureFrame:(CIImage * _Nonnull)frame;

@end

@interface VideoLayer : AVCaptureVideoPreviewLayer

- (void)setFrameRect:(CGRect)rect;
- (void)setCapturerDelegate:(id<VideoCaptureDelegate> _Nonnull)delegate;
- (void)start;
- (void)stop;
- (void)switchCamera;

@end
