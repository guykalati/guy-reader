#import "reading_origin.h"

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
    NSMutableArray *remaining = [NSMutableArray arrayWithObject:[block substringFromIndex:offset]];
    for (NSUInteger i = blockIndex + 1; i < blocks.count; i++) [remaining addObject:blocks[i]];
    return [[remaining componentsJoinedByString:@"\n\n"] stringByTrimmingCharactersInSet:space];
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

static NSString *textValue(AXUIElementRef element) {
    if (!element) return nil;
    NSString *role = attribute(element, kAXRoleAttribute);
    if ([attribute(element, kAXSubroleAttribute) isEqual:@"AXSecureTextField"]) return nil;
    if ([role isEqualToString:@"AXButton"] || [role isEqualToString:@"AXToolbar"] ||
        [role isEqualToString:@"AXMenuBar"] || [role isEqualToString:@"AXMenu"] ||
        [role isEqualToString:@"AXScrollBar"] || [role isEqualToString:@"AXSlider"]) return nil;

    NSString *str = extractString(attribute(element, kAXValueAttribute));
    if (str) return str;
    str = extractString(attribute(element, kAXTitleAttribute));
    if (str) return str;
    str = extractString(attribute(element, kAXDescriptionAttribute));
    if (str) return str;
    str = extractString(attribute(element, kAXHelpAttribute));
    if (str) return str;
    return nil;
}

static void collect(AXUIElementRef element, NSMutableArray *elements, NSMutableArray *texts, NSUInteger depth, NSUInteger *budget) {
    if (!element || !*budget || depth > 40) return;
    (*budget)--;
    NSString *role = attribute(element, kAXRoleAttribute);
    if ([role isEqualToString:@"AXToolbar"] ||
        [role isEqualToString:@"AXMenuBar"] || [role isEqualToString:@"AXMenu"] ||
        [role isEqualToString:@"AXScrollBar"] || [role isEqualToString:@"AXSlider"]) return;

    id children = attribute(element, kAXChildrenAttribute);
    BOOL hasChildren = [children isKindOfClass:[NSArray class]] && [(NSArray *)children count] > 0;

    // Native standalone push buttons without readable descendants are skipped.
    // Web/Electron elements with role="button" (cards, messages) contain readable children and must be traversed!
    if ([role isEqualToString:@"AXButton"] && !hasChildren) return;

    NSString *text = textValue(element);

    // A leaf element with text or a dedicated text area is collected
    if (text && (!hasChildren || [role isEqualToString:(__bridge NSString *)kAXTextAreaRole] || [role isEqualToString:(__bridge NSString *)kAXTextFieldRole])) {
        [elements addObject:(__bridge id)element];
        [texts addObject:text];
        return;
    }

    if (hasChildren) {
        for (id child in (NSArray *)children) {
            collect((__bridge AXUIElementRef)child, elements, texts, depth + 1, budget);
        }
    } else if (text) {
        [elements addObject:(__bridge id)element];
        [texts addObject:text];
    }
}

static NSUInteger indexOfAXElement(NSArray *elements, AXUIElementRef needle) {
    for (NSUInteger i = 0; i < elements.count; i++) {
        AXUIElementRef candidate = (__bridge AXUIElementRef)elements[i];
        if (candidate == needle || CFEqual(candidate, needle)) return i;
    }
    return NSNotFound;
}

