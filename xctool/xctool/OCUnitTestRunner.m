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

#import "OCUnitTestRunner.h"

#import <QuartzCore/QuartzCore.h>

#import "OCUnitCrashFilter.h"
#import "ReportStatus.h"

@implementation OCUnitTestRunner

+ (NSArray *)filterTestCases:(NSArray *)testCases
             withSenTestList:(NSString *)senTestList
          senTestInvertScope:(BOOL)senTestInvertScope
{
  NSSet *originalSet = [NSSet setWithArray:testCases];

  // Come up with a set of test cases that match the senTestList pattern.
  NSMutableSet *matchingSet = [NSMutableSet set];

  if ([senTestList isEqualToString:@"All"]) {
    [matchingSet addObjectsFromArray:testCases];
  } else if ([senTestList isEqualToString:@"None"]) {
    // None, we don't add anything to the set.
  } else {
    for (NSString *specifier in [senTestList componentsSeparatedByString:@","]) {
      // If we have a slash, assume it's int he form of "SomeClass/testMethod"
      BOOL hasClassAndMethod = [specifier rangeOfString:@"/"].length > 0;

      if (hasClassAndMethod) {
        if ([originalSet containsObject:specifier]) {
          [matchingSet addObject:specifier];
        }
      } else {
        NSString *matchingPrefix = [specifier stringByAppendingString:@"/"];
        for (NSString *testCase in testCases) {
          if ([testCase hasPrefix:matchingPrefix]) {
            [matchingSet addObject:testCase];
          }
        }
      }
    }
  }

  NSMutableArray *result = [NSMutableArray array];

  if (!senTestInvertScope) {
    [result addObjectsFromArray:[matchingSet allObjects]];
  } else {
    NSMutableSet *invertedSet = [[originalSet mutableCopy] autorelease];
    [invertedSet minusSet:matchingSet];
    [result addObjectsFromArray:[invertedSet allObjects]];
  }

  [result sortUsingSelector:@selector(compare:)];
  return result;
}

- (id)initWithBuildSettings:(NSDictionary *)buildSettings
                senTestList:(NSArray *)senTestList
                  arguments:(NSArray *)arguments
                environment:(NSDictionary *)environment
          garbageCollection:(NSNumber *)garbageCollection
             freshSimulator:(BOOL)freshSimulator
               freshInstall:(BOOL)freshInstall
              simulatorType:(NSString *)simulatorType
                  reporters:(NSArray *)reporters
{
  if (self = [super init]) {
    _buildSettings = [buildSettings retain];
    _senTestList = [senTestList retain];
    _arguments = [arguments retain];
    _environment = [environment retain];
    _garbageCollection = [garbageCollection boolValue];
    _freshSimulator = freshSimulator;
    _freshInstall = freshInstall;
    _simulatorType = [simulatorType retain];
    _reporters = [reporters retain];
    _framework = [FrameworkInfoForTestBundleAtPath([self testBundlePath]) retain];
  }
  return self;
}

- (void)dealloc
{
  [_buildSettings release];
  [_senTestList release];
  [_arguments release];
  [_environment release];
  [_simulatorType release];
  [_reporters release];
  [_framework release];
  [super dealloc];
}

- (BOOL)runTestsAndFeedOutputTo:(void (^)(NSString *))outputLineBlock
              gotUncaughtSignal:(BOOL *)gotUncaughtSignal
                          error:(NSString **)error
{
  // Subclasses will override this method.
  return NO;
}

