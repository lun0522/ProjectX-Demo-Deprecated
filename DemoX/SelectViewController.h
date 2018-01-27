//
//  SelectViewController.h
//  DemoX
//
//  Created by Pujun Lun on 1/26/18.
//  Copyright © 2018 Lun. All rights reserved.
//

#import <UIKit/UIKit.h>

@class PEAServer;

@interface SelectViewController : UIViewController

@property (strong, nonatomic) PEAServer *server;
@property (strong, nonatomic) UIImage *selfie;
@property (copy, nonatomic) NSString *photoTimestamp;

@end
