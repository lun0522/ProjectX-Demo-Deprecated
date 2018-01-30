//
//  StylizedViewController.m
//  DemoX
//
//  Created by Pujun Lun on 1/26/18.
//  Copyright © 2018 Lun. All rights reserved.
//

#import "StylizedViewController.h"

@interface StylizedViewController () {
    UILongPressGestureRecognizer *_longPressRecognizer;
}

@property (weak, nonatomic) IBOutlet UIImageView *imageView;

@end

@implementation StylizedViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _imageView.image = _stylizedImage;
    [_imageView setContentMode:UIViewContentModeScaleAspectFit];
    self.view.backgroundColor = UIColor.blackColor;
    
    _longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(longPress:)];
    _longPressRecognizer.minimumPressDuration = 0.3f;
    [_imageView addGestureRecognizer:_longPressRecognizer];
    
    UIBarButtonItem *rightBarItem = [[UIBarButtonItem alloc] initWithTitle:@"Share..."
                                                                     style:UIBarButtonItemStylePlain
                                                                    target:self
                                                                    action:@selector(tapShare)];
    self.navigationItem.rightBarButtonItem = rightBarItem;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)tapShare {
    UIAlertController *alert =
    [UIAlertController alertControllerWithTitle:nil
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save to album"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                UIImageWriteToSavedPhotosAlbum(_stylizedImage, self, @selector(image:didFinishSavingWithError:contextInfo:), nil);
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)longPress:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer == _longPressRecognizer) {
        if (recognizer.state == UIGestureRecognizerStateBegan) {
            _imageView.image = _originalPhoto;
        } else if (recognizer.state == UIGestureRecognizerStateEnded) {
            _imageView.image = _stylizedImage;
        }
    }
}

- (void)image:(UIImage *)image
didFinishSavingWithError:(NSError *)error
  contextInfo:(void *)contextInfo {
    UIAlertController *alert = [UIAlertController
                                alertControllerWithTitle:error? @"Error" : @"Success!"
                                message:error? error.localizedDescription : @"Please view in the album."
                                preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alert animated:YES completion:nil];
    });
}

@end
