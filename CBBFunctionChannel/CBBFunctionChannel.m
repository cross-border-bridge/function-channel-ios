// Copyright © 2017 DWANGO Co., Ltd.

#import "CBBFunctionChannel.h"
#import "CBBRemoteExportUtility.h"

NS_ASSUME_NONNULL_BEGIN

NSString* const CBBFunctionChannelFormatEDO = @"edo";
NSString* const CBBFunctionChannelFormatOMI = @"omi";
NSString* const CBBFunctionChannelFormatERR = @"err";

NSString* const CBBFunctionChannelErrorDomain = @"CBBFunctionChannelErrorDomain";
NSString* const CBBFunctionChannelErrorAsync = @"CBBFunctionChannelErrorAsync";

@interface CBBFunctionChannel ()
@property (readwrite) BOOL destroyed;
@property (nonatomic) CBBDataChannel* dataChannel;
@property (nonatomic) CBBDataChannelHandler handler;
@property (nonatomic) NSMutableDictionary<NSString*, id>* instanceTable;
@property (nonatomic) NSMutableDictionary<NSString*, NSDictionary*>* remoteExportMethodTable;
@end

@implementation CBBFunctionChannel

- (instancetype)initWithDataChannel:(CBBDataChannel*)dataChannel
{
    if (self = [super init]) {
        _dataChannel = dataChannel;
        _instanceTable = [NSMutableDictionary dictionary];
        _remoteExportMethodTable = [NSMutableDictionary dictionary];
        __weak typeof(self) __self = self;
        _handler = ^(id _Nullable packet, CBBDataChannelResponseCallback _Nullable callback) {
            if (__self.destroyed) {
                return;
            }
            [__self onReceiveWithFormat:packet[0] packet:packet[1] callback:callback];
        };
        [_dataChannel addHandler:_handler];
    }
    return self;
}

- (void)invokeWithInstanceId:(NSString*)instanceId
                      method:(NSString*)methodName
{
    [self invokeWithInstanceId:instanceId method:methodName arguments:nil timeout:0.0 callback:nil];
}

- (void)invokeWithInstanceId:(NSString*)instanceId
                      method:(NSString*)methodName
                   arguments:(nullable NSArray*)arguments
{
    [self invokeWithInstanceId:instanceId method:methodName arguments:arguments timeout:0.0 callback:nil];
}

- (void)invokeWithInstanceId:(NSString*)instanceId
                      method:(NSString*)methodName
                   arguments:(nullable NSArray*)arguments
                    callback:(nullable CBBFunctionChannelCallback)callback
{
    [self invokeWithInstanceId:instanceId method:methodName arguments:arguments timeout:0.0 callback:callback];
}

- (void)invokeWithInstanceId:(NSString*)instanceId
                      method:(NSString*)methodName
                   arguments:(nullable NSArray*)arguments
                     timeout:(NSTimeInterval)timeout
                    callback:(nullable CBBFunctionChannelCallback)callback
{
    if (_destroyed) {
        return;
    }
    CBBDataChannelCallback dcc = !callback ? nil : ^(NSError* _Nullable errorType, id _Nullable packet) {
        if (_destroyed) {
            return;
        }
        if (errorType) {
            callback(errorType, nil);
        } else if ([packet[0] isEqualToString:CBBFunctionChannelFormatERR]) {
            NSError* fcErrorType = [self parseWithPacket:packet[1]];
            callback(fcErrorType, nil);
        } else if ([packet[0] isEqualToString:CBBFunctionChannelFormatEDO]) {
            callback(nil, packet[1]);
        }
    };
    NSArray* data = @[ CBBFunctionChannelFormatOMI, @[ instanceId, methodName, arguments ? arguments : @[] ] ];
    dcc ? [_dataChannel sendRequest:data timeout:timeout callback:dcc] : [_dataChannel sendPush:data];
}

- (void)bindWithInstanceId:(NSString*)instanceId instance:(id)instance
{
    if (_destroyed) {
        return;
    }
    _instanceTable[instanceId] = instance;
    Class cls = [instance class];
    NSString* className = NSStringFromClass(cls);
    if (!_remoteExportMethodTable[className]) {
        _remoteExportMethodTable[className] = [CBBRemoteExportUtility exportRemoteExportMethodTableFromClass:cls];
        while (nil != (cls = [cls superclass])) {
            NSMutableDictionary* methods = [NSMutableDictionary dictionaryWithDictionary:_remoteExportMethodTable[className]];
            [methods addEntriesFromDictionary:[CBBRemoteExportUtility exportRemoteExportMethodTableFromClass:cls]];
            _remoteExportMethodTable[className] = methods;
        }
    }
}

- (void)unbindWithInstanceId:(NSString*)instanceId
{
    if (_destroyed) {
        return;
    }
    _instanceTable[instanceId] = nil;
}

- (void)destroy
{
    if (_destroyed) {
        return;
    }
    [_dataChannel removeHandler:_handler];
    _dataChannel = nil;
    [_instanceTable removeAllObjects];
    _instanceTable = nil;
    [_remoteExportMethodTable removeAllObjects];
    _destroyed = YES;
}

#pragma mark - Receive

