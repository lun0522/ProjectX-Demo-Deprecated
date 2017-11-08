//
//  PEAServer.m
//  DemoX
//
//  Created by Lun on 2017/9/25.
//  Copyright © 2017年 Lun. All rights reserved.
//

#import "DMXError.h"
#import "PEAServer.h"

static const NSString *kServerIdentityString = @"PEAServer";
static const NSString *kServerType = @"_demox._tcp.";
static const NSString *kServerDomain = @"local.";
static const NSString *kClientAuthenticationString = @"PortableEmotionAnalysis";
static NSDictionary *kDlibLandmarksMap = nil;
static NSDictionary *kServerOperationDict = nil;

@interface PEAServer () <NSNetServiceBrowserDelegate, NSNetServiceDelegate> {
    NSNetServiceBrowser *_netServiceBrowser;
    NSMutableArray *_netServiceResolverList;
    NSString *_serverAddress;
}

@end

@implementation PEAServer

- (instancetype)initWithAddress:(NSString *)address {
    if (self = [super init]) {
        kDlibLandmarksMap = @{
                              @"faceContour" : [NSValue valueWithRange:NSMakeRange(0, 17)],
                              @"leftEyebrow" : [NSValue valueWithRange:NSMakeRange(17, 5)],
                              @"rightEyebrow": [NSValue valueWithRange:NSMakeRange(22, 5)],
                              @"noseCrest"   : [NSValue valueWithRange:NSMakeRange(27, 4)],
                              @"nose"        : [NSValue valueWithRange:NSMakeRange(31, 5)],
                              @"leftEye"     : [NSValue valueWithRange:NSMakeRange(36, 6)],
                              @"rightEye"    : [NSValue valueWithRange:NSMakeRange(42, 6)],
                              @"outerLips"   : [NSValue valueWithRange:NSMakeRange(48,12)],
                              @"innerLips"   : [NSValue valueWithRange:NSMakeRange(60, 8)],
                              };
        kServerOperationDict = @{
                                 @(PEAServerStore)   : @"Store",
                                 @(PEAServerDelete)  : @"Delete",
                                 @(PEAServerTransfer): @"Transfer",
                                 };
        if (address) {
            _serverAddress = address;
            [self serverLog:[NSString stringWithFormat:@"Use address: %@", _serverAddress]];
        }
        else
            [self searchServerInLAN];
    }
    return self;
}

+ (PEAServer * _Nonnull)serverWithAddress:(NSString * _Nullable)address {
    return [[PEAServer alloc] initWithAddress:address];
}

- (NSDictionary * _Nonnull)getLandmarksMap {
    return kDlibLandmarksMap.copy;
}

- (void)serverLog:(NSString *)content {
    NSLog(@"%@", [NSString stringWithFormat:@"[PEAServer] %@", content]);
}

#pragma mark Search server with Bonjour

- (void)searchServerInLAN {
    if (!_netServiceBrowser) _netServiceBrowser = [[NSNetServiceBrowser alloc] init];
    if (!_netServiceResolverList) _netServiceResolverList = [[NSMutableArray alloc] init];
    [_netServiceBrowser setDelegate:self];
    [_netServiceBrowser searchForServicesOfType:kServerType.copy
                                       inDomain:kServerDomain.copy];
    [self serverLog:@"Start browsing for Bonjour services"];
}

- (void)stopBrowsing {
    [self serverLog:@"Stop browsing"];
    [self browserCleanup];
    for (NSNetService *netServiceResolver in _netServiceResolverList)
        [self resolverCleanup:netServiceResolver];
    [_netServiceResolverList removeAllObjects];
}

#pragma mark NSNetServiceBrowser

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
           didFindService:(NSNetService *)service
               moreComing:(BOOL)moreComing {
    [_netServiceResolverList addObject:service];
    [service setDelegate:self];
    [service resolveWithTimeout:10.0];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
             didNotSearch:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    [self stopBrowsing];
    [self serverLog:[NSString stringWithFormat:@"Error in browsing for Bonjour services: %@", errorDict]];
}

- (void)browserCleanup {
    if (_netServiceBrowser) {
        [_netServiceBrowser stop];
        [_netServiceBrowser setDelegate:nil];
    }
}

#pragma mark NSNetServiceResolver

