//
//  HttpManager.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/16/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "HttpResponse.h"
#import "HttpRequest.h"
#import "StreamConfiguration.h"
#import "TemporaryHost.h"

@interface HttpManager : NSObject <NSURLSessionDelegate>

- (id) initWithHost:(TemporaryHost*) host;
- (id) initWithAddress:(NSString*) hostAddressPortString httpsPort:(unsigned short) httpsPort serverCert:(NSData*) serverCert;
- (void) setServerCert:(NSData*) serverCert;
- (NSURLRequest*) newPairRequest:(NSData*)salt clientCert:(NSData*)clientCert;
- (NSURLRequest*) newUnpairRequest;
- (NSURLRequest*) newChallengeRequest:(NSData*)challenge;
- (NSURLRequest*) newChallengeRespRequest:(NSData*)challengeResp;
- (NSURLRequest*) newClientSecretRespRequest:(NSString*)clientPairSecret;
- (NSURLRequest*) newPairChallenge;
- (NSURLRequest*) newAppListRequest;
- (NSURLRequest*) newServerInfoRequest:(bool)fastFail;
- (NSURLRequest*) newHttpServerInfoRequest:(bool)fastFail;
- (NSURLRequest*) newHttpServerInfoRequest;
- (NSURLRequest*) newLaunchOrResumeRequest:(NSString*)verb config:(StreamConfiguration*)config;
- (NSURLRequest*) newQuitAppRequest;
- (NSURLRequest*) newAppAssetRequestWithAppId:(NSString*)appId;

// Apollo clipboard extension (text only, only while streaming).
// Responses are raw text, not XML, so send these with your own NSURLSession
// using this HttpManager as the session delegate (it handles the TLS pinning
// and client certificate) instead of executeRequestSynchronously.
- (NSURLRequest*) newGetClipboardRequest;
- (NSURLRequest*) newSetClipboardRequest:(NSData*)utf8Text;
- (void) executeRequestSynchronously:(HttpRequest*)request;

@end


