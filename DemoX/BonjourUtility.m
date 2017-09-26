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
    NSMutableArray *_netServiceResolverList;
    DMXSearchServerCompletionHandler _completionHandler;
    BOOL _isSearching;
}

@end

@implementation BonjourUtility

- (instancetype)init {
    if (self = [super init]) {
        _netServiceResolverList = [[NSMutableArray alloc] init];
        _isSearching = NO;
    }
    return self;
}

- (void)searchServerWithCompletionHandler:(DMXSearchServerCompletionHandler)completionHandler {
    if (!_isSearching) {
        _isSearching = YES;
        _netServiceBrowser = [[NSNetServiceBrowser alloc] init];
        [_netServiceBrowser setDelegate:self];
        [_netServiceBrowser searchForServicesOfType:kServerType.copy
                                           inDomain:kServerDomain.copy];
        _completionHandler = completionHandler;
        NSLog(@"Start browsing for Bonjour services");
    }
}

- (void)allCleanup {
    _isSearching = NO;
    [self browserCleanup];
    for (NSNetService *netServiceResolver in _netServiceResolverList)
        [self resolverCleanup:netServiceResolver];
    [_netServiceResolverList removeAllObjects];
    _completionHandler = nil;
}

#pragma mark NSNetServiceBrowserDelegate

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
           didFindService:(NSNetService *)service
               moreComing:(BOOL)moreComing {
    [_netServiceResolverList addObject:service];
    [service setDelegate:self];
    [service resolveWithTimeout:10.0];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
             didNotSearch:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    [self allCleanup];
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
                    _completionHandler([[NSString alloc] initWithData:(NSData *)txtRecord[@"Address"] encoding:NSUTF8StringEncoding]);
                    [self allCleanup];
                    return;
                }
                else NSLog(@"Authenticated, but no address found: %@", service);
            }
            else NSLog(@"Identified, but not authenticated: %@", service);
        }
        else NSLog(@"No identity: %@", service);
    }
    else NSLog(@"No TXT record: %@", service);
    
    if ([_netServiceResolverList containsObject:service])
        [_netServiceResolverList removeObject:service];
}

- (void)netService:(NSNetService *)service
     didNotResolve:(NSDictionary *)errorDict {
    if ([_netServiceResolverList containsObject:service])
        [_netServiceResolverList removeObject:service];
    NSLog(@"Error in resolving Bonjour service %@: %@", service, errorDict);
}

- (void)resolverCleanup:(NSNetService *)netServiceResolver {
    if (netServiceResolver) {
        [netServiceResolver stop];
        [netServiceResolver setDelegate:nil];
    }
}

@end
