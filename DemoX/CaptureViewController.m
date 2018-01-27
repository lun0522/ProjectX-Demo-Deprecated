//
//  CaptureViewController.m
//  DemoX
//
//  Created by Lun on 2017/9/19.
//  Copyright © 2017年 Lun. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>
#import "VideoLayer.h"
#import "LocalDetector.h"
#import "PEAServer.h"
#import "SelectViewController.h"
#import "CaptureViewController.h"

static const float kLandmarksDotsRadius = 6.0f;

@interface CaptureViewController () <UITextFieldDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, VideoCaptureDelegate> {
    VideoLayer *_videoLayer;
    CAShapeLayer *_shapeLayer;
    UIImagePickerController *_imagePickerController;
    CGSize _viewBoundsSize;
    
    LocalDetector *_detector;
    PEAServer *_server;
    
    UIImage *_selectedPhoto;
    NSString *_photoTimestamp;
    CIImage *_lastFrame;
    CGRect *_faceBoundingBox;
}

@property (weak, nonatomic) IBOutlet UIButton *selectPhotoButton;
@property (weak, nonatomic) IBOutlet UIButton *captureFaceButton;
@property (weak, nonatomic) IBOutlet UIButton *switchCameraButton;

@end

@implementation CaptureViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _viewBoundsSize = self.view.bounds.size;
    _detector = [[LocalDetector alloc] init];
    _server = [[PEAServer alloc] init];
    
    [self setupLayers];
    [self setupButtons];
}

- (void)setupLayers {
    _videoLayer = [[VideoLayer alloc] init];
    [_videoLayer setCapturerDelegate:self];
    [self.view.layer insertSublayer:_videoLayer atIndex:0];
    
    _shapeLayer = [[CAShapeLayer alloc] init];
    _shapeLayer.strokeColor = UIColor.redColor.CGColor;
    _shapeLayer.lineWidth = 2.0f;
    [_shapeLayer setAffineTransform:CGAffineTransformMakeScale(-1, -1)];
    [self.view.layer insertSublayer:_shapeLayer above:_videoLayer];
}

- (void)setupButtons {
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
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    // set frames at this point
    [_videoLayer setFrameRect:self.view.frame];
    _shapeLayer.frame = self.view.frame;
}

- (void)viewWillAppear:(BOOL)animated {
    [_videoLayer start];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewControllerLog:(NSString *)content {
    NSLog(@"%@", [NSString stringWithFormat:@"[CaptureViewController] %@", content]);
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
                                                [_videoLayer stop];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Take a photo"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                [self showImagePickerForSourceType:UIImagePickerControllerSourceTypeCamera];
                                                [_videoLayer stop];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)tapSwitchCamera {
    [_videoLayer switchCamera];
}

- (BOOL)shouldPerformSegueWithIdentifier:(NSString *)identifier sender:(id)sender {
    if (!_selectedPhoto || !_faceBoundingBox) {
        [self presentError:!_selectedPhoto ? @"Please select a photo" : @"No face found yet"];
        return NO;
    } else return YES;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    [_videoLayer stop];

    // the face part should be cropped down and mirrored
    CIImage *faceImage = [_lastFrame imageByCroppingToRect:[self scaleRect:*_faceBoundingBox
                                                                    toSize:_lastFrame.extent.size]];
    CIImage *faceImageMirrored = [faceImage imageByApplyingTransform:CGAffineTransformMakeScale(-1, 1)];

    // should convert CIImage to CGImage, and then to UIImage
    // otherwise UIImageJPEGRepresentation() will return nil
    CIContext *context = [[CIContext alloc] initWithOptions:nil];
    CGImageRef cgImage = [context createCGImage:faceImageMirrored
                                       fromRect:faceImageMirrored.extent];

    UINavigationController *nvc = segue.destinationViewController;
    SelectViewController *svc = nvc.viewControllers[0];
    svc.server = _server;
    svc.selfie = [UIImage imageWithCGImage:cgImage];
    svc.photoTimestamp = _photoTimestamp;
}

#pragma mark - Image picker

- (void)showImagePickerForSourceType:(UIImagePickerControllerSourceType)sourceType {
    _imagePickerController = [[UIImagePickerController alloc] init];
    _imagePickerController.sourceType = sourceType;
    _imagePickerController.delegate = self;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:_imagePickerController animated:YES completion:nil];
    });
}

- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
    [self dismissViewControllerAnimated:YES completion:nil];
    _imagePickerController = nil;
    [_videoLayer start];
    
    if (_photoTimestamp) [self deleteLastUploadedPhoto];
    _selectedPhoto = info[UIImagePickerControllerOriginalImage];
    
    // rotate the retrieved image
    UIGraphicsBeginImageContextWithOptions(_selectedPhoto.size, NO, _selectedPhoto.scale);
    [_selectedPhoto drawInRect:(CGRect){0, 0, _selectedPhoto.size}];
    _selectedPhoto = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    _photoTimestamp = [NSString stringWithFormat:@"%lu", (NSUInteger)([[NSDate date] timeIntervalSince1970] * 1000)];
    [self uploadSelectedPhoto];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [self dismissViewControllerAnimated:YES completion:nil];
    _imagePickerController = nil;
    [_videoLayer start];
}

#pragma mark - Video capture

- (void)didCaptureFrame:(CIImage *)frame {
    _lastFrame = frame;
    __weak typeof(self) weakSelf = self;
    [_detector detectFaceLandmarksInCIImage:_lastFrame
                        didFindFaceCallback:^(LDRFaceDetectionEvent event, CGRect faceBoundingBox) {
                            if (event == LDRFaceNotFound) {
                                [weakSelf clearShapeLayer];
                                _faceBoundingBox = nil;
                            } else {
                                _faceBoundingBox = &faceBoundingBox;
                                if (event == LDRFaceFoundByDetection) {
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        [weakSelf drawRectangle:[weakSelf scaleRect:faceBoundingBox toSize:_viewBoundsSize]];
                                    });
                                }
                            }
                        }
                              resultHandler:^(NSArray * _Nullable points, NSError * _Nullable error) {
                                  if (error) {
                                      [weakSelf presentError:error.localizedDescription];
                                  } else {
                                      [weakSelf clearShapeLayer];
                                      [weakSelf drawPoints:points
                                                 withColor:UIColor.redColor.CGColor];
                                  }
                              }];
}

#pragma mark - Upload

- (void)uploadSelectedPhoto {
    __weak typeof(self) weakSelf = self;
    [_server sendData:UIImageJPEGRepresentation(_selectedPhoto, 1.0)
     withHeaderFields:@{@"Timestamp": _photoTimestamp}
            operation:PEAServerStore
              timeout:30
      responseHandler:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
          if (error) [weakSelf presentError:error.localizedDescription];
          else [weakSelf viewControllerLog:@"Uploaded selected photo"];
      }];
}

- (void)deleteLastUploadedPhoto {
    // the request will be cancelled immediately if no body data is appended,
    // so pass an empty NSData here
    __weak typeof(self) weakSelf = self;
    [_server sendData:[[NSData alloc] init]
     withHeaderFields:@{@"Timestamp": _photoTimestamp}
            operation:PEAServerDelete
              timeout:10
      responseHandler:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
          if (error) [weakSelf presentError:error.localizedDescription];
          else [weakSelf viewControllerLog:@"Deleted the last uploaded photo"];
      }];
}

#pragma mark - UI

- (void)clearShapeLayer {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (CAShapeLayer *layer in [_shapeLayer.sublayers copy])
            [layer removeFromSuperlayer];
    });
}

- (void)drawPoints:(const NSArray<NSValue *> *)points
         withColor:(const CGColorRef)color {
    dispatch_async(dispatch_get_main_queue(), ^{
        [points enumerateObjectsUsingBlock:^(NSValue * _Nonnull point,
                                             NSUInteger idx,
                                             BOOL * _Nonnull stop) {
            CAShapeLayer *pointLayer = [[CAShapeLayer alloc] init];
            [pointLayer setFillColor:UIColor.redColor.CGColor];
            CGRect dotRect = CGRectMake(point.CGPointValue.x * _viewBoundsSize.width - kLandmarksDotsRadius / 2,
                                        point.CGPointValue.y * _viewBoundsSize.height - kLandmarksDotsRadius / 2,
                                        kLandmarksDotsRadius, kLandmarksDotsRadius);
            pointLayer.path = [UIBezierPath bezierPathWithOvalInRect:dotRect].CGPath;
            [_shapeLayer addSublayer:pointLayer];
        }];
    });
}

- (void)drawRectangle:(CGRect)rect {
    dispatch_async(dispatch_get_main_queue(), ^{
        CAShapeLayer *rectLayer = [[CAShapeLayer alloc] init];
        [rectLayer setFillColor:UIColor.clearColor.CGColor];
        [rectLayer setStrokeColor:UIColor.redColor.CGColor];
        rectLayer.path = [UIBezierPath bezierPathWithRect:rect].CGPath;
        [_shapeLayer addSublayer:rectLayer];
    });
}

- (CGRect)scaleRect:(CGRect)rect toSize:(CGSize)size {
    return CGRectMake(rect.origin.x * size.width,
                      rect.origin.y * size.height,
                      rect.size.width * size.width,
                      rect.size.height * size.height);
}

- (void)presentError:(NSString *)description {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                   message:description
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alert animated:YES completion:nil];
    });
}

@end
