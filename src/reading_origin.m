#import "reading_origin.h"

static BOOL getElementRect(AXUIElementRef element, CGRect *outRect);

static BOOL isStandaloneListMarker(NSString *str) {
    NSString *trimmed = [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0 || trimmed.length > 6) return NO;
    if ([trimmed isEqualToString:@"•"] || [trimmed isEqualToString:@"-"] || [trimmed isEqualToString:@"*"]) return YES;
    if ([trimmed hasSuffix:@"."] || [trimmed hasSuffix:@")"]) {
        NSString *numPart = [trimmed substringToIndex:trimmed.length - 1];
        if (numPart.length > 0 && [numPart rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound) {
            return YES;
        }
    }
    return NO;
}

static BOOL startsWithClosingPunctuation(NSString *str) {
    NSString *trimmed = [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return NO;
    unichar c = [trimmed characterAtIndex:0];
    return (c == '.' || c == ',' || c == ';' || c == ':' || c == '!' || c == '?' || c == ')' || c == ']');
}

static BOOL endsWithInlineContinuation(NSString *str) {
    NSString *trimmed = [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return NO;
    unichar c = [trimmed characterAtIndex:trimmed.length - 1];
    return (c == ',' || c == '(' || c == '[' || c == '/');
}

static BOOL endsWithSentenceTerminator(NSString *str) {
    NSString *trimmed = [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return NO;
    unichar c = [trimmed characterAtIndex:trimmed.length - 1];
    return (c == '.' || c == '!' || c == '?' || c == ':');
}

static BOOL areElementsInline(AXUIElementRef prevElem, NSString *prevText, AXUIElementRef currElem, NSString *currText) {
    if (!prevText.length || !currText.length) return NO;
    if (startsWithClosingPunctuation(currText)) return YES;
    if (isStandaloneListMarker(prevText) || endsWithInlineContinuation(prevText)) return YES;

    CGRect prevRect = CGRectZero, currRect = CGRectZero;
    BOOL hasPrev = getElementRect(prevElem, &prevRect);
    BOOL hasCurr = getElementRect(currElem, &currRect);
    if (hasPrev && hasCurr) {
        // Same visual horizontal line
        if (fabs(currRect.origin.y - prevRect.origin.y) < 12.0 && currRect.origin.x >= prevRect.origin.x - 8.0) {
            return YES;
        }
        // Wrapped line of the same paragraph when previous line did not finish a sentence
        CGFloat vGap = currRect.origin.y - CGRectGetMaxY(prevRect);
        if (vGap >= -6.0 && vGap < 8.0 && !endsWithSentenceTerminator(prevText)) {
            return YES;
        }
    }
    return NO;
}

NSString *GRReadingSuffix(NSArray<NSString *> *blocks, NSUInteger blockIndex, NSUInteger offset) {
    if (!blocks || blocks.count == 0 || blockIndex >= blocks.count) return nil;

    NSString *block = blocks[blockIndex];
    if (offset > block.length) return nil;
    if (offset == block.length) {
        if (blockIndex + 1 < blocks.count) {
            blockIndex++;
            offset = 0;
            block = blocks[blockIndex];
        } else {
            offset = 0;
        }
    }
    // A click inside a word starts at that word, not halfway through it.
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    while (offset > 0 && offset < block.length && ![space characterIsMember:[block characterAtIndex:offset - 1]]) offset--;

    NSMutableString *result = [NSMutableString stringWithString:[[block substringFromIndex:offset] stringByTrimmingCharactersInSet:space]];
    NSString *prevBlock = [result copy];
    for (NSUInteger i = blockIndex + 1; i < blocks.count; i++) {
        NSString *nextBlock = [blocks[i] stringByTrimmingCharactersInSet:space];
        if (nextBlock.length == 0) continue;
        if (result.length == 0) {
            [result appendString:nextBlock];
            prevBlock = nextBlock;
        } else if (startsWithClosingPunctuation(nextBlock) ||
                   ([prevBlock rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound && [nextBlock isEqualToString:@"."])) {
            [result appendString:nextBlock];
            prevBlock = [prevBlock stringByAppendingString:nextBlock];
        } else if (isStandaloneListMarker(prevBlock) || endsWithInlineContinuation(prevBlock)) {
            [result appendFormat:@" %@", nextBlock];
            prevBlock = nextBlock;
        } else {
            [result appendFormat:@"\n\n%@", nextBlock];
            prevBlock = nextBlock;
        }
    }
    return [result stringByTrimmingCharactersInSet:space];
}

NSString *GRPreferredReadingText(NSString *selection, NSString *clickedText, BOOL clickedAppMatches) {
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *exact = [selection stringByTrimmingCharactersInSet:space];
    if (exact.length) return exact;
    NSString *clicked = [clickedText stringByTrimmingCharactersInSet:space];
    return clickedAppMatches && clicked.length ? clicked : nil;
}

static id attribute(AXUIElementRef element, CFStringRef name) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, name, &value) != kAXErrorSuccess) return nil;
    return CFBridgingRelease(value);
}

static BOOL getElementRect(AXUIElementRef element, CGRect *outRect) {
    if (!element || !outRect) return NO;
    CFTypeRef posVal = NULL, sizeVal = NULL;
    CGPoint elPos = CGPointZero;
    CGSize elSize = CGSizeZero;
    BOOL ok = NO;
    if (AXUIElementCopyAttributeValue(element, kAXPositionAttribute, &posVal) == kAXErrorSuccess &&
        posVal && CFGetTypeID(posVal) == AXValueGetTypeID() &&
        AXValueGetValue((AXValueRef)posVal, kAXValueCGPointType, &elPos) &&
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute, &sizeVal) == kAXErrorSuccess &&
        sizeVal && CFGetTypeID(sizeVal) == AXValueGetTypeID() &&
        AXValueGetValue((AXValueRef)sizeVal, kAXValueCGSizeType, &elSize)) {
        if (elSize.width > 0 && elSize.height > 0) {
            *outRect = CGRectMake(elPos.x, elPos.y, elSize.width, elSize.height);
            ok = YES;
        }
    }
    if (posVal) CFRelease(posVal);
    if (sizeVal) CFRelease(sizeVal);
    return ok;
}

static void enableAccessibilityForPID(pid_t pid) {
    if (pid <= 0) return;
    AXUIElementRef appElem = AXUIElementCreateApplication(pid);
    if (appElem) {
        AXUIElementSetAttributeValue(appElem, (CFStringRef)@"AXManualAccessibility", kCFBooleanTrue);
        AXUIElementSetAttributeValue(appElem, (CFStringRef)@"AXEnhancedUserInterface", kCFBooleanTrue);
        CFRelease(appElem);
    }
}

static NSString *extractString(id val) {
    if (!val) return nil;
    if ([val isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)val stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return s.length ? (NSString *)val : nil;
    }
    if ([val isKindOfClass:[NSAttributedString class]]) {
        NSString *s = [[(NSAttributedString *)val string] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return s.length ? [(NSAttributedString *)val string] : nil;
    }
    return nil;
}

static BOOL isBrowserTabNoise(NSString *str) {
    if (!str || str.length == 0) return NO;
    return [str containsString:@"- Memory usage -"] ||
           [str containsString:@" - Part of group "] ||
           [str hasSuffix:@" - Audio playing"];
}

static NSString *textValue(AXUIElementRef element) {
    if (!element) return nil;
    NSString *role = attribute(element, kAXRoleAttribute);
    if ([attribute(element, kAXSubroleAttribute) isEqual:@"AXSecureTextField"]) return nil;
    if ([role isEqualToString:@"AXButton"] || [role isEqualToString:@"AXToolbar"] ||
        [role isEqualToString:@"AXMenuBar"] || [role isEqualToString:@"AXMenu"] ||
        [role isEqualToString:@"AXScrollBar"] || [role isEqualToString:@"AXSlider"] ||
        [role isEqualToString:@"AXTabGroup"] || [role isEqualToString:@"AXRadioButton"] ||
        [role isEqualToString:@"AXImage"]) return nil;

    NSString *str = extractString(attribute(element, kAXValueAttribute));
    if (str && !isBrowserTabNoise(str)) return str;
    str = extractString(attribute(element, kAXTitleAttribute));
    if (str && !isBrowserTabNoise(str)) return str;
    str = extractString(attribute(element, kAXDescriptionAttribute));
    if (str && !isBrowserTabNoise(str)) return str;
    str = extractString(attribute(element, kAXHelpAttribute));
    if (str && !isBrowserTabNoise(str)) return str;
    return nil;
}

static void collect(AXUIElementRef element, NSMutableArray *elements, NSMutableArray *texts, NSUInteger depth, NSUInteger *budget) {
    if (!element || !*budget || depth > 45) return;
    (*budget)--;
    NSString *role = attribute(element, kAXRoleAttribute);
    if ([role isEqualToString:@"AXToolbar"] ||
        [role isEqualToString:@"AXMenuBar"] || [role isEqualToString:@"AXMenu"] ||
        [role isEqualToString:@"AXScrollBar"] || [role isEqualToString:@"AXSlider"] ||
        [role isEqualToString:@"AXTabGroup"] || [role isEqualToString:@"AXRadioButton"] ||
        [role isEqualToString:@"AXImage"]) return;

    NSString *text = textValue(element);

    // Static text and text inputs are leaf reading units (do not descend into AXInlineTextBox line fragments)
    if (text && ([role isEqualToString:(__bridge NSString *)kAXStaticTextRole] ||
                 [role isEqualToString:(__bridge NSString *)kAXTextAreaRole] ||
                 [role isEqualToString:(__bridge NSString *)kAXTextFieldRole])) {
        [elements addObject:(__bridge id)element];
        [texts addObject:text];
        return;
    }

    id children = attribute(element, kAXChildrenAttribute);
    BOOL hasChildren = [children isKindOfClass:[NSArray class]] && [(NSArray *)children count] > 0;

    // Native standalone push buttons without readable descendants are skipped.
    // Web/Electron elements with role="button" (cards, messages) contain readable children and must be traversed!
    if ([role isEqualToString:@"AXButton"] && !hasChildren) return;

    if (text && !hasChildren) {
        [elements addObject:(__bridge id)element];
        [texts addObject:text];
        return;
    }

    if (hasChildren) {
        for (id child in (NSArray *)children) {
            collect((__bridge AXUIElementRef)child, elements, texts, depth + 1, budget);
        }
    }
}

static NSUInteger indexOfAXElement(NSArray *elements, AXUIElementRef needle) {
    if (!needle) return NSNotFound;
    for (NSUInteger i = 0; i < elements.count; i++) {
        AXUIElementRef candidate = (__bridge AXUIElementRef)elements[i];
        if (candidate == needle || CFEqual(candidate, needle)) return i;
    }
    return NSNotFound;
}

static NSUInteger findGeometryMatchIndex(NSArray *elements, CGPoint point) {
    NSUInteger bestDirectIdx = NSNotFound;
    CGFloat bestDirectArea = 1e18;
    for (NSUInteger i = 0; i < elements.count; i++) {
        AXUIElementRef cand = (__bridge AXUIElementRef)elements[i];
        CGRect rect;
        if (getElementRect(cand, &rect) && CGRectContainsPoint(rect, point)) {
            CGFloat area = rect.size.width * rect.size.height;
            if (area < bestDirectArea) {
                bestDirectArea = area;
                bestDirectIdx = i;
            }
        }
    }
    if (bestDirectIdx != NSNotFound) return bestDirectIdx;

    CGFloat bestDist = 1e9;
    NSUInteger bestNearIdx = NSNotFound;
    BOOL anyHasRect = NO;
    for (NSUInteger i = 0; i < elements.count; i++) {
        AXUIElementRef cand = (__bridge AXUIElementRef)elements[i];
        CGRect rect;
        if (getElementRect(cand, &rect)) {
            anyHasRect = YES;
            CGRect hitRect = CGRectInset(rect, -48, -48);
            if (CGRectContainsPoint(hitRect, point)) {
                CGFloat dy = fabs(point.y - CGRectGetMidY(rect));
                CGFloat dx = fabs(point.x - CGRectGetMidX(rect));
                CGFloat dist = dy * 2.0 + dx * 0.25;
                if (dist < bestDist) {
                    bestDist = dist;
                    bestNearIdx = i;
                }
            }
        }
    }
    if (bestNearIdx != NSNotFound) return bestNearIdx;

    if (anyHasRect) {
        CGFloat bestColDist = 1e9;
        NSUInteger bestColIdx = NSNotFound;
        for (NSUInteger i = 0; i < elements.count; i++) {
            AXUIElementRef cand = (__bridge AXUIElementRef)elements[i];
            CGRect rect;
            if (getElementRect(cand, &rect)) {
                CGFloat horizGap = 0.0;
                if (point.x < CGRectGetMinX(rect)) horizGap = CGRectGetMinX(rect) - point.x;
                else if (point.x > CGRectGetMaxX(rect)) horizGap = point.x - CGRectGetMaxX(rect);
                if (horizGap > 400.0) continue;

                CGFloat vertGap = 0.0;
                if (point.y < CGRectGetMinY(rect)) vertGap = CGRectGetMinY(rect) - point.y;
                else if (point.y > CGRectGetMaxY(rect)) vertGap = point.y - CGRectGetMaxY(rect);

                CGFloat score = vertGap * 2.0 + horizGap * 0.5;
                if (score < bestColDist) {
                    bestColDist = score;
                    bestColIdx = i;
                }
            }
        }
        if (bestColIdx != NSNotFound) return bestColIdx;
    }
    return NSNotFound;
}

static NSUInteger snapOffsetToSentenceStart(NSString *text, NSUInteger offset) {
    if (!text || offset == 0 || offset >= text.length) return 0;
    // Scan backwards from offset to find the beginning of the clicked sentence (. ! ? or newline)
    for (NSInteger i = (NSInteger)offset - 1; i >= 0; i--) {
        unichar c = [text characterAtIndex:(NSUInteger)i];
        if (c == '\n' || c == '\r') {
            NSUInteger start = (NSUInteger)i + 1;
            while (start < text.length && [[NSCharacterSet whitespaceCharacterSet] characterIsMember:[text characterAtIndex:start]]) start++;
            return start < text.length ? start : 0;
        }
        if (c == '.' || c == '!' || c == '?') {
            if ((NSUInteger)i + 1 < text.length && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[text characterAtIndex:(NSUInteger)i + 1]]) {
                NSUInteger start = (NSUInteger)i + 1;
                while (start < text.length && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[text characterAtIndex:start]]) start++;
                return start < text.length ? start : 0;
            }
        }
    }
    return 0;
}

