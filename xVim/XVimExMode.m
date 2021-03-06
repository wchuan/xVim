#ifdef __LP64__
#import "XVimMode.h"
#import "XGlobal.h"
#import "XTextViewBridge.h"

@interface XVimExModeHandler ()

@property (retain) NSPopover* popover;
@property (assign) VimMode    originalMode;
@property (assign) NSInteger  originalLocation;
@property (assign) BOOL       originalIsVisualLineMode;

- (void)showPrompt:(VimMode)submode;
- (void)runExCommand:(NSString*)cmd;

// Find the match range without altering the selection of the textview.
- (NSRange)searchResult:(NSString*)cmd backwards:(BOOL)backwards;

- (void) restoreSelection;
- (void) restoreMode;
- (void) setSelection:(NSRange)searchResult isFinal:(BOOL)flag;
@end


@implementation XVimExModeHandler

@synthesize popover;
@synthesize lastSearch;
@synthesize lastSearchWasForwards;
@synthesize lastCommand;
@synthesize originalLocation;
@synthesize originalMode;
@synthesize originalIsVisualLineMode;

-(void) enterWith:(VimMode)submode {
    [self showPrompt:submode];
    self.originalMode     = [controller mode];
    if (self.originalMode == VisualMode)
    {
        XVimVisualModeHandler* handler = (XVimVisualModeHandler*)[controller currentHandler];
        self.originalLocation = [handler selectionEnd];
        self.originalIsVisualLineMode = [handler isLineMode];
    } else {
        self.originalLocation = [[[controller bridge] targetView] selectedRange].location;
        self.originalIsVisualLineMode = NO;
    }
}

- (void)repeatSearch:(BOOL)reverse {
    if ([self.lastSearch length]) {
        
        if (self.originalMode == VisualMode)
        {
            XVimVisualModeHandler* handler = (XVimVisualModeHandler*)[controller currentHandler];
            self.originalLocation = [handler selectionEnd];
            self.originalIsVisualLineMode = [handler isLineMode];
        } else {
            self.originalLocation = [[[controller bridge] targetView] selectedRange].location;
            self.originalIsVisualLineMode = NO;
        }
        
        BOOL backwards = self.lastSearchWasForwards != reverse;
        [self setSelection:[self searchResult:lastSearch backwards:backwards] isFinal:YES];
    }
}
- (void)repeatCommand {
    if ([self.lastCommand length])
        [self runExCommand:self.lastCommand];
}

- (void)runCommand:(NSString*)str {
    if ([str length] <= 1)
        return;
    
    NSString* sstr = [str substringWithRange:NSMakeRange(1, [str length] - 1)];
    unichar   ch   = [str characterAtIndex:0];
    if (ch == ':') {
        [self runExCommand:sstr];
        self.lastCommand = sstr;
    } else if (ch == '/' || ch == '?')
    {
        BOOL backwards = ch == '?';
        self.lastSearch = sstr;
        self.lastSearchWasForwards = backwards;
        [self setSelection:[self searchResult:sstr backwards:backwards] isFinal:YES];
    }
}
- (void)runExCommand:(NSString*)cmd {
    if ([cmd isEqual:@"q"] || [cmd isEqual:@"quit"])
        [NSApp terminate:self];
    else if ([cmd isEqual:@"w"] || [cmd isEqual:@"write"])
        [NSApp sendAction:@selector(saveDocument:) to:nil from:self];
    else if ([cmd isEqual:@"wq"]) {
        [NSApp sendAction:@selector(saveDocument:) to:nil from:self];
        [NSApp terminate:self];
    }
}

