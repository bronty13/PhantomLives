// PurpleMark Spotlight importer — extracts searchable content + a title from a
// markdown file so Spotlight can find `.md` files by their contents and by
// their first heading.

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

// Cap indexed content so a giant file can't blow up the importer.
static const NSUInteger kMaxContentLength = 2 * 1024 * 1024;

/// The first ATX heading (`# …` … `###### …`), with the leading #'s and
/// surrounding whitespace stripped. Skips fenced code blocks. Returns nil if
/// there's no heading.
static NSString *FirstHeading(NSString *text) {
    __block NSString *result = nil;
    __block BOOL inFence = NO;
    [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix:@"```"] || [trimmed hasPrefix:@"~~~"]) {
            inFence = !inFence;
            return;
        }
        if (inFence || ![trimmed hasPrefix:@"#"]) return;
        NSUInteger level = 0;
        while (level < trimmed.length && [trimmed characterAtIndex:level] == '#') level++;
        if (level < 1 || level > 6) return;
        NSString *rest = [[trimmed substringFromIndex:level]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (rest.length > 0) { result = rest; *stop = YES; }
    }];
    return result;
}

Boolean GetMetadataForFile(void *thisInterface,
                           CFMutableDictionaryRef attributes,
                           CFStringRef contentTypeUTI,
                           CFStringRef pathToFile) {
    @autoreleasepool {
        NSString *path = (__bridge NSString *)pathToFile;
        if (path.length == 0) return FALSE;

        NSString *text = [NSString stringWithContentsOfFile:path
                                                   encoding:NSUTF8StringEncoding error:NULL];
        if (text == nil) {
            text = [NSString stringWithContentsOfFile:path
                                             encoding:NSISOLatin1StringEncoding error:NULL];
        }
        if (text == nil) return FALSE;

        NSMutableDictionary *attrs = (__bridge NSMutableDictionary *)attributes;

        NSString *content = text;
        if (content.length > kMaxContentLength) {
            content = [content substringToIndex:kMaxContentLength];
        }
        attrs[(__bridge NSString *)kMDItemTextContent] = content;
        attrs[(__bridge NSString *)kMDItemKind] = @"Markdown Document";

        NSString *title = FirstHeading(text);
        if (title.length > 0) {
            attrs[(__bridge NSString *)kMDItemTitle] = title;
            attrs[(__bridge NSString *)kMDItemDisplayName] = title;
        }

        return TRUE;
    }
}