NSString *GRReadingTextAtElement(AXUIElementRef element, CGPoint point) {
    if (!element) return nil;

    // Ensure accessibility tree is enabled on element's application process (essential for Electron/Chromium)
    pid_t pid = 0;
    if (AXUIElementGetPid(element, &pid) == kAXErrorSuccess && pid > 0) {
        enableAccessibilityForPID(pid);
    }

    NSString *role = attribute(element, kAXRoleAttribute);
    id heldElement = nil;
    if ([role isEqualToString:@"AXInlineTextBox"]) {
        id parent = attribute(element, kAXParentAttribute);
        if (parent) {
            heldElement = parent;
            element = (__bridge AXUIElementRef)heldElement;
            role = attribute(element, kAXRoleAttribute);
        }
    }

    NSString *directText = textValue(element);
    BOOL hasPoint = !(point.x == -1.0 && point.y == -1.0) && !isnan(point.x) && !isnan(point.y);

    // If hit-testing returned a top-level AXWindow or AXApplication and we have a point,
    // drill down geometrically to the deepest container enclosing the point.
    id drilledHolder = nil;
    if (hasPoint && ([role isEqualToString:@"AXWindow"] || [role isEqualToString:@"AXApplication"] || [role isEqualToString:@"AXSplitGroup"])) {
        AXUIElementRef curr = element;
        for (NSUInteger depth = 0; depth < 12; depth++) {
            id children = attribute(curr, kAXChildrenAttribute);
            if (![children isKindOfClass:[NSArray class]] || [(NSArray *)children count] == 0) break;
            id bestChild = nil;
            CGFloat bestArea = 1e18;
            for (id child in (NSArray *)children) {
                AXUIElementRef childRef = (__bridge AXUIElementRef)child;
                NSString *cRole = attribute(childRef, kAXRoleAttribute);
                if ([cRole isEqualToString:@"AXToolbar"] || [cRole isEqualToString:@"AXScrollBar"] || [cRole isEqualToString:@"AXMenuBar"]) continue;
                CGRect rect;
                if (getElementRect(childRef, &rect) && CGRectContainsPoint(rect, point)) {
                    CGFloat area = rect.size.width * rect.size.height;
                    if (area < bestArea) {
                        bestArea = area;
                        bestChild = child;
                    }
                }
            }
            if (!bestChild) break;
            drilledHolder = bestChild;
            curr = (__bridge AXUIElementRef)drilledHolder;
            NSString *currRole = attribute(curr, kAXRoleAttribute);
            NSString *currSubrole = attribute(curr, kAXSubroleAttribute);
            if ([currRole isEqualToString:@"AXStaticText"] || [currRole isEqualToString:@"AXTextArea"] ||
                [currSubrole isEqualToString:@"AXDocumentArticle"] || [currRole isEqualToString:@"AXArticle"]) {
                break;
            }
        }
        if (drilledHolder) {
            element = (__bridge AXUIElementRef)drilledHolder;
            role = attribute(element, kAXRoleAttribute);
            directText = textValue(element);
        }
    }

    NSMutableArray *ancestors = [NSMutableArray arrayWithObject:(__bridge id)element];
    BOOL editable = [role isEqualToString:@"AXTextArea"] || [role isEqualToString:@"AXTextField"];
    if (!editable) {
        id parent = (__bridge id)element;
        for (NSUInteger i = 0; i < 10; i++) {
            id next = attribute((__bridge AXUIElementRef)parent, kAXParentAttribute);
            if (!next) break;
            AXUIElementRef nextRef = (__bridge AXUIElementRef)next;
            NSString *parentRole = attribute(nextRef, kAXRoleAttribute);
            NSString *parentSubrole = attribute(nextRef, kAXSubroleAttribute);
            if ([parentRole isEqualToString:@"AXWindow"] ||
                [parentRole isEqualToString:@"AXApplication"] ||
                [parentRole isEqualToString:@"AXSplitGroup"] ||
                [parentRole isEqualToString:@"AXTabGroup"]) {
                break;
            }
            [ancestors addObject:next];
            if ([parentRole isEqualToString:@"AXScrollArea"] ||
                [parentRole isEqualToString:@"AXWebArea"] ||
                [parentRole isEqualToString:@"AXArticle"] ||
                [parentRole isEqualToString:@"AXDocument"] ||
                [parentSubrole isEqualToString:@"AXDocumentArticle"] ||
                [parentSubrole isEqualToString:@"AXDocument"] ||
                [parentSubrole isEqualToString:@"AXApplicationLog"]) {
                break;
            }
            parent = next;
        }
    }

    // Collect descendants of the clicked element itself so we know what belongs to it if it is a group
    NSMutableArray *groupElements = [NSMutableArray array], *groupTexts = [NSMutableArray array];
    NSUInteger groupBudget = 800;
    collect(element, groupElements, groupTexts, 0, &groupBudget);

    NSMutableArray *elements = [NSMutableArray array], *texts = [NSMutableArray array];
    NSUInteger index = NSNotFound;

    // Try collecting from the highest container ancestor down to closer ancestors if budget was exhausted
    for (NSInteger aIdx = (NSInteger)ancestors.count - 1; aIdx >= 0; aIdx--) {
        [elements removeAllObjects];
        [texts removeAllObjects];
        NSUInteger budget = 6000;
        collect((__bridge AXUIElementRef)ancestors[(NSUInteger)aIdx], elements, texts, 0, &budget);
        if (!elements.count) continue;

        // 1. Direct leaf match
        index = indexOfAXElement(elements, element);
        if (index != NSNotFound) break;

        // 2. Verify whether this ancestor collection actually reached `element`'s subtree
        BOOL reachedSubtree = (aIdx == 0);
        if (!reachedSubtree && groupElements.count > 0) {
            if (indexOfAXElement(elements, (__bridge AXUIElementRef)groupElements.firstObject) != NSNotFound) {
                reachedSubtree = YES;
            }
        }

        // 3. If `element` is a container and we have a screen point, match the exact child at `point`
        if (hasPoint && (reachedSubtree || groupElements.count == 0)) {
            index = findGeometryMatchIndex(elements, point);
            if (index != NSNotFound) break;
        }

        // 4. Fallback to first readable descendant of `element` if reached
        if (reachedSubtree && groupElements.count > 0) {
            index = indexOfAXElement(elements, (__bridge AXUIElementRef)groupElements.firstObject);
            if (index != NSNotFound) break;
        }
    }

    if (!elements.count) {
        return directText.length ? directText : nil;
    }

    if (index == NSNotFound) {
        if (directText.length) return directText;
        if (groupTexts.count) {
            return GRReadingSuffix(groupTexts, 0, 0);
        }
        if (!hasPoint) {
            index = 0;
        } else {
            return nil;
        }
    }

    AXUIElementRef leaf = (__bridge AXUIElementRef)elements[index];
    NSString *leafText = texts[index];
    NSUInteger offset = 0;
    BOOL exactRangeFound = NO;
    if (hasPoint) {
        AXValueRef position = AXValueCreate(kAXValueCGPointType, &point);
        CFTypeRef rawRange = NULL;
        AXError error = AXUIElementCopyParameterizedAttributeValue(leaf, kAXRangeForPositionParameterizedAttribute, position, &rawRange);
        CFRelease(position);
        if (error == kAXErrorSuccess && rawRange && CFGetTypeID(rawRange) == AXValueGetTypeID()) {
            CFRange range;
            if (AXValueGetValue((AXValueRef)rawRange, kAXValueCFRangeType, &range) && range.location >= 0) {
                offset = (NSUInteger)range.location;
                exactRangeFound = YES;
            }
        }
        if (rawRange) CFRelease(rawRange);
    }
    if (!exactRangeFound && offset == 0) {
        CFTypeRef caretRange = NULL;
        if (AXUIElementCopyAttributeValue(leaf, kAXSelectedTextRangeAttribute, &caretRange) == kAXErrorSuccess &&
            caretRange && CFGetTypeID(caretRange) == AXValueGetTypeID()) {
            CFRange range;
            if (AXValueGetValue((AXValueRef)caretRange, kAXValueCFRangeType, &range) && range.location > 0) {
                offset = (NSUInteger)range.location;
                exactRangeFound = YES;
            }
            CFRelease(caretRange);
        }
    }
    // For multi-line Chromium / Electron static text elements, estimate line offset and snap to sentence start
    if (!exactRangeFound && offset == 0 && hasPoint && leafText.length > 80) {
        CGRect rect;
        if (getElementRect(leaf, &rect) && rect.size.height > 36.0) {
            CGFloat relY = (point.y - rect.origin.y) / rect.size.height;
            if (relY < 0) relY = 0;
            if (relY > 1) relY = 1;
            CGFloat numLines = MAX(1.0, round(rect.size.height / 20.0));
            CGFloat lineIdx = floor(relY * numLines);
            if (lineIdx > 0) {
                CGFloat estFraction = lineIdx / numLines;
                NSUInteger rawOffset = (NSUInteger)(estFraction * leafText.length);
                offset = snapOffsetToSentenceStart(leafText, rawOffset);
            }
        }
    } else if (exactRangeFound && offset > 0 && offset < leafText.length) {
        offset = snapOffsetToSentenceStart(leafText, offset);
    }
    if (offset >= leafText.length) {
        offset = 0;
    }

    // If offset is 0 and the clicked element is an inline word inside a split sentence,
    // step backwards to the first inline word of that sentence.
    while (offset == 0 && index > 0) {
        AXUIElementRef prevElem = (__bridge AXUIElementRef)elements[index - 1];
        NSString *prevText = texts[index - 1];
        AXUIElementRef currElem = (__bridge AXUIElementRef)elements[index];
        NSString *currText = texts[index];
        if (!endsWithSentenceTerminator(prevText) && areElementsInline(prevElem, prevText, currElem, currText)) {
            index--;
            leaf = prevElem;
            leafText = prevText;
        } else {
            break;
        }
    }

    // Merge consecutive inline elements from `index` onward into unified paragraphs before GRReadingSuffix
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *firstSlice = [[leafText substringFromIndex:offset] stringByTrimmingCharactersInSet:space];
    NSMutableArray<NSString *> *mergedBlocks = [NSMutableArray array];
    NSMutableString *currentPara = [NSMutableString stringWithString:firstSlice ?: @""];
    AXUIElementRef prevElem = leaf;
    NSString *prevText = firstSlice ?: @"";

    for (NSUInteger i = index + 1; i < elements.count; i++) {
        AXUIElementRef currElem = (__bridge AXUIElementRef)elements[i];
        NSString *currText = [texts[i] stringByTrimmingCharactersInSet:space];
        if (!currText.length) continue;

        if (currentPara.length == 0) {
            [currentPara appendString:currText];
            prevText = currText;
        } else if (areElementsInline(prevElem, prevText, currElem, currText)) {
            if (startsWithClosingPunctuation(currText) || endsWithInlineContinuation(prevText)) {
                if ([prevText hasSuffix:@","]) {
                    [currentPara appendFormat:@" %@", currText];
                    prevText = currText;
                } else {
                    [currentPara appendString:currText];
                    prevText = [prevText stringByAppendingString:currText];
                }
            } else {
                [currentPara appendFormat:@" %@", currText];
                prevText = currText;
            }
        } else {
            [mergedBlocks addObject:[currentPara copy]];
            [currentPara setString:currText];
            prevText = currText;
        }
        prevElem = currElem;
    }
    if (currentPara.length > 0) {
        [mergedBlocks addObject:[currentPara copy]];
    }

    return GRReadingSuffix(mergedBlocks, 0, 0);
}

