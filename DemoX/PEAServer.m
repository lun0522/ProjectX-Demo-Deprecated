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
static const NSString *kLeanCloudUrl = @"https://us-api.leancloud.cn/1.1/classes/Server";
static const NSString *kLeanCloudAppId = @"OH4VbcK1AXEtklkhpkGCikPB-MdYXbMMI";
static const NSString *kLeanCloudAppKey = @"0azk0HxCkcrtNGIKC5BMwxnr";
static const NSString *kLeanCloudObjectId = @"5a40a4eee37d040044aa4733";
static const NSString *kClientAuthenticationString = @"PortableEmotionAnalysis";
static NSDictionary *kServerOperationDict = nil;

@interface PEAServer () <NSNetServiceBrowserDelegate, NSNetServiceDelegate> {
    NSNetServiceBrowser *_netServiceBrowser;
    NSMutableArray *_netServiceResolverList;
    NSString *_serverAddress;
}

@end

@implementation PEAServer

- (instancetype)init {
    if (self = [super init]) {
        kServerOperationDict = @{
                                 @(PEAServerStore)   : @"Store",
                                 @(PEAServerDelete)  : @"Delete",
                                 @(PEAServerTransfer): @"Transfer",
                                 };
//        [self searchServerInLAN];
        [self requestServerAddress];
    }
    return self;
}

- (void)serverLog:(NSString *)content {
    NSLog(@"%@", [NSString stringWithFormat:@"[PEAServer] %@", content]);
}

#pragma mark - Search server with Bonjour

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

#pragma mark - NSNetServiceBrowser

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

#pragma mark - NSNetServiceResolver

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

#pragma mark - HTTP requests

- (void)requestServerAddress {
    __weak PEAServer *weakSelf = self;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kLeanCloudUrl.copy]
                                                           cachePolicy:NSURLRequestReloadIgnoringCacheData
                                                       timeoutInterval:10];
    [request setHTTPMethod:@"GET"];
    NSDictionary *headerField = @{@"X-LC-Id": kLeanCloudAppId,
                                  @"X-LC-Key": kLeanCloudAppKey,
                                  @"Content-Type": @"application/json",
                                  };
    [headerField enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull field,
                                                     NSString * _Nonnull value,
                                                     BOOL * _Nonnull stop) {
        [request setValue:value forHTTPHeaderField:field];
    }];
    NSURLSession *urlSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    NSURLSessionTask *task =
    [urlSession dataTaskWithRequest:request
                  completionHandler:^(NSData * _Nullable data,
                                      NSURLResponse * _Nullable response,
                                      NSError * _Nullable error) {
                      if (error) {
                          [weakSelf serverLog:[@"Error in requesting server address: %@" stringByAppendingString:error.localizedDescription]];
                      } else if (!data) {
                          [weakSelf serverLog:@"No data returned by requesting server address"];
                      } else {
                          NSError *jsonError;
                          NSDictionary *responseDict =
                          [NSJSONSerialization JSONObjectWithData:data
                                                          options:kNilOptions
                                                            error:&jsonError];
                          
                          if (!responseDict[@"results"]) {
                              [weakSelf serverLog:@"No result returned by requesting server address"];
                          } else if (!_serverAddress) {
                              _serverAddress = ((NSDictionary *)((NSArray *)responseDict[@"results"])[0])[@"address"];
                              [weakSelf serverLog:[NSString stringWithFormat:@"Use address: %@", _serverAddress]];
                              [weakSelf stopBrowsing];
                          }
                      }
                  }];
    [task resume];
}

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
                                NSString *contentType = ((NSHTTPURLResponse *)response).allHeaderFields[@"Content-Type"];
                                if (contentType) {
                                    if ([contentType isEqualToString:@"application/json"]) {
                                        NSError *jsonError;
                                        NSDictionary *responseDict = data.length?
                                        [NSJSONSerialization JSONObjectWithData:data
                                                                        options:kNilOptions
                                                                          error:&jsonError]: nil;
                                        
                                        if (jsonError) responseHandler(nil, [self sendDataErrorWithDescription:
                                                                             [NSString stringWithFormat:
                                                                              @"Failed converting JSON to dictionary: %@",
                                                                              jsonError.localizedDescription]]);
                                        else responseHandler(responseDict, nil);
                                    } else if ([contentType isEqualToString:@"application/octet-stream"]) {
                                        NSDictionary *responseHeaderFields = ((NSHTTPURLResponse *)response).allHeaderFields;
                                        NSDictionary *responseDict = data.length? @{@"binaryData": data,
                                                                                    @"url": responseHeaderFields[@"Image-URL"],
                                                                                    @"title": responseHeaderFields[@"Image-Title"],
                                                                                    }: nil;
                                        responseHandler(responseDict, nil);
                                    } else {
                                        responseHandler(nil, [self sendDataErrorWithDescription:@"Unknown content type"]);
                                    }
                                } else {
                                    responseHandler(nil, [self sendDataErrorWithDescription:@"Content type not specified"]);
                                }
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
