//
//  SFMWindowController.m
//  Stockfish
//
//  Created by Daylen Yang on 1/7/14.
//  Copyright (c) 2014 Daylen Yang. All rights reserved.
//

#import "SFMWindowController.h"
#import "SFMBoardView.h"
#import "SFMChessGame.h"
#import "SFMUCIEngine.h"
#import "Constants.h"

@interface SFMWindowController ()

@property (weak) IBOutlet NSSplitView *mainSplitView;
@property (weak) IBOutlet NSTableView *gameListView;
@property (weak) IBOutlet SFMBoardView *boardView;

@property (weak) IBOutlet NSTextField *engineTextField;
@property (weak) IBOutlet NSTextField *engineStatusTextField;
@property (unsafe_unretained) IBOutlet NSTextView *lineTextView;

@property int currentGameIndex;
@property SFMChessGame *currentGame;
@property BOOL isAnalyzing;
@property SFMUCIEngine *engine;

@end

@implementation SFMWindowController

#pragma mark - Interactions

- (IBAction)flipBoard:(id)sender {
    self.boardView.boardIsFlipped = !self.boardView.boardIsFlipped;
}
- (IBAction)previousMove:(id)sender {
    [self.currentGame goBackOneMove];
    [self syncModelWithView];
}
- (IBAction)nextMove:(id)sender {
    [self.currentGame goForwardOneMove];
    [self syncModelWithView];
}
- (IBAction)firstMove:(id)sender
{
    [self.currentGame goToBeginning];
    [self syncModelWithView];
}
- (IBAction)lastMove:(id)sender
{
    [self.currentGame goToEnd];
    [self syncModelWithView];
}
- (IBAction)toggleInfiniteAnalysis:(id)sender {
    if (self.isAnalyzing) {
        [self stopAnalysis];
    } else {
        [self sendPositionToEngine];
    }
    self.isAnalyzing = !self.isAnalyzing;
}
#pragma mark - Helper methods
- (void)syncModelWithView
{
    self.boardView.position->copy(*self.currentGame.currPosition);
    [self.boardView updatePieceViews];
    if (self.isAnalyzing) {
        [self sendPositionToEngine];
    }
}
- (void)sendPositionToEngine
{
    [self.engine stopSearch];
    [self.engine sendCommandToEngine:self.currentGame.uciPositionString];
    [self.engine startInfiniteAnalysis];
}
- (void)stopAnalysis
{
    [self.engine stopSearch];
}

#pragma mark - Init

- (void)windowDidLoad
{
    [super windowDidLoad];
    [self.boardView setDelegate:self];
    [self loadGameAtIndex:0];
    self.isAnalyzing = NO;
    
    // Decide whether to show or hide the game sidebar
    if ([self.pgnFile.games count] > 1) {
        [self.gameListView setDelegate:self];
        [self.gameListView setDataSource:self];
        [self.gameListView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleSourceList];
    } else {
        [self.mainSplitView.subviews[0] removeFromSuperview];
    }
    
    // Subscribe to notifications
    [[NSNotificationCenter defaultCenter] addObserverForName:ENGINE_NAME_AVAILABLE_NOTIFICATION object:self.engine queue:nil usingBlock:^(NSNotification *note) {
        self.engineTextField.stringValue = self.engine.engineName;
    }];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(addAnalysisLine:) name:ENGINE_NEW_LINE_AVAILABLE_NOTIFICATION object:self.engine];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateEngineStatus:) name:ENGINE_CURRENT_MOVE_CHANGED_NOTIFICATION object:self.engine];
    self.engine = [[SFMUCIEngine alloc] initStockfish];
    
}

- (void)loadGameAtIndex:(int)index
{
    self.currentGameIndex = index;
    self.currentGame = self.pgnFile.games[index];
    [self.currentGame populateMovesFromMoveText];
    
    self.boardView.position->copy(*self.currentGame.startPosition);
    [self.boardView updatePieceViews];
    
    if (self.isAnalyzing) {
        [self sendPositionToEngine];
    }
}

#pragma mark - Menu items
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    if ([menuItem action] == @selector(toggleInfiniteAnalysis:)) {
        if (self.isAnalyzing) {
            [menuItem setTitle:@"Stop Infinite Analysis"];
        } else {
            [menuItem setTitle:@"Start Infinite Analysis"];
        }
    }
    return YES;
}

#pragma mark - View updates
- (void)updateEngineStatus:(NSNotification *)notification
{
    NSLog(@"Updating engine status");
    self.engineStatusTextField.stringValue = self.engine.currentInfo[@"currmove"];
}
- (void)addAnalysisLine:(NSNotification *)notification
{
    NSDictionary *data = [self.engine.lineHistory lastObject];
    NSString *currentlyBeingShown = self.lineTextView.string;
    self.lineTextView.string = [NSString stringWithFormat:@"%@\n%@", currentlyBeingShown, [data description]];
    [self.lineTextView scrollToEndOfDocument:self];
}

#pragma mark - SFMBoardViewDelegate

- (Move)doMoveFrom:(Chess::Square)fromSquare to:(Chess::Square)toSquare
{
    return [self doMoveFrom:fromSquare to:toSquare promotion:NO_PIECE_TYPE];
}

- (Chess::Move)doMoveFrom:(Chess::Square)fromSquare to:(Chess::Square)toSquare promotion:(Chess::PieceType)desiredPieceType
{
    Move m = [self.currentGame doMoveFrom:fromSquare to:toSquare promotion:desiredPieceType];
    if (self.isAnalyzing) {
        [self sendPositionToEngine];
    }
    [self checkIfGameOver];
    return m;
}

/*
 Check if the current position is a checkmate or a draw, and display an alert if so.
 */
- (void)checkIfGameOver
{
    if (self.currentGame.currPosition->is_mate()) {
        NSString *resultText = (self.currentGame.currPosition->side_to_move() == WHITE) ? @"0-1" : @"1-0";
        NSAlert *alert = [NSAlert alertWithMessageText:@"Game over!" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:(self.currentGame.currPosition->side_to_move() == WHITE) ? @"Black wins." : @"White wins."];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        self.currentGame.tags[@"Result"] = resultText;
    } else if (self.currentGame.currPosition->is_immediate_draw()) {
        NSAlert *alert = [NSAlert alertWithMessageText:@"Game over!" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"It's a draw."];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        self.currentGame.tags[@"Result"] = @"1/2-1/2";
    }
}

#pragma mark - Table View Delegate Methods

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return [self.pgnFile.games count];
}
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    static NSString* const rowIdentifier = @"CellView";
    NSTableCellView *view = [self.gameListView makeViewWithIdentifier:rowIdentifier owner:self];
    
    SFMChessGame *game = (SFMChessGame *) self.pgnFile.games[row];
    
    // Poke around in the view
    NSTextField *white = (NSTextField *) view.subviews[0];
    NSTextField *black = (NSTextField *) view.subviews[1];
    NSTextField *result = (NSTextField *) view.subviews[2];
    
    white.stringValue = [NSString stringWithFormat:@"White: %@", game.tags[@"White"]];
    black.stringValue = [NSString stringWithFormat:@"Black: %@", game.tags[@"Black"]];
    result.stringValue = [NSString stringWithFormat:@"Result: %@", game.tags[@"Result"]];
    return view;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    [self loadGameAtIndex:(int) self.gameListView.selectedRow];
}

@end