- (NSRange)searchResult:(NSString*)cmd backwards:(BOOL)backwards
{
    NSString* delim        = backwards ? @"\\?" : @"/";
    NSString* extractregex = [NSString stringWithFormat:@"^(([^%1$@]|\\\\%1$@)+)(%1$@([a-zA-Z]+))?(%1$@)?$", delim];
    NSError*  error        = nil;
    NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:extractregex 
                                                                           options:0 
                                                                             error:&error];
    NSTextCheckingResult* m = [regex firstMatchInString:cmd 
                                                options:0 
                                                  range:NSMakeRange(0, [cmd length])];
    
    if (!m)
        return NSMakeRange(NSNotFound, 0);
    
    NSRange r1 = [m rangeAtIndex:1];
    NSRange r4 = [m rangeAtIndex:4];
    
    NSString* search  = r1.length ? [cmd substringWithRange:r1] : nil;
    NSString* options = r4.length ? [cmd substringWithRange:r4] : nil;
    
    if (![search length])
        return NSMakeRange(NSNotFound, 0);
    
    
    // Replace \\ with XVIM_DOUBLE_BACKSLASH_STRING
    search = [search stringByReplacingOccurrencesOfString:@"\\\\" withString:@"XVIM_DOUBLE_BACKSLASH_STRING"];
    // Replace \ delim with delim
    search = [search stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"\\%@", delim] withString:delim];
    // Replace XVIM_DOUBLE_BACKSLASH_STRING with two backslashes
    search = [search stringByReplacingOccurrencesOfString:@"XVIM_DOUBLE_BACKSLASH_STRING" withString:@"\\\\"];
    
    NSTextView* tv = [[controller bridge] targetView];
    
    // All the search will base on the cursor position logged when entering ex mode.
    NSInteger start = backwards ? self.originalLocation : self.originalLocation + 1;
    NSInteger len   = [[[tv textStorage] string] length];
    
    NSRegularExpressionOptions opts = 0;
    if (options) {
        if ([options rangeOfString:@"i"].length != 0)
            opts |= NSRegularExpressionCaseInsensitive;
        if ([options rangeOfString:@"x"].length != 0)
            opts |= NSRegularExpressionAllowCommentsAndWhitespace;
        if ([options rangeOfString:@"m"].length != 0)
            opts |= NSRegularExpressionAnchorsMatchLines;
        if ([options rangeOfString:@"s"].length != 0)
            opts |= NSRegularExpressionDotMatchesLineSeparators;
    }
    
    regex = [NSRegularExpression regularExpressionWithPattern:search options:opts error:&error];
    
    NSRange searchRange;
    if (!backwards) {
        if (len - start <= 0)
            return NSMakeRange(NSNotFound, 0);
        
        searchRange = NSMakeRange(start, len - start);
        m = [regex firstMatchInString:[[tv textStorage] string] options:opts range:searchRange];
    }
    else {
        if (start <= 0)
            return NSMakeRange(NSNotFound, 0);
        
        searchRange = NSMakeRange(0, start);
        m = [[regex matchesInString:[[tv textStorage] string] options:opts range:searchRange] lastObject];
    }
    
    return !m || [m range].length == 0 ? NSMakeRange(NSNotFound, 0) : [m range];
}

- (void)showPrompt:(VimMode)submode {
    
    XTextViewBridge* bridge = [controller bridge];
    NSString* submodeString = @":";
    if (submode == SearchSubMode)
        submodeString = @"/";
    if (submode == BackwardsSearchSubMode)
        submodeString = @"?";
    
    if (bridge.cmdline) {
        // We have a real cmdline textfield, no need to use popover.
        [bridge.cmdline setFocus:self withText:submodeString];
        return;
    }
    
    self.popover = [[[NSPopover alloc] init] autorelease];
    popover.behavior = NSPopoverBehaviorSemitransient;
    popover.animates = NO;
    popover.appearance = NSPopoverAppearanceMinimal;
    NSViewController* vc = [[[NSViewController alloc] initWithNibName:nil bundle:nil] autorelease];
    
    CGFloat width = 350;
    CGFloat height = 22;
    CGFloat margin = 8;
    
    NSView* contentView = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, width + margin * 2, height + margin * 2)] autorelease];
    NSTextField* textField = [[[NSTextField alloc] initWithFrame:NSMakeRect(margin, margin, width, height)] autorelease];
    [textField setFont:[NSFont fontWithName:@"Monaco" size:11]];
    [textField setFocusRingType:NSFocusRingTypeNone];
    
    [textField setDelegate:self]; // We can now use XTextViewBridge as delegate
    
    [textField setStringValue:submodeString];
    
    [contentView addSubview:textField];
    [vc setView:contentView];
    popover.contentViewController = vc;
    
    NSTextView* tv = [bridge targetView];    
    NSString* string = [[tv textStorage] string];
    NSInteger start = [tv selectedRange].location;

    NSRect posRect = [[tv layoutManager] extraLineFragmentRect];
    posRect.size.width = 0;
    posRect.origin.y += [tv textContainerOrigin].y;
    
    if (self.originalMode == VisualMode) {
        start = [(XVimVisualModeHandler*)[controller handlerForMode:VisualMode] selectionEnd];
    }
    
    if (start < [string length]) {
        
        NSUInteger glyphIndex = [[tv layoutManager] glyphIndexForCharacterAtIndex:start];
        posRect = [[tv layoutManager] boundingRectForGlyphRange:NSMakeRange(glyphIndex, 1) inTextContainer:[tv textContainer]];

        unichar ch = [string characterAtIndex:start];
        if ((ch >= 0xA && ch <= 0xD) || ch == 0x85) {
            posRect.size.width = 0;
        }
    }
    
    [popover showRelativeToRect:posRect ofView:tv preferredEdge:NSMaxYEdge];
    [[textField currentEditor] moveRight:nil];
}