NSString *GRReadingTextAtElement(AXUIElementRef element, CGPoint point) {
    if (!element) return nil;

    // Ensure accessibility tree is enabled on element's application process (essential for Electron/Chromium)
    pid_t pid = 0;
    if (AXUIElementGetPid(element, &pid) == kAXErrorSuccess && pid > 0) {
        AXUIElementRef appElem = AXUIElementCreateApplication(pid);
        if (appElem) {
            AXUIElementSetAttributeValue(appElem, (CFStringRef)@"AXManualAccessibility", kCFBooleanTrue);
            CFRelease(appElem);
        }
    }

    NSString *directText = textValue(element);

    id root = (__bridge id)element;
    NSString *role = attribute(element, kAXRoleAttribute);
    BOOL editable = [role isEqualToString:@"AXTextArea"] || [role isEqualToString:@"AXTextField"];
    if (!editable) {
        id parent = root;
        for (NSUInteger i = 0; i < 10; i++) {
            id next = attribute((__bridge AXUIElementRef)parent, kAXParentAttribute);
            if (!next) break;
            NSString *parentRole = attribute((__bridge AXUIElementRef)next, kAXRoleAttribute);
            if ([parentRole isEqualToString:@"AXWindow"] || [parentRole isEqualToString:@"AXApplication"]) break;
            root = next;
            if ([parentRole isEqualToString:@"AXScrollArea"] || [parentRole isEqualToString:@"AXWebArea"]) break;
            parent = next;
        }
    }
    NSMutableArray *elements = [NSMutableArray array], *texts = [NSMutableArray array];
    NSUInteger budget = 3000;
    collect((__bridge AXUIElementRef)root, elements, texts, 0, &budget);
    if (!elements.count) {
        return directText.length ? directText : nil;
    }

    NSUInteger index = indexOfAXElement(elements, element);
    if (index == NSNotFound) {
        // Hit testing may return an enclosing group or paragraph. Locate its first readable descendant.
        NSMutableArray *groupElements = [NSMutableArray array], *groupTexts = [NSMutableArray array];
        budget = 600;
        collect(element, groupElements, groupTexts, 0, &budget);
        if (groupElements.count) {
            index = indexOfAXElement(elements, (__bridge AXUIElementRef)groupElements.firstObject);
        }
    }
    BOOL hasPoint = !(point.x == -1.0 && point.y == -1.0) && !isnan(point.x) && !isnan(point.y);

    if (index == NSNotFound && hasPoint) {
        // Find element enclosing the clicked point via geometry
        for (NSUInteger i = 0; i < elements.count; i++) {
            AXUIElementRef cand = (__bridge AXUIElementRef)elements[i];
            CFTypeRef posVal = NULL, sizeVal = NULL;
            CGPoint elPos; CGSize elSize;
            if (AXUIElementCopyAttributeValue(cand, kAXPositionAttribute, &posVal) == kAXErrorSuccess &&
                AXValueGetValue((AXValueRef)posVal, kAXValueCGPointType, &elPos) &&
                AXUIElementCopyAttributeValue(cand, kAXSizeAttribute, &sizeVal) == kAXErrorSuccess &&
                AXValueGetValue((AXValueRef)sizeVal, kAXValueCGSizeType, &elSize)) {
                CGRect rect = CGRectMake(elPos.x, elPos.y, elSize.width, elSize.height);
                if (CGRectContainsPoint(rect, point)) {
                    index = i;
                    if (posVal) CFRelease(posVal);
                    if (sizeVal) CFRelease(sizeVal);
                    break;
                }
            }
            if (posVal) CFRelease(posVal);
            if (sizeVal) CFRelease(sizeVal);
        }
    }
    if (index == NSNotFound && hasPoint) {
        // Nearest element fallback with margin
        CGFloat bestDist = 1e9;
        NSUInteger bestIdx = NSNotFound;
        for (NSUInteger i = 0; i < elements.count; i++) {
            AXUIElementRef cand = (__bridge AXUIElementRef)elements[i];
            CFTypeRef posVal = NULL, sizeVal = NULL;
            CGPoint elPos; CGSize elSize;
            if (AXUIElementCopyAttributeValue(cand, kAXPositionAttribute, &posVal) == kAXErrorSuccess &&
                AXValueGetValue((AXValueRef)posVal, kAXValueCGPointType, &elPos) &&
                AXUIElementCopyAttributeValue(cand, kAXSizeAttribute, &sizeVal) == kAXErrorSuccess &&
                AXValueGetValue((AXValueRef)sizeVal, kAXValueCGSizeType, &elSize)) {
                CGRect rect = CGRectMake(elPos.x, elPos.y, elSize.width, elSize.height);
                CGRect hitRect = CGRectInset(rect, -40, -40);
                if (CGRectContainsPoint(hitRect, point)) {
                    CGFloat dy = fabs(point.y - (elPos.y + elSize.height / 2.0));
                    CGFloat dx = fabs(point.x - (elPos.x + elSize.width / 2.0));
                    CGFloat dist = dy * 2.0 + dx;
                    if (dist < bestDist) {
                        bestDist = dist;
                        bestIdx = i;
                    }
                }
            }
            if (posVal) CFRelease(posVal);
            if (sizeVal) CFRelease(sizeVal);
        }
        if (bestIdx != NSNotFound) {
            index = bestIdx;
        }
    }
    if (index == NSNotFound) {
        if (directText.length) return directText;
        index = 0; // Default to first readable block in the clicked container
    }

    AXUIElementRef leaf = (__bridge AXUIElementRef)elements[index];
    NSString *leafText = texts[index];
    NSUInteger offset = 0;
    if (hasPoint) {
        AXValueRef position = AXValueCreate(kAXValueCGPointType, &point);
        CFTypeRef rawRange = NULL;
        AXError error = AXUIElementCopyParameterizedAttributeValue(leaf, kAXRangeForPositionParameterizedAttribute, position, &rawRange);
        CFRelease(position);
        if (error == kAXErrorSuccess && rawRange && CFGetTypeID(rawRange) == AXValueGetTypeID()) {
            CFRange range;
            if (AXValueGetValue((AXValueRef)rawRange, kAXValueCFRangeType, &range) && range.location >= 0) {
                offset = (NSUInteger)range.location;
            }
        }
        if (rawRange) CFRelease(rawRange);
    }
    if (offset == 0) {
        CFTypeRef caretRange = NULL;
        if (AXUIElementCopyAttributeValue(leaf, kAXSelectedTextRangeAttribute, &caretRange) == kAXErrorSuccess &&
            caretRange && CFGetTypeID(caretRange) == AXValueGetTypeID()) {
            CFRange range;
            if (AXValueGetValue((AXValueRef)caretRange, kAXValueCFRangeType, &range) && range.location >= 0) {
                offset = (NSUInteger)range.location;
            }
            CFRelease(caretRange);
        }
    }
    // Heuristic offset approximation for Chromium / Electron static text elements
    if (offset == 0 && hasPoint && leafText.length > 0) {
        CFTypeRef posVal = NULL, sizeVal = NULL;
        CGPoint elPos; CGSize elSize;
        if (AXUIElementCopyAttributeValue(leaf, kAXPositionAttribute, &posVal) == kAXErrorSuccess &&
            AXValueGetValue((AXValueRef)posVal, kAXValueCGPointType, &elPos) &&
            AXUIElementCopyAttributeValue(leaf, kAXSizeAttribute, &sizeVal) == kAXErrorSuccess &&
            AXValueGetValue((AXValueRef)sizeVal, kAXValueCGSizeType, &elSize)) {
            if (elSize.width > 0 && elSize.height > 0) {
                CGFloat relY = (point.y - elPos.y) / elSize.height;
                CGFloat relX = (point.x - elPos.x) / elSize.width;
                if (relY < 0) relY = 0; if (relY > 1) relY = 1;
                if (relX < 0) relX = 0; if (relX > 1) relX = 1;

                CGFloat estFraction = 0.0;
                if (elSize.height > 28.0) {
                    CGFloat numLines = MAX(1.0, round(elSize.height / 20.0));
                    CGFloat lineIdx = floor(relY * numLines);
                    estFraction = (lineIdx + relX) / numLines;
                } else {
                    estFraction = relX;
                }
                if (estFraction < 0) estFraction = 0;
                if (estFraction > 1) estFraction = 1;
                offset = (NSUInteger)(estFraction * leafText.length);
            }
        }
        if (posVal) CFRelease(posVal);
        if (sizeVal) CFRelease(sizeVal);
    }
    if (offset >= leafText.length) {
        offset = 0;
    }
    return GRReadingSuffix(texts, index, offset);
}
