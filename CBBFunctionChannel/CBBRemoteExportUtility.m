// Copyright © 2017 DWANGO Co., Ltd.

#import "CBBRemoteExport.h"
#import "CBBRemoteExportUtility.h"
#import <objc/runtime.h>

@implementation CBBRemoteExportUtility

+ (NSDictionary<NSString*, NSString*>*)exportRemoteExportMethodTableFromClass:(Class)cls
{
    NSArray* methods = [CBBRemoteExportUtility methodsConformsToProtocol:@protocol(CBBRemoteExport) class:cls];
    NSDictionary* result = [self remoteExportMethodTableFromMethodNames:methods];
    return result;
}

+ (NSDictionary<NSString*, NSString*>*)remoteExportMethodTableFromMethodNames:(NSArray*)methodNames
{
    NSMutableDictionary* result = [NSMutableDictionary dictionary];
    [methodNames enumerateObjectsUsingBlock:^(id _Nonnull obj, NSUInteger idx, BOOL* _Nonnull stop) {
        NSRange range = [obj rangeOfString:@"__CBB_REMOTE_EXPORT_AS__"];
        if (range.location == NSNotFound) {
            NSString* keyMethodName = ^() {
                NSMutableArray<NSString*>* array = [[obj componentsSeparatedByString:@":"] mutableCopy];
                for (int i = 0; i < array.count; ++i) {
                    array[i] = i ? array[i].capitalizedString : array[i];
                }
                return [array componentsJoinedByString:@""];
            }();
            result[keyMethodName] = obj;
        } else {
            NSString* originalMethodName = [obj substringToIndex:range.location];
            NSString* aliasMethodName = [obj substringFromIndex:range.location + range.length];
            result[[aliasMethodName substringToIndex:aliasMethodName.length - 1]] = originalMethodName;
        }
    }];
    return result;
}

+ (NSArray<NSString*>*)methodsConformsToProtocol:(Protocol*)protocol class:(Class)cls
{
    NSMutableArray* result = [NSMutableArray array];
    if ([cls conformsToProtocol:protocol]) {
        unsigned int count = 0;
        Protocol* __unsafe_unretained* adops = class_copyProtocolList(cls, &count);
        for (unsigned int i = 0; i < count; ++i) {
            if (protocol_conformsToProtocol(adops[i], protocol)) {
                unsigned int count = 0;
                struct objc_method_description* required_method_descriptions = protocol_copyMethodDescriptionList(adops[i], YES, YES, &count);
                for (unsigned int i = 0; i < count; ++i) {
                    NSString* str = NSStringFromSelector(required_method_descriptions[i].name);
                    [result addObject:str];
                }
                free(required_method_descriptions);
                count = 0;
                struct objc_method_description* optional_method_descriptions = protocol_copyMethodDescriptionList(adops[i], NO, YES, &count);
                for (unsigned int i = 0; i < count; ++i) {
                    NSString* str = NSStringFromSelector(optional_method_descriptions[i].name);
                    [result addObject:str];
                }
                free(optional_method_descriptions);
            }
        }
        free(adops);
    }
    return result;
}

@end
