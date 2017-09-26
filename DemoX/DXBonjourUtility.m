//
//  DXBonjourUtility.m
//  DemoX
//
//  Created by Lun on 2017/9/25.
//  Copyright © 2017年 Lun. All rights reserved.
//

#import "DXBonjourUtility.h"

static const NSString *kServerIdentityString = @"PEAServer";

@interface DXBonjourUtility () <NSNetServiceBrowserDelegate, NSNetServiceDelegate> {
    NSNetServiceBrowser *_netServiceBrowser;
}

@end

@implementation DXBonjourUtility

#pragma mark NSNetServiceBrowserDelegate

- (void)startNetServiceBrowser {
    _netServiceBrowser = [[NSNetServiceBrowser alloc] init];
    [_netServiceBrowser setDelegate:self];
    [_netServiceBrowser searchForServicesOfType:@"_demox._tcp."
                                       inDomain:@"local."];
    NSLog(@"Start browsing for Bonjour services");
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
           didFindService:(NSNetService *)service
               moreComing:(BOOL)moreComing {
    [service setDelegate:self];
    [service resolveWithTimeout:30.0];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
             didNotSearch:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    [self browserCleanup];
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
            if ([txtRecord[@"Identity"] isEqualToString:kServerIdentityString.copy]) {
                if (txtRecord[@"Address"]) NSLog(@"Address: %@", txtRecord[@"Address"]);
                else NSLog(@"Authenticated, but no address found");
            }
        }
    }
}

- (void)netService:(NSNetService *)service
     didNotResolve:(NSDictionary *)errorDict {
    [self resolverCleanup:service];
    NSLog(@"Error in resolving Bonjour service: %@", errorDict);
}

- (void)resolverCleanup:(NSNetService *)netServiceResolver {
    if (netServiceResolver) {
        [netServiceResolver stop];
        [netServiceResolver setDelegate:nil];
    }
}

@end
