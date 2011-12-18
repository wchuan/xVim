//
//  Created by Morris Liang on 11-12-7.
//  Copyright (c) 2011年 http://warwithinme.com . All rights reserved.
//

@class XVimController;

@interface XTextViewBridge : NSObject

-(XTextViewBridge*) initWithTextView:(NSTextView*) view;
-(void) dealloc;

// Return the hijacked targetView
-(NSTextView*) targetView;
// Return the vim controller that is with this textview.
-(XVimController*) vimController;
// Subclass can just calls this method to process the key event.
-(void) processKeyEvent:(NSEvent*) event;

// ====================
// Subclass should override the methods below.

// This method is called by the XVimController, subclass should override
// this method to let the hijacked textview to handle the fakeEvent.
-(void) handleFakeKeyEvent:(NSEvent*) fakeEvent;

// Ask the textview to close any popup(e.g. a code-complete popup).
// Return YES if a popup is closed.
-(BOOL) closePopup;

// Returns the current visible lines range. Starting with 0
-(NSRange) visibleParagraphRange;
// --------------------

@end
