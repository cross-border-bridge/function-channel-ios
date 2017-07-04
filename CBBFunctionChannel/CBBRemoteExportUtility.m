// Copyright © 2017 DWANGO Co., Ltd.

#import "CBBRemoteExport.h"
#import "CBBRemoteExportUtility.h"
#import <objc/runtime.h>

typedef NS_ENUM(NSUInteger, CBBMethodNamingConvension) {
    CBBMethodNamingConvension_ObjC,
    CBBMethodNamingConvension_Swift3,
};

@interface CBBRemoteMethodInfo : NSObject
@property (nonatomic) NSString* fullname;
@property (nonatomic) CBBMethodNamingConvension convention;
@end

@implementation CBBRemoteMethodInfo

+ (CBBRemoteMethodInfo*)infoByName:(NSString*)name convention:(CBBMethodNamingConvension)convention
{
    CBBRemoteMethodInfo* info = [[CBBRemoteMethodInfo alloc] init];
    if (info) {
        info.fullname = name;
        info.convention = convention;
    }
    return info;
}

- (NSString*)extractKeyMethodName
{
    if (_convention == CBBMethodNamingConvension_ObjC) {
        NSMutableArray<NSString*>* array = [[_fullname componentsSeparatedByString:@":"] mutableCopy];
        for (int i = 0; i < array.count; ++i) {
            array[i] = i ? array[i].capitalizedString : array[i];
        }
        return [array componentsJoinedByString:@""];
    } else {
        NSMutableArray<NSString*>* array = [[_fullname componentsSeparatedByString:@":"] mutableCopy];
        for (int i = 0; i < array.count; ++i) {
            if (i == 0) {
                NSRange range = [array[i] rangeOfString:@"With"];
                if (range.location != NSNotFound) {
                    array[i] = [array[i] substringToIndex:range.location];
                }
            } else {
                array[i] = array[i].capitalizedString;
            }
        }
        return [array componentsJoinedByString:@""];
    }
}

@end

@implementation CBBRemoteExportUtility

+ (NSDictionary<NSString*, NSString*>*)exportRemoteExportMethodTableFromClass:(Class)cls
{
    NSArray* protocols = [CBBRemoteExportUtility protocolsConformsToPortocol:@protocol(CBBRemoteExport) class:cls];
    NSArray<CBBRemoteMethodInfo*>* methods = [CBBRemoteExportUtility methodsConformsToProtocolNames:protocols];
    NSDictionary* result = [self remoteExportMethodTableFromMethodNames:methods];
    return result;
}

+ (NSDictionary<NSString*, NSString*>*)remoteExportMethodTableFromMethodNames:(NSArray<CBBRemoteMethodInfo*>*)methodNames
{
    NSMutableDictionary* result = [NSMutableDictionary dictionary];
    [methodNames enumerateObjectsUsingBlock:^(CBBRemoteMethodInfo* _Nonnull obj, NSUInteger idx, BOOL* _Nonnull stop) {
        NSRange range = [obj.fullname rangeOfString:@"__CBB_REMOTE_EXPORT_AS__"];
        if (range.location == NSNotFound) {
            NSString* keyMethodName = [obj extractKeyMethodName];
            result[keyMethodName] = obj.fullname;
        } else {
            NSString* originalMethodName = [obj.fullname substringToIndex:range.location];
            NSString* aliasMethodName = [obj.fullname substringFromIndex:range.location + range.length];
            result[[aliasMethodName substringToIndex:aliasMethodName.length - 1]] = originalMethodName;
        }
    }];
    return result;
}

+ (NSArray<CBBRemoteMethodInfo*>*)methodsConformsToProtocolNames:(NSArray*)protocolNames
{
    NSMutableArray* result = [NSMutableArray array];
    for (NSString* protocolName in protocolNames) {
        Protocol* protocol = NSProtocolFromString(protocolName);
        CBBMethodNamingConvension convention =
            protocol_conformsToProtocol(protocol, @protocol(CBBSwift3RemoteExport))
                ? CBBMethodNamingConvension_Swift3
                : CBBMethodNamingConvension_ObjC;
        unsigned int count = 0;
        struct objc_method_description* required_method_descriptions = protocol_copyMethodDescriptionList(protocol, YES, YES, &count);
        for (unsigned int i = 0; i < count; ++i) {
            [result addObject:[CBBRemoteMethodInfo
                                  infoByName:NSStringFromSelector(required_method_descriptions[i].name)
                                  convention:convention]];
        }
        free(required_method_descriptions);
        count = 0;
        struct objc_method_description* optional_method_descriptions = protocol_copyMethodDescriptionList(protocol, NO, YES, &count);
        for (unsigned int i = 0; i < count; ++i) {
            [result addObject:[CBBRemoteMethodInfo
                                  infoByName:NSStringFromSelector(optional_method_descriptions[i].name)
                                  convention:convention]];
        }
        free(optional_method_descriptions);
    }
    return result;
}

+ (NSArray<NSString*>*)protocolsConformsToPortocol:(Protocol*)protocol class:(Class)cls
{
    NSMutableArray* result = [NSMutableArray array];
    if ([cls conformsToProtocol:protocol]) {
        unsigned int count = 0;
        Protocol* __unsafe_unretained* adops = class_copyProtocolList(cls, &count);
        for (unsigned int i = 0; i < count; ++i) {
            if (protocol_conformsToProtocol(adops[i], protocol)) {
                [result addObject:[NSString stringWithFormat:@"%s", protocol_getName(adops[i])]];
            }
        }
        free(adops);
    }
    return result;
}

@end
