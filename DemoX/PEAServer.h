//
//  PEAServer.h
//  DemoX
//
//  Created by Lun on 2017/9/25.
//  Copyright © 2017年 Lun. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void (^PEAServerResponseHandler)(NSDictionary * _Nullable response, NSError * _Nullable error);

typedef NS_ENUM(NSUInteger, PEAServerOperation) {
    PEAServerStore = 1101,
    PEAServerDelete,
    PEAServerRetrieve,
    PEAServerTransfer,
};

@interface PEAServer : NSObject

- (void)sendData:(NSData * _Nonnull)requestData
withHeaderFields:(NSDictionary * _Nullable)headerFields
       operation:(PEAServerOperation)operation
         timeout:(NSTimeInterval)timeout
 responseHandler:(PEAServerResponseHandler _Nonnull)responseHandler;

@end
