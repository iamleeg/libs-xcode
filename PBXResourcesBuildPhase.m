#import "PBXCommon.h"
#import "PBXGroup.h"
#import "PBXResourcesBuildPhase.h"
#import "PBXFileReference.h"
#import "PBXBuildFile.h"
#import "PBXVariantGroup.h"
#import "NSString+PBXAdditions.h"
#import "GSXCBuildContext.h"

extern char **environ;

@implementation PBXResourcesBuildPhase
- (instancetype) init
{
  self = [super init];
  if (self != nil)
    {
      NSArray *objs = nil;
      objs = [[[GSXCBuildContext sharedBuildContext]
                objectForKey: @"objects"]
               allValues];
      
      ASSIGNCOPY(files, objs);
    }
  return self;
}

- (BOOL) processInfoPlistInput: (NSString *)inputFileName
                        output: (NSString *)outputFileName
{
  GSXCBuildContext *context = [GSXCBuildContext sharedBuildContext];
  NSString *settings = [context objectForKey: @"PRODUCT_SETTINGS_XML"];
  if(settings == nil)
    {
      NSMutableDictionary *dict = [NSMutableDictionary dictionary];
      NSString *inputFileString = [NSString stringWithContentsOfFile: inputFileName];
      NSString *outputFileString = nil;
      
      ASSIGNCOPY(outputFileString, inputFileString);
      
      // Get env vars...
      char **env = NULL;
      for (env = environ; *env != 0; env++)
        {
          char *thisEnv = *env;
          NSString *envStr = [NSString stringWithCString: thisEnv encoding: NSUTF8StringEncoding];
          NSArray *components = [envStr componentsSeparatedByString: @"="];
          [dict setObject: [components lastObject]
                   forKey: [components firstObject]];
        }
      
      // Replace all variables in the plist with the values...
      NSDebugLog(@"%@", dict);
      NSArray *keys = [dict allKeys];
      NSEnumerator *en = [keys objectEnumerator];
      NSString *k = nil;
      while ((k = [en nextObject]) != nil)
        {
          NSString *v = [dict objectForKey: k];
          outputFileString = [outputFileString stringByReplacingOccurrencesOfString: [NSString stringWithFormat: @"$(%@)",k]
                                                                         withString: v];
        }
      
      [outputFileString writeToFile: outputFileName
                         atomically: YES
                           encoding: NSUTF8StringEncoding
                              error: NULL];
      
      NSDebugLog(@"%@", outputFileString);
    }
  else
    {
      [settings writeToFile: outputFileName
                 atomically: YES
                   encoding: NSUTF8StringEncoding
                      error: NULL];      
    }
  return YES;
}

