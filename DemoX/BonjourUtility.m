//
//  BonjourUtility.m
//  DemoX
//
//  Created by Lun on 2017/9/25.
//  Copyright © 2017年 Lun. All rights reserved.
//

#import "BonjourUtility.h"

static const NSString *kServerIdentityString = @"PEAServer";
static const NSString *kServerType = @"_demox._tcp.";
static const NSString *kServerDomain = @"local.";

@interface BonjourUtility () <NSNetServiceBrowserDelegate, NSNetServiceDelegate> {
    NSNetServiceBrowser *_netServiceBrowser;
    NSNetService *_netServiceResolver;
    DMXSearchServerCompletionHandler _completionHandler;
    BOOL _isSearching;
}

@end

@implementation BonjourUtility

- (instancetype)init {
    if (self = [super init]) {
        _isSearching = NO;
    }
    return self;
}

- (void)searchServerWithCompletionHandler:(DMXSearchServerCompletionHandler)completionHandler {
    if (!_isSearching) {
        _isSearching = YES;
        _netServiceBrowser = [[NSNetServiceBrowser alloc] init];
        [_netServiceBrowser setDelegate:self];
        [_netServiceBrowser searchForServicesOfType:@"_demox._tcp."
                                           inDomain:@"local."];
        _completionHandler = completionHandler;
        NSLog(@"Start browsing for Bonjour services");
    }
}

- (void)allCleanup {
    _isSearching = NO;
    [self browserCleanup];
    [self resolverCleanup];
    _completionHandler = nil;
}

#pragma mark NSNetServiceBrowserDelegate

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
           didFindService:(NSNetService *)service
               moreComing:(BOOL)moreComing {
    _netServiceResolver = service;
    [_netServiceResolver setDelegate:self];
    [_netServiceResolver resolveWithTimeout:10.0];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
             didNotSearch:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    NSLog(@"Error in browsing for Bonjour services: %@", errorDict);
}

- (void)browserCleanup {
    if (_netServiceBrowser) {
        [_netServiceBrowser stop];
        [_netServiceBrowser setDelegate:nil];
        _netServiceBrowser = nil;
    }
}

#pragma mark NSNetServiceDelegate

- (void)netServiceDidResolveAddress:(NSNetService *)service {
    if (service.TXTRecordData) {
        NSDictionary *txtRecord = [NSNetService dictionaryFromTXTRecordData:service.TXTRecordData];
        if (txtRecord[@"Identity"]) {
            if ([[[NSString alloc] initWithData:(NSData *)txtRecord[@"Identity"] encoding:NSUTF8StringEncoding] isEqualToString:kServerIdentityString.copy]) {
                if (txtRecord[@"Address"]) {
                    NSLog(@"Address: %@", [[NSString alloc] initWithData:(NSData *)txtRecord[@"Address"] encoding:NSUTF8StringEncoding]);
                    _completionHandler();
                    [self allCleanup];
                }
                else NSLog(@"Authenticated, but no address found");
            }
        }
    }
}

- (void)netService:(NSNetService *)service
     didNotResolve:(NSDictionary *)errorDict {
    NSLog(@"Error in resolving Bonjour service: %@", errorDict);
}

- (void)resolverCleanup {
    if (_netServiceResolver) {
        [_netServiceResolver stop];
        [_netServiceResolver setDelegate:nil];
    }
}

@end
