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

@interface PEAServer () <NSNetServiceBrowserDelegate, NSNetServiceDelegate> {
    NSNetServiceBrowser *_netServiceBrowser;
    NSMutableArray *_netServiceResolverList;
    NSString *_serverAddress;
}

@end

@implementation PEAServer

- (instancetype)initWithAddress:(NSString *)address {
    if (self = [super init]) {
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

- (void)serverLog:(NSString *)content {
    NSLog(@"%@", [NSString stringWithFormat:@"PEAServer Log - %@", content]);
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

- (void)stopSearch {
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
    [self stopSearch];
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
                    [self stopSearch];
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

#pragma mark Send request to server
- (void)sendRequest:(NSDictionary * _Nonnull)requestDict
    responseHandler:(PEAServerResponseHandler _Nonnull)responseHandler {
    if (!_serverAddress) {
        NSString *errorString = @"No server address found";
        [self serverLog:errorString];
        responseHandler(@{@"error": errorString});
        return;
    }
    
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:requestDict
                                                       options:kNilOptions
                                                         error:&error];
    if (error) {
        NSString *errorString = [NSString stringWithFormat:@"Failed converting dictionary to JSON: %@", error.localizedDescription];
        [self serverLog:errorString];
        responseHandler(@{@"error": errorString});
        return;
    }
    
    NSString *dataLength = [NSString stringWithFormat:@"%ld", jsonData.length];
    NSMutableURLRequest *request =
    [NSMutableURLRequest requestWithURL:[NSURL URLWithString:_serverAddress]
                            cachePolicy:NSURLRequestReloadIgnoringCacheData
                        timeoutInterval:10];
    
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:jsonData];
    [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request addValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:dataLength forHTTPHeaderField:@"Content-Length"];
    [request setValue:kClientAuthenticationString.copy forHTTPHeaderField:@"Authentication"];
    
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    [configuration setTimeoutIntervalForRequest:10];
    NSURLSession *urlSession = [NSURLSession sessionWithConfiguration:configuration];
    NSURLSessionTask *task =
    [urlSession uploadTaskWithRequest:request
                             fromData:jsonData
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