- (BOOL) build
{
  puts("=== Executing Resources Build Phase");
  NSFileManager *mgr = [NSFileManager defaultManager];
  NSString *productOutputDir = [NSString stringWithCString: getenv("PRODUCT_OUTPUT_DIR")];
  NSString *resourcesDir = [productOutputDir stringByAppendingPathComponent: @"Resources"];
  NSError *error = nil;
  NSString *productName = [target productName];
  
  // Pre create directory....
  [mgr createDirectoryAtPath:resourcesDir
       withIntermediateDirectories:YES
                  attributes:nil
                       error:&error];

  // Copy all resources...
  NSEnumerator *en = [files objectEnumerator];
  BOOL result = YES;
  id file = nil;
  while((file = [en nextObject]) != nil && result)
    {
      id fileRef = [file fileRef];
      //      NSLog(@"fileRef = %@", fileRef);
      if ([fileRef isKindOfClass: [PBXVariantGroup class]])
        {
          NSArray *children = [fileRef children];
          NSEnumerator *e = [children objectEnumerator];
          id child = nil;
          while ((child = [e nextObject]) != nil)
            {
              //              NSLog(@"\t%@", child);
              //              NSLog(@"child = %@", [child path]);
              NSString *filePath = [child path];
              NSString *resourceFilePath = [filePath stringByDeletingLastPathComponent];
              BOOL edited = NO;
              if ([mgr fileExistsAtPath: [child path]] == NO)
                {
                  edited = YES;
                  filePath = [productName stringByAppendingPathComponent: [child path]];
                }

              // NSLog(@"resourceFilePath = %@", resourceFilePath);
              NSString *fileDir = [resourcesDir stringByAppendingPathComponent:
                                                  resourceFilePath];
              NSString *fileName = [filePath lastPathComponent];
              NSString *destPath = [resourcesDir stringByAppendingPathComponent: fileName];
              NSError *error = nil;
              BOOL copyResult = NO; 
              
              // If there is more than one path component...
              // then the intervening directories need to
              // be created.
              if([[filePath pathComponents] count] > 1)
                {
                  NSString *dirs = [filePath stringByDeletingLastPathComponent];
                  if (edited)
                    {
                      dirs = [dirs stringByReplacingOccurrencesOfString: productName withString: @""];
                    }
                  destPath = [resourcesDir stringByAppendingPathComponent: dirs];
                  destPath = [destPath stringByAppendingPathComponent: fileName];
                }
              
              NSDebugLog(@"\tCreate %@",fileDir);
              copyResult = [mgr       createDirectoryAtPath: fileDir
                                withIntermediateDirectories: YES
                                                 attributes: nil
                                                      error: &error];
              if (copyResult == NO)
                {
                  NSLog(@"\tFILE CREATION ERROR:  %@, %@", error, fileDir);
                }

              NSDebugLog(@"\tCopy child %@  -> %@",filePath,destPath);
              puts([[NSString stringWithFormat: @"\tCopy child resource %@ --> %@", filePath, destPath] cString]);
              copyResult = [mgr copyItemAtPath: filePath
                                        toPath: destPath
                                         error: &error];
              if (copyResult == NO)
                {
                  NSLog(@"\tERROR: %@, %@ -> %@", error, filePath, destPath);
                }
            }
          continue;
        }
      
      NSString *filePath = [file path];
      if ([mgr fileExistsAtPath: [file path]] == NO)
        {
          filePath = [productName stringByAppendingPathComponent: [file path]];
        }

      NSString *fileName = [filePath lastPathComponent];
      NSString *destPath = [resourcesDir stringByAppendingPathComponent: fileName];
      NSError *error = nil;
      BOOL copyResult = NO; 
      NSDebugLog(@"\tXXXX Copy %@ -> %@",filePath,destPath);
      puts([[NSString stringWithFormat: @"\tCopy resource %@ --> %@",filePath,destPath] cString]);      
      copyResult = [mgr copyItemAtPath: filePath
                                toPath: destPath
                                 error: &error];

      if(!copyResult)
	{
	  NSDebugLog(@"\tCopy Error: %@ copying %@ -> %@",[error localizedDescription],
                     filePath, destPath);
	}
    }

  // Handle Info.plist....
  char *infoplist = getenv("INFOPLIST_FILE") == NULL ? "":getenv("INFOPLIST_FILE");
  NSString *inputPlist = [NSString stringWithCString:
                                     infoplist];
  if ([mgr fileExistsAtPath: inputPlist] == NO)
    {
      inputPlist = [inputPlist lastPathComponent];
    }
  
  NSString *outputPlist = [resourcesDir
                            stringByAppendingPathComponent: @"Info-gnustep.plist"];
  NSLog(@"resourcesDir = %@ %s", resourcesDir, infoplist);
  [self processInfoPlistInput: inputPlist
                       output: outputPlist];

  // Move Base.lproj to English.lproj until Base.lproj is supported..
  NSString *baseLproj = [resourcesDir
                          stringByAppendingPathComponent: @"Base.lproj"];
  NSString *engLproj =  [resourcesDir
                          stringByAppendingPathComponent: @"English.lproj"];
  [mgr moveItemAtPath: baseLproj
               toPath: engLproj
                error: NULL];
  
  puts("=== Resources Build Phase Completed");
  return result;
}
@end
