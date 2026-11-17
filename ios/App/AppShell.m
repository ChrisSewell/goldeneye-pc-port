/* The app's start: SDL2main's UIApplicationMain calls the game's main
 * (port/src/main.c, built as SDL_main), which calls iosHostStart() first.
 *
 * The port looks for its data folder as data/ under the working directory
 * (sysResolvePath "$S/"), so the working directory becomes Documents and
 * the ROM, its converted files, the save and the settings all live in
 * Documents/data, reachable from the Files app and Finder.
 *
 * A personal build can carry that data itself (ios_build.sh with
 * GE_BUNDLE_DATA=1, for an install over the air): its BundledData folder is
 * copied into Documents/data, file by file, where nothing is there yet. */
#import <UIKit/UIKit.h>
#include <SDL.h>
#include <unistd.h>
#include <sys/stat.h>

void iosHostStart(void)
{
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (docs && chdir(docs.fileSystemRepresentation) == 0)
        mkdir("data", 0755);
    NSString *bundled = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"BundledData"];
    NSFileManager *fm = NSFileManager.defaultManager;
    if (docs && [fm fileExistsAtPath:bundled]) {
        NSString *dest = [docs stringByAppendingPathComponent:@"data"];
        for (NSString *name in [fm contentsOfDirectoryAtPath:bundled error:nil]) {
            NSString *to = [dest stringByAppendingPathComponent:name];
            if ([fm fileExistsAtPath:to]) continue;
            NSError *err = nil;
            if ([fm copyItemAtPath:[bundled stringByAppendingPathComponent:name] toPath:to error:&err])
                fprintf(stderr, "[ios] copied %s into data\n", name.UTF8String);
            else
                fprintf(stderr, "[ios] could not copy %s: %s\n", name.UTF8String,
                        err.localizedDescription.UTF8String);
        }
    }
    fprintf(stderr, "[ios] data folder: %s/data\n", docs.UTF8String);
    /* Touches drive the on-screen pad (TouchPad.m), not the mouse: as mouse
     * events they would turn the view and fire. */
    SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "0");
    SDL_SetHint(SDL_HINT_MOUSE_TOUCH_EVENTS, "0");
    SDL_SetHint(SDL_HINT_IOS_HIDE_HOME_INDICATOR, "2");
}