-(void) restoreMode
{
    if (self.originalMode == VisualMode) {
        [controller switchToMode:VisualMode 
                         subMode:self.originalIsVisualLineMode ? VisualLineMode : NoSubMode];
    } else{
        [controller switchToMode:self.originalMode];
    }
    
    if (self.popover) {
        [self.popover close];
        self.popover = nil;
    } else {
        XTextViewBridge* b  = [controller bridge];
        NSTextView*      tv = [b targetView];
        [b.cmdline focusRemoved];
        [[tv window] makeFirstResponder:tv];
    } 
}

- (void) restoreSelection
{
    NSTextView* view    = [[controller bridge] targetView];
    NSRange     orignal = {self.originalLocation, 0};
    
    if (self.originalMode == VisualMode) {
        [(XVimVisualModeHandler*)[controller handlerForMode:VisualMode] setNewSelectionEnd:self.originalLocation];
    } else {
        [view setSelectedRange:orignal];
    }
    [view scrollRangeToVisible:orignal];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command
{
    if (command == @selector(cancelOperation:))
    {
        [self cmdlineCanceled];
    } else if (command == @selector(insertNewline:))
    {
        [self cmdlineAccepted:[textView string]];
    }
    return NO;
}

- (void)controlTextDidChange:(NSNotification*)obj
{
    NSTextView* field  = [[obj userInfo] objectForKey:@"NSFieldEditor"];
    [self cmdlineTextDidChange:[field string]];
}

-(void) cmdlineTextDidChange:(NSString*) string
{
    if ([string length] == 0) {
        [self cmdlineCanceled];
        return;
    }
    DLog(@"Popup text has changed : %@", string);
    
    // Seach as we type.
    unichar firstCh = [string characterAtIndex:0];
    if (firstCh == '/' || firstCh == '?')
    {
        NSString* sstr   = [string substringWithRange:NSMakeRange(1, [string length] - 1)];
        NSRange   result = [self searchResult:sstr backwards:firstCh == '?'];
        DLog(@"Sstr: %@, result: %@", sstr, NSStringFromRange(result));
        [self setSelection:result isFinal:NO];
    } 
}

-(void) cmdlineCanceled
{
    [self restoreMode];
    [self restoreSelection];
}

-(void) cmdlineAccepted:(NSString*) controlStr
{
    [self runCommand:controlStr];
    [self restoreMode];
}

- (void) setSelection:(NSRange)result isFinal:(BOOL)final
{
    if (result.location == NSNotFound) {
        [self restoreSelection];
    } else {
        // Modify the selection to show where we are, since the caret is not shown.
        if (self.originalMode == VisualMode)
        {
            XVimVisualModeHandler* h = (XVimVisualModeHandler*)[controller handlerForMode:VisualMode];
            NSInteger currentEnd = self.originalLocation;
            if (currentEnd < result.location) {
                currentEnd = result.location + result.length - 1;
            } else {
                currentEnd = result.location;
            }
            [h setNewSelectionEnd:currentEnd];
        } else {
            if (final) { result.length = 0; }
            NSTextView* tv = [[controller bridge] targetView];
            [tv setSelectedRange:result];
            [tv scrollRangeToVisible:result];
        }
    }
}

@end
#endif