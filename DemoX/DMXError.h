//
//  DMXError.h
//  DemoX
//
//  Created by Lun on 2017/10/7.
//  Copyright © 2017年 Lun. All rights reserved.
//

#ifndef DMXError_h
#define DMXError_h

#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *const DMXErrorDomain;

enum {
    DMXSendDataError = 1000,
    DMXDetectionError,
};

#endif /* DMXError_h */
