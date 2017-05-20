// SBTUITunneledHost.m
//
// Copyright (C) 2017 Subito.it S.r.l (www.subito.it)
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "SBTUITunneledHost.h"
#include <ifaddrs.h>
#include <arpa/inet.h>

NSString * const SBTUITestTunnelHostValidationToken = @"lkju32yt$£bmnA";
NSString * const SBTUITestTunnelHostResponseResultKey = @"result";
NSString * const SBTUITestTunnelHostHTTPMethod = @"POST";

// For the time being we use localhost here
// We could alternatively check for the "com.sbtuitesttunnel.mac.host" bonjour service to get address and port
NSString * const SBTUITunneledHostDefaultHost = @"localhost";
const uint16_t SBTUITunneledHostDefaultPort = 8667;

const NSTimeInterval SBTUITunneledHostDefaultTimeout = 30.0;

@interface SBTUITunneledHost()

@property (nonatomic, assign) BOOL connected;
@property (nonatomic, weak) XCUIApplication *app;
@property (nonatomic, assign) NSUInteger remotePort;
@property (nonatomic, strong) NSNetService *remoteService;
@property (nonatomic, strong) NSString *remoteHost;

@end

@implementation SBTUITunneledHost

- (instancetype)initWithApp:(XCUIApplication *)app
{
    self = [super init];
    
    if (self) {
        _connected = NO;
        _remotePort = SBTUITunneledHostDefaultPort;
        _remoteHost = SBTUITunneledHostDefaultHost;
        _app = app;
    }
    
    return self;
}

- (void)connect
{
    NSAssert([self executeCommand:@""] != nil, @"Failed to connect to remote host");
    
    self.connected = YES;
}

- (NSString *)performAction:(NSString *)action data:(NSString *)data
{
    NSDictionary *params = @{ @"command": data, @"app_frame": NSStringFromCGRect(self.app.frame), @"token": SBTUITestTunnelHostValidationToken };
    
    NSString *urlString = [NSString stringWithFormat:@"http://%@:%d/%@", self.remoteHost, (unsigned int)self.remotePort, action];
    
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSMutableURLRequest *request = nil;
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    
    NSMutableArray *queryItems = [NSMutableArray array];
    [params enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        NSCharacterSet *URLBase64CharacterSet = [[NSCharacterSet characterSetWithCharactersInString:@"/+=\n"] invertedSet];
        NSString *escapedValue = [value stringByAddingPercentEncodingWithAllowedCharacters:URLBase64CharacterSet];
        
        [queryItems addObject:[NSURLQueryItem queryItemWithName:key value:escapedValue]];
    }];
    components.queryItems = queryItems;
    
    if ([SBTUITestTunnelHostHTTPMethod isEqualToString:@"GET"]) {
        request = [NSMutableURLRequest requestWithURL:components.URL];
    } else if ([SBTUITestTunnelHostHTTPMethod isEqualToString:@"POST"]) {
        request = [NSMutableURLRequest requestWithURL:url];
        
        request.HTTPBody = [components.query dataUsingEncoding:NSUTF8StringEncoding];
    }
    request.HTTPMethod = SBTUITestTunnelHostHTTPMethod;
    
    if (!request) {
        NSAssert(NO, @"[SBTUITestTunnelHost] Did fail to create url component");
        return nil;
    }
    
    dispatch_semaphore_t synchRequestSemaphore = dispatch_semaphore_create(0);
    
    NSURLSession *session = [NSURLSession sharedSession];
    
    __block NSString *responseString = nil;
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSAssert(NO, @"[SBTUITestTunnelHost] Failed to get http response");
        } else {
            NSDictionary *jsonData = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
            responseString = jsonData[SBTUITestTunnelHostResponseResultKey];
            
            NSAssert(((NSHTTPURLResponse *)response).statusCode == 200, @"[SBTUITestTunnelHost] Message sending failed");
        }
        
        dispatch_semaphore_signal(synchRequestSemaphore);
    }] resume];
    
    dispatch_semaphore_wait(synchRequestSemaphore, DISPATCH_TIME_FOREVER);
    
    return responseString;
}

- (NSString *)executeCommand:(NSString *)command;
{
    NSString *commandB64 = [[command dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed];

    NSString *action = @"exec";
    
    return [self performAction:action data:commandB64];
}

- (void)executeMouseClicks:(NSArray<SBTUITunneledHostMouseClick *> *)clicks
{
    NSData *encodedDrags = [NSKeyedArchiver archivedDataWithRootObject:clicks];
    NSString *commandB64 = [encodedDrags base64EncodedStringWithOptions:0];
    
    NSString *action = @"mouse/clicks";
    
    [self performAction:action data:commandB64];
}

- (void)executeMouseDrags:(NSArray<SBTUITunneledHostMouseDrag *> *)drags
{
    NSData *encodedDrags = [NSKeyedArchiver archivedDataWithRootObject:drags];
    NSString *commandB64 = [encodedDrags base64EncodedStringWithOptions:0];
    
    NSString *action = @"mouse/drags";
    
    [self performAction:action data:commandB64];
}

@end
