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

#import "XCOSXLogicTestQueryRunner.h"

#import "TaskUtil.h"
#import "XCToolUtil.h"
#import "XcodeBuildSettings.h"

@implementation XCOSXLogicTestQueryRunner

- (void)prepareToRunQuery
{
  // otest-query defaults are cleared to ensure that when the task created below
  // is launched `NSUserDefaults` won't have unexpected values.
  NSTask *cleanTask = CreateTaskInSameProcessGroup();
  [cleanTask setLaunchPath:@"/usr/bin/defaults"];
  [cleanTask setArguments:@[@"delete", @"otest-query-osx"]];
  [cleanTask setStandardError:[NSFileHandle fileHandleWithNullDevice]];
  [cleanTask launch];
  [cleanTask waitUntilExit];
}

- (NSTask *)createTaskForQuery
{
  NSString *builtProductsDir = _buildSettings[Xcode_BUILT_PRODUCTS_DIR];

  NSTask *task = CreateTaskInSameProcessGroup();
  [task setLaunchPath:[XCToolLibExecPath() stringByAppendingPathComponent:@"otest-query-osx"]];
  [task setArguments:@[ [self bundlePath] ]];
  [task setEnvironment:@{
  // Specifying `NSArgumentDomain` forces XCTest/SenTestingKit frameworks to use values
  // of otest-query-osx `NSUserDefaults` which are changed in otest-query to manipulate
  // mentioned frameworks behaviour.
    @"NSArgumentDomain" : @"otest-query-osx",
    @"DYLD_FRAMEWORK_PATH" : builtProductsDir,
    @"DYLD_LIBRARY_PATH" : builtProductsDir,
    @"DYLD_FALLBACK_FRAMEWORK_PATH" : OSXTestFrameworkDirectories(),
    @"NSUnbufferedIO" : @"YES",
    @"OBJC_DISABLE_GC" : @"YES",
    @"__CFPREFERENCES_AVOID_DAEMON" : @"YES",
  }];

  return task;
}


@end
