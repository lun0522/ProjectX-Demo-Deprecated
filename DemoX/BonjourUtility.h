//
//  BonjourUtility.h
//  DemoX
//
//  Created by Lun on 2017/9/25.
//  Copyright © 2017年 Lun. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void (^DMXSearchServerCompletionHandler)(void);

@interface BonjourUtility : NSObject

- (void)searchServerWithCompletionHandler:(DMXSearchServerCompletionHandler)handler;

@end