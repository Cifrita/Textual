/* *********************************************************************
                  _____         _               _
                 |_   _|____  _| |_ _   _  __ _| |
                   | |/ _ \ \/ / __| | | |/ _` | |
                   | |  __/>  <| |_| |_| | (_| | |
                   |_|\___/_/\_\\__|\__,_|\__,_|_|

 Copyright (c) 2010 - 2016 Codeux Software, LLC & respective contributors.
        Please see Acknowledgements.pdf for additional information.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Textual and/or "Codeux Software, LLC", nor the 
      names of its contributors may be used to endorse or promote products 
      derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 SUCH DAMAGE.

 *********************************************************************** */

NS_ASSUME_NONNULL_BEGIN

@interface TVCWK1AutoScroller ()
{
	CGFloat _scrollLastPosition1;
	CGFloat _scrollLastPosition2;
	CGFloat _currentScrollTopValue;
	BOOL _isScrolledByUser;
/*	NSRect _lastFrame; */
}

@property (nonatomic, weak) WebFrameView *frameView;
@end

@implementation TVCWK1AutoScroller

/* Maximum distance user can scroll up before automatic scrolling is disabled. */
static CGFloat _scrollTopUserConstant = 25.0;

- (instancetype)initWitFrameView:(WebFrameView *)frameView;
{
	NSParameterAssert(frameView != nil);

	if ((self = [super init])) {
		self.frameView = frameView;

		[self prepareInitialState];

		return self;
	}

	return nil;
}

- (void)prepareInitialState
{
	WebFrameView *frameView = self.frameView;

	NSView *documentView = frameView.documentView;

	[RZNotificationCenter() addObserver:self
							   selector:@selector(webViewDidChangeFrame:)
								   name:NSViewFrameDidChangeNotification
								 object:frameView];

	[RZNotificationCenter() addObserver:self
							   selector:@selector(webViewDidChangeFrame:)
								   name:NSViewFrameDidChangeNotification
								 object:documentView];

	[RZNotificationCenter() addObserver:self
							   selector:@selector(webViewDidChangeBounds:)
								   name:NSViewBoundsDidChangeNotification
								 object:documentView.enclosingScrollView.contentView];

	self->_scrollLastPosition1 = 0.0;
	self->_scrollLastPosition2 = 0.0;

	self->_isScrolledByUser = NO;
}

- (BOOL)viewingBottom
{
	return (self->_isScrolledByUser == NO);
}

- (void)saveScrollerPosition
{
	;
}

- (void)restoreScrollerPosition
{
	if (self->_isScrolledByUser) {
		return;
	}

	NSView *documentView = self.frameView.documentView;

	[self scrollViewToBottom:documentView];
}

- (void)scrollViewToBottom:(NSView *)aView
{
	NSRect visibleRect = aView.visibleRect;

	visibleRect.origin.y = (aView.frame.size.height - visibleRect.size.height);

	self->_currentScrollTopValue = visibleRect.origin.y;
	
	[aView scrollRectToVisible:visibleRect];
}

- (void)dealloc
{
	[RZNotificationCenter() removeObserver:self];

	self.frameView = nil;
}

- (BOOL)canScroll
{
	WebFrameView *frameView = self.frameView;

	NSRect frameRect = frameView.frame;

	NSRect contentRect = frameView.documentView.frame;

	return (contentRect.size.height > frameRect.size.height);
}

- (void)redrawFrameIfNeeded
{
	/* WebKit uses layered compositing for position: fixed elements as of Yosemite.
	 However, there are some issues related to this change which results in position
	 fixed elements flickering while scrolling. This has been filed as radar #18211024
	 but in the meantime, we redraw the WebView on scroll to workaround this issue. */
	static BOOL _performForceRedraw = NO;

	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		_performForceRedraw =
		([XRSystemInformation isUsingOSXYosemiteOrLater] &&
		 [XRSystemInformation isUsingOSXElCapitanOrLater] == NO);
	});

	if (_performForceRedraw == NO) {
		return;
	}

	[self redrawFrame];
}

- (void)redrawFrame
{
	[self.frameView.documentView setNeedsLayout:YES];
}

- (void)webViewDidChangeBounds:(NSNotification *)aNotification
{
	/* Context */
	WebFrameView *frameView = self.frameView;

	NSView *documentView = frameView.documentView;

	NSRect visibleRect = documentView.visibleRect;

	/* The maximum scrollPosition can equal. The bottom */
	CGFloat scrollHeight = (documentView.frame.size.height - visibleRect.size.height);

	/* The current position. When at bottom, will == scrollHeight */
	CGFloat scrollPosition = visibleRect.origin.y;

	/* Ignore events that are related to elastic scrolling. */
	if (scrollPosition > scrollHeight) {
		return;
	}

	/* 	Record the last two known scrollY values. These properties are compared
		to determine if the user is scrolling upwards or downwards. */
	self->_scrollLastPosition2 = self->_scrollLastPosition1;

	self->_scrollLastPosition1 = scrollPosition;

	/* 	If the current scroll top value exceeds the view height, then it means
		that some lines were probably removed to enforce size limit. */
	/* 	Reset the value to be the absolute bottom when this occurs. */
	if (self->_currentScrollTopValue > scrollHeight) {
		self->_currentScrollTopValue = scrollHeight;

		if (self->_currentScrollTopValue < 0) {
			self->_currentScrollTopValue = 0;
		}
	}

	if (self->_isScrolledByUser) {
		/* Check whether the user has scrolled back to the bottom */
		CGFloat scrollTop = (scrollHeight - self->_scrollLastPosition1);

		if (scrollTop < _scrollTopUserConstant) {
			LogToConsoleDebug("Scrolled below threshold. Enabled auto scroll.")

			self->_isScrolledByUser = NO;

			self->_currentScrollTopValue = self->_scrollLastPosition1;
		}
	}
	else
	{
		/* 	Check if the user is scrolling upwards. If they are, then check if they have went
			above the threshold that defines whether its a user initated event or not. */
		if (self->_scrollLastPosition1 < self->_scrollLastPosition2) {
			CGFloat scrollTop = (self->_currentScrollTopValue - self->_scrollLastPosition1);

			if (scrollTop > _scrollTopUserConstant) {
				LogToConsoleDebug("User scrolled above threshold. Disabled auto scroll.")

				self->_isScrolledByUser = YES;
			}
		}

		/* 	If the user is scrolling downward and passes last threshold location, then
			move the location further downward. */
		if (self->_scrollLastPosition1 > self->_currentScrollTopValue) {
			self->_currentScrollTopValue = self->_scrollLastPosition1;
		}
	}
	
	[self redrawFrameIfNeeded];
}

- (void)webViewDidChangeFrame:(NSNotification *)aNotification
{
	/* Never scroll if user scrolled up */
	if (self->_isScrolledByUser) {
		return;
	}

	/* Perform automatic scrolling */
	WebFrameView *frameView = self.frameView;

	NSView *documentView = frameView.documentView;

/*
	if (aNotification.object == documentView) {
		NSRect documentViewFrame = documentView.frame;

		if (NSEqualRects(documentViewFrame, self->_lastFrame)) {
			return;
		}

		self->_lastFrame = documentViewFrame;
	} 
*/

	[self scrollViewToBottom:documentView];
}

@end

NS_ASSUME_NONNULL_END