- (void)onReceiveWithFormat:(NSString*)format packet:(nullable id)packet callback:(nullable CBBDataChannelResponseCallback)callback
{
    if ([format isEqualToString:CBBFunctionChannelFormatOMI]) {
        NSArray* packetArray;
        if ([packet isKindOfClass:[NSArray class]]) {
            packetArray = packet;
        }
        if (!packetArray || packetArray.count < 2) {
            return;
        }
        NSString* instanceId = packetArray[0];
        NSString* methodName = packetArray[1];
        NSArray* arguments = (packetArray.count >= 3 && ![packetArray[2] isEqual:[NSNull null]]) ? packetArray[2] : nil;
        if ([callback isEqual:[NSNull null]])
            callback = nil;

        [self dispatchMethodInvocationWithInstanceId:instanceId methodName:methodName arguments:arguments callback:callback];
    } else {
        NSLog(@"Unknown format %@", format);
    }
}

- (void)dispatchMethodInvocationWithInstanceId:(NSString*)instanceId
                                    methodName:(NSString*)methodName
                                     arguments:(nullable NSArray*)arguments
                                      callback:(nullable CBBDataChannelResponseCallback)callback
{
    id instance = self.instanceTable[instanceId];
    if (!instance) {
        if (callback) {
            NSString* errorString = [self stringFromErrorType:CBBFunctionChannelErrorTypeObjectNotBound];
            callback(@[ CBBFunctionChannelFormatERR, errorString ]);
        }
    } else {
        NSString* className = NSStringFromClass([instance class]);
        NSString* conformsMethod = self.remoteExportMethodTable[className][methodName];
        if (!conformsMethod) {
            if (callback) {
                NSString* errorString = [self stringFromErrorType:CBBFunctionChannelErrorTypeMethodNotExist];
                callback(@[ CBBFunctionChannelFormatERR, errorString ]);
            }
            return;
        }
        SEL selector = NSSelectorFromString(conformsMethod);

        NSMethodSignature* methodSignature = [instance methodSignatureForSelector:selector];
        if (methodSignature.numberOfArguments != arguments.count + 2) {
            if (callback) {
                NSString* errorString = [self stringFromErrorType:CBBFunctionChannelErrorTypeMethodNotExist];
                callback(@[ CBBFunctionChannelFormatERR, errorString ]);
            }
            return;
        }

        NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
        invocation.selector = selector;
        invocation.target = instance;
        NSInteger index = 2;
        for (id argument in arguments) {
            [invocation setArgument:(void*)&argument atIndex:index++];
        }
        [invocation retainArguments];
        [invocation invoke];

        if (callback) {
            // 戻り値型に応じたコールバック
            switch (invocation.methodSignature.methodReturnType[0]) {
                case 'v':
                    callback(@[ CBBFunctionChannelFormatEDO, [NSNull null] ]);
                    break;
                case '@': { // オブジェクト型
                    CFTypeRef result;
                    [invocation getReturnValue:&result];
                    CFRetain(result);
                    id resultObject = (__bridge_transfer id)result;
                    if ([resultObject isKindOfClass:[CBBAsyncResult class]]) {
                        // CBBAsyncResultの場合は結果をコールバックで返す
                        ((CBBAsyncResult*)resultObject).onComplete(^(id result) {
                            callback(@[ CBBFunctionChannelFormatEDO, result ]);
                        });
                        [(CBBAsyncResult*)resultObject execute];
                    } else {
                        callback(@[ CBBFunctionChannelFormatEDO, resultObject ]);
                    }
                    break;
                }
                case 'b':
                case 'B': { // bool/BOOL型
                    BOOL result;
                    [invocation getReturnValue:&result];
                    callback(@[ CBBFunctionChannelFormatEDO, @(result) ]);
                    break;
                }
                case 'f': { // float型
                    float result;
                    [invocation getReturnValue:&result];
                    callback(@[ CBBFunctionChannelFormatEDO, @(result) ]);
                    break;
                }
                case 'd': { // double型
                    double result;
                    [invocation getReturnValue:&result];
                    callback(@[ CBBFunctionChannelFormatEDO, @(result) ]);
                    break;
                }
                default: { // その他は全て NSInteger に変換したオブジェクトで返す
                    NSInteger result;
                    [invocation getReturnValue:&result];
                    callback(@[ CBBFunctionChannelFormatEDO, @(result) ]);
                    break;
                }
            }
        }
    }
}

#pragma mark - Error

- (CBBFunctionChannelErrorType)errorTypeFromString:(NSString*)errorString
{
    if ([errorString isEqualToString:@"ObjectNotBound"]) {
        return CBBFunctionChannelErrorTypeObjectNotBound;
    } else if ([errorString isEqualToString:@"MethodNotExist"]) {
        return CBBFunctionChannelErrorTypeMethodNotExist;
    } else {
        return CBBFunctionChannelErrorTypeUnspecified;
    }
}

- (NSString*)stringFromErrorType:(CBBFunctionChannelErrorType)errorType
{
    NSString* result = nil;
    switch (errorType) {
        case CBBFunctionChannelErrorTypeObjectNotBound:
            result = @"ObjectNotBound";
            break;
        case CBBFunctionChannelErrorTypeMethodNotExist:
            result = @"MethodNotExist";
            break;
        default:
            break;
    }
    return result;
}

- (NSError*)parseWithPacket:(id)packetObject
{
    CBBFunctionChannelErrorType errorType = [self errorTypeFromString:packetObject];
    NSError* error = [NSError errorWithDomain:CBBFunctionChannelErrorDomain code:errorType userInfo:nil];
    return error;
}

@end

NS_ASSUME_NONNULL_END