- (BOOL)runTestsWithError:(NSString **)error {
  __block BOOL didReceiveTestEvents = NO;

  _testRunnerState = [[OCUnitCrashFilter alloc] initWithTests:_senTestList reporters:_reporters];

  void (^feedOutputToBlock)(NSString *) = ^(NSString *line) {
    NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];

    [_testRunnerState parseAndHandleEvent:line];
    [_reporters makeObjectsPerformSelector:@selector(publishDataForEvent:) withObject:lineData];

    didReceiveTestEvents = YES;
  };

  NSString *runTestsError = nil;
  BOOL didTerminateWithUncaughtSignal = NO;

  [_testRunnerState prepareToRun];

  BOOL succeeded = [self runTestsAndFeedOutputTo:feedOutputToBlock
                                 gotUncaughtSignal:&didTerminateWithUncaughtSignal
                                             error:&runTestsError];
  if (runTestsError) {
    *error = runTestsError;
  }

  if (!succeeded && runTestsError == nil && !didReceiveTestEvents) {
    // otest failed but clearly no tests ran.  We've seen this when a test target had no
    // source files.  In that case, xcodebuild generated the test bundle, but didn't build the
    // actual mach-o bundle/binary (because of no source files!)
    //
    // e.g., Xcode would generate...
    //   DerivedData/Something-ejutnghaswljrqdalvadkusmnhdc/Build/Products/Debug-iphonesimulator/SomeTests.octest
    //
    // but, you would not have...
    //   DerivedData/Something-ejutnghaswljrqdalvadkusmnhdc/Build/Products/Debug-iphonesimulator/SomeTests.octest/SomeTests
    //
    // otest would then exit immediately with...
    //   The executable for the test bundle at /path/to/Something/Facebook-ejutnghaswljrqdalvadkusmnhdc/Build/Products/
    //     Debug-iphonesimulator/SomeTests.octest could not be found.
    //
    // Xcode (via Cmd-U) just counts this as a pass even though the exit code from otest was non-zero.
    // That seems a little wrong, but we'll do the same.
    succeeded = YES;
  }

  [_testRunnerState finishedRun:didTerminateWithUncaughtSignal];

  return succeeded;
}

- (NSArray *)testArguments
{
  // These are the same arguments Xcode would use when invoking otest.  To capture these, we
  // just ran a test case from Xcode that dumped 'argv'.  It's a little tricky to do that outside
  // of the 'main' function, but you can use _NSGetArgc and _NSGetArgv.  See --
  // http://unixjunkie.blogspot.com/2006/07/access-argc-and-argv-from-anywhere.html
  NSMutableArray *args = [NSMutableArray arrayWithArray:@[
           // Not sure exactly what this does...
           @"-NSTreatUnknownArgumentsAsOpen", @"NO",
           // Not sure exactly what this does...
           @"-ApplePersistenceIgnoreState", @"YES",
           // SenTest / XCTest is one of Self, All, None,
           // or TestClassName[/testCaseName][,TestClassName2]
           _framework[kTestingFrameworkFilterTestArgsKey], [_senTestList componentsJoinedByString:@","],
           // SenTestInvertScope / XCTestInvertScope optionally inverts whatever
           // SenTest would normally select. We never invert, since we always
           // pass the exact list of test cases to be run.
           _framework[kTestingFrameworkInvertScopeKey], @"NO",
           ]];

  // Add any argments that might have been specifed in the scheme.
  [args addObjectsFromArray:_arguments];

  return args;
}

- (NSDictionary *)otestEnvironmentWithOverrides:(NSDictionary *)overrides
{
  NSMutableDictionary *env = [NSMutableDictionary dictionary];

  NSArray *layers = @[
                      // Xcode will let your regular environment pass-thru to
                      // the test.
                      [[NSProcessInfo processInfo] environment],
                      // Any special environment vars set in the scheme.
                      _environment,
                      // Whatever values we need to make the test run at all for
                      // ios/mac or logic/application tests.
                      overrides,
                      ];
  for (NSDictionary *layer in layers) {
    [layer enumerateKeysAndObjectsUsingBlock:^(id key, id val, BOOL *stop){
      if ([key isEqualToString:@"DYLD_INSERT_LIBRARIES"]) {
        // It's possible that the scheme (or regular host environment) has its
        // own value for DYLD_INSERT_LIBRARIES.  In that case, we don't want to
        // stomp on it when insert otest-shim.
        NSString *existingVal = env[key];
        if (existingVal) {
          env[key] = [existingVal stringByAppendingFormat:@":%@", val];
        } else {
          env[key] = val;
        }
      } else {
        env[key] = val;
      }
    }];
  }

  return env;
}

- (NSString *)testBundlePath
{
  return [NSString stringWithFormat:@"%@/%@",
          _buildSettings[@"BUILT_PRODUCTS_DIR"],
          _buildSettings[@"FULL_PRODUCT_NAME"]
          ];
}

@end
