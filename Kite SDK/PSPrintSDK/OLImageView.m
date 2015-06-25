//
//  OLImageView.m
//  KitePrintSDK
//
//  Created by Konstadinos Karayannis on 19/6/15.
//  Copyright (c) 2015 Deon Botha. All rights reserved.
//

#import "OLImageView.h"

@implementation OLImageView

- (BOOL)canBecomeFirstResponder{
    return YES;
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender{
    NSArray *whiteList = @[@"deletePage", @"addPage", @"cropImage"];
    
    if ([self respondsToSelector:action] && [self.delegate respondsToSelector:action] && [whiteList containsObject:NSStringFromSelector(action)]){
        return YES;
    }
    else{
        return NO;
    }
    
}

- (void)deletePage{
    [self.delegate performSelector:@selector(deletePage)];
}

- (void)addPage{
    [self.delegate performSelector:@selector(addPage)];
}

- (void)cropImage{
    [self.delegate performSelector:@selector(cropImage)];
}

@end