pid_t GRAppPIDAtScreenPoint(CGPoint point, pid_t excludePID) {
    CFArrayRef windowList = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
    pid_t foundPID = 0;
    if (windowList) {
        CFIndex count = CFArrayGetCount(windowList);
        for (CFIndex i = 0; i < count; i++) {
            NSDictionary *win = (__bridge NSDictionary *)CFArrayGetValueAtIndex(windowList, i);
            int layer = [win[(__bridge NSString *)kCGWindowLayer] intValue];
            if (layer != 0) continue;
            pid_t ownerPID = [win[(__bridge NSString *)kCGWindowOwnerPID] intValue];
            if (ownerPID <= 0 || ownerPID == excludePID) continue;
            double alpha = win[(__bridge NSString *)kCGWindowAlpha] ? [win[(__bridge NSString *)kCGWindowAlpha] doubleValue] : 1.0;
            if (alpha <= 0.01) continue;
            NSDictionary *boundsDict = win[(__bridge NSString *)kCGWindowBounds];
            CGRect bounds = CGRectZero;
            if (boundsDict && CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)boundsDict, &bounds)) {
                if (CGRectContainsPoint(bounds, point)) {
                    foundPID = ownerPID;
                    break;
                }
            }
        }
        CFRelease(windowList);
    }
    return foundPID;
}

