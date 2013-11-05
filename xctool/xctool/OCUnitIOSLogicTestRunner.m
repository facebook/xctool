//
// Copyright 2013 Facebook
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "OCUnitIOSLogicTestRunner.h"

#import "NSConcreteTask.h"
#import "TaskUtil.h"
#import "TestingFramework.h"
#import "XCToolUtil.h"

@implementation OCUnitIOSLogicTestRunner

- (NSDictionary *)environmentOverrides
{
  NSString *version = [_buildSettings[@"SDK_NAME"] stringByReplacingOccurrencesOfString:@"iphonesimulator" withString:@""];
  NSString *productVersion = GetProductVersionForSDKVersion(version);
  NSString *simulatorHome = [NSString stringWithFormat:@"%@/Library/Application Support/iPhone Simulator/%@", NSHomeDirectory(), productVersion];
  NSString *simVersions = GetIPhoneSimulatorVersionsStringForSDKVersion(version);

  return @{@"CFFIXED_USER_HOME" : simulatorHome,
           @"HOME" : simulatorHome,
           @"IPHONE_SHARED_RESOURCES_DIRECTORY" : simulatorHome,
           @"DYLD_FALLBACK_FRAMEWORK_PATH" : @"/Developer/Library/Frameworks",
           @"DYLD_FRAMEWORK_PATH" : _buildSettings[@"BUILT_PRODUCTS_DIR"],
           @"DYLD_LIBRARY_PATH" : _buildSettings[@"BUILT_PRODUCTS_DIR"],
           @"DYLD_ROOT_PATH" : _buildSettings[@"SDKROOT"],
           @"IPHONE_SIMULATOR_ROOT" : _buildSettings[@"SDKROOT"],
           @"IPHONE_SIMULATOR_VERSIONS" : simVersions,
           @"NSUnbufferedIO" : @"YES"};
}

- (NSTask *)otestTaskWithTestBundle:(NSString *)testBundlePath
{
  // As of the Xcode 5 GM, the iPhoneSimulator version of 'otest' is now a
  // universal binary. By default, the x86_64 version will be run. That's a
  // problem because *most* .octest / .xctest bundles are 32-bit only.
  //
  // The only time we should run for 64-bit is when the test is built for
  // the iPhone (4-inch 64-bit) simulator. (Also, this is limited to iOS 7.)
  //
  // When a `-destination` is supplied with the 'name' key set, xctool parses
  // through the argument to figure out which simulator is being targetted.
  // From there, it looks at certain plists in the system to determine the arch
  // for the simulator being targetted. Here, we just have to use the already-
  // populated architecture value and create the correct NSTask.
  if ([self cpuType] == CPU_TYPE_ANY) {
    [self setCpuType:CPU_TYPE_I386];
  }
  NSConcreteTask *task = (NSConcreteTask *)[CreateTaskInSameProcessGroupWithArch([self cpuType]) autorelease];

  [task setLaunchPath:[NSString stringWithFormat:@"%@/Developer/%@", _buildSettings[@"SDKROOT"], _framework[kTestingFrameworkIOSTestrunnerName]]];
  [task setArguments:[[self testArguments] arrayByAddingObject:testBundlePath]];
  NSMutableDictionary *env = [[self.environmentOverrides mutableCopy] autorelease];
  env[@"DYLD_INSERT_LIBRARIES"] = [XCToolLibPath() stringByAppendingPathComponent:@"otest-shim-ios.dylib"];
  [task setEnvironment:[self otestEnvironmentWithOverrides:env]];
  return task;
}

- (BOOL)runTestsAndFeedOutputTo:(void (^)(NSString *))outputLineBlock
                       gotError:(BOOL *)gotError
                          error:(NSString **)error
{
  NSString *sdkName = _buildSettings[@"SDK_NAME"];
  NSAssert([sdkName hasPrefix:@"iphonesimulator"], @"Unexpected SDK name: %@", sdkName);

  NSString *testBundlePath = [self testBundlePath];
  BOOL bundleExists = [[NSFileManager defaultManager] fileExistsAtPath:testBundlePath];

  if (IsRunningUnderTest()) {
    // If we're running under test, pretend the bundle exists even if it doesn't.
    bundleExists = YES;
  }

  if (bundleExists) {
    @autoreleasepool {
      NSTask *task = [self otestTaskWithTestBundle:testBundlePath];
      LaunchTaskAndFeedOuputLinesToBlock(task,
                                         @"running otest/xctest on test bundle",
                                         outputLineBlock);
      *gotError = task.terminationReason == NSTaskTerminationReasonUncaughtSignal;

      return [task terminationStatus] == 0 ? YES : NO;
    }
  } else {
    *error = [NSString stringWithFormat:@"Test bundle not found at: %@", testBundlePath];
    *gotError = NO;
    return NO;
  }
}

@end
