#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
// This test uses the public reader-origin API against an OS accessibility adapter.
#import "../src/reading_origin.h"
int main(void) {
 @autoreleasepool {
  NSArray *blocks=@[@"First paragraph.", @"Second target paragraph.", @"Final paragraph."];
  NSString *text=GRReadingSuffix(blocks, 1, 7);
  if (![text isEqualToString:@"target paragraph.\n\nFinal paragraph."]) {
   fprintf(stderr,"FAIL: clicked word must retain remaining paragraphs\n");return 1;
  }
  if (GRReadingSuffix(blocks, 8, 0) != nil || GRReadingSuffix(blocks, 1, 99) != nil) return 1;
  if (![GRPreferredReadingText(@"  exact highlight  ", @"clicked suffix", YES) isEqualToString:@"exact highlight"]) return 1;
  if (![GRPreferredReadingText(nil, @" clicked suffix ", YES) isEqualToString:@"clicked suffix"]) return 1;
  NSArray *inlineBlocks = @[@"4", @".", @"Speed Button Fixed"];
  if (![GRReadingSuffix(inlineBlocks, 0, 0) isEqualToString:@"4. Speed Button Fixed"]) {
   fprintf(stderr,"FAIL: inline list number and period must stitch cleanly\n");return 1;
  }
  puts("Clicked origin tests passed (6)");
 }
 return 0;
}