static NSString *selectedTextForApplication(AXUIElementRef appElem) {
    if (!appElem) return nil;
    CFTypeRef focused = NULL;
    if (AXUIElementCopyAttributeValue(appElem, kAXFocusedUIElementAttribute, &focused) == kAXErrorSuccess && focused) {
        NSString *sel = extractString(attribute((AXUIElementRef)focused, kAXSelectedTextAttribute));
        CFRelease(focused);
        if (sel.length > 1) return sel;
    }
    return nil;
}

static NSString *hitTestPointInApplication(AXUIElementRef appElem, AXUIElementRef system, CGPoint point, pid_t targetPID) {
    CGPoint offsets[] = {
        {0, 0},
        {0, -8},
        {0, 8},
        {-16, 0},
        {16, 0}
    };
    size_t numOffsets = sizeof(offsets) / sizeof(offsets[0]);

    for (size_t i = 0; i < numOffsets; i++) {
        CGPoint pt = CGPointMake(point.x + offsets[i].x, point.y + offsets[i].y);
        AXUIElementRef hit = NULL;

        // 1. Prefer application-specific hit-testing (drills into Electron/Chromium web areas directly)
        if (appElem && AXUIElementCopyElementAtPosition(appElem, pt.x, pt.y, &hit) == kAXErrorSuccess && hit) {
            pid_t hitPid = 0;
            if (AXUIElementGetPid(hit, &hitPid) == kAXErrorSuccess && hitPid > 0 && hitPid != targetPID) {
                enableAccessibilityForPID(hitPid);
            }
            NSString *txt = GRReadingTextAtElement(hit, pt);
            CFRelease(hit);
            if (txt.length > 0) return txt;
        }

        // 2. Fallback to system-wide hit-testing
        hit = NULL;
        if (system && AXUIElementCopyElementAtPosition(system, pt.x, pt.y, &hit) == kAXErrorSuccess && hit) {
            pid_t hitPid = 0;
            AXUIElementGetPid(hit, &hitPid);
            if (hitPid > 0 && hitPid != targetPID) {
                enableAccessibilityForPID(hitPid);
            }
            NSString *txt = GRReadingTextAtElement(hit, pt);
            CFRelease(hit);
            if (txt.length > 0) return txt;
        }
    }
    return nil;
}

