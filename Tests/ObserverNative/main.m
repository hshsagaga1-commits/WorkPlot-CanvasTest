#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "ObserverNative.h"
#include <assert.h>

@interface Fixture : NSObject
@property(nonatomic, readonly) NSString *name;
@property(nonatomic, readonly) NSInteger displayId;
@property(nonatomic, readonly) CGRect bounds;
@property(nonatomic, readonly) CGSize nativeSize;
@property(nonatomic, readonly) double pointScale;
@property(nonatomic, readonly) void *logicalScale;
@end
@implementation Fixture
- (NSString *)name { return @"synthetic"; }
- (NSInteger)displayId { return 7; }
- (CGRect)bounds { return CGRectMake(0, 0, 10, 20); }
- (CGSize)nativeSize { return CGSizeMake(20, 40); }
- (double)pointScale { @throw [NSException exceptionWithName:@"SyntheticException" reason:@"fixture" userInfo:nil]; }
- (void *)logicalScale { assert(false && "Unsupported return type must not be called"); return NULL; }
@end

int main(void) {
    @autoreleasepool {
        NSDictionary *result = RLObserveDisplayObject([Fixture new]);
        assert([result[@"name"][@"value"] isEqual:@"synthetic"]);
        assert([result[@"displayId"][@"value"] integerValue] == 7);
        assert([result[@"bounds"][@"value"][@"width"] doubleValue] == 10);
        assert([result[@"nativeSize"][@"value"][@"height"] doubleValue] == 40);
        assert([result[@"pointScale"][@"status"] isEqual:@"exception"]);
        assert([result[@"logicalScale"][@"status"] isEqual:@"unsupported_return_type"]);
        assert([result[@"deviceName"][@"status"] isEqual:@"unavailable"]);
        NSError *error = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:result options:0 error:&error];
        assert(json && !error);
        puts("Observer native tests passed: values, geometry, missing selector, unknown type, exception and JSON.");
    }
    return 0;
}
