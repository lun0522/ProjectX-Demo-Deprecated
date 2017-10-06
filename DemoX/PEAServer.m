//
//  PEAServer.m
//  DemoX
//
//  Created by Lun on 2017/9/25.
//  Copyright © 2017年 Lun. All rights reserved.
//

#import "PEAServer.h"

static const NSString *kServerIdentityString = @"PEAServer";
static const NSString *kServerType = @"_demox._tcp.";
static const NSString *kServerDomain = @"local.";
static const NSString *kClientAuthenticationString = @"PortableEmotionAnalysis";
static NSDictionary *kDlibLandmarksMap = nil;

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
- (void)sendData:(NSData * _Nonnull)data
 responseHandler:(PEAServerResponseHandler _Nonnull)responseHandler {
    if (!_serverAddress) {
        NSString *errorString = @"No server address found";
        [self serverLog:errorString];
        responseHandler(@{@"error": errorString});
        return;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:_serverAddress]
                                                           cachePolicy:NSURLRequestReloadIgnoringCacheData
                                                       timeoutInterval:10];
    
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:data];
    [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request addValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:[NSString stringWithFormat:@"%ld", data.length] forHTTPHeaderField:@"Content-Length"];
    [request setValue:kClientAuthenticationString.copy forHTTPHeaderField:@"Authentication"];
    
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    [configuration setTimeoutIntervalForRequest:10];
    NSURLSession *urlSession = [NSURLSession sessionWithConfiguration:configuration];
    NSURLSessionTask *task =
    [urlSession uploadTaskWithRequest:request
                             fromData:data
                    completionHandler:^(NSData * _Nullable data,
                                        NSURLResponse * _Nullable response,
                                        NSError * _Nullable error) {
                        if (error) {
                            NSString *errorString = [NSString stringWithFormat:@"Failed in uploading: %@", error.localizedDescription];
                            [self serverLog:errorString];
                            responseHandler(@{@"error": errorString});
                        } else {
                            NSError *error;
                            NSDictionary *responseDict =
                            [NSJSONSerialization JSONObjectWithData:data
                                                            options:kNilOptions
                                                              error:&error];
                            if (error) {
                                NSString *errorString = [NSString stringWithFormat:@"Failed converting JSON to dictionary: %@", error.localizedDescription];
                                [self serverLog:errorString];
                                responseHandler(@{@"error": errorString});
                            } else {
                                responseHandler(responseDict);
                            }
                        }
                    }];
    [task resume];
}

@end