NSString *GRExtractReadingTextAtScreenPoint(CGPoint point, pid_t targetPID) {
    BOOL hasPoint = !(point.x == -1.0 && point.y == -1.0) && !isnan(point.x) && !isnan(point.y);
    if (targetPID <= 0 && hasPoint) {
        targetPID = GRAppPIDAtScreenPoint(point, getpid());
    }
    if (targetPID <= 0) return nil;

    enableAccessibilityForPID(targetPID);
    AXUIElementRef appElem = AXUIElementCreateApplication(targetPID);
    AXUIElementRef system = AXUIElementCreateSystemWide();

    // 1. If user explicitly highlighted text in the target app, read that selection
    NSString *selected = selectedTextForApplication(appElem);
    if (selected.length > 0) {
        if (appElem) CFRelease(appElem);
        if (system) CFRelease(system);
        return selected;
    }

    // 2. Hit-test at the clicked screen coordinate
    NSString *result = nil;
    if (hasPoint) {
        useconds_t delays[] = {0, 80000, 140000, 180000};
        for (size_t d = 0; d < sizeof(delays) / sizeof(delays[0]); d++) {
            if (delays[d] > 0) usleep(delays[d]);
            result = hitTestPointInApplication(appElem, system, point, targetPID);
            if (result.length > 0) break;
        }
    }

    // 3. Fallback to focused UI element or focused window at point
    if (!result.length && appElem) {
        CFTypeRef focused = NULL;
        if (AXUIElementCopyAttributeValue(appElem, kAXFocusedUIElementAttribute, &focused) == kAXErrorSuccess && focused) {
            result = GRReadingTextAtElement((AXUIElementRef)focused, point);
            CFRelease(focused);
        }
        if (!result.length) {
            CFTypeRef focWin = NULL;
            if (AXUIElementCopyAttributeValue(appElem, kAXFocusedWindowAttribute, &focWin) == kAXErrorSuccess && focWin) {
                result = GRReadingTextAtElement((AXUIElementRef)focWin, point);
                CFRelease(focWin);
            }
        }
    }

    if (appElem) CFRelease(appElem);
    if (system) CFRelease(system);
    return result.length ? result : nil;
}