- (void)netServiceDidResolveAddress:(NSNetService *)service {
    if (service.TXTRecordData) {
        NSDictionary *txtRecord = [NSNetService dictionaryFromTXTRecordData:service.TXTRecordData];
        if (txtRecord[@"Identity"]) {
            if ([[[NSString alloc] initWithData:(NSData *)txtRecord[@"Identity"]
                                       encoding:NSUTF8StringEncoding]
                 isEqualToString:kServerIdentityString.copy]) {
                if (txtRecord[@"Address"]) {
                    _serverAddress = [[NSString alloc] initWithData:(NSData *)txtRecord[@"Address"]
                                                           encoding:NSUTF8StringEncoding];
                    [self serverLog:[NSString stringWithFormat:@"Use address: %@", _serverAddress]];
                    [self stopBrowsing];
                    return;
                }
                else [self serverLog:[NSString stringWithFormat:@"Authenticated, but no address found: %@", service]];
            }
            else [self serverLog:[NSString stringWithFormat:@"Identified, but not authenticated: %@", service]];
        }
        else [self serverLog:[NSString stringWithFormat:@"No identity: %@", service]];
    }
    else [self serverLog:[NSString stringWithFormat:@"No TXT record: %@", service]];
    
    if ([_netServiceResolverList containsObject:service])
        [_netServiceResolverList removeObject:service];
}

- (void)netService:(NSNetService *)service
     didNotResolve:(NSDictionary *)errorDict {
    if ([_netServiceResolverList containsObject:service])
        [_netServiceResolverList removeObject:service];
    [self serverLog:[NSString stringWithFormat:@"Error in resolving Bonjour service %@: %@", service, errorDict]];
}

- (void)resolverCleanup:(NSNetService *)netServiceResolver {
    if (netServiceResolver) {
        [netServiceResolver stop];
        [netServiceResolver setDelegate:nil];
    }
}

#pragma mark Send data to server
- (void)sendData:(NSData * _Nonnull)requestData
 withHeaderField:(NSDictionary * _Nullable)headerField
       operation:(PEAServerOperation)operation
         timeout:(NSTimeInterval)timeout
 responseHandler:(PEAServerResponseHandler _Nonnull)responseHandler {
    if (!_serverAddress) {
        responseHandler(nil, [self sendDataErrorWithDescription:@"No server address found"]);
        return;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:_serverAddress]
                                                           cachePolicy:NSURLRequestReloadIgnoringCacheData
                                                       timeoutInterval:timeout];
    
    [request setHTTPMethod:operation == PEAServerDelete? @"DELETE": @"POST"];
    [request setValue:kServerOperationDict[@(operation)] forHTTPHeaderField:@"Operation"];
    [request setValue:kClientAuthenticationString.copy forHTTPHeaderField:@"Authentication"];
    [request setValue:[NSString stringWithFormat:@"%ld", requestData.length] forHTTPHeaderField:@"Content-Length"];
    if (headerField)
        [headerField enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull field,
                                                         NSString * _Nonnull value,
                                                         BOOL * _Nonnull stop) {
            [request setValue:value forHTTPHeaderField:field];
        }];
    
    NSURLSession *urlSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    NSURLSessionTask *task =
    [urlSession uploadTaskWithRequest:request
                             fromData:requestData
                    completionHandler:^(NSData * _Nullable data,
                                        NSURLResponse * _Nullable response,
                                        NSError * _Nullable error) {
                        if (error) {
                            responseHandler(nil, [self sendDataErrorWithDescription:
                                                  [NSString stringWithFormat:@"Failed in sending data: %@", error.localizedDescription]]);
                        } else {
                            NSInteger statusCode = ((NSHTTPURLResponse *)response).statusCode;
                            if (statusCode != 200) {
                                responseHandler(nil, [self sendDataErrorWithDescription:
                                                      [NSString stringWithFormat:@"Error in sending data: status code %ld", statusCode]]);
                            } else {
                                NSError *jsonError;
                                NSDictionary *responseDict = data.length?
                                [NSJSONSerialization JSONObjectWithData:data
                                                                options:kNilOptions
                                                                  error:&jsonError]: nil;
                                
                                if (jsonError) responseHandler(nil, [self sendDataErrorWithDescription:
                                                                     [NSString stringWithFormat:@"Failed converting JSON to dictionary: %@", jsonError.localizedDescription]]);
                                else responseHandler(responseDict, nil);
                            }
                        }
                    }];
    [task resume];
}

- (NSError *)sendDataErrorWithDescription:(NSString *)description {
    [self serverLog:description];
    return [NSError errorWithDomain:DMXErrorDomain
                               code:DMXSendDataError
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

@end
