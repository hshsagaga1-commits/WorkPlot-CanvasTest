#import "ObserverNative.h"
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <math.h>
#include <string.h>

static NSDictionary *RLField(id object, NSString *key) {
    @try {
        SEL selector = NSSelectorFromString(key);
        if (![object respondsToSelector:selector]) return @{@"status": @"unavailable"};
        NSMethodSignature *signature = [object methodSignatureForSelector:selector];
        if (!signature || signature.numberOfArguments != 2) return @{@"status": @"unsupported_signature"};
        const char *type = signature.methodReturnType;
        while (*type && strchr("rnNoORV", *type)) type++;
        BOOL scalar = strlen(type) == 1 && strchr("BcsilqCSILQfd", *type);
        BOOL geometry = strcmp(type, @encode(CGRect)) == 0 || strcmp(type, @encode(CGSize)) == 0;
        BOOL objectType = strcmp(type, @encode(id)) == 0;
        if (!scalar && !geometry && !objectType) return @{@"status": @"unsupported_return_type"};

        id value = [object valueForKey:key];
        if (!value) return @{@"status": @"nil"};
        if ([value isKindOfClass:NSString.class]) {
            NSString *text = value;
            return @{@"status": @"ok", @"type": @"string", @"value": [text substringToIndex:MIN(text.length, 256)]};
        }
        if ([value isKindOfClass:NSNumber.class]) {
            if (!isfinite([value doubleValue])) return @{@"status": @"non_finite"};
            return @{@"status": @"ok", @"type": @"number", @"value": value};
        }
        if ([value isKindOfClass:NSValue.class] && strcmp([value objCType], @encode(CGRect)) == 0) {
            CGRect rect;
            [value getValue:&rect size:sizeof(rect)];
            if (!isfinite(rect.origin.x) || !isfinite(rect.origin.y) || !isfinite(rect.size.width) || !isfinite(rect.size.height)) {
                return @{@"status": @"non_finite"};
            }
            return @{@"status": @"ok", @"type": @"CGRect", @"units": @"framework_defined",
                     @"value": @{@"x": @(rect.origin.x), @"y": @(rect.origin.y),
                                 @"width": @(rect.size.width), @"height": @(rect.size.height)}};
        }
        if ([value isKindOfClass:NSValue.class] && strcmp([value objCType], @encode(CGSize)) == 0) {
            CGSize size;
            [value getValue:&size size:sizeof(size)];
            if (!isfinite(size.width) || !isfinite(size.height)) return @{@"status": @"non_finite"};
            return @{@"status": @"ok", @"type": @"CGSize", @"units": @"framework_defined",
                     @"value": @{@"width": @(size.width), @"height": @(size.height)}};
        }
        return @{@"status": @"unsupported_value"};
    } @catch (NSException *exception) {
        return @{@"status": @"exception", @"exceptionName": exception.name ?: @"unknown"};
    }
}

NSDictionary<NSString *, id> *RLObserveDisplayObject(id object) {
    NSArray *keys = @[@"name", @"deviceName", @"displayId", @"displayType", @"isExternal",
                       @"bounds", @"nativeSize", @"pointScale", @"logicalScale"];
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    for (NSString *key in keys) fields[key] = RLField(object, key);
    return fields;
}

NSDictionary<NSString *, id> *RLReadCADisplayInventory(void) {
    @autoreleasepool {
        @try {
            (void)[CALayer class];
            Class displayClass = NSClassFromString(@"CADisplay");
            if (!displayClass) return @{@"status": @"class_unavailable", @"displays": @[]};
            SEL selector = NSSelectorFromString(@"displays");
            if (![displayClass respondsToSelector:selector]) return @{@"status": @"enumeration_unavailable", @"displays": @[]};
            NSMethodSignature *signature = [displayClass methodSignatureForSelector:selector];
            if (signature.numberOfArguments != 2 || strcmp(signature.methodReturnType, @encode(id)) != 0) {
                return @{@"status": @"enumeration_signature_unsupported", @"displays": @[]};
            }
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            invocation.target = displayClass;
            invocation.selector = selector;
            [invocation invoke];
            __unsafe_unretained id returned = nil;
            [invocation getReturnValue:&returned];
            id collection = returned;
            if (![collection isKindOfClass:NSArray.class]) return @{@"status": @"collection_unavailable", @"displays": @[]};
            NSArray *displays = collection;
            NSMutableArray *rows = [NSMutableArray array];
            NSUInteger count = MIN(displays.count, 8);
            for (NSUInteger index = 0; index < count; index++) [rows addObject:RLObserveDisplayObject(displays[index])];
            return @{@"status": @"completed", @"reportedCount": @(displays.count),
                     @"collectedCount": @(count), @"truncated": @(count < displays.count), @"displays": rows};
        } @catch (NSException *exception) {
            return @{@"status": @"enumeration_exception", @"exceptionName": exception.name ?: @"unknown", @"displays": @[]};
        }
    }
}
